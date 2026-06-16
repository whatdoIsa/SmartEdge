import Foundation
import CoreBluetooth
import Combine

// Legacy delegate for backward compatibility
protocol BluetoothServiceDelegate: AnyObject {
    func bluetoothService(_ service: BluetoothService, didUpdateState state: CBManagerState)
    func bluetoothService(_ service: BluetoothService, didDiscoverDevice device: LegacyBluetoothDevice)
    func bluetoothService(_ service: BluetoothService, didConnectDevice device: LegacyBluetoothDevice)
    func bluetoothService(_ service: BluetoothService, didDisconnectDevice device: LegacyBluetoothDevice)
}

@MainActor
final class BluetoothService: NSObject, ObservableObject, BluetoothServiceProtocol {
    // MARK: - Published Properties (Protocol Conformance)
    
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var connectedDevices: [BluetoothDevice] = []
    @Published var availableDevices: [BluetoothDevice] = []
    @Published var isScanning: Bool = false
    
    // MARK: - Protocol Conformance
    
    var isBluetoothAvailable: Bool {
        return bluetoothState == .poweredOn
    }
    
    nonisolated var connectedDevicesPublisher: Published<[BluetoothDevice]>.Publisher {
        $connectedDevices
    }
    
    nonisolated var bluetoothStatePublisher: Published<CBManagerState>.Publisher {
        $bluetoothState
    }
    
    // MARK: - Properties
    
    weak var delegate: BluetoothServiceDelegate?
    private var centralManager: CBCentralManager?
    private var discoveredPeripherals: [CBPeripheral] = []
    private var cancellables = Set<AnyCancellable>()
    private var scanningTask: Task<Void, Never>?
    private var batteryServiceUUID = CBUUID(string: "180F")
    
    // MARK: - Legacy Types for Backward Compatibility
    
    struct LegacyBluetoothDevice {
        let id: UUID
        let name: String
        let rssi: NSNumber?
        let isConnected: Bool
        let deviceType: DeviceType
        let batteryLevel: Double?
        
        enum DeviceType {
            case headphones
            case speaker
            case mouse
            case keyboard
            case trackpad
            case phone
            case computer
            case unknown
            
            var iconName: String {
                switch self {
                case .headphones: return "headphones"
                case .speaker: return "speaker.2"
                case .mouse: return "computermouse"
                case .keyboard: return "keyboard"
                case .trackpad: return "trackpad"
                case .phone: return "iphone"
                case .computer: return "macbook"
                case .unknown: return "antenna.radiowaves.left.and.right"
                }
            }
        }
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupBluetoothManager()
    }
    
    deinit {
        Task { @MainActor in
            await stopScanning()
        }
    }
    
    // MARK: - Protocol Implementation
    
    func startScanning() async {
        guard bluetoothState == .poweredOn else { 
            throw BluetoothServiceError.bluetoothPoweredOff
        }
        
        await stopScanning() // Stop any existing scanning
        
        isScanning = true
        availableDevices.removeAll()
        discoveredPeripherals.removeAll()
        
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
            CBCentralManagerScanOptionSolicitedServiceUUIDsKey: []
        ]
        
        centralManager?.scanForPeripherals(withServices: nil, options: options)
        
        // Auto-stop scanning after 30 seconds
        scanningTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await stopScanning()
        }
        
        print("Bluetooth scanning started")
    }
    
    func stopScanning() async {
        centralManager?.stopScan()
        isScanning = false
        scanningTask?.cancel()
        scanningTask = nil
        print("Bluetooth scanning stopped")
    }
    
    func connect(to device: BluetoothDevice) async throws {
        guard let peripheral = discoveredPeripherals.first(where: { $0.identifier == device.id }) else {
            throw BluetoothServiceError.deviceNotFound
        }
        
        guard bluetoothState == .poweredOn else {
            throw BluetoothServiceError.bluetoothPoweredOff
        }
        
        centralManager?.connect(peripheral, options: nil)
    }
    
    func disconnect(from device: BluetoothDevice) async throws {
        guard let peripheral = discoveredPeripherals.first(where: { $0.identifier == device.id }) else {
            throw BluetoothServiceError.deviceNotFound
        }
        
        centralManager?.cancelPeripheralConnection(peripheral)
    }
    
    func refreshConnectedDevices() async {
        await updateConnectedDevices()
    }
    
    func getBatteryLevel(for device: BluetoothDevice) async -> Double? {
        guard let peripheral = discoveredPeripherals.first(where: { $0.identifier == device.id }),
              device.supportsBattery else {
            return nil
        }
        
        // This would require connecting to the device and reading battery service
        // For now, return cached value if available
        return device.batteryLevel
    }
    
    func getSignalStrength(for device: BluetoothDevice) async -> Int? {
        guard let peripheral = discoveredPeripherals.first(where: { $0.identifier == device.id }),
              peripheral.state == .connected else {
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            peripheral.readRSSI()
            // Would need to implement peripheral delegate to get actual RSSI
            continuation.resume(returning: device.rssi)
        }
    }
    
    func supportsBatteryLevel(_ device: BluetoothDevice) async -> Bool {
        return device.supportsBattery
    }
    
    // MARK: - Legacy Methods (for backward compatibility)
    
    func startScanning() {
        Task {
            try? await startScanning()
        }
    }
    
    func stopScanning() {
        Task {
            await stopScanning()
        }
    }
    
    func connect(to device: LegacyBluetoothDevice) {
        let bluetoothDevice = convertLegacyToNew(device: device)
        Task {
            try? await connect(to: bluetoothDevice)
        }
    }
    
    func disconnect(from device: LegacyBluetoothDevice) {
        let bluetoothDevice = convertLegacyToNew(device: device)
        Task {
            try? await disconnect(from: bluetoothDevice)
        }
    }
    
    func refreshConnectedDevices() {
        Task {
            await refreshConnectedDevices()
        }
    }
    
    // MARK: - Private Methods
    
    private func setupBluetoothManager() {
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }
    
    private func updateConnectedDevices() async {
        guard let manager = centralManager else { return }
        
        // Get connected peripherals for common service UUIDs
        let serviceUUIDs = [
            CBUUID(string: "180F"), // Battery Service
            CBUUID(string: "1812"), // Human Interface Device
            CBUUID(string: "110B"), // Audio Sink
            CBUUID(string: "110A"), // Audio Source
        ]
        
        let connectedPeripherals = manager.retrieveConnectedPeripherals(withServices: serviceUUIDs)
        
        let devices = connectedPeripherals.compactMap { peripheral -> BluetoothDevice? in
            return createBluetoothDevice(from: peripheral, isConnected: true)
        }
        
        connectedDevices = devices
    }
    
    private func determineDeviceType(from peripheral: CBPeripheral) -> BluetoothDevice.DeviceType {
        guard let name = peripheral.name?.lowercased() else {
            return .unknown
        }
        
        if name.contains("airpods") || name.contains("headphone") || name.contains("beats") || name.contains("earphone") {
            return .headphones
        } else if name.contains("speaker") {
            return .speaker
        } else if name.contains("mouse") {
            return .mouse
        } else if name.contains("keyboard") {
            return .keyboard
        } else if name.contains("trackpad") {
            return .trackpad
        } else if name.contains("iphone") {
            return .phone
        } else if name.contains("mac") {
            return .computer
        } else if name.contains("watch") || name.contains("apple watch") {
            return .watch
        } else if name.contains("ipad") {
            return .tablet
        } else if name.contains("controller") || name.contains("gamepad") {
            return .gameController
        } else {
            return .unknown
        }
    }
    
    private func createBluetoothDevice(from peripheral: CBPeripheral, rssi: NSNumber? = nil, isConnected: Bool = false) -> BluetoothDevice {
        let deviceType = determineDeviceType(from: peripheral)
        
        return BluetoothDevice(
            id: peripheral.identifier,
            name: peripheral.name ?? "Unknown Device",
            rssi: rssi?.intValue,
            isConnected: isConnected,
            deviceType: deviceType,
            batteryLevel: nil, // Would be fetched separately
            lastSeen: Date(),
            manufacturerData: nil,
            serviceUUIDs: peripheral.services?.compactMap { $0.uuid } ?? [],
            isPaired: false // Would need additional API to determine
        )
    }
    
    private func convertLegacyToNew(device: LegacyBluetoothDevice) -> BluetoothDevice {
        let deviceType: BluetoothDevice.DeviceType
        switch device.deviceType {
        case .headphones: deviceType = .headphones
        case .speaker: deviceType = .speaker
        case .mouse: deviceType = .mouse
        case .keyboard: deviceType = .keyboard
        case .trackpad: deviceType = .trackpad
        case .phone: deviceType = .phone
        case .computer: deviceType = .computer
        case .unknown: deviceType = .unknown
        }
        
        return BluetoothDevice(
            id: device.id,
            name: device.name,
            rssi: device.rssi?.intValue,
            isConnected: device.isConnected,
            deviceType: deviceType,
            batteryLevel: device.batteryLevel
        )
    }
    
    private func convertNewToLegacy(device: BluetoothDevice) -> LegacyBluetoothDevice {
        let deviceType: LegacyBluetoothDevice.DeviceType
        switch device.deviceType {
        case .headphones: deviceType = .headphones
        case .speaker: deviceType = .speaker
        case .mouse: deviceType = .mouse
        case .keyboard: deviceType = .keyboard
        case .trackpad: deviceType = .trackpad
        case .phone: deviceType = .phone
        case .computer: deviceType = .computer
        default: deviceType = .unknown
        }
        
        return LegacyBluetoothDevice(
            id: device.id,
            name: device.name,
            rssi: device.rssi as NSNumber?,
            isConnected: device.isConnected,
            deviceType: deviceType,
            batteryLevel: device.batteryLevel
        )
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        delegate?.bluetoothService(self, didUpdateState: central.state)
        
        if central.state == .poweredOn {
            Task {
                await updateConnectedDevices()
            }
        } else if central.state != .poweredOn && isScanning {
            Task {
                await stopScanning()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Avoid duplicates
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
            
            let device = createBluetoothDevice(from: peripheral, rssi: RSSI, isConnected: false)
            availableDevices.append(device)
            
            // Notify legacy delegate
            let legacyDevice = convertNewToLegacy(device: device)
            delegate?.bluetoothService(self, didDiscoverDevice: legacyDevice)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let device = createBluetoothDevice(from: peripheral, isConnected: true)
        
        // Move from available to connected
        availableDevices.removeAll { $0.id == peripheral.identifier }
        
        // Add to connected devices if not already there
        if !connectedDevices.contains(where: { $0.id == peripheral.identifier }) {
            connectedDevices.append(device)
        }
        
        // Set up peripheral delegate for battery readings
        peripheral.delegate = self
        peripheral.discoverServices([batteryServiceUUID])
        
        // Notify legacy delegate
        let legacyDevice = convertNewToLegacy(device: device)
        delegate?.bluetoothService(self, didConnectDevice: legacyDevice)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let device = createBluetoothDevice(from: peripheral)
        
        // Remove from connected devices
        connectedDevices.removeAll { $0.id == peripheral.identifier }
        
        // Add back to available if we were scanning and it's not an error
        if isScanning && error == nil {
            availableDevices.append(device)
        }
        
        // Notify legacy delegate
        let legacyDevice = convertNewToLegacy(device: device)
        delegate?.bluetoothService(self, didDisconnectDevice: legacyDevice)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to \(peripheral.name ?? "unknown device"): \(error?.localizedDescription ?? "Unknown error")")
        
        // Remove from connected devices if somehow there
        connectedDevices.removeAll { $0.id == peripheral.identifier }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        
        peripheral.services?.forEach { service in
            if service.uuid == batteryServiceUUID {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else { return }
        
        if service.uuid == batteryServiceUUID {
            service.characteristics?.forEach { characteristic in
                if characteristic.uuid == CBUUID(string: "2A19") { // Battery Level
                    peripheral.readValue(for: characteristic)
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              characteristic.uuid == CBUUID(string: "2A19"),
              let data = characteristic.value,
              !data.isEmpty else { return }
        
        let batteryLevel = Double(data[0]) / 100.0
        
        // Update the device in connected devices
        if let index = connectedDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
            let device = connectedDevices[index]
            let updatedDevice = BluetoothDevice(
                id: device.id,
                name: device.name,
                rssi: device.rssi,
                isConnected: device.isConnected,
                deviceType: device.deviceType,
                batteryLevel: batteryLevel,
                lastSeen: device.lastSeen,
                manufacturerData: device.manufacturerData,
                serviceUUIDs: device.serviceUUIDs,
                isPaired: device.isPaired
            )
            connectedDevices[index] = updatedDevice
        }
    }
}