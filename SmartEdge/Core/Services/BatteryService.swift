import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import Combine
import os

@MainActor
final class BatteryService: ObservableObject, BatteryServiceProtocol {
    // MARK: - Published Properties (Protocol Conformance)
    
    @Published var batteryInfo: BatteryInfo = BatteryInfo()
    @Published var batteryLevel: Double = 0.0
    @Published var isCharging: Bool = false
    @Published var timeRemaining: TimeInterval = 0
    @Published var isPluggedIn: Bool = false
    
    // MARK: - Protocol Conformance
    
    var batteryInfoPublisher: Published<BatteryInfo>.Publisher {
        $batteryInfo
    }
    
    // MARK: - Properties

    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    nonisolated(unsafe) private var powerSourceRunLoopSource: CFRunLoopSource?
    private let updateInterval: TimeInterval = 5.0
    
    
    // MARK: - Initialization
    
    init() {
        setupBatteryMonitoring()
        Task {
            await startMonitoring()
        }
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    // MARK: - Protocol Implementation
    
    func startMonitoring() async {
        // Idempotent. Without this guard, every caller (`init`, the
        // ServiceContainer wiring, the SystemStatusViewModel mount) would
        // log "stopped" + "started" pairs and momentarily tear down the
        // CFRunLoop power-source notification.
        guard updateTimer == nil else { return }

        setupPowerSourceNotifications()
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateBatteryInfo()
            }
        }
        await updateBatteryInfo()
        AppLogger.battery.info("Battery monitoring started")
    }

    func stopMonitoring() async {
        // Symmetric guard. The previous version always emitted the
        // "stopped" log even when there was nothing to stop, producing
        // the "stopped → started" sequence on every cold launch.
        guard updateTimer != nil else { return }
        updateTimer?.invalidate()
        updateTimer = nil
        await cleanupPowerSourceNotifications()
        AppLogger.battery.info("Battery monitoring stopped")
    }
    
    func refreshBatteryInfo() async {
        await updateBatteryInfo()
    }
    
    func getBatteryHealth() async -> BatteryHealth? {
        return await withCheckedContinuation { continuation in
            Task.detached { [weak self] in
                let health = self?.fetchBatteryHealth()
                continuation.resume(returning: health)
            }
        }
    }
    
    func isLowPowerModeEnabled() async -> Bool {
        return await withCheckedContinuation { continuation in
            Task.detached { [weak self] in
                let isEnabled = self?.checkLowPowerMode() ?? false
                continuation.resume(returning: isEnabled)
            }
        }
    }
    
    
    // MARK: - Private Methods
    
    private func setupBatteryMonitoring() {
        // Legacy setup - keeping for compatibility
    }
    
    private func setupPowerSourceNotifications() {
        let runLoop = CFRunLoopGetMain()
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            
            Task { @MainActor in
                await service.updateBatteryInfo()
            }
        }
        
        powerSourceRunLoopSource = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue()
        
        if let source = powerSourceRunLoopSource {
            CFRunLoopAddSource(runLoop, source, CFRunLoopMode.defaultMode)
        }
    }
    
    private func cleanupPowerSourceNotifications() async {
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.defaultMode)
            powerSourceRunLoopSource = nil
        }
    }
    
    private func updateBatteryInfo() async {
        let info = await fetchBatteryInfo()
        
        batteryInfo = info
        batteryLevel = info.level
        isCharging = info.isCharging
        timeRemaining = info.timeRemaining
        isPluggedIn = info.isPluggedIn
    }
    
    private func fetchBatteryInfo() async -> BatteryInfo {
        return await withCheckedContinuation { continuation in
            Task.detached {
                // Get power source information using IOKit
                guard let powerSources = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                      let sourcesArray = IOPSCopyPowerSourcesList(powerSources)?.takeRetainedValue() as? [CFTypeRef],
                      !sourcesArray.isEmpty else {
                    continuation.resume(returning: BatteryInfo())
                    return
                }
                
                // Find the first battery source
                var batterySource: CFTypeRef?
                for source in sourcesArray {
                    if let sourceInfo = IOPSGetPowerSourceDescription(powerSources, source)?.takeUnretainedValue() as? [String: Any],
                       let type = sourceInfo[kIOPSTypeKey] as? String,
                       type == kIOPSInternalBatteryType {
                        batterySource = source
                        break
                    }
                }
                
                guard let source = batterySource,
                      let sourceInfo = IOPSGetPowerSourceDescription(powerSources, source)?.takeUnretainedValue() as? [String: Any] else {
                    continuation.resume(returning: BatteryInfo())
                    return
                }
                
                // Extract battery information
                let currentCapacity = sourceInfo[kIOPSCurrentCapacityKey] as? Int ?? 0
                let maxCapacity = sourceInfo[kIOPSMaxCapacityKey] as? Int ?? 100
                let isCharging = sourceInfo[kIOPSIsChargingKey] as? Bool ?? false
                let isPluggedIn = sourceInfo[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
                let timeToEmpty = sourceInfo[kIOPSTimeToEmptyKey] as? Int ?? 0
                let timeToFull = sourceInfo[kIOPSTimeToFullChargeKey] as? Int ?? 0
                let temperature = sourceInfo["Temperature"] as? Double
                
                // Calculate level
                let level = maxCapacity > 0 ? Double(currentCapacity) / Double(maxCapacity) : 0.0
                
                // Calculate time remaining
                let timeRemaining: TimeInterval
                if isCharging && timeToFull > 0 {
                    timeRemaining = TimeInterval(timeToFull * 60)
                } else if !isCharging && timeToEmpty > 0 {
                    timeRemaining = TimeInterval(timeToEmpty * 60)
                } else {
                    timeRemaining = 0
                }
                
                // Determine power source type
                let powerSourceType: PowerSourceType = isPluggedIn ? .acPower : .battery
                
                // Determine charging state
                let chargingState: ChargingState
                if isCharging {
                    chargingState = .charging
                } else if isPluggedIn && level >= 0.95 {
                    chargingState = .fullyCharged
                } else if isPluggedIn {
                    chargingState = .notCharging
                } else {
                    chargingState = .discharging
                }
                
                let batteryInfo = BatteryInfo(
                    level: level,
                    isCharging: isCharging,
                    isPluggedIn: isPluggedIn,
                    timeRemaining: timeRemaining,
                    temperature: temperature,
                    powerSourceType: powerSourceType,
                    chargingState: chargingState,
                    lastUpdated: Date()
                )
                
                continuation.resume(returning: batteryInfo)
            }
        }
    }
    
    nonisolated private func fetchBatteryHealth() -> BatteryHealth? {
        // This requires more advanced IOKit usage to access battery registry entries
        // Would need to access IORegistry for detailed battery information
        // For now, returning nil as this requires lower-level system access
        return nil
    }
    
    nonisolated private func checkLowPowerMode() -> Bool {
        // Check if Low Power Mode is enabled
        // This typically requires system-level APIs that might not be accessible
        // in a sandboxed app without special entitlements
        return false
    }
}