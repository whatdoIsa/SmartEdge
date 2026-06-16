import Foundation
import Combine

/// Starts and stops Spotify Web API polling based on whether the user is
/// actually looking at music in the notch.
///
/// Polling fires when ALL of these are true:
/// - notch is expanded
/// - notch content is `.musicPlayer`
/// - SpotifyService is signed in
///
/// When any input changes the gate is re-evaluated. Without this gate, an
/// always-on poll would run even when the notch is collapsed (invisible to
/// the user) — wasted API quota and battery for no benefit.
@MainActor
final class SpotifyPollingCoordinator {
    private let notchViewModel: NotchViewModel
    private let spotifyService: SpotifyService
    private var cancellables = Set<AnyCancellable>()
    private var pollingTask: Task<Void, Never>?

    /// 15s cadence: short enough for responsive track changes in the
    /// augmented Now Playing display, well under Spotify's published
    /// ~180 req/min/user rate limit.
    private let intervalNs: UInt64 = 15 * 1_000_000_000

    init(notchViewModel: NotchViewModel, spotifyService: SpotifyService) {
        self.notchViewModel = notchViewModel
        self.spotifyService = spotifyService
    }

    func start() {
        // Feature-flagged off while the Spotify integration is on hold.
        // No subscription, no polling, no Spotify API calls regardless of
        // sign-in state. Flip the flag back on to restore.
        guard FeatureFlags.isSpotifyEnabled else { return }
        // CombineLatest3 emits whenever any source changes AND has emitted
        // at least once. Each @Published source emits its initial value on
        // subscribe, so the first evaluation happens synchronously after
        // .sink — i.e. we don't need a separate "kickoff" call.
        Publishers.CombineLatest3(
            notchViewModel.$isExpanded,
            notchViewModel.$currentContent,
            spotifyService.$state
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] expanded, content, state in
            self?.evaluateGate(expanded: expanded, content: content, state: state)
        }
        .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        pollingTask?.cancel()
        pollingTask = nil
    }

    deinit {
        // pollingTask is cancellable from any thread.
        pollingTask?.cancel()
    }

    // MARK: - Private

    private func evaluateGate(expanded: Bool, content: NotchContent, state: SpotifyService.AuthState) {
        let isMusicContent: Bool
        if case .musicPlayer = content {
            isMusicContent = true
        } else {
            isMusicContent = false
        }
        let shouldPoll = expanded && isMusicContent && state == .signedIn

        if shouldPoll && pollingTask == nil {
            AppLogger.media.notice(
                "Spotify polling: START (expanded=\(expanded, privacy: .public) music=\(isMusicContent, privacy: .public) signedIn=\(state == .signedIn, privacy: .public))"
            )
            pollingTask = makePollingTask()
        } else if !shouldPoll, let task = pollingTask {
            AppLogger.media.notice(
                "Spotify polling: STOP (expanded=\(expanded, privacy: .public) music=\(isMusicContent, privacy: .public) signedIn=\(state == .signedIn, privacy: .public))"
            )
            task.cancel()
            pollingTask = nil
        }
    }

    private func makePollingTask() -> Task<Void, Never> {
        let spotify = spotifyService
        let interval = intervalNs
        return Task { [weak spotify] in
            while !Task.isCancelled {
                await spotify?.fetchPlayerState()
                do {
                    // Task.sleep is cancellation-aware — when the gate
                    // closes and we call task.cancel(), the sleep throws
                    // and we exit the loop cleanly.
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    break
                }
            }
        }
    }
}
