//
//  BatteryServiceProtocol.swift
//  SmartEdge
//

import Foundation
import Combine

/// Protocol defining the interface for battery monitoring services
@MainActor
protocol BatteryServiceProtocol: ObservableObject {
    /// Current battery information
    var batteryInfo: BatteryInfo { get }
    
    /// Current battery level (0.0 - 1.0)
    var batteryLevel: Double { get }
    
    /// Whether the device is currently charging
    var isCharging: Bool { get }
    
    /// Estimated time remaining for current operation (charging or discharging)
    var timeRemaining: TimeInterval { get }
    
    /// Whether a power adapter is connected
    var isPluggedIn: Bool { get }
    
    /// Publisher for battery information updates
    var batteryInfoPublisher: Published<BatteryInfo>.Publisher { get }
    
    /// Start monitoring battery status
    func startMonitoring() async
    
    /// Stop monitoring battery status
    func stopMonitoring() async
    
    /// Force refresh of battery information
    func refreshBatteryInfo() async
    
    /// Get battery health information
    func getBatteryHealth() async -> BatteryHealth?
    
    /// Check if battery is in low power mode
    func isLowPowerModeEnabled() async -> Bool
}

/// Comprehensive battery information structure
struct BatteryInfo: Equatable {
    let level: Double                    // 0.0 - 1.0
    let isCharging: Bool
    let isPluggedIn: Bool
    let timeRemaining: TimeInterval      // in seconds, 0 if unknown
    let temperature: Double?             // in Celsius
    let powerSourceType: PowerSourceType
    let chargingState: ChargingState
    let lastUpdated: Date
    
    init(
        level: Double = 0.0,
        isCharging: Bool = false,
        isPluggedIn: Bool = false,
        timeRemaining: TimeInterval = 0,
        temperature: Double? = nil,
        powerSourceType: PowerSourceType = .battery,
        chargingState: ChargingState = .unknown,
        lastUpdated: Date = Date()
    ) {
        self.level = max(0.0, min(1.0, level))
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.timeRemaining = timeRemaining
        self.temperature = temperature
        self.powerSourceType = powerSourceType
        self.chargingState = chargingState
        self.lastUpdated = lastUpdated
    }
    
    /// User-friendly battery level percentage
    var levelPercentage: Int {
        return Int(round(level * 100))
    }
    
    /// Formatted time remaining string
    var timeRemainingFormatted: String {
        guard timeRemaining > 0 else { return "Calculating..." }
        
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60
        
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes))"
        } else {
            return "\(minutes) min"
        }
    }
    
    /// Battery status icon name
    var iconName: String {
        if isCharging {
            if level >= 0.8 { return "battery.100.bolt" }
            else if level >= 0.5 { return "battery.75.bolt" }
            else if level >= 0.25 { return "battery.50.bolt" }
            else { return "battery.25.bolt" }
        } else {
            if level >= 0.8 { return "battery.100" }
            else if level >= 0.5 { return "battery.75" }
            else if level >= 0.25 { return "battery.50" }
            else { return "battery.25" }
        }
    }
    
    /// Whether battery level is considered low (< 20%)
    var isLow: Bool {
        return level < 0.2
    }
    
    /// Whether battery level is critical (< 5%)
    var isCritical: Bool {
        return level < 0.05
    }
}

/// Battery health information
struct BatteryHealth: Equatable {
    let maxCapacity: Int                 // mAh
    let currentCapacity: Int             // mAh
    let cycleCount: Int
    let healthPercentage: Double         // 0.0 - 1.0
    let conditionState: BatteryCondition
    let manufactureDate: Date?
    let serialNumber: String?
    
    var healthPercentageFormatted: String {
        return "\(Int(round(healthPercentage * 100)))%"
    }
    
    var isHealthGood: Bool {
        return healthPercentage >= 0.8
    }
}

/// Power source types
enum PowerSourceType: String, CaseIterable {
    case battery = "Battery"
    case acPower = "AC Power"
    case ups = "UPS"
    case unknown = "Unknown"
    
    var iconName: String {
        switch self {
        case .battery: return "battery.100"
        case .acPower: return "bolt.fill"
        case .ups: return "battery.100.bolt"
        case .unknown: return "questionmark.circle"
        }
    }
}

/// Charging states
enum ChargingState: String, CaseIterable {
    case charging = "Charging"
    case discharging = "Discharging"
    case fullyCharged = "Fully Charged"
    case notCharging = "Not Charging"
    case unknown = "Unknown"
    
    var iconName: String {
        switch self {
        case .charging: return "bolt.fill"
        case .discharging: return "battery.100"
        case .fullyCharged: return "battery.100.bolt"
        case .notCharging: return "battery.100"
        case .unknown: return "questionmark"
        }
    }
}

/// Battery condition states
enum BatteryCondition: String, CaseIterable {
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case checkBattery = "Check Battery"
    case replace = "Replace Battery"
    case unknown = "Unknown"
    
    var color: String {
        switch self {
        case .good: return "green"
        case .fair: return "yellow"
        case .poor: return "orange"
        case .checkBattery: return "orange"
        case .replace: return "red"
        case .unknown: return "gray"
        }
    }
}

/// Battery monitoring errors
enum BatteryServiceError: LocalizedError {
    case permissionDenied
    case systemUnavailable
    case batteryNotFound
    case monitoringFailed
    case ioKitError(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permission denied to access battery information"
        case .systemUnavailable:
            return "Battery monitoring is not available on this system"
        case .batteryNotFound:
            return "No battery found on this device"
        case .monitoringFailed:
            return "Failed to start battery monitoring"
        case .ioKitError(let message):
            return "IOKit error: \(message)"
        }
    }
}