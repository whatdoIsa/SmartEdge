import Foundation
import Combine

@MainActor
final class ServiceContainer: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = ServiceContainer()
    
    // MARK: - Services (lazily initialized)
    lazy var settingsService: SettingsServiceProtocol = SettingsService()
    // AppleScript-backed (Apple Music + Spotify) — App Store compatible.
    // Replaced the old `MediaService` (mediaremote-adapter / perl), which
    // the sandbox + App Review prohibit. Old service kept in the repo until
    // M3 removes it.
    lazy var mediaService: MediaServiceProtocol = AppleScriptMediaService()
    lazy var systemService: SystemServiceProtocol = SystemService()
    lazy var systemHUDService: any SystemHUDServiceProtocol = SystemHUDService()
    /// CGEvent-tap-backed interceptor for system volume/brightness keys.
    /// Separate from SystemHUDService so the protocol surface (HUD events,
    /// publishers) stays decoupled from the OS-permission-gated event tap.
    /// Wired via `wireHUDInterception()` in `setupServices()`.
    lazy var hudInterceptionService: HUDInterceptionService = HUDInterceptionService()

    /// CoreAudio-backed system volume reader/writer. Lazily instantiated
    /// because `getDefaultOutputDevice` on init can briefly block the audio
    /// HAL during app launch — leaving it lazy means the cost is only paid
    /// when the user first triggers (or queries) volume.
    lazy var volumeMonitorService: any VolumeMonitorProtocol = VolumeMonitorService()

    /// IOKit-backed system brightness reader/writer. NOTE: the underlying
    /// `IODisplayConnect` matching may not return results on Apple Silicon
    /// without an external display — Phase 5 will check this and, if so,
    /// swap in a DisplayServices.framework-backed implementation via dlopen.
    lazy var brightnessMonitorService: any BrightnessMonitorProtocol = BrightnessMonitorService()
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
    lazy var webhookService: WebhookService = WebhookService()
    
    // MARK: - Shelf Services
    lazy var clipboardMonitorService: ClipboardMonitorService = ClipboardMonitorService()
    lazy var fileSharingService: FileSharingServiceProtocol = FileSharingService()
    lazy var shelfService: ShelfServiceProtocol = ShelfService(
        clipboardMonitor: clipboardMonitorService,
        fileSharingService: fileSharingService
    )
    
    // MARK: - Initialization
    private init() {
        setupServices()
    }
    
    private func setupServices() {
        // Battery / bluetooth `startMonitoring` lives in `startSystemMonitoring()`
        // (called once from `SmartEdgeApp.initializeApp`). Used to also fire
        // here, causing "Battery monitoring started" to log twice on every
        // launch and BatteryService to spin up two parallel observers.
        wireHUDInterception()
    }

    /// Connect the CGEvent tap interceptor to the HUD service so that
    /// volume/brightness key presses suppress the system HUD and surface
    /// our notch HUD instead. Only kicks off the actual event tap when
    /// Accessibility permission is already granted — without it
    /// `CGEvent.tapCreate` would fail and the user has no visual signal
    /// of *why* the interceptor isn't working. The Settings panel (Phase 4)
    /// is the canonical path to grant the permission and retry.
    ///
    /// Concrete-type cast: SystemHUDServiceProtocol intentionally doesn't
    /// expose `setInterceptionService` because that's an implementation
    /// detail of the CGEventTap-backed concrete service. The downcast is
    /// safe in production because we instantiate `SystemHUDService` in
    /// `systemHUDService` above; if a test ever swaps the concrete type
    /// the interceptor simply won't wire and the cast guard exits early.
    private func wireHUDInterception() {
        guard let concrete = systemHUDService as? SystemHUDService else {
            AppLogger.general.error("Cannot wire HUD interception: systemHUDService is not a SystemHUDService instance")
            return
        }
        concrete.setInterceptionService(hudInterceptionService)
        concrete.setVolumeController(volumeMonitorService)
        concrete.setBrightnessController(brightnessMonitorService)

        // Kick off the system-side monitors so the HUD service can react
        // to *external* changes too (menu-bar volume slider, third-party
        // tools, etc), not just to the keys we intercept.
        Task { [vm = volumeMonitorService, bm = brightnessMonitorService] in
            try? await vm.startMonitoring()
            try? await bm.startMonitoring()
        }

        // Initial start: only if the user wants interception AND has the
        // permission. Either missing → idle until both flip true. The
        // settings toggle is the user's "do this" switch; the permission
        // is the OS's "ok, this is allowed" gate. Both must agree.
        reconcileHUDInterception(concrete: concrete)

        // React to changes in either input. The settings toggle is owned
        // by SettingsViewModel via @AppStorage, which writes through to
        // UserDefaults — so observing the UserDefaults key catches both
        // the toggle flip *and* any external write (e.g. defaults command
        // line, settings restore).
        UserDefaults.standard
            .publisher(for: \.interceptSystemHUD)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak concrete] _ in
                guard let self = self, let concrete = concrete else { return }
                self.reconcileHUDInterception(concrete: concrete)
            }
            .store(in: &hudCancellables)

        // The permission manager polls every 2s already; observing its
        // @Published lets us flip on the moment the user grants the
        // permission in System Settings, without making them restart.
        systemPermissionManager.$hasAccessibilityPermission
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self, weak concrete] _ in
                guard let self = self, let concrete = concrete else { return }
                self.reconcileHUDInterception(concrete: concrete)
            }
            .store(in: &hudCancellables)
    }

    /// Tracks the last (userWants, granted) tuple reconciled so we can
    /// silence the "deferred" log when nothing actually changed. Without
    /// this guard the initial wiring fires three reconcile passes (direct
    /// call + interceptSystemHUD publisher initial value + permission
    /// publisher initial value), all logging the same denial message.
    private var lastHUDReconcileState: (userWants: Bool, granted: Bool)?

    private func reconcileHUDInterception(concrete: SystemHUDService) {
        let userWants = UserDefaults.standard
            .object(forKey: SettingsKeys.interceptSystemHUD) as? Bool ?? true
        Task { @MainActor [weak self, weak concrete] in
            guard let self = self, let concrete = concrete else { return }
            let granted = await self.systemPermissionManager.hasAccessibilityPermission()
            let next = (userWants: userWants, granted: granted)
            if let prev = self.lastHUDReconcileState, prev == next { return }
            self.lastHUDReconcileState = next

            switch (userWants, granted) {
            case (true, true):
                concrete.startIntercepting()
            case (true, false):
                concrete.stopIntercepting()
                AppLogger.general.notice("HUD interception requested but Accessibility not granted")
            case (false, _):
                concrete.stopIntercepting()
            }
        }
    }

    /// Held separately from per-service `cancellables` because these are
    /// container-lifetime subscriptions (live as long as ServiceContainer.shared
    /// itself), not service-scoped.
    private var hudCancellables = Set<AnyCancellable>()
    
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
            systemHUDService: systemHUDService,
            calendarService: calendarService,
            shelfService: shelfService,
            batteryService: batteryService,
            bluetoothService: bluetoothService
        )
    }
    
    func createHUDViewModel() -> HUDViewModel {
        return HUDViewModel(
            systemService: systemService, 
            systemHUDService: systemHUDService
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

// MARK: - UserDefaults KVO bridge for HUD interception toggle
//
// `UserDefaults.publisher(for: \.someProp)` observes the property via
// Objective-C KVO. For the publisher to fire on a `setBool:forKey:` write
// (which is what SwiftUI's @AppStorage does under the hood), the @objc
// dynamic property name MUST exactly match the UserDefaults key name —
// because UserDefaults' KVO machinery is keyed by string. The computed
// getter just reads the same key back; the existence of the @objc dynamic
// property is what makes Swift KeyPath observable.
private extension UserDefaults {
    @objc dynamic var interceptSystemHUD: Bool {
        bool(forKey: SettingsKeys.interceptSystemHUD)
    }
}