import SwiftUI

struct MusicPlayerView: View {
    @StateObject private var viewModel = MusicPlayerViewModel()
    
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
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.25), value: viewModel.error)
        .animation(.easeInOut(duration: 0.25), value: viewModel.nowPlaying)
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
        .onReceive(NotificationCenter.default.publisher(for: .musicPlayerStateChanged)) { _ in
            Task {
                await viewModel.refreshPlayerState()
            }
        }
    }
}

// MARK: - Active Music Player View
private struct ActiveMusicPlayerView: View {
    let nowPlaying: NowPlayingInfo
    @EnvironmentObject private var viewModel: MusicPlayerViewModel
    @State private var isExpanded = false
    @State private var showingControls = false
    
    var body: some View {
        VStack(spacing: 0) {
            CompactPlayerView(
                nowPlaying: nowPlaying,
                isExpanded: $isExpanded,
                showingControls: $showingControls
            )
            
            if isExpanded {
                ExpandedPlayerView(nowPlaying: nowPlaying)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
    @Binding var isExpanded: Bool
    @Binding var showingControls: Bool
    @EnvironmentObject private var viewModel: MusicPlayerViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Album artwork with loading state
            AlbumArtworkView(
                artwork: nowPlaying.artwork,
                size: 48
            )
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(nowPlaying.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(nowPlaying.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 8)
            
            // Media controls with loading states
            MediaControlsView(
                isPlaying: nowPlaying.isPlaying,
                isVisible: showingControls,
                isLoading: viewModel.isControlLoading
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: - Album Artwork View
private struct AlbumArtworkView: View {
    let artwork: NSImage?
    let size: CGFloat
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if let artwork = artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .onAppear {
                        isLoading = false
                    }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                    
                    if isLoading {
                        LoadingSpinner(size: 16)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 16, weight: .light))
                            .foregroundColor(.secondary)
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        isLoading = false
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
    }
}

// MARK: - Expanded Player View
private struct ExpandedPlayerView: View {
    let nowPlaying: NowPlayingInfo
    @EnvironmentObject private var viewModel: MusicPlayerViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            Divider()
                .padding(.horizontal, 16)
            
            // Progress bar with loading state
            if let progress = nowPlaying.progress, let duration = nowPlaying.duration {
                ProgressBarView(
                    progress: progress,
                    duration: duration,
                    isLoading: viewModel.isControlLoading
                )
                .padding(.horizontal, 16)
            } else {
                SkeletonView(height: 6, cornerRadius: 3)
                    .padding(.horizontal, 16)
            }
            
            // Additional controls
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
                        .fill(.accent)
                        .frame(
                            width: geometry.size.width * progressRatio,
                            height: 6
                        )
                        .animation(.linear(duration: 0.1), value: progressRatio)
                    
                    // Loading overlay
                    if isLoading {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.accent.opacity(0.3))
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