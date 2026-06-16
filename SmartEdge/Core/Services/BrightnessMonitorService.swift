import Foundation
import Combine
import IOKit
import IOKit.graphics
import CoreGraphics
import Darwin

// MARK: - DisplayServices private framework bridge
//
// Apple Silicon Macs do not expose internal display brightness through the
// public IOKit `IODisplayConnect` matching that the legacy implementation
// below uses — every call returns 0 or a noop. The private
// `DisplayServices.framework`, present on macOS 11+ on every Apple Silicon
// machine, has working accessors.
//
// We resolve the symbols via dlopen at first-use so:
//   - older Intel Macs without the framework still link and run.
//   - the working path is preferred on every modern Mac.
//   - the IODisplay path remains as last-resort fallback below.
//
// Requires `com.apple.security.cs.disable-library-validation` in the app's
// entitlements (already set in `SmartEdge.entitlements`) so the dlopen of a
// private framework is permitted.

private typealias DisplayServicesGetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias DisplayServicesSetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32

private enum DisplayServicesBridge {
    static let handle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    }()

    static let getBrightness: DisplayServicesGetBrightnessFunc? = {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(sym, to: DisplayServicesGetBrightnessFunc.self)
    }()

    static let setBrightness: DisplayServicesSetBrightnessFunc? = {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(sym, to: DisplayServicesSetBrightnessFunc.self)
    }()
}

protocol BrightnessMonitorProtocol {
    var brightnessPublisher: AnyPublisher<Float, Never> { get }
    var delegate: BrightnessMonitorDelegate? { get set }
    
    func startMonitoring() async throws
    func stopMonitoring() async
    func getCurrentBrightness() async -> Float
    func setBrightness(_ brightness: Float) async throws
}

protocol BrightnessMonitorDelegate: AnyObject {
    func brightnessDidChange(to brightness: Float)
}

/// `@MainActor` isolates the mutable `displayServices` array + timer state
/// so the polling tick, start/stop calls, and `SystemHUDService`'s reads
/// all serialize on one actor — closes the audit medium-#10 race where
/// `discoverDisplays` (mutating the array) could interleave with
/// `releaseDisplayServices`. The earlier attempt failed because `deinit`
/// called the `@MainActor` methods `stopBrightnessPolling()` /
/// `releaseDisplayServices()`; the fix is to inline that cleanup —
/// `deinit` is allowed to touch stored properties directly (it has
/// exclusive access) and the underlying `Timer.invalidate` /
/// `IOObjectRelease` are thread-safe C calls.
@MainActor
final class BrightnessMonitorService: BrightnessMonitorProtocol {
    
    // MARK: - Properties
    
    weak var delegate: BrightnessMonitorDelegate?
    
    private let brightnessSubject = PassthroughSubject<Float, Never>()
    
    var brightnessPublisher: AnyPublisher<Float, Never> {
        brightnessSubject.eraseToAnyPublisher()
    }
    
    private var displayServices: [io_service_t] = []
    private var isMonitoring = false
    private var brightnessTimer: Timer?
    
    // MARK: - BrightnessMonitorProtocol Implementation
    
    func startMonitoring() async throws {
        guard !isMonitoring else { return }
        
        try await discoverDisplays()
        
        // Start polling for brightness changes (IOKit doesn't provide notifications)
        startBrightnessPolling()
        
        isMonitoring = true
    }
    
    func stopMonitoring() async {
        guard isMonitoring else { return }
        
        stopBrightnessPolling()
        releaseDisplayServices()
        
        isMonitoring = false
    }
    
    func getCurrentBrightness() async -> Float {
        // Modern path: DisplayServices works on every Apple Silicon Mac
        // and recent Intel Macs. Returns 0 on success.
        if let getter = DisplayServicesBridge.getBrightness {
            var brightness: Float = 0
            if getter(CGMainDisplayID(), &brightness) == 0 {
                return brightness
            }
        }
        // Legacy IODisplay fallback for the rare Mac where DisplayServices
        // isn't present or refuses the main display ID.
        guard !displayServices.isEmpty else { return 0.0 }
        let service = displayServices[0]
        var brightness: Float = 0.0
        let result = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
        return result == kIOReturnSuccess ? brightness : 0.0
    }

    func setBrightness(_ brightness: Float) async throws {
        let clamped = max(0.0, min(1.0, brightness))

        // Modern path first.
        if let setter = DisplayServicesBridge.setBrightness {
            if setter(CGMainDisplayID(), clamped) == 0 {
                return
            }
        }

        // Fall back to IODisplay only if the modern path failed AND we
        // discovered displays during init. Empty `displayServices` on a
        // Mac where DisplayServices is also unavailable is a real failure
        // (not just "feature opted out"), so surface it.
        guard !displayServices.isEmpty else {
            throw SmartEdgeError.systemAccess(.notAuthorized)
        }
        for service in displayServices {
            let result = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clamped)
            guard result == kIOReturnSuccess else {
                throw SmartEdgeError.systemAccess(.operationFailed("Failed to set brightness"))
            }
        }
    }
    
    func getDisplayCount() async -> Int {
        return displayServices.count
    }
    
    func getBrightness(for displayIndex: Int) async -> Float {
        guard displayIndex < displayServices.count else { return 0.0 }
        
        let service = displayServices[displayIndex]
        var brightness: Float = 0.0
        let result = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
        
        return result == kIOReturnSuccess ? brightness : 0.0
    }
    
    func setBrightness(_ brightness: Float, for displayIndex: Int) async throws {
        guard displayIndex < displayServices.count else {
            throw SmartEdgeError.systemAccess(.operationFailed("Invalid display index"))
        }
        
        let clampedBrightness = max(0.0, min(1.0, brightness))
        let service = displayServices[displayIndex]
        
        let result = IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, clampedBrightness)
        
        guard result == kIOReturnSuccess else {
            throw SmartEdgeError.systemAccess(.operationFailed("Failed to set brightness for display \(displayIndex)"))
        }
    }
    
    // MARK: - Private Methods
    
    private func discoverDisplays() async throws {
        let iterator = try createDisplayIterator()
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            // Check if this display supports brightness control
            if await supportsDisplayBrightness(service) {
                displayServices.append(service)
            } else {
                IOObjectRelease(service)
            }
            service = IOIteratorNext(iterator)
        }

        // Apple Silicon Macs return an empty iterator here for the internal
        // display — that's expected, not an error. As long as DisplayServices
        // is loadable we can still read/write brightness via the modern path.
        // Throwing only when *both* paths are unavailable means we don't
        // break monitoring on machines that never had IODisplayConnect
        // results in the first place.
        if displayServices.isEmpty && DisplayServicesBridge.getBrightness == nil {
            throw SmartEdgeError.systemAccess(.operationFailed("No usable brightness backend (IODisplay empty + DisplayServices unavailable)"))
        }
    }
    
    private func createDisplayIterator() throws -> io_iterator_t {
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect"),
            &iterator
        )
        
        guard result == kIOReturnSuccess else {
            throw SmartEdgeError.systemAccess(.operationFailed("Failed to get display services"))
        }
        
        return iterator
    }
    
    private func supportsDisplayBrightness(_ service: io_service_t) async -> Bool {
        var brightness: Float = 0.0
        let result = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
        return result == kIOReturnSuccess
    }
    
    private func startBrightnessPolling() {
        // 1Hz is plenty: brightness changes via the OS only when the user
        // taps F1/F2 (and our intercept feeds the HUD synchronously anyway)
        // or when ambient light auto-adjust runs (which itself moves in
        // ~1s steps). Polling at 10Hz used to wake `brightnessSubject`
        // 36,000 times an hour on an idle MacBook, every tick paying the
        // DisplayServices private-framework call cost.
        brightnessTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.pollBrightnessChanges()
            }
        }
    }
    
    private func stopBrightnessPolling() {
        brightnessTimer?.invalidate()
        brightnessTimer = nil
    }
    
    private func pollBrightnessChanges() async {
        let currentBrightness = await getCurrentBrightness()

        // Only emit when something actually changed. The previous version
        // republished the same value every tick, waking every downstream
        // subscriber (notch HUD, settings preview, etc.) and forcing them
        // to do their own dedupe. 0.001 epsilon because the brightness
        // backend can return floating-point noise around an unchanged
        // value when read from polled timers.
        if abs(currentBrightness - lastReportedBrightness) > 0.001 {
            lastReportedBrightness = currentBrightness
            brightnessSubject.send(currentBrightness)
            await MainActor.run {
                delegate?.brightnessDidChange(to: currentBrightness)
            }
        }
    }

    /// Last value pushed through `brightnessSubject` — used by the dedupe
    /// guard in `pollBrightnessChanges`. Sentinel of -1 ensures the first
    /// reading after `startMonitoring` always fires (no real brightness
    /// can be negative).
    private var lastReportedBrightness: Float = -1
    
    private func releaseDisplayServices() {
        for service in displayServices {
            IOObjectRelease(service)
        }
        displayServices.removeAll()
    }
    
    // The three sync-wrapper convenience methods that used to live here
    // (`startMonitoring()`, `stopMonitoring()`, `setBrightness(_:)` with
    // no `await`) were removed. They had the same names as the async
    // protocol methods and quietly spawned `Task { try? await … }`,
    // which made every external `monitor.startMonitoring()` call a
    // fire-and-forget coin flip — caller wasn't sure whether they were
    // hitting the sync wrapper or the async original. Grep across the
    // codebase confirmed zero callers depended on the sync forms.

    deinit {
        // Inlined cleanup — see the class doc-comment. Calling the
        // @MainActor methods stopBrightnessPolling()/releaseDisplayServices()
        // from this nonisolated deinit is a compile error; touching the
        // stored properties directly is allowed and the C calls are
        // thread-safe.
        brightnessTimer?.invalidate()
        for service in displayServices {
            IOObjectRelease(service)
        }
    }
}

// MARK: - IOKit Extensions

private extension BrightnessMonitorService {
    
    func getDisplayInfo(for service: io_service_t) -> DisplayInfo? {
        var displayInfo = DisplayInfo()

        if IORegistryEntryCreateCFProperty(service, "IODisplayEDID" as CFString, kCFAllocatorDefault, 0) != nil {
            displayInfo.name = "Display"
        }

        if let mainDisplayRef = IORegistryEntryCreateCFProperty(service, "IODisplayIsMain" as CFString, kCFAllocatorDefault, 0) {
            let value = mainDisplayRef.takeRetainedValue()
            if let number = value as? NSNumber {
                displayInfo.isMainDisplay = number.boolValue
            }
        }

        return displayInfo
    }
}

// MARK: - Supporting Types

struct DisplayInfo {
    var name: String = "Unknown Display"
    var isMainDisplay: Bool = false
    var supportsBacklight: Bool = false
}