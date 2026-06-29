import SwiftUI
import Combine

struct MusicPlayerView: View {
    // Must be @ObservedObject — `let viewModel` does not subscribe to the
    // VM's `objectWillChange`, so when `nowPlaying` is republished (track
    // change, play/pause flip, artwork arrival) the parent body never
    // re-runs. The child `ActiveMusicPlayerView` receives `nowPlaying` via
    // its init, so without a body re-run that struct is permanently
    // initialized with whatever value was visible at first mount — which
    // is exactly the "track doesn't update, play button doesn't toggle"
    // bug surfaced by the user. ActiveMusicPlayerView's own EnvironmentObject
    // subscription only re-renders that child's body, not its `let`
    // properties — those are captured at init time.
    @ObservedObject var viewModel: MusicPlayerViewModel

    init(viewModel: MusicPlayerViewModel) {
        self.viewModel = viewModel
    }

    init() {
        // Default initializer for preview
        self.viewModel = MusicPlayerViewModel(
            mediaService: PreviewMockMediaService()
        )
    }
    
    var body: some View {
        Group {
            if viewModel.isLoading {
                MusicPlayerSkeleton()
                    .fadeTransition()
            } else if let error = viewModel.error {
                ErrorView(error: error) {
                    Task {
                        await viewModel.refreshPlayerState()
                    }
                }
                .fadeTransition()
            } else if viewModel.authorization == .needsPermission {
                EmptyStateView(
                    icon: "lock.fill",
                    title: "음악 권한 필요",
                    subtitle: "노치에 곡을 표시하려면 Apple Music · Spotify 제어를 허용해 주세요",
                    actionTitle: "권한 허용",
                    action: {
                        Task { await viewModel.requestAuthorization() }
                    }
                )
                .fadeTransition()
            } else if viewModel.nowPlaying == nil {
                EmptyStateView(
                    icon: "music.note",
                    title: "No Music Playing",
                    subtitle: "Start playing music to see controls here",
                    actionTitle: "Open Music App",
                    action: {
                        viewModel.openMusicApp()
                    }
                )
                .fadeTransition()
            } else {
                ActiveMusicPlayerView(nowPlaying: viewModel.nowPlaying!)
                    .environmentObject(viewModel)
                    .fadeTransition()
            }
        }
        // Single animation driven by a unified display-state hash. Three
        // separate `.animation(value:)` modifiers each created an independent
        // SwiftUI transaction; when isLoading, error, and nowPlaying changed
        // together they could fire three render passes. One `.animation`
        // on a combined hashValue is one pass.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: viewModel.displayStateHash)
        .overlay(alignment: .topTrailing) {
            if let error = viewModel.transientError {
                ErrorToast(error: error)
                    .padding(.top, 8)
                    .padding(.trailing, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .task {
            await viewModel.initialize()
        }
        // `.onReceive` for `.musicPlayerStateChanged` was removed. The
        // ViewModel's `setupNotificationObservers()` already handles this
        // notification and updates `nowPlaying` — the View having its own
        // subscription caused `refreshPlayerState()` to run twice per event.
    }
}

// MARK: - Active Music Player View
private struct ActiveMusicPlayerView: View {
    let nowPlaying: NowPlayingInfo
    @EnvironmentObject private var viewModel: MusicPlayerViewModel

    private var displayedTitle: String { nowPlaying.title ?? "Unknown Track" }
    private var displayedArtist: String { nowPlaying.artist ?? "Unknown Artist" }
    /// Read from the view model's smoothly-ticking value instead of the
    /// `NowPlayingInfo.progress` snapshot, otherwise the progress bar
    /// sits frozen between helper emissions (which only fire on actual
    /// player events, not at a 1Hz cadence).
    private var displayedProgress: TimeInterval? {
        guard nowPlaying.duration > 0 else { return nil }
        return viewModel.displayedElapsed
    }
    private var displayedDuration: TimeInterval { nowPlaying.duration }

    var body: some View {
        // Fills the expanded notch: artwork + track info pinned to the top,
        // progress in the middle, transport controls centered at the bottom —
        // a full now-playing surface rather than a compact one-liner.
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                AlbumArtworkView(
                    artwork: nowPlaying.artwork,
                    size: NotchTheme.artworkSize,
                    cornerRadius: NotchTheme.artworkCornerRadius
                )
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayedTitle)
                        .font(.system(size: NotchTheme.trackTitleSize, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    Text(displayedArtist)
                        .font(.system(size: NotchTheme.trackArtistSize))
                        .foregroundColor(.white.opacity(NotchTheme.trackArtistOpacity))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(nowPlaying.isPlaying ? "Playing" : "Paused"): \(displayedTitle) by \(displayedArtist)")

                Spacer(minLength: 8)
            }

            Spacer(minLength: 10)

            if let progress = displayedProgress, displayedDuration > 0 {
                NotchProgressBar(progress: progress, duration: displayedDuration)
                Spacer(minLength: 10)
            }

            TransportControls(
                isPlaying: nowPlaying.isPlaying,
                isLoading: viewModel.isControlLoading
            )
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

// MARK: - Transport Controls
private struct TransportControls: View {
    let isPlaying: Bool
    let isLoading: Bool
    @EnvironmentObject private var viewModel: MusicPlayerViewModel

    var body: some View {
        HStack(spacing: 14) {
            Button {
                Task { await viewModel.previousTrack() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: NotchTheme.transportGlyphSize * 0.66, weight: .medium))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous track")

            // Primary action: filled white circle, inverted glyph.
            Button {
                Task { await viewModel.togglePlayPause() }
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: NotchTheme.playButtonDiameter, height: NotchTheme.playButtonDiameter)
                    if isLoading {
                        LoadingSpinner(size: NotchTheme.playGlyphSize)
                    } else {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: NotchTheme.playGlyphSize, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            Button {
                Task { await viewModel.nextTrack() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: NotchTheme.transportGlyphSize * 0.66, weight: .medium))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next track")
        }
    }
}

// MARK: - Notch Progress Bar
private struct NotchProgressBar: View {
    let progress: TimeInterval
    let duration: TimeInterval

    private var ratio: Double {
        guard duration > 0 else { return 0 }
        return min(max(progress / duration, 0), 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(NotchTheme.progressTrackOpacity))
                        .frame(height: NotchTheme.progressBarHeight)
                    Capsule()
                        .fill(.white)
                        .frame(width: geo.size.width * ratio, height: NotchTheme.progressBarHeight)
                        // 1s linear matches the 1Hz tick so the fill glides.
                        .animation(.linear(duration: 1.0), value: ratio)
                }
            }
            .frame(height: NotchTheme.progressBarHeight)

            HStack {
                Text(formatTime(progress))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.white.opacity(NotchTheme.progressTimeOpacity))
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    MusicPlayerView()
        .frame(width: 480, height: 160)
        .background(.black)
}