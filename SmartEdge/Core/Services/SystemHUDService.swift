import Foundation
import IOKit
import Combine

@MainActor
final class SystemHUDService: ObservableObject, SystemHUDServiceProtocol, HUDInterceptionDelegate {
    // MARK: - SystemHUDServiceProtocol Properties
    
    @Published var isIntercepting: Bool = false
    @Published var currentHUD: SystemHUDInfo? = nil
    @Published var hasAccessibilityPermission: Bool = false
    
    // MARK: - Additional Properties
    
    @Published var currentVolume: Double = 0.5
    @Published var currentBrightness: Double = 0.5
    
    // MARK: - Properties

    weak var delegate: SystemHUDServiceDelegate?
    private var cancellables = Set<AnyCancellable>()

    /// CGEvent-tap-backed keystroke interceptor. Optional because:
    /// 1. Unit tests / SwiftUI previews construct SystemHUDService without
    ///    the real CGEventTap (which requires Accessibility permission and
    ///    a running CFRunLoop — neither is appropriate in a preview).
    /// 2. ServiceContainer wires it post-init via `setInterceptionService`
    ///    so the two services can be lazy-instantiated independently
    ///    without a circular dependency.
    private weak var hudInterceptionService: HUDInterceptionService?

    /// Concrete controllers that talk to CoreAudio and IOKit on our behalf.
    /// Optional & wired post-init for the same reasons as the interceptor.
    /// Without these, intercepted keys still pop the notch HUD (Phase 1
    /// behavior) but don't mutate the actual system state — useful for
    /// preview / test environments where touching real audio hardware is
    /// undesirable.
    private var volumeController: (any VolumeMonitorProtocol)?
    private var brightnessController: (any BrightnessMonitorProtocol)?

    /// One-shot step size for a single key press. macOS uses 1/16 by
    /// default (16 ticks across the full range), so we mirror it to keep
    /// the per-press feel consistent with the system's own HUD.
    private static let volumeStep: Float = 1.0 / 16.0
    private static let brightnessStep: Float = 1.0 / 16.0
    
    // MARK: - Interception State
    
    private var isInterceptionEnabled: Bool {
        return isIntercepting
    }
    
    // MARK: - Publishers
    
    var hudPublisher: AnyPublisher<SystemHUDInfo?, Never> {
        $currentHUD.eraseToAnyPublisher()
    }
    
    var interceptingPublisher: AnyPublisher<Bool, Never> {
        $isIntercepting.eraseToAnyPublisher()
    }
    
    // MARK: - Types

    // VolumeKeyDirection / BrightnessKeyDirection live at module scope in
    // HUDInterceptionService.swift — they were duplicated here as nested
    // types but the protocol conformance for HUDInterceptionDelegate
    // requires the *module-scope* versions, so the nested duplicates were
    // both unused and a source of name-resolution ambiguity inside this
    // class's body. Removed.

    struct SystemHUDPermissionStatus {
        let accessibility: Bool
        let inputMonitoring: Bool
        let canInterceptHUD: Bool
        
        var isComplete: Bool {
            return accessibility && inputMonitoring
        }
        
        var missingPermissions: [String] {
            var missing: [String] = []
            if !accessibility { missing.append("Accessibility") }
            if !inputMonitoring { missing.append("Input Monitoring") }
            return missing
        }
    }
    
    // MARK: - Initialization

    init() {
        // No setup at init time. The real wiring happens when ServiceContainer
        // calls `setVolumeController` / `setBrightnessController` /
        // `setInterceptionService` once the underlying services are
        // available. The previous dummy `VolumeObserver` / `BrightnessObserver`
        // were placeholders that listened for a notification nobody sent and
        // polled a hard-coded brightness — both removed.
    }
    
    // MARK: - SystemHUDServiceProtocol Methods
    
    func requestAccessibilityPermission() {
        // Check and request accessibility permission
        hasAccessibilityPermission = checkAccessibilityPermission()
    }

    /// Called once at app start by ServiceContainer to wire the cross-service
    /// link. Kept as a method rather than an init parameter so the two services
    /// can be `lazy var` in the container without one's init blocking on the
    /// other's instantiation order.
    func setInterceptionService(_ service: HUDInterceptionService) {
        hudInterceptionService = service
        service.delegate = self
    }

    /// Inject the CoreAudio-backed volume controller. Without this, intercepted
    /// volume keys still pop the notch HUD but don't mutate the system mixer.
    /// Also subscribes to the controller's publishers so *external* volume
    /// changes (menu-bar slider, other apps, AppleScript, etc) also surface
    /// the notch HUD — not just the keys we intercept.
    func setVolumeController(_ controller: any VolumeMonitorProtocol) {
        volumeController = controller
        // Snapshot current state so the displayed level matches reality
        // before the user touches anything.
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let level = await controller.getCurrentVolume()
            let muted = await controller.isMuted()
            self.currentVolume = Double(level)
            self.currentHUD = SystemHUDInfo(
                type: .volume(level),
                value: Double(level),
                isMuted: muted
            )
        }
        // External-change forwarding. CoreAudio fires the listener for both
        // our own setVolume writes *and* outside writes, which would loop
        // the notch HUD forever if we re-handled every event. The notch
        // pulse is debounced inside NotchViewModel, so a small extra event
        // is harmless — but we still gate on a meaningful delta to avoid
        // toggling for floating-point precision noise.
        controller.volumePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self = self else { return }
                guard abs(Double(level) - self.currentVolume) > 0.001 else { return }
                let muted = (self.currentHUD?.isMuted) ?? false
                self.handleVolumeChange(level, isMuted: muted)
            }
            .store(in: &cancellables)
        controller.muteStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                guard let self = self else { return }
                self.handleVolumeChange(Float(self.currentVolume), isMuted: muted)
            }
            .store(in: &cancellables)
    }

    /// Inject the IOKit-backed brightness controller. Same caveats and
    /// external-change forwarding as `setVolumeController`.
    func setBrightnessController(_ controller: any BrightnessMonitorProtocol) {
        brightnessController = controller
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let level = await controller.getCurrentBrightness()
            self.currentBrightness = Double(level)
        }
        controller.brightnessPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self = self else { return }
                guard abs(Double(level) - self.currentBrightness) > 0.001 else { return }
                self.handleBrightnessChange(level)
            }
            .store(in: &cancellables)
    }

    func startIntercepting() {
        guard let service = hudInterceptionService else {
            AppLogger.general.error("SystemHUDService.startIntercepting called before setInterceptionService — no-op")
            return
        }
        Task { [weak self] in
            do {
                try await service.startInterception()
            } catch {
                await MainActor.run { [weak self] in
                    self?.isIntercepting = false
                }
                AppLogger.general.error("HUD interception failed to start: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func stopIntercepting() {
        Task { [weak hudInterceptionService] in
            await hudInterceptionService?.stopInterception()
        }
    }
    
    func handleVolumeChange(_ level: Float, isMuted: Bool) {
        currentVolume = Double(level)
        let hudType = SystemHUDType.volume(level)
        let hud = SystemHUDInfo(type: hudType, value: Double(level), isMuted: isMuted)
        currentHUD = hud
    }

    func handleBrightnessChange(_ level: Float) {
        currentBrightness = Double(level)
        let hudType = SystemHUDType.brightness(level)
        let hud = SystemHUDInfo(type: hudType, value: Double(level))
        currentHUD = hud
    }

    func handleKeyboardBacklightChange(_ level: Float) {
        let hudType = SystemHUDType.keyboardBacklight(level)
        let hud = SystemHUDInfo(type: hudType, value: Double(level))
        currentHUD = hud
    }
    
    // MARK: - HUDInterceptionDelegate

    // The first three callbacks reflect lifecycle of the underlying
    // CGEventTap. We mirror that into our @Published `isIntercepting` so the
    // Settings panel reflects truth, even if startInterception() failed
    // silently inside the perl spawn or accessibility check downstream.

    func hudInterceptionDidStart() {
        isIntercepting = true
        AppLogger.general.notice("HUD interception started")
    }

    func hudInterceptionDidStop() {
        isIntercepting = false
        AppLogger.general.notice("HUD interception stopped")
    }

    func hudInterceptionDidFail(with error: Error) {
        isIntercepting = false
        AppLogger.general.error("HUD interception failed: \(String(describing: error), privacy: .public)")
    }

    // Phase 2: keys are intercepted, the underlying CoreAudio mixer
    // (volume) or IOKit display (brightness) is mutated, and the resulting
    // value is mirrored to the notch HUD. We read the *post-write* value
    // from the controller instead of trusting the local delta — this catches
    // the case where the user is already at min/max (the controller clamps,
    // we don't want the HUD to lie and show a value past the rail).
    //
    // If the controller is absent (preview / test) we degrade to the Phase
    // 1 behavior: pop the notch HUD with a synthetic value so the user still
    // sees the visual feedback, just without the system actually moving.

    func didInterceptVolumeKey(direction: VolumeKeyDirection) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let controller = self.volumeController else {
                self.synthesizeVolumeFeedback(direction: direction)
                return
            }

            switch direction {
            case .mute:
                let wasMuted = await controller.isMuted()
                try? await controller.setMuted(!wasMuted)
                let level = await controller.getCurrentVolume()
                self.handleVolumeChange(level, isMuted: !wasMuted)

            case .up, .down:
                let current = await controller.getCurrentVolume()
                let delta: Float = direction == .up ? Self.volumeStep : -Self.volumeStep
                let target = max(0, min(1, current + delta))
                try? await controller.setVolume(target)
                let actual = await controller.getCurrentVolume()
                let muted = await controller.isMuted()
                self.handleVolumeChange(actual, isMuted: muted)
            }
        }
    }

    func didInterceptBrightnessKey(direction: BrightnessKeyDirection) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let controller = self.brightnessController else {
                self.synthesizeBrightnessFeedback(direction: direction)
                return
            }
            let current = await controller.getCurrentBrightness()
            let delta: Float = direction == .up ? Self.brightnessStep : -Self.brightnessStep
            let target = max(0, min(1, current + delta))
            try? await controller.setBrightness(target)
            let actual = await controller.getCurrentBrightness()
            self.handleBrightnessChange(actual)
        }
    }

    /// Keyboard backlight key intercept. We pop the notch HUD so the user
    /// gets feedback, but we don't drive the system backlight level
    /// itself yet — that requires HIDManager/IOServiceOpen wiring against
    /// the keyboard device, which is a separate work-package.
    /// `direction.up` / `.down` step the displayed value; `.toggle` flips
    /// between the last non-zero level and zero.
    func didInterceptKeyboardBacklightKey(direction: KeyboardBacklightKeyDirection) {
        let step: Double = 1.0 / 16.0
        let nextLevel: Double
        switch direction {
        case .up:
            nextLevel = min(1, lastKeyboardBacklightLevel + step)
        case .down:
            nextLevel = max(0, lastKeyboardBacklightLevel - step)
        case .toggle:
            // Flip between off and the last non-zero level. Default to 0.5
            // if we've never recorded a non-zero level (first launch).
            if lastKeyboardBacklightLevel > 0 {
                lastNonZeroKeyboardBacklight = lastKeyboardBacklightLevel
                nextLevel = 0
            } else {
                nextLevel = lastNonZeroKeyboardBacklight > 0 ? lastNonZeroKeyboardBacklight : 0.5
            }
        }
        lastKeyboardBacklightLevel = nextLevel
        if nextLevel > 0 { lastNonZeroKeyboardBacklight = nextLevel }
        handleKeyboardBacklightChange(Float(nextLevel))
    }

    /// Cached displayed level for the keyboard backlight HUD. Lives here
    /// instead of in @Published because the notch HUD only cares about
    /// the transient `currentHUD` event — we just need somewhere to read
    /// the previous level when stepping.
    private var lastKeyboardBacklightLevel: Double = 0.5
    private var lastNonZeroKeyboardBacklight: Double = 0.5

    // Phase-1 fallback paths for environments without a real controller
    // (SwiftUI previews, unit tests). The notch HUD still pops so the
    // visual chain can be exercised end-to-end without touching system
    // hardware.
    private func synthesizeVolumeFeedback(direction: VolumeKeyDirection) {
        switch direction {
        case .mute:
            let newMuted = !(currentHUD?.isMuted ?? false)
            handleVolumeChange(Float(currentVolume), isMuted: newMuted)
        case .up:
            let next = min(1, currentVolume + Double(Self.volumeStep))
            handleVolumeChange(Float(next), isMuted: false)
        case .down:
            let next = max(0, currentVolume - Double(Self.volumeStep))
            handleVolumeChange(Float(next), isMuted: false)
        }
    }

    private func synthesizeBrightnessFeedback(direction: BrightnessKeyDirection) {
        let delta: Double = direction == .up
            ? Double(Self.brightnessStep)
            : -Double(Self.brightnessStep)
        let next = max(0, min(1, currentBrightness + delta))
        handleBrightnessChange(Float(next))
    }

    deinit {
        cancellables.removeAll()
    }
}