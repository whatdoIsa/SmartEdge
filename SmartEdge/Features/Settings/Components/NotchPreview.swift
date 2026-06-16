import SwiftUI

struct NotchPreview: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var isExpanded = false
    @State private var animationTrigger = false
    /// Strong reference to the 3s repeat timer so we can invalidate it
    /// on view disappearance. Without this @State holder the timer was a
    /// detached fire-and-forget: opening/closing the Settings panel a few
    /// times stacked multiple live timers, each firing every 3s and
    /// retaining the view's animation state.
    @State private var animationTimer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                
                HStack {
                    Spacer()
                    
                    notchContent
                        .frame(width: isExpanded ? 300 : 180, height: 36)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: settings.cornerRadius))
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: settings.cornerRadius)
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        )
                        .scaleEffect(isExpanded ? 1.05 : 1.0)
                        .animation(
                            .spring(response: settings.animationSpeed, dampingFraction: 0.8),
                            value: isExpanded
                        )
                        .animation(
                            .spring(response: settings.animationSpeed, dampingFraction: 0.8),
                            value: animationTrigger
                        )
                        .onTapGesture {
                            withAnimation(.spring(response: settings.animationSpeed, dampingFraction: 0.8)) {
                                isExpanded.toggle()
                            }
                        }
                        .onHover { hovering in
                            if settings.hoverBehavior != HoverBehavior.none.rawValue {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isExpanded = hovering
                                }
                            }
                        }
                    
                    Spacer()
                }
                
                Spacer()
                
                previewControls
            }
        }
        .onAppear {
            startPeriodicAnimation()
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }
    
    @ViewBuilder
    private var notchContent: some View {
        let priority = NotchPriorityPreset(rawValue: settings.notchContentPriority) ?? .balanced
        
        HStack(spacing: 12) {
            switch priority {
            case .music:
                musicContent
                if isExpanded {
                    systemStatusContent
                }
                
            case .calendar:
                calendarContent
                if isExpanded {
                    systemStatusContent
                }
                
            case .system:
                systemStatusContent
                if isExpanded {
                    musicContent
                }
                
            case .balanced:
                if isExpanded {
                    musicContent
                    Divider()
                        .frame(height: 20)
                        .opacity(0.5)
                    calendarContent
                } else {
                    balancedContent
                }
            }
            
            if isExpanded && settings.hoverBehavior == HoverBehavior.showControls.rawValue {
                Divider()
                    .frame(height: 20)
                    .opacity(0.5)
                
                controlButtons
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .clipped()
    }
    
    private var musicContent: some View {
        HStack(spacing: 8) {
            if settings.showAlbumArt {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.blue.gradient)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Song Title")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if isExpanded {
                    Text("Artist Name")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            if settings.enableVisualizer {
                visualizer
            }
        }
    }
    
    private var calendarContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("Team Meeting")
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if isExpanded {
                    Text("2:00 PM - 3:00 PM")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("2:00 PM")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
    
    private var systemStatusContent: some View {
        HStack(spacing: 8) {
            if settings.showBatteryStatus {
                HStack(spacing: 3) {
                    Image(systemName: "battery.75")
                        .font(.caption2)
                        .foregroundColor(.green)
                    
                    if isExpanded {
                        Text("75%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if settings.showBluetoothStatus {
                HStack(spacing: 3) {
                    Image(systemName: "bluetooth")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    
                    if isExpanded {
                        Text("2")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.2), in: RoundedRectangle(cornerRadius: 2))
                            .foregroundColor(.blue)
                    }
                }
            }
        }
    }
    
    private var balancedContent: some View {
        HStack(spacing: 8) {
            // Show music or calendar based on what would be prioritized
            Image(systemName: "music.note")
                .font(.caption)
                .foregroundColor(.blue)
            
            Text("Now Playing")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
            
            if settings.enableVisualizer {
                miniVisualizer
            }
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: 6) {
            Button(action: {}) {
                Image(systemName: "backward.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            
            Button(action: {}) {
                Image(systemName: "play.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            
            Button(action: {}) {
                Image(systemName: "forward.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(.secondary)
    }
    
    private var visualizer: some View {
        HStack(spacing: 1) {
            ForEach(0..<6) { index in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.blue.opacity(0.7))
                    .frame(width: 2, height: CGFloat.random(in: 3...8))
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: animationTrigger
                    )
            }
        }
        .frame(height: 8)
    }
    
    private var miniVisualizer: some View {
        HStack(spacing: 1) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.blue.opacity(0.7))
                    .frame(width: 1.5, height: CGFloat.random(in: 2...6))
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animationTrigger
                    )
            }
        }
        .frame(height: 6)
    }
    
    private var previewControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Click to test expand/collapse • Hover to test hover behavior")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            HStack(spacing: 16) {
                Button("Test Animation") {
                    withAnimation(.spring(response: settings.animationSpeed, dampingFraction: 0.8)) {
                        animationTrigger.toggle()
                    }
                }
                .font(.caption)
                
                Button(isExpanded ? "Collapse" : "Expand") {
                    withAnimation(.spring(response: settings.animationSpeed, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
                .font(.caption)
                
                Spacer()
                
                Text("Preview responds to your settings changes")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    private func startPeriodicAnimation() {
        // Re-entrancy guard: SwiftUI can fire `.onAppear` multiple times
        // (NavigationSplitView re-layout, parent re-render) and without
        // this each pass would leak a fresh timer.
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.1)) {
                animationTrigger.toggle()
            }
        }
    }
}

// MARK: - Simplified Notch Preview

struct SimpleNotchPreview: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var isExpanded = false
    
    var body: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 8) {
                Circle()
                    .fill(.blue)
                    .frame(width: 8, height: 8)
                
                Text("SmartEdge Preview")
                    .font(.caption)
                    .fontWeight(.medium)
                
                if isExpanded {
                    Text("• Expanded")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: settings.cornerRadius))
            .scaleEffect(isExpanded ? 1.1 : 1.0)
            .animation(.spring(response: settings.animationSpeed, dampingFraction: 0.8), value: isExpanded)
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }
            
            Spacer()
        }
        .frame(height: 60)
    }
}

#Preview("Full Notch Preview") {
    NotchPreview()
        .environmentObject(SettingsViewModel())
        .frame(width: 500, height: 200)
        .background(.gray.opacity(0.1))
}

#Preview("Simple Preview") {
    SimpleNotchPreview()
        .environmentObject(SettingsViewModel())
        .frame(width: 400, height: 100)
        .background(.gray.opacity(0.1))
}