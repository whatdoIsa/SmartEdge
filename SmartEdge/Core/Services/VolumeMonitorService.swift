import Foundation
import Combine
import CoreAudio
import AudioToolbox
import os

protocol VolumeMonitorProtocol {
    var volumePublisher: AnyPublisher<Float, Never> { get }
    var muteStatusPublisher: AnyPublisher<Bool, Never> { get }
    var delegate: VolumeMonitorDelegate? { get set }
    
    func startMonitoring() async throws
    func stopMonitoring() async
    func getCurrentVolume() async -> Float
    func setVolume(_ volume: Float) async throws
    func isMuted() async -> Bool
    func setMuted(_ muted: Bool) async throws
}

protocol VolumeMonitorDelegate: AnyObject {
    func volumeDidChange(to volume: Float)
    func muteStatusDidChange(isMuted: Bool)
}

/// `@MainActor` for the same audit medium-#10 reason as
/// BrightnessMonitorService: `audioDeviceID` / `isMonitoring` mutation
/// (start/stop) and the CoreAudio listener callbacks all serialize on one
/// actor. The C `propertyListener` is a pure function pointer that
/// reconstructs `self` from `clientData` and only touches isolated state
/// inside a `Task { @MainActor in }`, so it stays compatible.
@MainActor
final class VolumeMonitorService: VolumeMonitorProtocol {
    
    // MARK: - Properties
    
    weak var delegate: VolumeMonitorDelegate?
    
    private let volumeSubject = PassthroughSubject<Float, Never>()
    private let muteStatusSubject = PassthroughSubject<Bool, Never>()
    
    var volumePublisher: AnyPublisher<Float, Never> {
        volumeSubject.eraseToAnyPublisher()
    }
    
    var muteStatusPublisher: AnyPublisher<Bool, Never> {
        muteStatusSubject.eraseToAnyPublisher()
    }
    
    private var audioDeviceID: AudioDeviceID = kAudioObjectUnknown
    private var isMonitoring = false
    
    // `passUnretained(self)` (in register*) + `takeUnretainedValue()` here
    // is safe because VolumeMonitorService is a process-lifetime singleton
    // on ServiceContainer.shared — it never actually deinits, so an
    // in-flight CoreAudio callback can't reconstruct a dangling `self`.
    // If this is ever made non-singleton, switch to passRetained + an
    // explicit release in stopMonitoring, OR guard the listener body on a
    // generation token, to avoid use-after-free on a queued callback.
    private let propertyListener: AudioObjectPropertyListenerProc = { objectID, numberAddresses, addresses, clientData in
        guard let userData = clientData else { return noErr }
        let service = Unmanaged<VolumeMonitorService>.fromOpaque(userData).takeUnretainedValue()
        
        for i in 0..<Int(numberAddresses) {
            let address = addresses[i]
            
            switch address.mSelector {
            case kAudioHardwareServiceDeviceProperty_VirtualMainVolume:
                Task { @MainActor in
                    let volume = await service.getCurrentVolume()
                    service.volumeSubject.send(volume)
                    service.delegate?.volumeDidChange(to: volume)
                }
                
            case kAudioDevicePropertyMute:
                Task { @MainActor in
                    let isMuted = await service.isMuted()
                    service.muteStatusSubject.send(isMuted)
                    service.delegate?.muteStatusDidChange(isMuted: isMuted)
                }
                
            default:
                break
            }
        }
        
        return noErr
    }
    
    // MARK: - VolumeMonitorProtocol Implementation
    
    // Properly async (matches the protocol's `async throws` requirement and
    // BrightnessMonitorService's model). Previously this was a sync method
    // that kicked off the device-discovery + listener registration in a
    // detached `Task` and returned immediately — so a caller doing
    // `try? await vm.startMonitoring()` got a completion signal *before*
    // the CoreAudio listener was actually installed, dropping the first
    // external volume change. Now the await genuinely waits for setup.
    func startMonitoring() async throws {
        guard !isMonitoring else { return }
        audioDeviceID = try await getDefaultOutputDevice()
        try registerVolumeChangeListener()
        try registerMuteChangeListener()
        isMonitoring = true
    }

    func stopMonitoring() async {
        guard isMonitoring else { return }
        unregisterVolumeChangeListener()
        unregisterMuteChangeListener()
        isMonitoring = false
    }
    
    func getCurrentVolume() async -> Float {
        guard audioDeviceID != kAudioObjectUnknown else { return 0.0 }
        
        var volume: Float32 = 0.0
        var size = UInt32(MemoryLayout<Float32>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            audioDeviceID,
            &address,
            0,
            nil,
            &size,
            &volume
        )
        
        return status == noErr ? volume : 0.0
    }
    
    func isMuted() async -> Bool {
        guard audioDeviceID != kAudioObjectUnknown else { return false }
        
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            audioDeviceID,
            &address,
            0,
            nil,
            &size,
            &muted
        )
        
        return status == noErr ? muted != 0 : false
    }
    
    func setVolume(_ volume: Float) async throws {
        guard audioDeviceID != kAudioObjectUnknown else {
            throw SmartEdgeError.systemAccess(.notAuthorized)
        }
        
        let clampedVolume = max(0.0, min(1.0, volume))
        var volumeValue: Float32 = clampedVolume
        let size = UInt32(MemoryLayout<Float32>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            audioDeviceID,
            &address,
            0,
            nil,
            size,
            &volumeValue
        )
        
        guard status == noErr else {
            throw SmartEdgeError.systemAccess(.operationFailed("Failed to set volume"))
        }
    }
    
    func setMuted(_ muted: Bool) async throws {
        guard audioDeviceID != kAudioObjectUnknown else {
            throw SmartEdgeError.systemAccess(.notAuthorized)
        }
        
        var muteValue: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            audioDeviceID,
            &address,
            0,
            nil,
            size,
            &muteValue
        )
        
        guard status == noErr else {
            throw SmartEdgeError.systemAccess(.operationFailed("Failed to set mute status"))
        }
    }
    
    // MARK: - Private Methods
    
    private func getDefaultOutputDevice() async throws -> AudioDeviceID {
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            throw SmartEdgeError.systemAccess(.notAuthorized)
        }
        
        return deviceID
    }
    
    private func registerVolumeChangeListener() throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let userData = Unmanaged.passUnretained(self).toOpaque()
        
        let status = AudioObjectAddPropertyListener(
            audioDeviceID,
            &address,
            propertyListener,
            userData
        )
        
        guard status == noErr else {
            throw SmartEdgeError.systemAccess(.operationFailed("Failed to register volume listener"))
        }
    }
    
    private func registerMuteChangeListener() throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let userData = Unmanaged.passUnretained(self).toOpaque()
        
        let status = AudioObjectAddPropertyListener(
            audioDeviceID,
            &address,
            propertyListener,
            userData
        )
        
        guard status == noErr else {
            throw SmartEdgeError.systemAccess(.operationFailed("Failed to register mute listener"))
        }
    }
    
    private func unregisterVolumeChangeListener() {
        guard audioDeviceID != kAudioObjectUnknown else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let userData = Unmanaged.passUnretained(self).toOpaque()
        
        AudioObjectRemovePropertyListener(
            audioDeviceID,
            &address,
            propertyListener,
            userData
        )
    }
    
    private func unregisterMuteChangeListener() {
        guard audioDeviceID != kAudioObjectUnknown else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let userData = Unmanaged.passUnretained(self).toOpaque()
        
        AudioObjectRemovePropertyListener(
            audioDeviceID,
            &address,
            propertyListener,
            userData
        )
    }
    
}