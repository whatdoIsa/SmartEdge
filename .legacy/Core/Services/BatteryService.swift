import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import Combine

// Legacy delegate for backward compatibility
protocol BatteryServiceDelegate: AnyObject {
    func batteryService(_ service: BatteryService, didUpdateBatteryInfo info: LegacyBatteryInfo)
}

@MainActor
final class BatteryService: ObservableObject, BatteryServiceProtocol {
    // MARK: - Published Properties (Protocol Conformance)
    
    @Published var batteryInfo: BatteryInfo = BatteryInfo()
    @Published var batteryLevel: Double = 0.0
    @Published var isCharging: Bool = false
    @Published var timeRemaining: TimeInterval = 0
    @Published var isPluggedIn: Bool = false
    
    // MARK: - Protocol Conformance
    
    nonisolated var batteryInfoPublisher: Published<BatteryInfo>.Publisher {
        $batteryInfo
    }
    
    // MARK: - Properties
    
    weak var delegate: BatteryServiceDelegate?
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private let updateInterval: TimeInterval = 5.0
    
    // MARK: - Legacy Types for Backward Compatibility
    
    struct LegacyBatteryInfo {
        let level: Double
        let isCharging: Bool
        let timeRemaining: TimeInterval
        let isPluggedIn: Bool
        let temperature: Double?
        let cycleCount: Int?
        let maxCapacity: Int?
        let currentCapacity: Int?
        
        init(
            level: Double = 0.0,
            isCharging: Bool = false,
            timeRemaining: TimeInterval = 0,
            isPluggedIn: Bool = false,
            temperature: Double? = nil,
            cycleCount: Int? = nil,
            maxCapacity: Int? = nil,
            currentCapacity: Int? = nil
        ) {
            self.level = level
            self.isCharging = isCharging
            self.timeRemaining = timeRemaining
            self.isPluggedIn = isPluggedIn
            self.temperature = temperature
            self.cycleCount = cycleCount
            self.maxCapacity = maxCapacity
            self.currentCapacity = currentCapacity
        }
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupBatteryMonitoring()
        Task {
            await startMonitoring()
        }
    }
    
    deinit {
        Task { @MainActor in
            await stopMonitoring()
        }
    }
    
    // MARK: - Protocol Implementation
    
    func startMonitoring() async {
        await stopMonitoring() // Stop any existing monitoring
        
        setupPowerSourceNotifications()
        
        // Start periodic updates
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateBatteryInfo()
            }
        }
        
        // Initial update
        await updateBatteryInfo()
        print("Battery monitoring started")
    }
    
    func stopMonitoring() async {
        updateTimer?.invalidate()
        updateTimer = nil
        cleanupPowerSourceNotifications()
        print("Battery monitoring stopped")
    }
    
    func refreshBatteryInfo() async {
        await updateBatteryInfo()
    }
    
    func getBatteryHealth() async -> BatteryHealth? {
        return await withCheckedContinuation { continuation in
            Task.detached {
                let health = self.fetchBatteryHealth()
                continuation.resume(returning: health)
            }
        }
    }
    
    func isLowPowerModeEnabled() async -> Bool {
        return await withCheckedContinuation { continuation in
            Task.detached {
                let isEnabled = self.checkLowPowerMode()
                continuation.resume(returning: isEnabled)
            }
        }
    }
    
    // MARK: - Legacy Methods (for backward compatibility)
    
    func startMonitoring() {
        Task {
            await startMonitoring()
        }
    }
    
    func stopMonitoring() {
        Task {
            await stopMonitoring()
        }
    }
    
    func refreshBatteryInfo() {
        Task {
            await refreshBatteryInfo()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupBatteryMonitoring() {
        // Legacy setup - keeping for compatibility
    }
    
    private func setupPowerSourceNotifications() {
        let runLoop = CFRunLoopGetCurrent()
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
    
    private func cleanupPowerSourceNotifications() {
        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode)
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
        
        // Update legacy delegate
        let legacyInfo = LegacyBatteryInfo(
            level: info.level,
            isCharging: info.isCharging,
            timeRemaining: info.timeRemaining,
            isPluggedIn: info.isPluggedIn,
            temperature: info.temperature,
            cycleCount: nil,
            maxCapacity: nil,
            currentCapacity: nil
        )
        
        delegate?.batteryService(self, didUpdateBatteryInfo: legacyInfo)
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
    
    private func fetchBatteryHealth() -> BatteryHealth? {
        // This requires more advanced IOKit usage to access battery registry entries
        // Would need to access IORegistry for detailed battery information
        // For now, returning nil as this requires lower-level system access
        return nil
    }
    
    private func checkLowPowerMode() -> Bool {
        // Check if Low Power Mode is enabled
        // This typically requires system-level APIs that might not be accessible
        // in a sandboxed app without special entitlements
        return false
    }
}