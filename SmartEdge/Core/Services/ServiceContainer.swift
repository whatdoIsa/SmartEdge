import Foundation
import Combine

@MainActor
final class ServiceContainer: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = ServiceContainer()
    
    // MARK: - Services (lazily initialized)
    lazy var settingsService: SettingsServiceProtocol = SettingsService()
    // AppleScript-backed (Apple Music + Spotify) — App Store compatible.
    lazy var mediaService: MediaServiceProtocol = AppleScriptMediaService()
    lazy var systemService: SystemServiceProtocol = SystemService()
    /// StoreKit 2 Pro entitlement (Freemium gating). Single source of truth
    /// for `isPro`; features read this to lock/unlock.
    lazy var storeService: StoreService = StoreService()
    lazy var notchWindowManager: NotchWindowManagerProtocol = NotchWindowManager(serviceContainer: self)
    lazy var calendarService: any CalendarServiceProtocol = CalendarService()
    lazy var eventNotificationService: EventNotificationService = EventNotificationService()

    // MARK: - System Monitoring Services
    lazy var batteryService: any BatteryServiceProtocol = BatteryService()
    lazy var bluetoothService: any BluetoothServiceProtocol = BluetoothService()
    lazy var systemPermissionManager: SystemPermissionManager = SystemPermissionManager()
    lazy var pomodoroService: PomodoroService = PomodoroService()
    lazy var systemStatsService: SystemStatsService = SystemStatsService()
    lazy var globalHotkeyManager: GlobalHotkeyManager = GlobalHotkeyManager()
    lazy var quickAddHotkeyManager: GlobalHotkeyManager = GlobalHotkeyManager()
    lazy var webhookService: WebhookService = WebhookService()
    
    // MARK: - Shelf Services
    lazy var clipboardMonitorService: ClipboardMonitorService = ClipboardMonitorService()
    lazy var fileSharingService: FileSharingServiceProtocol = FileSharingService()
    lazy var shelfService: ShelfServiceProtocol = ShelfService(
        clipboardMonitor: clipboardMonitorService,
        fileSharingService: fileSharingService
    )
    
    // MARK: - Initialization
    private init() {}

    // MARK: - Coordinators
    
    lazy var notchCoordinator: any NotchCoordinatorProtocol = {
        // For now, create a simple temporary coordinator until we implement the full NotchCoordinator
        return TemporaryNotchCoordinator()
    }()
    
    // MARK: - Service Access Methods
    func createMusicPlayerViewModel() -> MusicPlayerViewModel {
        return MusicPlayerViewModel(mediaService: mediaService)
    }

    func createPomodoroViewModel() -> PomodoroViewModel {
        return PomodoroViewModel(service: pomodoroService)
    }

    func createClipboardViewModel() -> ClipboardViewModel {
        return ClipboardViewModel(service: clipboardMonitorService)
    }
    
    func createNotchViewModel(coordinator: any AppCoordinatorProtocol) -> NotchViewModel {
        return NotchViewModel(
            mediaService: mediaService,
            calendarService: calendarService,
            shelfService: shelfService,
            batteryService: batteryService,
            bluetoothService: bluetoothService
        )
    }

    func createCalendarViewModel() -> CalendarViewModel {
        return CalendarViewModel(
            calendarService: calendarService,
            quickActions: CalendarQuickActions(calendarService: calendarService),
            notificationService: eventNotificationService
        )
    }
    
    func createShelfViewModel() -> ShelfViewModel {
        return ShelfViewModel(shelfService: shelfService, fileSharingService: fileSharingService)
    }
    
    func createSystemStatusViewModel() -> SystemStatusViewModel {
        return SystemStatusViewModel(
            batteryService: batteryService,
            bluetoothService: bluetoothService
        )
    }
    
    func createSettingsViewModel(notchCoordinator: any NotchCoordinatorProtocol) -> SettingsViewModel {
        return SettingsViewModel()
    }
    
    
    // MARK: - Service Lifecycle Management
    
    func startSystemMonitoring() async {
        await batteryService.startMonitoring()
        await bluetoothService.refreshConnectedDevices()
    }
    
    func stopSystemMonitoring() async {
        await batteryService.stopMonitoring()
        await bluetoothService.stopScanning()
    }
    
    func refreshSystemStatus() async {
        await batteryService.refreshBatteryInfo()
        await bluetoothService.refreshConnectedDevices()
    }
}

// MARK: - Temporary NotchCoordinator Implementation

@MainActor
private class TemporaryNotchCoordinator: ObservableObject, NotchCoordinatorProtocol {
    @Published var isExpanded: Bool = false
    @Published var isVisible: Bool = true
    @Published var currentContent: NotchContent? = nil
    @Published var currentState: NotchState = .collapsed
    
    var contentPublisher: AnyPublisher<NotchContent?, Never> {
        $currentContent.eraseToAnyPublisher()
    }
    
    var statePublisher: AnyPublisher<NotchState, Never> {
        $currentState.eraseToAnyPublisher()
    }
    
    func showNotch() {
        isVisible = true
    }
    
    func hideNotch() {
        isVisible = false
    }
    
    func expandNotch() {
        isExpanded = true
        currentState = .expanded
    }
    
    func collapseNotch() {
        isExpanded = false
        currentState = .collapsed
    }
    
    func updateContent(_ content: NotchContent, animated: Bool) {
        currentContent = content
    }
    
    func handleHover(_ hovering: Bool) {
        // TODO: Implement hover handling
    }
    
    func handleClick() {
        // TODO: Implement click handling
        if isExpanded {
            collapseNotch()
        } else {
            expandNotch()
        }
    }
}