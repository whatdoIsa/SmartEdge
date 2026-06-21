import SwiftUI
import Combine
import AppKit

@MainActor
final class MusicPlayerViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var nowPlaying: NowPlayingInfo?
    @Published var isLoading = false
    @Published var isControlLoading = false
    @Published var error: AppError?
    @Published var transientError: AppError?
    /// Smoothly-ticking elapsed time for the progress bar. Driven by a
    /// 1-second timer while the track is playing and re-anchored to the
    /// authoritative `nowPlaying.elapsedTime` whenever a fresh metadata
    /// emission arrives. Surfaced as a separate `@Published` (rather
    /// than mutating `nowPlaying.elapsedTime` every second) so the view
    /// can bind directly without rebuilding the whole `NowPlayingInfo`
    /// struct on each tick.
    @Published var displayedElapsed: TimeInterval = 0
    /// Whether the app can read Now Playing. When `.needsPermission` the view
    /// shows a "grant access" affordance instead of the generic empty state.
    @Published var authorization: MediaAuthorizationStatus = .unknown
    /// Combined hash of the three display-driving properties. The View uses
    /// a single `.animation(value: displayStateHash)` instead of three
    /// separate modifiers so that simultaneous changes cause one SwiftUI
    /// render pass, not three.
    var displayStateHash: Int {
        var hasher = Hasher()
        hasher.combine(isLoading)
        hasher.combine(error?.localizedDescription)
        hasher.combine(nowPlaying?.title)
        hasher.combine(nowPlaying?.artist)
        hasher.combine(authorization)
        return hasher.finalize()
    }

    // MARK: - Private Properties
    private let mediaService: MediaServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var transientErrorTimer: Timer?
    /// Ticks `displayedElapsed` once per second while playing.
    private var progressTimer: Timer?
    private var stateObserver: NSObjectProtocol?
    /// Guards against repeated `initialize()` calls when the SwiftUI view
    /// containing this VM mounts/unmounts repeatedly (e.g. notch open/close).
    private var isInitialized = false

    // MARK: - Initialization
    init(mediaService: MediaServiceProtocol) {
        self.mediaService = mediaService
        setupBindings()
        // Notification observers are the single source of truth for state
        // refreshes; the View's `.onReceive` duplicate was removed.
        setupNotificationObservers()
    }

    deinit {
        transientErrorTimer?.invalidate()
        progressTimer?.invalidate()
        if let observer = stateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public Methods
    func initialize() async {
        guard !isInitialized else { return }
        // `isInitialized = true` used to live HERE — before the try. If
        // `mediaService.initialize()` then threw (helper launch race, perl
        // not in PATH yet, brief sandbox glitch), the flag stayed true
        // and every subsequent `.task` re-mount short-circuited, leaving
        // the player permanently stuck on "No Music Playing" until the
        // user quit and relaunched the app. Now we only flip the flag
        // after the initialize call succeeds, so a transient failure can
        // self-heal on the next view mount.
        isLoading = true
        error = nil

        do {
            try await mediaService.initialize()
            await refreshPlayerState()
            setupNotificationObservers()
            isInitialized = true
        } catch {
            await handleError(.mediaServiceUnavailable, transient: false)
        }

        isLoading = false
    }
    
    func refreshPlayerState() async {
        nowPlaying = mediaService.currentNowPlaying
        error = nil
    }
    
    func togglePlayPause() async {
        await performControlAction {
            try await mediaService.togglePlayPause()
        }
    }
    
    func nextTrack() async {
        await performControlAction {
            try await mediaService.nextTrack()
        }
    }
    
    func previousTrack() async {
        await performControlAction {
            try await mediaService.previousTrack()
        }
    }
    
    func toggleShuffle() async {
        await performControlAction {
            try await mediaService.toggleShuffle()
        }
    }
    
    func toggleRepeat() async {
        await performControlAction {
            try await mediaService.toggleRepeat()
        }
    }
    
    func openMusicApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// Surface the macOS Automation prompt so the user can grant SmartEdge
    /// permission to read the running player. Re-anchors state afterward.
    func requestAuthorization() async {
        await mediaService.requestMusicAuthorization()
        await refreshPlayerState()
    }

    /// Fallback when the prompt was already dismissed/denied: deep-link to the
    /// Automation pane where the user can flip the toggle manually.
    func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Listen for media service changes
        mediaService.currentTrackPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nowPlaying in
                guard let self = self else { return }
                self.nowPlaying = nowPlaying
                self.error = nil
                // Re-anchor the smoothly-ticking progress to whatever the
                // helper just reported, and start/stop the tick timer
                // based on the new playback state.
                self.displayedElapsed = nowPlaying?.elapsedTime ?? 0
                self.updateProgressTimer(isPlaying: nowPlaying?.isPlaying ?? false)
            }
            .store(in: &cancellables)

        mediaService.authorizationStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.authorization = status
            }
            .store(in: &cancellables)

        // Listen for media service errors
        //         mediaService.errorPublisher
        //             .receive(on: DispatchQueue.main)
        //             .sink { [weak self] error in
        //                 Task { @MainActor in
        //                     await self?.handleError(.unknownError(error.localizedDescription), transient: true)
        //                 }
        //             }
        //             .store(in: &cancellables)
    }
    
    /// Start or stop the 1-second progress tick. While playing, the
    /// view's progress bar moves smoothly between metadata updates
    /// (which can otherwise sit static for tens of seconds). On pause
    /// we tear the timer down so a paused track doesn't visually creep.
    /// Re-entering "playing" re-anchors on the next metadata pulse via
    /// `setupBindings`.
    private func updateProgressTimer(isPlaying: Bool) {
        progressTimer?.invalidate()
        progressTimer = nil
        guard isPlaying else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard let total = self.nowPlaying?.duration, total > 0 else { return }
                let next = self.displayedElapsed + 1
                self.displayedElapsed = min(next, total)
            }
        }
    }

    private func setupNotificationObservers() {
        if let existing = stateObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        stateObserver = NotificationCenter.default.addObserver(
            forName: .musicPlayerStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshPlayerState()
            }
        }
    }
    
    private func performControlAction(_ action: () async throws -> Void) async {
        isControlLoading = true
        
        do {
            try await action()
            await refreshPlayerState()
        } catch {
            await handleError(.unknownError("Control action failed"), transient: true)
        }
        
        isControlLoading = false
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
            Task { @MainActor [weak self] in
                self?.transientError = nil
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let musicPlayerStateChanged = Notification.Name("musicPlayerStateChanged")
}

// NowPlayingInfo is defined in MediaModels.swift

// MARK: - MediaService Protocol defined in MediaServiceProtocol.swift
// Mock MediaService is defined in ServiceProtocols.swift