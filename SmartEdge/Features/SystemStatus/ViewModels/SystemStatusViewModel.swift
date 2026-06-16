//
//  SystemStatusViewModel.swift
//  SmartEdge
//

import Foundation
import Combine
import CoreBluetooth
import os

@MainActor
final class SystemStatusViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var systemStatus: SystemStatus = SystemStatus()
    @Published var batteryInfo: BatteryInfo = BatteryInfo()
    @Published var bluetoothStatus: BluetoothStatus = BluetoothStatus()
    @Published var connectedDevices: [BluetoothDevice] = []
    @Published var isMonitoring: Bool = false
    @Published var lastUpdateTime: Date = Date()
    
    // MARK: - Services
    
    private let batteryService: any BatteryServiceProtocol
    private let bluetoothService: any BluetoothServiceProtocol
    
    // MARK: - Public Service Accessors
    var isBluetoothAvailable: Bool { 
        bluetoothService.isBluetoothAvailable 
    }
    
    var isBluetoothScanning: Bool {
        bluetoothService.isScanning
    }
    
    // MARK: - Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 10.0
    
    // MARK: - Initialization
    
    init(batteryService: any BatteryServiceProtocol, bluetoothService: any BluetoothServiceProtocol) {
        self.batteryService = batteryService
        self.bluetoothService = bluetoothService
        
        setupObservations()
        startMonitoring()
    }
    
    deinit {
        updateTimer?.invalidate()
        updateTimer = nil
        // Note: isMonitoring will be set to false when stopMonitoring() is called
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        Task {
            await batteryService.startMonitoring()
            await bluetoothService.refreshConnectedDevices()
            
            await MainActor.run {
                isMonitoring = true
                setupPeriodicUpdates()
            }
        }
    }
    
    func stopMonitoring() {
        isMonitoring = false
        updateTimer?.invalidate()
        updateTimer = nil
        
        Task {
            await batteryService.stopMonitoring()
            await bluetoothService.stopScanning()
        }
    }
    
    func refreshAll() {
        Task {
            await refreshSystemStatus()
        }
    }
    
    func refreshBattery() {
        Task {
            await batteryService.refreshBatteryInfo()
        }
    }
    
    func refreshBluetooth() {
        Task {
            await bluetoothService.refreshConnectedDevices()
        }
    }
    
    func startBluetoothScanning() {
        Task {
            await bluetoothService.startScanning()
        }
    }
    
    func stopBluetoothScanning() {
        Task {
            await bluetoothService.stopScanning()
        }
    }
    
    func connectToDevice(_ device: BluetoothDevice) {
        Task {
            do {
                try await bluetoothService.connect(to: device)
            } catch {
                AppLogger.bluetooth.error("Failed to connect to device: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func disconnectFromDevice(_ device: BluetoothDevice) {
        Task {
            do {
                try await bluetoothService.disconnect(from: device)
            } catch {
                AppLogger.bluetooth.error("Failed to disconnect from device: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func getBatteryHealth() async -> BatteryHealth? {
        return await batteryService.getBatteryHealth()
    }
    
    func isLowPowerModeEnabled() async -> Bool {
        return await batteryService.isLowPowerModeEnabled()
    }
    
    // MARK: - Private Methods
    
    private func setupObservations() {
        // Observe battery service updates
        batteryService.batteryInfoPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] batteryInfo in
                self?.batteryInfo = batteryInfo
                self?.updateSystemStatus()
            }
            .store(in: &cancellables)
        
        // Observe Bluetooth service updates
        bluetoothService.connectedDevicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.connectedDevices = devices
                self?.updateBluetoothStatus()
                self?.updateSystemStatus()
            }
            .store(in: &cancellables)
        
        bluetoothService.bluetoothStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateBluetoothStatus()
                self?.updateSystemStatus()
            }
            .store(in: &cancellables)
    }
    
    private func setupPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshSystemStatus()
            }
        }
    }
    
    private func refreshSystemStatus() async {
        await batteryService.refreshBatteryInfo()
        await bluetoothService.refreshConnectedDevices()
        
        await MainActor.run {
            lastUpdateTime = Date()
        }
    }
    
    private func updateBluetoothStatus() {
        let primaryAudioDevice = connectedDevices.first { device in
            device.deviceType.category == .audio && device.isConnected
        }
        
        let primaryInputDevice = connectedDevices.first { device in
            device.deviceType.category == .input && device.isConnected
        }
        
        bluetoothStatus = BluetoothStatus(
            isEnabled: bluetoothService.bluetoothState == .poweredOn,
            connectedDevicesCount: connectedDevices.count,
            primaryAudioDevice: primaryAudioDevice,
            primaryInputDevice: primaryInputDevice,
            lastUpdated: Date()
        )
    }
    
    private func updateSystemStatus() {
        let powerStatus = PowerStatus(
            adapterConnected: batteryInfo.isPluggedIn,
            adapterType: batteryInfo.powerSourceType == .acPower ? .usbc : .unknown,
            isPowerSaveModeEnabled: false, // Would need to implement
            thermalPressure: .nominal, // Would need to implement
            systemLoadAverage: 0.0, // Would need to implement
            lastUpdated: Date()
        )
        
        let thermalStatus = ThermalStatus(
            currentTemperature: batteryInfo.temperature,
            maxTemperature: nil,
            fanSpeed: nil,
            thermalPressure: .nominal,
            cpuThrottling: false,
            lastUpdated: Date()
        )
        
        systemStatus = SystemStatus(
            battery: batteryInfo,
            bluetooth: bluetoothStatus,
            power: powerStatus,
            thermal: thermalStatus,
            lastUpdated: Date()
        )
    }
}

// MARK: - Computed Properties

extension SystemStatusViewModel {
    var batteryLevelFormatted: String {
        return "\(batteryInfo.levelPercentage)%"
    }
    
    var batteryTimeRemainingFormatted: String {
        return batteryInfo.timeRemainingFormatted
    }
    
    var batteryStatusColor: String {
        if batteryInfo.isCritical {
            return "red"
        } else if batteryInfo.isLow {
            return "orange"
        } else if batteryInfo.isCharging {
            return "green"
        } else {
            return "primary"
        }
    }
    
    var bluetoothStatusIcon: String {
        return bluetoothStatus.iconName
    }
    
    var bluetoothStatusDescription: String {
        return bluetoothStatus.statusDescription
    }
    
    var hasConnectedAudioDevice: Bool {
        return bluetoothStatus.primaryAudioDevice != nil
    }
    
    var hasConnectedInputDevice: Bool {
        return bluetoothStatus.primaryInputDevice != nil
    }
    
    var systemHealthLevel: SystemHealthLevel {
        return systemStatus.systemHealth
    }
    
    var criticalAlerts: [SystemAlert] {
        return systemStatus.criticalAlerts
    }
    
    var hasCriticalAlerts: Bool {
        return !criticalAlerts.isEmpty
    }
}

// MARK: - Device Management Helpers

extension SystemStatusViewModel {
    func devicesByCategory() -> [BluetoothDevice.DeviceCategory: [BluetoothDevice]] {
        return Dictionary(grouping: connectedDevices) { device in
            device.deviceType.category
        }
    }
    
    func audioDevices() -> [BluetoothDevice] {
        return connectedDevices.filter { $0.deviceType.category == .audio }
    }
    
    func inputDevices() -> [BluetoothDevice] {
        return connectedDevices.filter { $0.deviceType.category == .input }
    }
    
    func computingDevices() -> [BluetoothDevice] {
        return connectedDevices.filter { $0.deviceType.category == .computing }
    }
    
    func devicesWithBattery() -> [BluetoothDevice] {
        return connectedDevices.filter { $0.supportsBattery && $0.batteryLevel != nil }
    }
    
    func lowBatteryDevices() -> [BluetoothDevice] {
        return devicesWithBattery().filter { 
            guard let batteryLevel = $0.batteryLevel else { return false }
            return batteryLevel < 0.2
        }
    }
}