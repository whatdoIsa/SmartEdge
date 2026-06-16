import SwiftUI
import Combine

struct HUDView: View {
    // Must be @ObservedObject — same root cause as MusicPlayerView. A plain
    // `let viewModel` does not subscribe to `objectWillChange`, so when the
    // VM republishes `currentHUD` / `isInitializing` / `error`, this body
    // never re-runs and the child `ActiveHUDView(hudType:)` stays frozen
    // on the init-time value. That manifests as the notch HUD failing to
    // update when the volume/brightness key is hit again with a different
    // value, or refusing to dismiss after the underlying HUD clears.
    @ObservedObject var viewModel: HUDViewModel

    init(viewModel: HUDViewModel) {
        self.viewModel = viewModel
    }

    init() {
        // Default initializer for preview
        self.viewModel = HUDViewModel(
            systemService: PreviewMockSystemService(),
            systemHUDService: PreviewMockSystemHUDService()
        )
    }
    @State private var isVisible = false
    
    var body: some View {
        Group {
            if viewModel.isInitializing {
                InitializingHUDView()
                    .fadeTransition()
            } else if let error = viewModel.error {
                ErrorHUDView(error: error) {
                    Task {
                        await viewModel.reinitialize()
                    }
                }
                .fadeTransition()
            } else if let hudType = viewModel.currentHUD {
                ActiveHUDView(hudType: hudType)
                    .environmentObject(viewModel)
                    .fadeTransition()
            } else {
                EmptyView()
            }
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isVisible)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isInitializing)
        .animation(.easeInOut(duration: 0.25), value: viewModel.error)
        .overlay(alignment: .bottom) {
            if let transientError = viewModel.transientError {
                ErrorToast(error: transientError)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .task {
            await viewModel.initialize()
        }
        .onReceive(viewModel.hudVisibilityPublisher) { visible in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isVisible = visible
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .systemHUDDidShow)) { _ in
            Task {
                await viewModel.refreshState()
            }
        }
    }
}

// MARK: - Initializing HUD View
private struct InitializingHUDView: View {
    var body: some View {
        VStack(spacing: 12) {
            LoadingSpinner(size: 20)
            
            Text("Initializing HUD...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Error HUD View
private struct ErrorHUDView: View {
    let error: AppError
    let retry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("HUD Error")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(error.localizedDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                if let recovery = error.recoverySuggestion {
                    Text(recovery)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Button("Retry") {
                retry()
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.accentColor)
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Active HUD View
private struct ActiveHUDView: View {
    let hudType: SystemHUDType
    @EnvironmentObject private var viewModel: HUDViewModel

    var body: some View {
        VStack(spacing: 12) {
            HUDIcon(type: hudType, isMuted: viewModel.isMuted, isLoading: viewModel.isAdjusting)

            if viewModel.isAdjusting {
                SkeletonView(width: 120, height: 6, cornerRadius: 3)
            } else {
                HUDProgressBar(
                    value: viewModel.currentValue,
                    animationProgress: viewModel.currentValue,
                    isMuted: viewModel.isMuted
                )
                .frame(width: 120, height: 6)
            }

            if viewModel.isAdjusting {
                SkeletonView(width: 40, height: 12, cornerRadius: 2)
            } else {
                // When muted, swap the "63%" readout for an explicit
                // "Muted" label and dim the color. The progress bar's
                // diagonal slash + the slashed speaker icon + this label
                // together give three independent cues — readability
                // doesn't depend on any single channel (color, geometry,
                // or text).
                let isVolumeMuted: Bool = {
                    if case .volume = hudType, viewModel.isMuted { return true }
                    return false
                }()
                if isVolumeMuted {
                    Text("Muted")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text(formatValue(viewModel.currentValue, for: hudType))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func formatValue(_ value: Double, for type: SystemHUDType) -> String {
        switch type {
        case .volume, .brightness, .keyboardBacklight:
            return "\(Int(value * 100))%"
        case .airplayConnecting, .airplayConnected, .airplayDisconnected:
            return type.title
        case .doNotDisturb:
            return type.title
        }
    }
}

// MARK: - HUD Icon
private struct HUDIcon: View {
    let type: SystemHUDType
    let isMuted: Bool
    let isLoading: Bool

    /// Mute pre-empts the level-based volume icon. `SystemHUDType.iconName`
    /// only returns `speaker.slash.fill` when level == 0, so without this
    /// override a "mute key pressed while volume is 50%" state showed a
    /// normal speaker icon with no visual cue. Mirroring the macOS
    /// system HUD's behavior: slash + muted color the moment isMuted is
    /// true, regardless of the underlying level.
    private var iconName: String {
        if case .volume = type, isMuted {
            return "speaker.slash.fill"
        }
        return type.iconName
    }

    private var iconColor: Color {
        if case .volume = type, isMuted {
            return .secondary
        }
        return .primary
    }

    var body: some View {
        ZStack {
            if isLoading {
                LoadingSpinner(size: 16)
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
                    .symbolRenderingMode(.hierarchical)
                    .animation(.easeInOut(duration: 0.15), value: isMuted)
            }
        }
        .frame(width: 24, height: 24)
    }
}
