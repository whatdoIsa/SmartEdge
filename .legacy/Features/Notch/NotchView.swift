import SwiftUI

struct NotchView: View {
    @StateObject private var viewModel = NotchViewModel()
    @State private var isHovering = false
    @State private var isExpanded = false
    
    var body: some View {
        Group {
            if viewModel.isInitializing {
                InitializingNotchView()
                    .fadeTransition()
            } else if let error = viewModel.error {
                ErrorNotchView(error: error) {
                    Task {
                        await viewModel.reinitialize()
                    }
                }
                .fadeTransition()
            } else {
                ActiveNotchView(
                    isHovering: $isHovering,
                    isExpanded: $isExpanded
                )
                .environmentObject(viewModel)
                .fadeTransition()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isInitializing)
        .animation(.easeInOut(duration: 0.3), value: viewModel.error)
        .overlay(alignment: .bottom) {
            if let transientError = viewModel.transientError {
                ErrorToast(error: transientError)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .task {
            await viewModel.initialize()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notchStateChanged)) { _ in
            Task {
                await viewModel.refreshState()
            }
        }
    }
}

// MARK: - Initializing Notch View
private struct InitializingNotchView: View {
    var body: some View {
        HStack(spacing: 12) {
            LoadingSpinner(size: 16)
            
            Text("Initializing...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: NotchShape())
    }
}

// MARK: - Error Notch View  
private struct ErrorNotchView: View {
    let error: AppError
    let retry: () -> Void
    @State private var showingDetails = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14, weight: .medium))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Service Error")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                if showingDetails {
                    Text(error.localizedDescription)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .leading)))
                }
            }
            
            Spacer()
            
            Button("Retry") {
                retry()
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.accentColor)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: NotchShape())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingDetails.toggle()
            }
        }
    }
}

// MARK: - Active Notch View
private struct ActiveNotchView: View {
    @Binding var isHovering: Bool
    @Binding var isExpanded: Bool
    @EnvironmentObject private var viewModel: NotchViewModel
    @State private var showingStatusBar = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Collapsed notch view
            CompactNotchView(
                isHovering: $isHovering,
                isExpanded: $isExpanded,
                showingStatusBar: $showingStatusBar
            )
            
            // Expanded content
            if isExpanded {
                ExpandedNotchContent()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(.ultraThinMaterial, in: NotchShape(expanded: isExpanded))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
                if !hovering {
                    showingStatusBar = false
                }
            }
        }
        .onReceive(viewModel.hoverDetectionFailurePublisher) {
            Task { @MainActor in
                await viewModel.handleHoverFailure()
            }
        }
    }
}

// MARK: - Compact Notch View
private struct CompactNotchView: View {
    @Binding var isHovering: Bool
    @Binding var isExpanded: Bool
    @Binding var showingStatusBar: Bool
    @EnvironmentObject private var viewModel: NotchViewModel
    
    var body: some View {
        HStack(spacing: 0) {
            // Left status indicators
            LeftStatusView(isVisible: isHovering || showingStatusBar)
                .environmentObject(viewModel)
            
            Spacer()
            
            // Center content (time or mini music player)
            CenterNotchContent(
                isHovering: isHovering,
                showingStatusBar: showingStatusBar
            )
            .environmentObject(viewModel)
            
            Spacer()
            
            // Right status indicators
            RightStatusView(isVisible: isHovering || showingStatusBar)
                .environmentObject(viewModel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if isHovering {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingStatusBar = true
                }
                
                // Auto-hide status bar after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showingStatusBar = false
                    }
                }
            }
        }
    }
}

// MARK: - Left Status View
private struct LeftStatusView: View {
    let isVisible: Bool
    @EnvironmentObject private var viewModel: NotchViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            if viewModel.isServiceLoading {
                LoadingSpinner(size: 12)
            } else {
                // Wi-Fi indicator
                if let wifiStrength = viewModel.wifiStrength {
                    WifiIndicator(strength: wifiStrength, hasError: viewModel.hasNetworkError)
                } else if viewModel.hasNetworkError {
                    InlineErrorView("No WiFi", compact: true)
                } else {
                    SkeletonView(width: 16, height: 12, cornerRadius: 2)
                }
                
                // Bluetooth indicator
                if viewModel.bluetoothEnabled {
                    BluetoothIndicator(isConnected: viewModel.bluetoothConnected)
                } else if viewModel.hasBluetoothError {
                    InlineErrorView("BT Error", compact: true)
                }
            }
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isServiceLoading)
    }
}

// MARK: - Center Notch Content
private struct CenterNotchContent: View {
    let isHovering: Bool
    let showingStatusBar: Bool
    @EnvironmentObject private var viewModel: NotchViewModel
    
    var body: some View {
        Group {
            if showingStatusBar {
                CurrentTimeView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if viewModel.hasActiveMusicPlayer && isHovering {
                MiniMusicPlayerView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                // Default notch appearance
                RoundedRectangle(cornerRadius: 2)
                    .fill(.primary)
                    .frame(width: 4, height: 4)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showingStatusBar)
        .animation(.easeInOut(duration: 0.25), value: isHovering)
    }
}

// MARK: - Right Status View
private struct RightStatusView: View {
    let isVisible: Bool
    @EnvironmentObject private var viewModel: NotchViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            if viewModel.isServiceLoading {
                SkeletonView(width: 24, height: 12, cornerRadius: 2)
            } else {
                // Battery indicator
                if let batteryLevel = viewModel.batteryLevel {
                    BatteryIndicator(
                        level: batteryLevel,
                        isCharging: viewModel.isCharging,
                        hasError: viewModel.hasBatteryError
                    )
                } else if viewModel.hasBatteryError {
                    InlineErrorView("Battery", compact: true)
                } else {
                    SkeletonView(width: 24, height: 12, cornerRadius: 2)
                }
                
                // Control Center access
                ControlCenterButton()
                    .environmentObject(viewModel)
            }
        }
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isServiceLoading)
    }
}

// MARK: - WiFi Indicator
private struct WifiIndicator: View {
    let strength: Int
    let hasError: Bool
    
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(barColor(for: index))
                    .frame(width: 2, height: CGFloat(4 + index * 2))
                    .animation(.easeInOut(duration: 0.2), value: strength)
            }
        }
        .frame(width: 8, height: 8)
    }
    
    private func barColor(for index: Int) -> Color {
        if hasError {
            return .orange
        } else if index < strength {
            return .primary
        } else {
            return .primary.opacity(0.3)
        }
    }
}

// MARK: - Bluetooth Indicator
private struct BluetoothIndicator: View {
    let isConnected: Bool
    
    var body: some View {
        Image(systemName: "bluetooth")
            .font(.system(size: 8, weight: .medium))
            .foregroundColor(isConnected ? .accentColor : .secondary)
    }
}

// MARK: - Battery Indicator
private struct BatteryIndicator: View {
    let level: Double
    let isCharging: Bool
    let hasError: Bool
    
    var body: some View {
        HStack(spacing: 2) {
            // Battery body
            ZStack {
                RoundedRectangle(cornerRadius: 1)
                    .stroke(.primary, lineWidth: 0.5)
                    .frame(width: 16, height: 8)
                
                HStack {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(batteryColor)
                        .frame(width: 14 * level, height: 6)
                    
                    Spacer(minLength: 0)
                }
                .frame(width: 14, height: 6)
                .clipped()
                
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 4, weight: .bold))
                        .foregroundColor(.primary)
                }
            }
            
            // Battery tip
            RoundedRectangle(cornerRadius: 0.5)
                .fill(.primary)
                .frame(width: 1, height: 4)
        }
    }
    
    private var batteryColor: Color {
        if hasError {
            return .orange
        } else if level < 0.2 {
            return .red
        } else if level < 0.5 {
            return .yellow
        } else {
            return .green
        }
    }
}

// MARK: - Current Time View
private struct CurrentTimeView: View {
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Text(currentTime.formatted(date: .omitted, time: .shortened))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.primary)
            .onReceive(timer) { time in
                currentTime = time
            }
    }
}

// MARK: - Mini Music Player View  
private struct MiniMusicPlayerView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    
    var body: some View {
        HStack(spacing: 6) {
            if let nowPlaying = viewModel.currentTrack {
                Text(nowPlaying.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 80)
                
                Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.accentColor)
            } else {
                LoadingSpinner(size: 8)
                Text("Loading...")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Control Center Button
private struct ControlCenterButton: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    
    var body: some View {
        Button {
            Task {
                await viewModel.toggleControlCenter()
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Expanded Notch Content
private struct ExpandedNotchContent: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal, 16)
            
            if viewModel.isContentLoading {
                VStack(spacing: 12) {
                    SkeletonView(height: 48, cornerRadius: 8)
                        .padding(.horizontal, 16)
                    
                    SkeletonView(height: 24, cornerRadius: 4)
                        .padding(.horizontal, 16)
                }
            } else {
                // Quick settings
                QuickSettingsView()
                    .environmentObject(viewModel)
                
                // Active features (Music, Calendar, etc.)
                ActiveFeaturesView()
                    .environmentObject(viewModel)
            }
        }
        .padding(.bottom, 16)
    }
}

// MARK: - Quick Settings View
private struct QuickSettingsView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            QuickToggleButton(
                icon: "wifi",
                isOn: viewModel.wifiStrength != nil,
                isLoading: viewModel.isServiceLoading
            ) {
                Task {
                    await viewModel.toggleWiFi()
                }
            }
            
            QuickToggleButton(
                icon: "bluetooth",
                isOn: viewModel.bluetoothEnabled,
                isLoading: viewModel.isServiceLoading
            ) {
                Task {
                    await viewModel.toggleBluetooth()
                }
            }
            
            QuickToggleButton(
                icon: "moon",
                isOn: viewModel.isDarkMode,
                isLoading: false
            ) {
                Task {
                    await viewModel.toggleDarkMode()
                }
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Quick Toggle Button
private struct QuickToggleButton: View {
    let icon: String
    let isOn: Bool
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn ? .accent : .quaternary)
                        .frame(width: 32, height: 32)
                    
                    if isLoading {
                        LoadingSpinner(size: 12)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isOn ? .white : .secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Active Features View
private struct ActiveFeaturesView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    
    var body: some View {
        VStack(spacing: 8) {
            if viewModel.hasActiveMusicPlayer {
                MusicPlayerView()
                    .frame(height: 60)
            }
            
            if viewModel.hasActiveCalendar {
                CalendarPreviewView()
                    .frame(height: 40)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Calendar Preview View
private struct CalendarPreviewView: View {
    var body: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(.accentColor)
            
            Text("No events today")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - NotchShape
private struct NotchShape: Shape {
    let expanded: Bool
    
    init(expanded: Bool = false) {
        self.expanded = expanded
    }
    
    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = expanded ? 16 : 12
        
        return Path { path in
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        }
    }
}

#Preview {
    NotchView()
        .frame(width: 400, height: 200)
        .background(.black)
}