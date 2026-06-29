import SwiftUI
import Combine

@MainActor
final class AppCoordinator: ObservableObject, AppCoordinatorProtocol {
    // MARK: - Published Properties
    @Published private(set) var currentState: AppState = .loading
    @Published private(set) var isNotchVisible = true
    @Published private(set) var activeWindow: WindowType?
    @Published private(set) var error: AppError?

    // MARK: - Menu Bar
    private let menuBarController = MenuBarController()

    // MARK: - Child Windows
    private let childWindows = ChildWindowCoordinator()

    func showPermissionGuide() {
        childWindows.showPermissionGuide { [weak self] in
            Task { [weak self] in
                _ = await self?.requestPermissions()
            }
        }
    }


    // MARK: - Protocol Requirements
    @Published private(set) var isInitialized = false
    @Published private(set) var isServicesRunning = false
    
    // Protocol properties
    internal let mediaService: MediaServiceProtocol
    var lastError: Error? { error }
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    /// Self-contained subsystems extracted out of AppCoordinator so this
    /// class stays focused on lifecycle / system events / window routing.
    /// Each coordinator manages its own subscriptions and tasks.
    private var webhookCoordinator: WebhookCoordinator?
    private var systemEventCoordinator: SystemEventCoordinator?
    private let windowManager: NotchWindowManagerProtocol
    private let settingsService: SettingsServiceProtocol
    private let systemService: SystemServiceProtocol
    
    // Child ViewModels (managed by coordinator)
    private(set) lazy var notchViewModel: NotchViewModel = {
        ServiceContainer.shared.createNotchViewModel(coordinator: self)
    }()
    
    private(set) lazy var musicPlayerViewModel: MusicPlayerViewModel = {
        ServiceContainer.shared.createMusicPlayerViewModel()
    }()
    
    private(set) lazy var calendarViewModel: CalendarViewModel = {
        ServiceContainer.shared.createCalendarViewModel()
    }()
    
    private(set) lazy var shelfViewModel: ShelfViewModel = {
        ServiceContainer.shared.createShelfViewModel()
    }()

    private(set) lazy var pomodoroViewModel: PomodoroViewModel = {
        ServiceContainer.shared.createPomodoroViewModel()
    }()

    private(set) lazy var clipboardViewModel: ClipboardViewModel = {
        ServiceContainer.shared.createClipboardViewModel()
    }()
    
    private(set) lazy var settingsViewModel: SettingsViewModel = {
        ServiceContainer.shared.createSettingsViewModel(notchCoordinator: ServiceContainer.shared.notchCoordinator)
    }()
    
    // MARK: - Initialization
    init(
        windowManager: NotchWindowManagerProtocol,
        settingsService: SettingsServiceProtocol,
        mediaService: MediaServiceProtocol,
        systemService: SystemServiceProtocol,
        previewMode: Bool = false
    ) {
        self.windowManager = windowManager
        self.settingsService = settingsService
        self.mediaService = mediaService
        self.systemService = systemService

        // Inject self into NotchWindowManager if it's our concrete type
        if let notchWindowManager = windowManager as? NotchWindowManager {
            notchWindowManager.setAppCoordinator(self)
        }

        setupBindings()

        // Catches duplicate / missing SettingsKeys at app launch in DEBUG
        // builds. Stripped from Release entirely (zero runtime cost).
        #if DEBUG
        SettingsKeys.validate()
        #endif

        // Preview mode skips wiring that has visible side effects (NSStatusItem,
        // notification routing, theme binding) so Xcode previews don't spawn
        // menu bar icons or background subscriptions every time they render.
        guard !previewMode else { return }

        menuBarController.attach(to: self)
        setupNotificationRouting()
        // Wire the notch's theme color through the pomodoro view model so the
        // view layer never reaches into a service directly.
        notchViewModel.bindPomodoroTheme(pomodoroViewModel)

        // Spin up self-contained subsystems. Each owns its own subscriptions
        // so AppCoordinator only has to remember to call start().
        let webhook = WebhookCoordinator(
            pomodoroService: ServiceContainer.shared.pomodoroService,
            webhookService: ServiceContainer.shared.webhookService
        )
        webhook.start()
        self.webhookCoordinator = webhook

        // System event coordinator owns the volume/brightness/playback/
        // sleep-wake/screen-change → notch UI translation. hide/show
        // callbacks let it drive AppCoordinator without circular ownership.
        self.systemEventCoordinator = SystemEventCoordinator(
            notchViewModel: notchViewModel,
            settingsService: settingsService,
            windowManager: windowManager,
            hideNotch: { [weak self] in self?.hideNotch() },
            showNotch: { [weak self] in self?.showNotch() }
        )
        // Polling monitors (clipboard, system stats) start once permissions
        // are resolved and the app enters .ready — see performStartupSequence.

        // Auto-trigger startup. SmartEdgeApp delegates `start()` to the
        // Settings scene's `.task` modifier, but `Settings` windows do
        // not auto-appear in `LSUIElement` (menubar-only) apps — meaning
        // `.task` never fires until the user actually opens Settings,
        // which means the notch window never gets created on launch.
        //
        // Calling `start()` here makes initialization independent of any
        // SwiftUI scene appearing. Dispatched to the next run-loop so we
        // don't try to mutate published state before the StateObject
        // wrapper is fully wired up.
        print("[SmartEdge] AppCoordinator.init complete; scheduling start()")
        Task { @MainActor [weak self] in
            print("[SmartEdge] AppCoordinator: auto-start firing")
            self?.start()
        }
    }

    deinit {
        cancellables.removeAll()
    }

    private func startSystemStatsMonitoring() {
        let stats = ServiceContainer.shared.systemStatsService
        stats.onAlert = { [weak self] alert in
            guard let self = self else { return }
            let content: NotchContent = .notification(
                title: alert.title,
                body: alert.body(),
                icon: alert.icon
            )
            self.notchViewModel.forceShowContent(content)
        }
        stats.start()
    }

    private func startClipboardMonitoring() {
        Task { [weak self] in
            await self?.fireClipboardStart()
        }
    }

    /// Wires up system-wide hot keys so the user can summon notch features
    /// even when SmartEdge isn't the frontmost app.
    private func registerGlobalHotkeys() {
        let manager = ServiceContainer.shared.globalHotkeyManager
        manager.onTrigger = { [weak self] in
            self?.showClipboardHistory()
        }
        let success = manager.register(
            keyCode: GlobalHotkeyManager.keyCodeV,
            modifiers: GlobalHotkeyManager.modifiersCmdShift
        )
        if !success {
            AppLogger.general.error("Failed to register global hot key \\u{2318}+\\u{21E7}+V — likely taken by another app.")
        }
    }

    private func fireClipboardStart() async {
        await ServiceContainer.shared.clipboardMonitorService.startMonitoring()
    }

    /// Freemium gate. Returns true if the Pro feature may proceed; otherwise
    /// surfaces a brief upsell on the notch and returns false. Pro features
    /// per the monetization decision: Shelf, Calendar, Pomodoro. Music +
    /// clock + basic notch stay free.
    @discardableResult
    func requirePro(_ featureName: String) -> Bool {
        if ServiceContainer.shared.storeService.isPro { return true }
        notchViewModel.forceShowContent(.notification(
            title: "SmartEdge Pro",
            body: "\(featureName)은(는) Pro 기능입니다. 설정에서 잠금 해제하세요.",
            icon: "lock.fill"
        ))
        return false
    }

    /// Forces the notch to switch to the pomodoro timer view.
    func showPomodoro() {
        guard requirePro("뽀모도로") else { return }
        notchViewModel.forceShowContent(.pomodoro)
    }

    /// Opens the Shelf list in the notch, pinned so files can be dragged in
    /// without it auto-hiding. Pro-gated like other shelf access.
    func showShelf() {
        guard requirePro("선반") else { return }
        notchViewModel.showShelfPanel()
    }

    /// A file drag entered the notch — surface the pinned Shelf as the target.
    /// Silent (no upsell) here; the actual drop runs the Pro gate.
    func prepareShelfForDrop() {
        guard ServiceContainer.shared.storeService.isPro else { return }
        notchViewModel.showShelfPanel()
    }

    /// Files dropped onto the notch overlay → add them to the Shelf.
    func handleNotchFileDrop(_ urls: [URL]) {
        guard requirePro("선반") else { return }
        notchViewModel.showShelfPanel()
        shelfViewModel.handleDroppedURLs(urls)
    }

    /// Forces the notch to show the clipboard history list.
    func showClipboardHistory() {
        notchViewModel.forceShowContent(.clipboardHistory)
    }

    /// Forces the notch to show the quick-actions panel.
    func showQuickActions() {
        notchViewModel.forceShowContent(.actions)
    }

    /// Opens a separate window showing pomodoro session statistics.
    func showPomodoroStatistics() {
        childWindows.showPomodoroStatistics(viewModel: pomodoroViewModel)
    }

    /// Routes incoming UNNotifications to the notch instead of macOS banners.
    private func setupNotificationRouting() {
        ServiceContainer.shared.eventNotificationService.onNotificationPresented = { [weak self] title, body, icon in
            guard let self = self else { return }
            let content: NotchContent = .notification(title: title, body: body, icon: icon)
            self.notchViewModel.forceShowContent(content)
        }
    }
    
    // MARK: - AppCoordinatorProtocol
    func start() {
        Task {
            await performStartupSequence()
        }
    }
    
    func showNotch() {
        isNotchVisible = true
        activeWindow = .notch
        
        Task {
            do {
                try await windowManager.showNotchWindow()
            } catch {
                await handleError(.notchServiceFailed)
            }
        }
    }
    
    func hideNotch() {
        isNotchVisible = false
        activeWindow = nil
        
        Task {
            try await windowManager.hideNotchWindow()
        }
    }
    
    func showSettings() {
        activeWindow = .settings
        
        Task {
            do {
                try await windowManager.showSettingsWindow()
            } catch {
                await handleError(.notchServiceFailed)
            }
        }
    }
    
    func hideSettings() {
        if activeWindow == .settings {
            activeWindow = isNotchVisible ? .notch : nil
        }
        
        Task {
            try await windowManager.hideSettingsWindow()
        }
    }
    
    func handleSystemEvent(_ event: SystemEvent) {
        // Delegate to the dedicated coordinator. Falls back to a no-op
        // before init wiring completes (previewMode + early-cycle calls).
        systemEventCoordinator?.handle(event)
    }
    
    func handleError(_ error: AppError) async {
        await MainActor.run {
            self.error = error
            self.currentState = .error
        }
        
        // Auto-clear error after delay
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            await MainActor.run {
                if self.error?.id == error.id {
                    self.clearError()
                }
            }
        }
    }
    
    func clearError() {
        error = nil
        currentState = .ready
    }
    
    func requestPermissions() async -> Bool {
        do {
            let manager = ServiceContainer.shared.systemPermissionManager
            let defaults = UserDefaults.standard

            // Two independent reasons to skip the request flow:
            // 1. We've already prompted at least once (`hasRequestedSystemPermissions`).
            //    The user knows where the toggles live and we shouldn't pester them.
            // 2. The OS already reports every required permission as granted.
            //    Re-prompting in this state is what caused the "권한 다 켰는데
            //    또 다이얼로그 뜬다" bug — dev rebuilds occasionally cause the
            //    `AXIsProcessTrusted` check to flicker false, which used to
            //    trigger an NSAlert before this guard.
            //
            // Either condition true → skip everything. Only first-ever launch
            // *and* missing-permission state runs the prompt path.
            let alreadyPrompted = defaults.bool(forKey: SettingsKeys.hasRequestedSystemPermissions)
            let alreadyGranted = await manager.areAllRequiredPermissionsGranted()

            if alreadyPrompted || alreadyGranted {
                AppLogger.general.notice(
                    "Permissions: skipping prompt (alreadyPrompted=\(alreadyPrompted, privacy: .public), alreadyGranted=\(alreadyGranted, privacy: .public))"
                )
                // Mark prompted so subsequent launches stay quiet even if
                // a future permission flicker briefly reports false.
                if !alreadyPrompted {
                    defaults.set(true, forKey: SettingsKeys.hasRequestedSystemPermissions)
                }
                await MainActor.run { currentState = .ready }
                return true
            }

            AppLogger.general.notice("Permissions: first-run prompt flow starting")
            await manager.requestAllRequiredPermissions()
            _ = await ServiceContainer.shared.calendarService.requestCalendarAccess()
            defaults.set(true, forKey: SettingsKeys.hasRequestedSystemPermissions)

            // The stub returns true; once we wire real permission checks here
            // this becomes the source of truth.
            let permissionsGranted = try await systemService.requestAllPermissions()

            if permissionsGranted {
                await MainActor.run { currentState = .ready }
                return true
            } else {
                await handleError(.permissionsDenied)
                showPermissionGuide()
                return false
            }
        } catch {
            await handleError(.permissionsFailed(error))
            showPermissionGuide()
            return false
        }
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Listen to settings changes
        settingsService.settingsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self = self else { return }
                self.handleSettingsChange(settings)
            }
            .store(in: &cancellables)

        // Both publishers route through SystemEventCoordinator. The
        // isPlayingPublisher emits a Bool, which we wrap as a
        // `.mediaPlaybackChanged` event so the coordinator has a single
        // entry point regardless of source.
        systemService.systemEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.systemEventCoordinator?.handle(event)
            }
            .store(in: &cancellables)

        mediaService.isPlayingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                self?.systemEventCoordinator?.handle(.mediaPlaybackChanged(isPlaying))
            }
            .store(in: &cancellables)
    }
    
    /// Startup runs in three layers, ordered by "what must succeed for the
    /// next layer to matter":
    ///
    /// **Layer 1 — Notch UI shell.** The NSWindow + SwiftUI overlay. If
    /// this fails the app is useless, so failure does propagate to error
    /// state. **Critically, this runs FIRST** — before any other service.
    /// Earlier versions initialized media/system services first, and a
    /// throw from `mediaService.initialize()` (e.g. MRMediaRemote returning
    /// "Operation not permitted" on macOS 14.4+) silently killed the notch.
    ///
    /// **Layer 2 — Content services.** Settings / media / system metadata
    /// providers. Wrapped in `try?` because any of them can fail without
    /// the notch needing to go away — the user can still see the overlay
    /// with empty content. A failed mediaService just means no Now Playing
    /// display; a failed systemService just means no volume HUD.
    ///
    /// **Layer 3 — Permission-dependent monitors.** Clipboard, system
    /// stats, global hotkeys. These trigger OS permission flows on first
    /// run, so they go after the UI is already on screen.
    ///
    /// Every step logs so Console.app can pinpoint where startup got stuck.
    private func performStartupSequence() async {
        // print() instead of AppLogger so output appears in Xcode's debug
        // console regardless of subsystem filtering. We tracked an issue
        // where AppLogger.notice messages weren't surfacing — this gives
        // a guaranteed-visible trace.
        print("[SmartEdge] Startup: performStartupSequence begin")
        await MainActor.run { currentState = .loading }

        // Layer 1 — Notch UI. Must succeed.
        do {
            print("[SmartEdge] Startup: Layer 1 — initializing notch window")
            try await windowManager.initialize()
            print("[SmartEdge] Startup: Layer 1 — windowManager.initialize() returned")
            await MainActor.run { currentState = .ready }
            showNotch()
            print("[SmartEdge] Startup: Layer 1 — showNotch() called")
        } catch {
            print("[SmartEdge] Startup: Layer 1 FAILED — \(error.localizedDescription)")
            await handleError(.initializationFailed(error))
            return
        }

        // Layer 2 — Content services, best-effort. A throw here (e.g.
        // MRMediaRemote permission denial) used to kill the notch; now
        // it just means that one content source stays empty.
        AppLogger.general.notice("Startup: bringing up content services (best-effort)")
        try? await settingsService.initialize()
        try? await mediaService.initialize()
        try? await systemService.initialize()

        // Layer 3 — Permission flow + polling monitors. These can prompt
        // the user on first launch; the notch is already visible by now.
        // `requestPermissions()` returns true when the *flow completed*
        // (prompted, or skipped because already-prompted/granted). It does
        // NOT mean every permission is granted — the earlier log "skipping
        // prompt (alreadyPrompted=true, alreadyGranted=false)" + this line
        // saying "granted = true" was a misleading pair that read like the
        // app contradicted itself. Renamed to "flow completed" so the two
        // logs reconcile.
        let permissionFlowDone = await requestPermissions()
        AppLogger.general.notice(
            "Startup: permission flow completed = \(permissionFlowDone, privacy: .public)"
        )

        startClipboardMonitoring()
        startSystemStatsMonitoring()
        registerGlobalHotkeys()
    }
    
    private func handleSettingsChange(_ settings: AppSettings) {
        // Update notch visibility based on settings
        if settings.notchEnabled != isNotchVisible {
            if settings.notchEnabled {
                showNotch()
            } else {
                hideNotch()
            }
        }
    }
    
    // processSystemEvent + handleMediaPlaybackChange moved to
    // SystemEventCoordinator (P-tier refactor). Forwarding lives in
    // handleSystemEvent(_:) above.


    // MARK: - AppCoordinatorProtocol Methods
    
    func initialize() async throws {
        // Mark as initialized
        isInitialized = true
    }
    
    func startServices() async throws {
        // Start all services
        isServicesRunning = true
    }
    
    func stopServices() async {
        // Flush any in-progress pomodoro focus before pausing so partial work
        // isn't lost when the user quits mid-session.
        ServiceContainer.shared.pomodoroService.flushInProgressSession()
        ServiceContainer.shared.pomodoroService.pause()
        ServiceContainer.shared.systemStatsService.stop()
        await ServiceContainer.shared.clipboardMonitorService.stopMonitoring()
        ServiceContainer.shared.globalHotkeyManager.unregister()
        menuBarController.remove()
        isServicesRunning = false
    }
    
    func shutdown() async {
        await stopServices()
    }
    
    func handleServiceError(_ error: Error, from service: String) {
        Task {
            await handleError(.initializationFailed(error))
        }
    }
    
    func handleAppDidBecomeActive() {
        // Handle app becoming active
    }
    
    func handleAppWillResignActive() {
        // Handle app resigning active
    }
    
    func handleAppWillTerminate() {
        Task {
            await shutdown()
        }
    }
    
    func handleSystemSleep() {
        // Handle system sleep
    }
    
    func handleSystemWake() {
        // Handle system wake
    }
}

// MARK: - AppState
enum AppState {
    case loading
    case ready
    case error
}

// MARK: - WindowType
enum WindowType {
    case notch
    case settings
}

// SystemEvent enum moved to Shared/Models/SystemEvent.swift for protocol-level access

// Using AppError enum from ErrorViews.swift

// WindowCloseHandler moved to ChildWindowCoordinator.swift