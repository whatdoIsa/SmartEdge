//
//  BluetoothServiceProtocol.swift
//  SmartEdge
//

import Foundation
import CoreBluetooth
import Combine

/// Protocol defining the interface for Bluetooth device monitoring services
@MainActor
protocol BluetoothServiceProtocol: ObservableObject {
    /// Current Bluetooth adapter state
    var bluetoothState: CBManagerState { get }
    
    /// List of currently connected devices
    var connectedDevices: [BluetoothDevice] { get }
    
    /// List of available/discoverable devices
    var availableDevices: [BluetoothDevice] { get }
    
    /// Whether the service is currently scanning for devices
    var isScanning: Bool { get }
    
    /// Whether Bluetooth is enabled and available
    var isBluetoothAvailable: Bool { get }
    
    /// Publisher for connected devices updates
    var connectedDevicesPublisher: Published<[BluetoothDevice]>.Publisher { get }
    
    /// Publisher for Bluetooth state changes
    var bluetoothStatePublisher: Published<CBManagerState>.Publisher { get }
    
    /// Start scanning for available devices
    func startScanning() async
    
    /// Stop scanning for devices
    func stopScanning() async
    
    /// Connect to a specific device
    func connect(to device: BluetoothDevice) async throws
    
    /// Disconnect from a specific device
    func disconnect(from device: BluetoothDevice) async throws
    
    /// Refresh the list of connected devices
    func refreshConnectedDevices() async
    
    /// Get battery level for a specific device (if supported)
    func getBatteryLevel(for device: BluetoothDevice) async -> Double?
    
    /// Get signal strength (RSSI) for a connected device
    func getSignalStrength(for device: BluetoothDevice) async -> Int?
    
    /// Check if a device supports battery level reporting
    func supportsBatteryLevel(_ device: BluetoothDevice) async -> Bool
}

/// Bluetooth device information
struct BluetoothDevice: Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let rssi: Int?                      // Signal strength in dBm
    let isConnected: Bool
    let deviceType: DeviceType
    let batteryLevel: Double?           // 0.0 - 1.0, nil if not supported
    let lastSeen: Date
    let manufacturerData: Data?
    let serviceUUIDs: [CBUUID]
    let isPaired: Bool
    
    init(
        id: UUID,
        name: String,
        rssi: Int? = nil,
        isConnected: Bool = false,
        deviceType: DeviceType = .unknown,
        batteryLevel: Double? = nil,
        lastSeen: Date = Date(),
        manufacturerData: Data? = nil,
        serviceUUIDs: [CBUUID] = [],
        isPaired: Bool = false
    ) {
        self.id = id
        self.name = name.isEmpty ? "Unknown Device" : name
        self.rssi = rssi
        self.isConnected = isConnected
        self.deviceType = deviceType
        self.batteryLevel = batteryLevel
        self.lastSeen = lastSeen
        self.manufacturerData = manufacturerData
        self.serviceUUIDs = serviceUUIDs
        self.isPaired = isPaired
    }
    
    /// Device type classification
    enum DeviceType: String, CaseIterable {
        case headphones = "Headphones"
        case speaker = "Speaker"
        case mouse = "Mouse"
        case keyboard = "Keyboard"
        case trackpad = "Trackpad"
        case phone = "Phone"
        case computer = "Computer"
        case watch = "Watch"
        case tablet = "Tablet"
        case gameController = "Game Controller"
        case healthDevice = "Health Device"
        case unknown = "Unknown"
        
        var iconName: String {
            switch self {
            case .headphones: return "headphones"
            case .speaker: return "speaker.2.fill"
            case .mouse: return "computermouse.fill"
            case .keyboard: return "keyboard.fill"
            case .trackpad: return "trackpad.fill"
            case .phone: return "iphone"
            case .computer: return "macbook"
            case .watch: return "applewatch"
            case .tablet: return "ipad"
            case .gameController: return "gamecontroller.fill"
            case .healthDevice: return "heart.fill"
            case .unknown: return "antenna.radiowaves.left.and.right"
            }
        }
        
        var category: DeviceCategory {
            switch self {
            case .headphones, .speaker:
                return .audio
            case .mouse, .keyboard, .trackpad, .gameController:
                return .input
            case .phone, .computer, .tablet, .watch:
                return .computing
            case .healthDevice:
                return .health
            case .unknown:
                return .other
            }
        }
    }
    
    /// Device categories for grouping
    enum DeviceCategory: String, CaseIterable {
        case audio = "Audio"
        case input = "Input Devices"
        case computing = "Computing"
        case health = "Health"
        case other = "Other"
        
        var iconName: String {
            switch self {
            case .audio: return "speaker.wave.3.fill"
            case .input: return "keyboard.fill"
            case .computing: return "desktopcomputer"
            case .health: return "heart.fill"
            case .other: return "ellipsis.circle.fill"
            }
        }
    }
    
    /// Battery level percentage (0-100)
    var batteryPercentage: Int? {
        guard let batteryLevel = batteryLevel else { return nil }
        return Int(round(batteryLevel * 100))
    }
    
    /// Signal strength description
    var signalStrengthDescription: String {
        guard let rssi = rssi else { return "Unknown" }
        
        switch rssi {
        case -30...0: return "Excellent"
        case -50...(-31): return "Good"
        case -70...(-51): return "Fair"
        case -90...(-71): return "Poor"
        default: return "Very Poor"
        }
    }
    
    /// Signal strength icon
    var signalStrengthIcon: String {
        guard let rssi = rssi else { return "wifi.slash" }
        
        switch rssi {
        case -30...0: return "wifi"
        case -50...(-31): return "wifi"
        case -70...(-51): return "wifi"
        case -90...(-71): return "wifi"
        default: return "wifi.slash"
        }
    }
    
    /// Whether device supports battery level reporting
    var supportsBattery: Bool {
        return [.headphones, .mouse, .keyboard, .trackpad, .gameController].contains(deviceType)
    }
    
    /// Time since last seen formatted
    var lastSeenFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastSeen, relativeTo: Date())
    }
    
    /// Connection status with details
    var connectionStatus: ConnectionStatus {
        if isConnected {
            return .connected
        } else if isPaired {
            return .paired
        } else {
            return .available
        }
    }
    
    enum ConnectionStatus {
        case connected
        case paired
        case available
        
        var description: String {
            switch self {
            case .connected: return "Connected"
            case .paired: return "Paired"
            case .available: return "Available"
            }
        }
        
        var color: String {
            switch self {
            case .connected: return "green"
            case .paired: return "blue"
            case .available: return "gray"
            }
        }
    }
}

/// Bluetooth scanning options
struct BluetoothScanOptions {
    let allowDuplicates: Bool
    let scanDuration: TimeInterval
    let serviceUUIDs: [CBUUID]?
    
    static let `default` = BluetoothScanOptions(
        allowDuplicates: false,
        scanDuration: 30.0,
        serviceUUIDs: nil
    )
    
    static let quick = BluetoothScanOptions(
        allowDuplicates: false,
        scanDuration: 10.0,
        serviceUUIDs: nil
    )
    
    static let comprehensive = BluetoothScanOptions(
        allowDuplicates: true,
        scanDuration: 60.0,
        serviceUUIDs: nil
    )
}

/// Bluetooth service statistics
struct BluetoothServiceStats {
    let totalDevicesDiscovered: Int
    let currentConnections: Int
    let scanDuration: TimeInterval
    let lastScanTime: Date?
    let bluetoothUptime: TimeInterval
    
    var averageDevicesPerScan: Double {
        guard scanDuration > 0 else { return 0 }
        return Double(totalDevicesDiscovered) / (scanDuration / 60.0)
    }
}

/// Bluetooth service errors
enum BluetoothServiceError: LocalizedError {
    case bluetoothUnavailable
    case bluetoothPoweredOff
    case bluetoothUnauthorized
    case bluetoothRestricted
    case deviceNotFound
    case connectionFailed
    case scanningFailed
    case unsupportedFeature
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is not available on this device"
        case .bluetoothPoweredOff:
            return "Bluetooth is turned off. Please enable it in System Settings."
        case .bluetoothUnauthorized:
            return "App is not authorized to use Bluetooth"
        case .bluetoothRestricted:
            return "Bluetooth access is restricted"
        case .deviceNotFound:
            return "Bluetooth device not found"
        case .connectionFailed:
            return "Failed to connect to device"
        case .scanningFailed:
            return "Failed to scan for devices"
        case .unsupportedFeature:
            return "This feature is not supported by the device"
        case .timeout:
            return "Operation timed out"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .bluetoothPoweredOff:
            return "Turn on Bluetooth in System Settings > Bluetooth"
        case .bluetoothUnauthorized:
            return "Grant Bluetooth permission in System Settings > Privacy & Security > Bluetooth"
        case .bluetoothRestricted:
            return "Contact your system administrator"
        case .deviceNotFound:
            return "Make sure the device is discoverable and try again"
        case .connectionFailed:
            return "Move closer to the device and try again"
        default:
            return "Try again later"
        }
    }
}