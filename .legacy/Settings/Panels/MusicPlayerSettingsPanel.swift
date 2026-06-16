import SwiftUI

struct MusicPlayerSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var isPlaying = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                panelHeader
                
                enabledSection
                
                Divider()
                
                displaySection
                
                Divider()
                
                visualizerSection
                
                Divider()
                
                controlsSection
                
                Divider()
                
                permissionsSection
            }
            .padding()
        }
    }
    
    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Music Player")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            
            Text("Configure music player integration and visualization")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var enabledSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Integration")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show music player in notch", isOn: $settings.showMusicInNotch)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Display currently playing music information in the notch area")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                if settings.showMusicInNotch {
                    musicPlayerPreview
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var musicPlayerPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                // Album Art
                RoundedRectangle(cornerRadius: 8)
                    .fill(.blue.gradient)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sample Song Title")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Sample Artist")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if settings.enableVisualizer {
                        visualizerPreview
                    }
                }
                
                Spacer()
                
                if settings.musicControlsEnabled {
                    HStack(spacing: 8) {
                        Button(action: {}) {
                            Image(systemName: "backward.fill")
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { isPlaying.toggle() }) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {}) {
                            Image(systemName: "forward.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var visualizerPreview: some View {
        HStack(spacing: 2) {
            ForEach(0..<8) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(.blue.opacity(0.7))
                    .frame(width: 2, height: CGFloat.random(in: 4...12))
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: isPlaying
                    )
            }
        }
        .frame(height: 12)
    }
    
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Display Options")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show album artwork", isOn: $settings.showAlbumArt)
                    .disabled(!settings.showMusicInNotch)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Display album cover art alongside track information")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var visualizerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Visualization")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable audio visualizer", isOn: $settings.enableVisualizer)
                    .disabled(!settings.showMusicInNotch)
                    .onChange(of: settings.enableVisualizer) { newValue in
                        if newValue {
                            isPlaying = true
                        }
                    }
                
                if settings.enableVisualizer {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Visualizer Style")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("Style", selection: $settings.visualizerStyle) {
                            ForEach(VisualizerStyle.allCases, id: \.self) { style in
                                Text(style.title).tag(style.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Style Preview")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            visualizerStylePreview
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Real-time audio visualization that responds to music playback")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    @ViewBuilder
    private var visualizerStylePreview: some View {
        let style = VisualizerStyle(rawValue: settings.visualizerStyle) ?? .bars
        
        HStack(spacing: 4) {
            switch style {
            case .bars:
                ForEach(0..<12) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.blue.opacity(0.7))
                        .frame(width: 3, height: CGFloat.random(in: 6...20))
                        .animation(
                            .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.08),
                            value: isPlaying
                        )
                }
            case .wave:
                ForEach(0..<20) { index in
                    Circle()
                        .fill(.blue.opacity(0.5 + CGFloat.random(in: 0...0.5)))
                        .frame(width: 2, height: 2)
                        .offset(y: isPlaying ? CGFloat.random(in: -8...8) : 0)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.05),
                            value: isPlaying
                        )
                }
            case .circular:
                ZStack {
                    ForEach(0..<8) { index in
                        Circle()
                            .stroke(.blue.opacity(0.3), lineWidth: 1)
                            .frame(width: 20 + CGFloat(index) * 4)
                            .scaleEffect(isPlaying ? 1.0 + CGFloat.random(in: 0...0.3) : 1.0)
                            .animation(
                                .easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.1),
                                value: isPlaying
                            )
                    }
                }
            case .minimal:
                HStack(spacing: 3) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(.blue)
                            .frame(width: 4, height: 4)
                            .scaleEffect(isPlaying ? CGFloat.random(in: 0.8...1.2) : 1.0)
                            .animation(
                                .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                                value: isPlaying
                            )
                    }
                }
            }
        }
        .frame(height: 24)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            isPlaying.toggle()
        }
        .overlay(alignment: .bottom) {
            Text("Tap to test animation")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, -20)
        }
    }
    
    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Playback Controls")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable music controls", isOn: $settings.musicControlsEnabled)
                    .disabled(!settings.showMusicInNotch)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show play/pause and skip controls in the notch area")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                PermissionStatusView(
                    title: "Media Remote Access",
                    description: "Required to display and control music playback",
                    isGranted: true, // This would check actual permission status
                    action: {
                        requestMediaPermission()
                    }
                )
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SmartEdge needs permission to access media information and control playback. This enables displaying currently playing music and providing playback controls.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private func requestMediaPermission() {
        // Implement media permission request
        // This would use MediaPlayer or other frameworks to request access
    }
}

#Preview {
    MusicPlayerSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 900)
}