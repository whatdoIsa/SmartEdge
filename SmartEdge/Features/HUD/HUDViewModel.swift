import SwiftUI
import Combine

struct HUDPermissions {
    let accessibility: Bool
    let inputMonitoring: Bool
    let canInterceptHUD: Bool
}

@MainActor
final class HUDViewModel: ObservableObject {
    @Published var isVolumeHUDVisible = false
    @Published var isBrightnessHUDVisible = false
    @Published var currentVolume: Float = 0.5
    @Published var currentBrightness: Float = 0.7
    @Published var isMuted: Bool = false
    @Published var isHUDInterceptionActive = false
    @Published var permissionStatus: Bool?
    @Published var isInitializing = false
    @Published var error: AppError?
    @Published var transientError: AppError?
    @Published var currentHUD: SystemHUDType?
    @Published var isAdjusting = false
    @Published var currentValue: Double = 0.5
    
    var hudVisibilityPublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest($isVolumeHUDVisible, $isBrightnessHUDVisible)
            .map { volume, brightness in volume || brightness }
            .eraseToAnyPublisher()
    }
    
    private let systemService: SystemServiceProtocol
    private let systemHUDService: any SystemHUDServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var hideTimer: Timer?
    
    init(systemService: SystemServiceProtocol, systemHUDService: any SystemHUDServiceProtocol) {
        self.systemService = systemService
        self.systemHUDService = systemHUDService
        setupBindings()
        initializeSystemHUD()
    }
    
    private func setupBindings() {
        systemHUDService.hudPublisher
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] info in
                guard let self = self else { return }
                self.handleHUDInfo(info)
            }
            .store(in: &cancellables)

        systemHUDService.interceptingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.isHUDInterceptionActive = active
            }
            .store(in: &cancellables)
    }

    private func handleHUDInfo(_ info: SystemHUDInfo) {
        currentHUD = info.type
        currentValue = info.value
        switch info.type {
        case .volume(let level):
            currentVolume = level
            isMuted = info.isMuted
            showVolumeHUD()
        case .brightness(let level):
            currentBrightness = level
            showBrightnessHUD()
        case .keyboardBacklight:
            break
        case .airplayConnecting, .airplayConnected, .airplayDisconnected, .doNotDisturb:
            break
        }
    }
    
    private func initializeSystemHUD() {
        // Interception lifecycle is owned by ServiceContainer (which gates
        // on the user's Settings toggle *and* the Accessibility permission).
        // HUDViewModel used to call startIntercepting() here, which both
        // double-fired the start and — worse — caused stopIntercepting()
        // in deinit to kill the tap whenever HUDView unmounted (which it
        // does every time the notch auto-collapses the HUD content).
        permissionStatus = systemHUDService.checkAccessibilityPermission()
    }

    // MARK: - Public Methods

    func initialize() async {
        isInitializing = true
        error = nil

        // Same rationale as initializeSystemHUD(): do not touch the
        // interception lifecycle here.
        permissionStatus = systemHUDService.checkAccessibilityPermission()

        isInitializing = false
    }
    
    func reinitialize() async {
        await initialize()
    }
    
    func refreshState() async {
        permissionStatus = systemHUDService.checkAccessibilityPermission()
    }
    
    func requestPermissions() {
        // Delegates to the protocol method which now no-ops on the
        // legacy `SystemHUDService.requestAccessibilityPermission` path
        // (the canonical request flow lives on SystemPermissionManager,
        // surfaced via the Settings panel's permission rows).
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.systemHUDService.requestAccessibilityPermission()
            self.permissionStatus = self.systemHUDService.checkAccessibilityPermission()
        }
    }
    
    func setVolume(_ volume: Float) {
        // Update current volume immediately for responsive UI
        currentVolume = volume
        showVolumeHUD()
    }

    func setBrightness(_ brightness: Float) {
        // Update current brightness immediately for responsive UI
        currentBrightness = brightness
        showBrightnessHUD()
    }
    
    private func showVolumeHUD() {
        isVolumeHUDVisible = true
        isBrightnessHUDVisible = false
        scheduleHide()
    }
    
    private func showBrightnessHUD() {
        isBrightnessHUDVisible = true
        isVolumeHUDVisible = false
        scheduleHide()
    }
    
    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isVolumeHUDVisible = false
                self.isBrightnessHUDVisible = false
            }
        }
    }
    
    deinit {
        // Do NOT stop interception here — the tap is shared, container-owned.
        // Killing it on view unmount would defeat the whole feature: every
        // time the notch auto-collapsed the HUD after the 2s display, the
        // next volume/brightness press would fall back to the system HUD.
        cancellables.removeAll()
        hideTimer?.invalidate()
        hideTimer = nil
    }
}

