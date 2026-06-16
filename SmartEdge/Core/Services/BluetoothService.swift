import Foundation
import CoreBluetooth
import Combine
import os

// MARK: - Legacy Types for Backward Compatibility

/// Legacy bluetooth device structure (for backward compatibility)
struct LegacyBluetoothDevice {
    let identifier: UUID
    let name: String?
    let isConnected: Bool
    let rssi: NSNumber?
    
    init(from peripheral: CBPeripheral, rssi: NSNumber? = nil) {
        self.identifier = peripheral.identifier
        self.name = peripheral.name
        self.isConnected = peripheral.state == .connected
        self.rssi = rssi
    }
    
    init(from device: BluetoothDevice) {
        self.identifier = device.id
        self.name = device.name
        self.isConnected = device.isConnected
        self.rssi = device.rssi as NSNumber?
    }
}

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
    
    var connectedDevicesPublisher: Published<[BluetoothDevice]>.Publisher {
        $connectedDevices
    }
    
    var bluetoothStatePublisher: Published<CBManagerState>.Publisher {
        $bluetoothState
    }
    
    // MARK: - Properties
    
    weak var delegate: BluetoothServiceDelegate?
    private var centralManager: CBCentralManager?
    private var discoveredPeripherals: [CBPeripheral] = []
    private var cancellables = Set<AnyCancellable>()
    private var scanningTask: Task<Void, Never>?
    private var batteryServiceUUID = CBUUID(string: "180F")
    
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupBluetoothManager()
    }
    
    deinit {
        scanningTask?.cancel()
        centralManager?.stopScan()
        centralManager = nil
        cancellables.removeAll()
    }
    
    // MARK: - Protocol Implementation
    
    func startScanning() async {
        guard bluetoothState == .poweredOn else { 
            return
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
        
        AppLogger.bluetooth.info("Bluetooth scanning started")
    }
    
    func stopScanning() async {
        centralManager?.stopScan()
        isScanning = false
        scanningTask?.cancel()
        scanningTask = nil
        AppLogger.bluetooth.info("Bluetooth scanning stopped")
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
        guard let _ = discoveredPeripherals.first(where: { $0.identifier == device.id }),
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
    
    
    // MARK: - Private Methods
    
    private func setupBluetoothManager() {
        centralManager = CBCentralManager(delegate: self, queue: .main)
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
        return BluetoothDevice(
            id: device.identifier,
            name: device.name ?? "Unknown Device",
            rssi: device.rssi?.intValue,
            isConnected: device.isConnected
        )
    }
    
    private func convertNewToLegacy(device: BluetoothDevice) -> LegacyBluetoothDevice {
        return LegacyBluetoothDevice(from: device)
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothService: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            bluetoothState = central.state
            delegate?.bluetoothService(self, didUpdateState: central.state)
            
            if central.state == .poweredOn {
                await updateConnectedDevices()
            } else if central.state != .poweredOn && isScanning {
                await stopScanning()
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
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
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
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
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
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
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            AppLogger.bluetooth.error("Failed to connect to \(peripheral.name ?? "unknown device", privacy: .public): \(error?.localizedDescription ?? "Unknown error", privacy: .public)")
            
            // Remove from connected devices if somehow there
            connectedDevices.removeAll { $0.id == peripheral.identifier }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothService: @preconcurrency CBPeripheralDelegate {
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
        Task { @MainActor in
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
}