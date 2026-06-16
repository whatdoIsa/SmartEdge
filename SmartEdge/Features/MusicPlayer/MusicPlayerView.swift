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
    @State private var isExpanded = false
    @State private var showingControls = false

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
        VStack(spacing: 0) {
            CompactPlayerView(
                nowPlaying: nowPlaying,
                displayedTitle: displayedTitle,
                displayedArtist: displayedArtist,
                isExpanded: $isExpanded,
                showingControls: $showingControls
            )

            if isExpanded {
                ExpandedPlayerView(
                    nowPlaying: nowPlaying,
                    displayedProgress: displayedProgress,
                    displayedDuration: displayedDuration
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Side gutters so the title row, progress bar, and transport
        // controls don't hug the curved corners of the notch shape.
        // Vertical breathing room at the bottom keeps the row above the
        // bottom edge — without it the shuffle/repeat buttons feel like
        // they're falling off the box.
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        // Background intentionally NOT applied here. The host (NotchView)
        // already paints a solid black notch background, and the previous
        // `.ultraThinMaterial` overlay produced a translucent gray card
        // floating *over* that black surface — exactly the "two-tone
        // floating card" effect the user flagged as ugly. Leaving the
        // background transparent lets the player chrome read as part of
        // the notch instead of a separate sheet.
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showingControls = hovering
            }
        }
    }
}

// MARK: - Compact Player View
private struct CompactPlayerView: View {
    let nowPlaying: NowPlayingInfo
    let displayedTitle: String
    let displayedArtist: String
    @Binding var isExpanded: Bool
    @Binding var showingControls: Bool
    @EnvironmentObject private var viewModel: MusicPlayerViewModel

    private var trackAccessibilityLabel: String {
        let state = nowPlaying.isPlaying ? "Playing" : "Paused"
        return "\(state): \(displayedTitle) by \(displayedArtist)"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Album artwork with loading state
            AlbumArtworkView(
                artwork: nowPlaying.artwork,
                size: 48
            )
            .accessibilityHidden(true)

            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(displayedTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(displayedArtist)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(trackAccessibilityLabel)

            Spacer(minLength: 8)

            // Hover toggles between visualizer (idle) and media controls (active).
            ZStack {
                MusicVisualizerView(
                    isPlaying: nowPlaying.isPlaying,
                    isVisible: !showingControls && nowPlaying.isPlaying
                )
                .accessibilityHidden(true)

                MediaControlsView(
                    isPlaying: nowPlaying.isPlaying,
                    isVisible: showingControls,
                    isLoading: viewModel.isControlLoading
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityHint("Tap to expand player")
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: - Media Controls View
private struct MediaControlsView: View {
    let isPlaying: Bool
    let isVisible: Bool
    let isLoading: Bool
    @EnvironmentObject private var viewModel: MusicPlayerViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            // Previous button
            MediaButton(
                icon: "backward.fill",
                size: 20,
                isVisible: isVisible,
                isLoading: isLoading
            ) {
                Task {
                    await viewModel.previousTrack()
                }
            }
            
            // Play/Pause button
            MediaButton(
                icon: isPlaying ? "pause.fill" : "play.fill",
                size: 24,
                isVisible: true,
                isLoading: isLoading
            ) {
                Task {
                    await viewModel.togglePlayPause()
                }
            }
            
            // Next button
            MediaButton(
                icon: "forward.fill",
                size: 20,
                isVisible: isVisible,
                isLoading: isLoading
            ) {
                Task {
                    await viewModel.nextTrack()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVisible)
    }
}

// MARK: - Media Button
private struct MediaButton: View {
    let icon: String
    let size: CGFloat
    let isVisible: Bool
    let isLoading: Bool
    let action: () -> Void

    @State private var isPressed = false

    private var accessibilityLabel: String {
        switch icon {
        case "backward.fill": return "Previous track"
        case "forward.fill": return "Next track"
        case "play.fill": return "Play"
        case "pause.fill": return "Pause"
        case "shuffle": return "Toggle shuffle"
        case "repeat": return "Toggle repeat"
        default: return "Media control"
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    LoadingSpinner(size: size * 0.6)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: size * 0.6, weight: .medium))
                }
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary, in: Circle())
        .foregroundColor(.primary)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) {
            // Long press ended
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
        .disabled(isLoading)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isLoading ? "Loading" : "")
    }
}

// MARK: - Expanded Player View
private struct ExpandedPlayerView: View {
    let nowPlaying: NowPlayingInfo
    let displayedProgress: TimeInterval?
    let displayedDuration: TimeInterval
    @EnvironmentObject private var viewModel: MusicPlayerViewModel

    var body: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal, 16)

            if let progress = displayedProgress, displayedDuration > 0 {
                ProgressBarView(
                    progress: progress,
                    duration: displayedDuration,
                    isLoading: viewModel.isControlLoading
                )
                .padding(.horizontal, 16)
            } else {
                SkeletonView(height: 6, cornerRadius: 3)
                    .padding(.horizontal, 16)
            }

            AdditionalControlsView()
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
    }
}

// MARK: - Progress Bar View
private struct ProgressBarView: View {
    let progress: TimeInterval
    let duration: TimeInterval
    let isLoading: Bool
    
    private var progressRatio: Double {
        guard duration > 0 else { return 0 }
        return min(max(progress / duration, 0), 1)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(height: 6)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.tint)
                        .frame(
                            width: geometry.size.width * progressRatio,
                            height: 6
                        )
                        // 1.0s linear interpolation matches the 1Hz tick
                        // in MusicPlayerViewModel. Without this match the
                        // ratio jumps once per second and reads as choppy
                        // — the bar should glide between ticks just like
                        // the system Now Playing widget does.
                        .animation(.linear(duration: 1.0), value: progressRatio)

                    // Loading overlay
                    if isLoading {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(height: 6)
                    }
                }
            }
            .frame(height: 6)
            
            // Time labels
            HStack {
                Text(formatTime(progress))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatTime(duration))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Additional Controls View
private struct AdditionalControlsView: View {
    @EnvironmentObject private var viewModel: MusicPlayerViewModel
    
    var body: some View {
        HStack {
            // Shuffle button
            Button {
                Task {
                    await viewModel.toggleShuffle()
                }
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Volume control
            VolumeControlView()
            
            Spacer()
            
            // Repeat button
            Button {
                Task {
                    await viewModel.toggleRepeat()
                }
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Volume Control View
private struct VolumeControlView: View {
    @State private var volume: Double = 0.5
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            
            Slider(value: $volume, in: 0...1)
                .frame(width: 60)
                .accentColor(.primary)
        }
    }
}

#Preview {
    MusicPlayerView()
        .frame(width: 320, height: 200)
        .background(.black)
}