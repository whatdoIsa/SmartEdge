import Foundation

/// Translates `SystemEvent`s (volume change, brightness change, media
/// playback, sleep/wake, screen change) into notch UI updates.
///
/// Extracted from AppCoordinator with the P-tier refactor. The processing
/// rules themselves don't change here — what moved is the *ownership*:
/// AppCoordinator now just forwards `handleSystemEvent(_:)` to this
/// coordinator, keeping the top-level class focused on app lifecycle.
///
/// Two dependencies are passed as closures (`hideNotch`/`showNotch`)
/// rather than direct references because those actions live in
/// AppCoordinator and also touch state (`activeWindow`, async window
/// manager calls) that doesn't belong here.
@MainActor
final class SystemEventCoordinator {
    private let notchViewModel: NotchViewModel
    private let settingsService: SettingsServiceProtocol
    private let windowManager: NotchWindowManagerProtocol
    private let hideNotch: () -> Void
    private let showNotch: () -> Void

    init(
        notchViewModel: NotchViewModel,
        settingsService: SettingsServiceProtocol,
        windowManager: NotchWindowManagerProtocol,
        hideNotch: @escaping () -> Void,
        showNotch: @escaping () -> Void
    ) {
        self.notchViewModel = notchViewModel
        self.settingsService = settingsService
        self.windowManager = windowManager
        self.hideNotch = hideNotch
        self.showNotch = showNotch
    }

    /// Fire-and-forget entry point matching the previous AppCoordinator API.
    /// Wraps the async processing so call sites don't need to know it's async.
    func handle(_ event: SystemEvent) {
        Task { await process(event) }
    }

    // MARK: - Private

    private func process(_ event: SystemEvent) async {
        switch event {
        case .volumeChanged(let level):
            showHUD(.volume(level), value: Double(level))

        case .brightnessChanged(let level):
            showHUD(.brightness(level), value: Double(level))

        case .mediaPlaybackChanged(let isPlaying):
            handleMediaPlaybackChange(isPlaying: isPlaying)

        case .systemSleep:
            hideNotch()

        case .systemWake:
            // Only restore the notch if the user hasn't disabled it via
            // settings — respect their preference across sleep/wake cycles.
            let settings = await settingsService.getCurrentSettings()
            if settings.notchEnabled {
                showNotch()
            }

        case .screenParametersChanged:
            // The notch window manager handles its own KVO/notification
            // subscriptions; this call is the explicit "the system told
            // us, in case you missed it" prompt.
            Task {
                try await windowManager.updateNotchPosition()
            }
        }
    }

    /// Builds a system HUD payload and pushes it to the notch, expanding
    /// the notch if it wasn't already open so the user actually sees the
    /// volume/brightness change feedback.
    private func showHUD(_ type: SystemHUDType, value: Double) {
        let info = SystemHUDInfo(type: type, value: value, isMuted: false)
        let content = NotchContent.systemHUD(info: info)
        notchViewModel.setContent(content)
        if !notchViewModel.isExpanded {
            notchViewModel.expand(to: content)
        }
    }

    /// When the system reports music started playing, switch the notch
    /// content to the music player so the user can immediately see + control
    /// it. If the notch is already showing music, we leave it alone — the
    /// MusicPlayer view subscribes to MediaService and updates its own
    /// title/artist via Combine.
    private func handleMediaPlaybackChange(isPlaying: Bool) {
        guard isPlaying else { return }
        if case .musicPlayer = notchViewModel.currentContent { return }
        // Placeholder title/artist — the MusicPlayerViewModel will replace
        // these as soon as it gets a real NowPlayingInfo from MediaService.
        let musicContent = NotchContent.musicPlayer(
            isPlaying: isPlaying,
            title: "Now Playing",
            artist: "Unknown Artist"
        )
        notchViewModel.setContent(musicContent)
    }
}
