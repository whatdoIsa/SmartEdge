import SwiftUI
import Combine

@MainActor
final class NotchViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isInitializing = false
    @Published var isServiceLoading = false
    @Published var isContentLoading = false
    @Published var error: AppError?
    @Published var transientError: AppError?
    
    // Network status
    @Published var wifiStrength: Int?
    @Published var hasNetworkError = false
    
    // Bluetooth status
    @Published var bluetoothEnabled = false
    @Published var bluetoothConnected = false
    @Published var hasBluetoothError = false
    
    // Battery status
    @Published var batteryLevel: Double?
    @Published var isCharging = false
    @Published var hasBatteryError = false
    
    // System status
    @Published var isDarkMode = false
    
    // Music player integration
    @Published var hasActiveMusicPlayer = false
    @Published var currentTrack: NowPlayingInfo?
    
    // Calendar integration
    @Published var hasActiveCalendar = false
    
    // MARK: - Private Properties
    private let notchWindowService: NotchWindowServiceProtocol
    private let systemStatusService: SystemStatusServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var transientErrorTimer: Timer?
    
    // Publishers for service failures
    private let hoverDetectionFailureSubject = PassthroughSubject<Void, Never>()
    
    var hoverDetectionFailurePublisher: AnyPublisher<Void, Never> {
        hoverDetectionFailureSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    init(
        notchWindowService: NotchWindowServiceProtocol = NotchWindowService.shared,
        systemStatusService: SystemStatusServiceProtocol = SystemStatusService.shared
    ) {
        self.notchWindowService = notchWindowService
        self.systemStatusService = systemStatusService
        
        setupBindings()
    }
    
    deinit {
        transientErrorTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    func initialize() async {
        isInitializing = true
        error = nil
        
        do {
            // Initialize notch window service
            try await notchWindowService.initialize()
            
            // Initialize system status service
            try await systemStatusService.initialize()
            
            // Load initial state
            await refreshState()
            
            // Setup notification observers
            setupNotificationObservers()
            
            error = nil
        } catch {
            await handleError(.notchServiceFailed, transient: false)
        }
        
        isInitializing = false
    }
    
    func reinitialize() async {
        await initialize()
    }
    
    func refreshState() async {
        isServiceLoading = true
        
        await withTaskGroup(of: Void.self) { group in
            // Load network status
            group.addTask { [weak self] in
                await self?.loadNetworkStatus()
            }
            
            // Load bluetooth status  
            group.addTask { [weak self] in
                await self?.loadBluetoothStatus()
            }
            
            // Load battery status
            group.addTask { [weak self] in
                await self?.loadBatteryStatus()
            }
            
            // Load system preferences
            group.addTask { [weak self] in
                await self?.loadSystemStatus()
            }
            
            // Load music player status
            group.addTask { [weak self] in
                await self?.loadMusicPlayerStatus()
            }
        }
        
        isServiceLoading = false
    }
    
    // MARK: - User Actions
    func toggleWiFi() async {
        await performSystemAction {
            try await systemStatusService.toggleWiFi()
        }
    }
    
    func toggleBluetooth() async {
        await performSystemAction {
            try await systemStatusService.toggleBluetooth()
        }
    }
    
    func toggleDarkMode() async {
        await performSystemAction {
            try await systemStatusService.toggleAppearance()
        }
    }
    
    func toggleControlCenter() async {
        await performSystemAction {
            try await systemStatusService.openControlCenter()
        }
    }
    
    // MARK: - Error Handling
    func handleHoverFailure() async {
        await handleError(.unknownError("Hover detection failed"), transient: true)
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Listen for service errors
        notchWindowService.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                Task { @MainActor in
                    await self?.handleError(.notchServiceFailed, transient: true)
                }
            }
            .store(in: &cancellables)
        
        systemStatusService.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                Task { @MainActor in
                    await self?.handleError(.unknownError(error.localizedDescription), transient: true)
                }
            }
            .store(in: &cancellables)
        
        // Listen for hover detection failures
        notchWindowService.hoverFailurePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.hoverDetectionFailureSubject.send()
            }
            .store(in: &cancellables)
        
        // Listen for system status changes
        systemStatusService.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateFromSystemStatus(status)
            }
            .store(in: &cancellables)
    }
    
    private func setupNotificationObservers() {
        // System status changes
        NotificationCenter.default.addObserver(
            forName: .systemStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshState()
            }
        }
        
        // Music player changes
        NotificationCenter.default.addObserver(
            forName: .musicPlayerStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadMusicPlayerStatus()
            }
        }
    }
    
    private func loadNetworkStatus() async {
        do {
            let networkStatus = try await systemStatusService.getNetworkStatus()
            wifiStrength = networkStatus.wifiStrength
            hasNetworkError = false
        } catch {
            wifiStrength = nil
            hasNetworkError = true
        }
    }
    
    private func loadBluetoothStatus() async {
        do {
            let bluetoothStatus = try await systemStatusService.getBluetoothStatus()
            bluetoothEnabled = bluetoothStatus.isEnabled
            bluetoothConnected = bluetoothStatus.isConnected
            hasBluetoothError = false
        } catch {
            bluetoothEnabled = false
            bluetoothConnected = false
            hasBluetoothError = true
        }
    }
    
    private func loadBatteryStatus() async {
        do {
            let batteryStatus = try await systemStatusService.getBatteryStatus()
            batteryLevel = batteryStatus.level
            isCharging = batteryStatus.isCharging
            hasBatteryError = false
        } catch {
            batteryLevel = nil
            isCharging = false
            hasBatteryError = true
        }
    }
    
    private func loadSystemStatus() async {
        do {
            let appearance = try await systemStatusService.getAppearance()
            isDarkMode = appearance == .dark
        } catch {
            // Use current system appearance as fallback
            isDarkMode = NSApp.effectiveAppearance.name == .darkAqua
        }
    }
    
    private func loadMusicPlayerStatus() async {
        do {
            let musicStatus = try await systemStatusService.getMusicPlayerStatus()
            hasActiveMusicPlayer = musicStatus.isActive
            currentTrack = musicStatus.currentTrack
        } catch {
            hasActiveMusicPlayer = false
            currentTrack = nil
        }
    }
    
    private func performSystemAction(_ action: () async throws -> Void) async {
        do {
            try await action()
            await refreshState()
        } catch {
            await handleError(.unknownError("Action failed"), transient: true)
        }
    }
    
    private func updateFromSystemStatus(_ status: SystemStatus) {
        wifiStrength = status.network.wifiStrength
        hasNetworkError = status.network.hasError
        
        bluetoothEnabled = status.bluetooth.isEnabled
        bluetoothConnected = status.bluetooth.isConnected
        hasBluetoothError = status.bluetooth.hasError
        
        batteryLevel = status.battery.level
        isCharging = status.battery.isCharging
        hasBatteryError = status.battery.hasError
        
        isDarkMode = status.appearance == .dark
        
        hasActiveMusicPlayer = status.musicPlayer.isActive
        currentTrack = status.musicPlayer.currentTrack
    }
    
    private func handleError(_ appError: AppError, transient: Bool) async {
        if transient {
            transientError = appError
            scheduleTransientErrorDismissal()
        } else {
            error = appError
        }
    }
    
    private func scheduleTransientErrorDismissal() {
        transientErrorTimer?.invalidate()
        transientErrorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.transientError = nil
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let notchStateChanged = Notification.Name("notchStateChanged")
    static let systemStatusChanged = Notification.Name("systemStatusChanged")
}

// MARK: - Service Protocols
protocol NotchWindowServiceProtocol {
    var errorPublisher: AnyPublisher<Error, Never> { get }
    var hoverFailurePublisher: AnyPublisher<Void, Never> { get }
    
    func initialize() async throws
}

protocol SystemStatusServiceProtocol {
    var errorPublisher: AnyPublisher<Error, Never> { get }
    var statusPublisher: AnyPublisher<SystemStatus, Never> { get }
    
    func initialize() async throws
    func getNetworkStatus() async throws -> NetworkStatus
    func getBluetoothStatus() async throws -> BluetoothStatus
    func getBatteryStatus() async throws -> BatteryStatus
    func getAppearance() async throws -> AppearanceMode
    func getMusicPlayerStatus() async throws -> MusicPlayerStatus
    func toggleWiFi() async throws
    func toggleBluetooth() async throws
    func toggleAppearance() async throws
    func openControlCenter() async throws
}

// MARK: - Status Models
struct SystemStatus {
    let network: NetworkStatus
    let bluetooth: BluetoothStatus
    let battery: BatteryStatus
    let appearance: AppearanceMode
    let musicPlayer: MusicPlayerStatus
}

struct NetworkStatus {
    let wifiStrength: Int?
    let hasError: Bool
}

struct BluetoothStatus {
    let isEnabled: Bool
    let isConnected: Bool
    let hasError: Bool
}

struct BatteryStatus {
    let level: Double?
    let isCharging: Bool
    let hasError: Bool
}

struct MusicPlayerStatus {
    let isActive: Bool
    let currentTrack: NowPlayingInfo?
}

enum AppearanceMode {
    case light
    case dark
    case auto
}

// MARK: - Mock Services
final class MockNotchWindowService: NotchWindowServiceProtocol {
    private let errorSubject = PassthroughSubject<Error, Never>()
    private let hoverFailureSubject = PassthroughSubject<Void, Never>()
    
    var errorPublisher: AnyPublisher<Error, Never> {
        errorSubject.eraseToAnyPublisher()
    }
    
    var hoverFailurePublisher: AnyPublisher<Void, Never> {
        hoverFailureSubject.eraseToAnyPublisher()
    }
    
    func initialize() async throws {
        // Simulate initialization delay
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}

final class MockSystemStatusService: SystemStatusServiceProtocol {
    private let errorSubject = PassthroughSubject<Error, Never>()
    private let statusSubject = CurrentValueSubject<SystemStatus, Never>(
        SystemStatus(
            network: NetworkStatus(wifiStrength: 3, hasError: false),
            bluetooth: BluetoothStatus(isEnabled: true, isConnected: true, hasError: false),
            battery: BatteryStatus(level: 0.75, isCharging: false, hasError: false),
            appearance: .dark,
            musicPlayer: MusicPlayerStatus(isActive: false, currentTrack: nil)
        )
    )
    
    var errorPublisher: AnyPublisher<Error, Never> {
        errorSubject.eraseToAnyPublisher()
    }
    
    var statusPublisher: AnyPublisher<SystemStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }
    
    func initialize() async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
    }
    
    func getNetworkStatus() async throws -> NetworkStatus {
        return statusSubject.value.network
    }
    
    func getBluetoothStatus() async throws -> BluetoothStatus {
        return statusSubject.value.bluetooth
    }
    
    func getBatteryStatus() async throws -> BatteryStatus {
        return statusSubject.value.battery
    }
    
    func getAppearance() async throws -> AppearanceMode {
        return statusSubject.value.appearance
    }
    
    func getMusicPlayerStatus() async throws -> MusicPlayerStatus {
        return statusSubject.value.musicPlayer
    }
    
    func toggleWiFi() async throws {
        var current = statusSubject.value
        current = SystemStatus(
            network: NetworkStatus(
                wifiStrength: current.network.wifiStrength == nil ? 3 : nil,
                hasError: false
            ),
            bluetooth: current.bluetooth,
            battery: current.battery,
            appearance: current.appearance,
            musicPlayer: current.musicPlayer
        )
        statusSubject.send(current)
    }
    
    func toggleBluetooth() async throws {
        var current = statusSubject.value
        current = SystemStatus(
            network: current.network,
            bluetooth: BluetoothStatus(
                isEnabled: !current.bluetooth.isEnabled,
                isConnected: current.bluetooth.isConnected,
                hasError: false
            ),
            battery: current.battery,
            appearance: current.appearance,
            musicPlayer: current.musicPlayer
        )
        statusSubject.send(current)
    }
    
    func toggleAppearance() async throws {
        var current = statusSubject.value
        current = SystemStatus(
            network: current.network,
            bluetooth: current.bluetooth,
            battery: current.battery,
            appearance: current.appearance == .dark ? .light : .dark,
            musicPlayer: current.musicPlayer
        )
        statusSubject.send(current)
    }
    
    func openControlCenter() async throws {
        // Simulate opening control center
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}