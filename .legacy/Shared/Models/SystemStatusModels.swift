//
//  SystemStatusModels.swift
//  SmartEdge
//

import Foundation

/// Comprehensive system status information
struct SystemStatus: Equatable {
    let battery: BatteryInfo
    let bluetooth: BluetoothStatus
    let power: PowerStatus
    let thermal: ThermalStatus
    let lastUpdated: Date
    
    init(
        battery: BatteryInfo = BatteryInfo(),
        bluetooth: BluetoothStatus = BluetoothStatus(),
        power: PowerStatus = PowerStatus(),
        thermal: ThermalStatus = ThermalStatus(),
        lastUpdated: Date = Date()
    ) {
        self.battery = battery
        self.bluetooth = bluetooth
        self.power = power
        self.thermal = thermal
        self.lastUpdated = lastUpdated
    }
    
    /// Overall system health indicator
    var systemHealth: SystemHealthLevel {
        var issues: [SystemHealthIssue] = []
        
        if battery.isCritical {
            issues.append(.batteryCritical)
        } else if battery.isLow {
            issues.append(.batteryLow)
        }
        
        if thermal.isOverheating {
            issues.append(.overheating)
        } else if thermal.isWarm {
            issues.append(.thermal)
        }
        
        if power.isPowerSaveModeEnabled {
            issues.append(.powerSaveMode)
        }
        
        switch issues.count {
        case 0: return .excellent
        case 1: return .good
        case 2: return .fair
        default: return .poor
        }
    }
    
    /// Critical alerts that need immediate attention
    var criticalAlerts: [SystemAlert] {
        var alerts: [SystemAlert] = []
        
        if battery.isCritical {
            alerts.append(.batteryCritical(level: battery.levelPercentage))
        }
        
        if thermal.isOverheating {
            alerts.append(.overheating(temperature: thermal.currentTemperature))
        }
        
        if power.isLowPowerModeEnabled {
            alerts.append(.lowPowerMode)
        }
        
        return alerts
    }
}

/// Bluetooth system status
struct BluetoothStatus: Equatable {
    let isEnabled: Bool
    let connectedDevicesCount: Int
    let primaryAudioDevice: BluetoothDevice?
    let primaryInputDevice: BluetoothDevice?
    let lastUpdated: Date
    
    init(
        isEnabled: Bool = false,
        connectedDevicesCount: Int = 0,
        primaryAudioDevice: BluetoothDevice? = nil,
        primaryInputDevice: BluetoothDevice? = nil,
        lastUpdated: Date = Date()
    ) {
        self.isEnabled = isEnabled
        self.connectedDevicesCount = connectedDevicesCount
        self.primaryAudioDevice = primaryAudioDevice
        self.primaryInputDevice = primaryInputDevice
        self.lastUpdated = lastUpdated
    }
    
    /// Quick status description
    var statusDescription: String {
        if !isEnabled {
            return "Bluetooth Off"
        } else if connectedDevicesCount == 0 {
            return "No Devices"
        } else if connectedDevicesCount == 1 {
            return "1 Device"
        } else {
            return "\(connectedDevicesCount) Devices"
        }
    }
    
    /// Icon representation
    var iconName: String {
        if !isEnabled {
            return "bluetooth.slash"
        } else if connectedDevicesCount > 0 {
            return "bluetooth.fill"
        } else {
            return "bluetooth"
        }
    }
}

/// Power management status
struct PowerStatus: Equatable {
    let adapterConnected: Bool
    let adapterType: PowerAdapterType
    let isPowerSaveModeEnabled: Bool
    let thermalPressure: ThermalPressureLevel
    let systemLoadAverage: Double
    let lastUpdated: Date
    
    init(
        adapterConnected: Bool = false,
        adapterType: PowerAdapterType = .unknown,
        isPowerSaveModeEnabled: Bool = false,
        thermalPressure: ThermalPressureLevel = .nominal,
        systemLoadAverage: Double = 0.0,
        lastUpdated: Date = Date()
    ) {
        self.adapterConnected = adapterConnected
        self.adapterType = adapterType
        self.isPowerSaveModeEnabled = isPowerSaveModeEnabled
        self.thermalPressure = thermalPressure
        self.systemLoadAverage = systemLoadAverage
        self.lastUpdated = lastUpdated
    }
    
    enum PowerAdapterType: String, CaseIterable {
        case magsafe = "MagSafe"
        case usbc = "USB-C"
        case lightning = "Lightning"
        case unknown = "Unknown"
        
        var iconName: String {
            switch self {
            case .magsafe: return "cable.connector"
            case .usbc: return "cable.connector"
            case .lightning: return "cable.connector"
            case .unknown: return "bolt"
            }
        }
    }
    
    enum ThermalPressureLevel: String, CaseIterable {
        case nominal = "Nominal"
        case moderate = "Moderate"
        case heavy = "Heavy"
        case trapping = "Trapping"
        
        var color: String {
            switch self {
            case .nominal: return "green"
            case .moderate: return "yellow"
            case .heavy: return "orange"
            case .trapping: return "red"
            }
        }
    }
}

/// Thermal status information
struct ThermalStatus: Equatable {
    let currentTemperature: Double?     // in Celsius
    let maxTemperature: Double?
    let fanSpeed: Int?                  // RPM
    let thermalPressure: PowerStatus.ThermalPressureLevel
    let cpuThrottling: Bool
    let lastUpdated: Date
    
    init(
        currentTemperature: Double? = nil,
        maxTemperature: Double? = nil,
        fanSpeed: Int? = nil,
        thermalPressure: PowerStatus.ThermalPressureLevel = .nominal,
        cpuThrottling: Bool = false,
        lastUpdated: Date = Date()
    ) {
        self.currentTemperature = currentTemperature
        self.maxTemperature = maxTemperature
        self.fanSpeed = fanSpeed
        self.thermalPressure = thermalPressure
        self.cpuThrottling = cpuThrottling
        self.lastUpdated = lastUpdated
    }
    
    /// Whether system is overheating
    var isOverheating: Bool {
        return thermalPressure == .trapping || cpuThrottling
    }
    
    /// Whether system is running warm
    var isWarm: Bool {
        return thermalPressure == .heavy || thermalPressure == .moderate
    }
    
    /// Temperature status description
    var temperatureDescription: String? {
        guard let temp = currentTemperature else { return nil }
        return String(format: "%.1f°C", temp)
    }
    
    /// Fan speed description
    var fanSpeedDescription: String? {
        guard let speed = fanSpeed else { return nil }
        return "\(speed) RPM"
    }
}

/// System health levels
enum SystemHealthLevel: String, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    
    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "green"
        case .fair: return "yellow"
        case .poor: return "red"
        }
    }
    
    var iconName: String {
        switch self {
        case .excellent: return "checkmark.circle.fill"
        case .good: return "checkmark.circle"
        case .fair: return "exclamationmark.triangle"
        case .poor: return "xmark.circle.fill"
        }
    }
    
    var description: String {
        switch self {
        case .excellent: return "System running optimally"
        case .good: return "System running well"
        case .fair: return "System has minor issues"
        case .poor: return "System needs attention"
        }
    }
}

/// Health issues that affect system performance
enum SystemHealthIssue: String, CaseIterable {
    case batteryCritical = "Battery Critical"
    case batteryLow = "Battery Low"
    case overheating = "Overheating"
    case thermal = "High Temperature"
    case powerSaveMode = "Power Save Mode"
    case bluetoothIssues = "Bluetooth Issues"
    case memoryPressure = "Memory Pressure"
    case diskSpace = "Low Disk Space"
    
    var severity: AlertSeverity {
        switch self {
        case .batteryCritical, .overheating:
            return .critical
        case .batteryLow, .thermal, .memoryPressure:
            return .warning
        case .powerSaveMode, .bluetoothIssues, .diskSpace:
            return .info
        }
    }
}

/// System alerts for critical issues
enum SystemAlert: Equatable {
    case batteryCritical(level: Int)
    case overheating(temperature: Double?)
    case lowPowerMode
    case bluetoothConnectionLost(deviceName: String)
    case memoryPressure(usage: Double)
    
    var title: String {
        switch self {
        case .batteryCritical(let level):
            return "Battery Critical (\(level)%)"
        case .overheating:
            return "System Overheating"
        case .lowPowerMode:
            return "Low Power Mode Active"
        case .bluetoothConnectionLost(let deviceName):
            return "Bluetooth Device Disconnected"
        case .memoryPressure:
            return "High Memory Usage"
        }
    }
    
    var message: String {
        switch self {
        case .batteryCritical(let level):
            return "Battery level is critically low at \(level)%. Please connect a power adapter."
        case .overheating(let temperature):
            if let temp = temperature {
                return "System temperature is \(String(format: "%.1f", temp))°C. Performance may be reduced."
            } else {
                return "System is overheating. Performance may be reduced."
            }
        case .lowPowerMode:
            return "Low Power Mode is enabled to extend battery life."
        case .bluetoothConnectionLost(let deviceName):
            return "\(deviceName) has been disconnected."
        case .memoryPressure(let usage):
            return "Memory usage is \(Int(usage * 100))%. Consider closing some applications."
        }
    }
    
    var severity: AlertSeverity {
        switch self {
        case .batteryCritical, .overheating:
            return .critical
        case .memoryPressure:
            return .warning
        case .lowPowerMode, .bluetoothConnectionLost:
            return .info
        }
    }
    
    var actionable: Bool {
        switch self {
        case .batteryCritical, .overheating, .memoryPressure:
            return true
        case .lowPowerMode, .bluetoothConnectionLost:
            return false
        }
    }
}

/// Alert severity levels
enum AlertSeverity: String, CaseIterable {
    case critical = "Critical"
    case warning = "Warning"
    case info = "Info"
    
    var color: String {
        switch self {
        case .critical: return "red"
        case .warning: return "orange"
        case .info: return "blue"
        }
    }
    
    var iconName: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.triangle"
        case .info: return "info.circle"
        }
    }
}

/// System monitoring preferences
struct SystemMonitoringPreferences: Codable, Equatable {
    let batteryMonitoringEnabled: Bool
    let bluetoothMonitoringEnabled: Bool
    let thermalMonitoringEnabled: Bool
    let lowBatteryThreshold: Double         // 0.0 - 1.0
    let criticalBatteryThreshold: Double    // 0.0 - 1.0
    let updateInterval: TimeInterval        // in seconds
    let enableNotifications: Bool
    let quietHoursEnabled: Bool
    let quietHoursStart: Date
    let quietHoursEnd: Date
    
    static let `default` = SystemMonitoringPreferences(
        batteryMonitoringEnabled: true,
        bluetoothMonitoringEnabled: true,
        thermalMonitoringEnabled: true,
        lowBatteryThreshold: 0.2,
        criticalBatteryThreshold: 0.05,
        updateInterval: 10.0,
        enableNotifications: true,
        quietHoursEnabled: false,
        quietHoursStart: Calendar.current.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date(),
        quietHoursEnd: Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    )
}

/// System monitoring statistics
struct SystemMonitoringStats: Equatable {
    let monitoringStartTime: Date
    let totalUpdates: Int
    let lastUpdateTime: Date
    let averageUpdateInterval: TimeInterval
    let alertsGenerated: Int
    let criticalAlertsGenerated: Int
    
    var uptimeFormatted: String {
        let uptime = Date().timeIntervalSince(monitoringStartTime)
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    var updatesPerHour: Double {
        let uptime = Date().timeIntervalSince(monitoringStartTime) / 3600
        return uptime > 0 ? Double(totalUpdates) / uptime : 0
    }
}