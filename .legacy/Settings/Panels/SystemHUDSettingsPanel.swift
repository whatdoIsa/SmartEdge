import SwiftUI

struct SystemHUDSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var showingHUDDemo = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                panelHeader
                
                enabledSection
                
                Divider()
                
                interceptSection
                
                Divider()
                
                displaySection
                
                Divider()
                
                permissionsSection
            }
            .padding()
        }
    }
    
    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "display")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("System HUD")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Test HUD") {
                    testHUD()
                }
                .font(.caption)
            }
            
            Text("Intercept and customize system HUD displays")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var enabledSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HUD Interception")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Intercept system HUD", isOn: $settings.interceptSystemHUD)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Replace system volume, brightness, and other HUD displays with notch-integrated versions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                if settings.interceptSystemHUD {
                    hudPreview
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var hudPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                // Volume HUD
                if settings.interceptVolume {
                    hudIndicator(
                        icon: "speaker.wave.2",
                        value: 0.7,
                        label: "Volume"
                    )
                }
                
                // Brightness HUD
                if settings.interceptBrightness {
                    hudIndicator(
                        icon: "sun.max",
                        value: 0.85,
                        label: "Brightness"
                    )
                }
                
                // Keyboard HUD
                if settings.interceptKeyboard {
                    hudIndicator(
                        icon: "keyboard",
                        value: 0.5,
                        label: "Backlight",
                        isDiscrete: true
                    )
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func hudIndicator(icon: String, value: Double, label: String, isDiscrete: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
            
            if isDiscrete {
                HStack(spacing: 3) {
                    ForEach(0..<16) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Double(index) < value * 16 ? .blue : .gray.opacity(0.3))
                            .frame(width: 3, height: 8)
                    }
                }
            } else {
                ProgressView(value: value)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(width: 60)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 80)
    }
    
    private var interceptSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HUD Types")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Volume controls", isOn: $settings.interceptVolume)
                    .disabled(!settings.interceptSystemHUD)
                
                Toggle("Brightness controls", isOn: $settings.interceptBrightness)
                    .disabled(!settings.interceptSystemHUD)
                
                Toggle("Keyboard backlight", isOn: $settings.interceptKeyboard)
                    .disabled(!settings.interceptSystemHUD)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose which system HUD displays to intercept and show in the notch")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Display Settings")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Duration")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Slider(value: $settings.hudDisplayDuration, in: 0.5...5.0, step: 0.5)
                            .disabled(!settings.interceptSystemHUD)
                        
                        Text(String(format: "%.1fs", settings.hudDisplayDuration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 35)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("How long HUD indicators remain visible after interaction")
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
            Text("System Permissions")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                PermissionStatusView(
                    title: "Accessibility Access",
                    description: "Required to intercept system HUD events",
                    isGranted: false, // This would check actual accessibility permission
                    action: {
                        openAccessibilitySettings()
                    }
                )
                
                PermissionStatusView(
                    title: "IOKit Framework Access",
                    description: "Required for low-level system event monitoring",
                    isGranted: true, // This would check IOKit access
                    action: {
                        // No action needed if already granted
                    }
                )
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System HUD interception requires elevated permissions to monitor hardware events. SmartEdge will request these permissions when first launched.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                if !settings.interceptSystemHUD {
                    HStack {
                        Text("⚠️ Enable HUD interception to access permission settings")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private func testHUD() {
        // Simulate HUD display for testing
        showingHUDDemo = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.hudDisplayDuration) {
            showingHUDDemo = false
        }
        
        // In real implementation, this would trigger the actual HUD system
    }
    
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - HUD Demo Overlay

struct HUDDemoOverlay: View {
    let isVisible: Bool
    let duration: Double
    
    var body: some View {
        if isVisible {
            VStack {
                HStack {
                    Spacer()
                    
                    VStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title)
                            .foregroundColor(.white)
                        
                        ProgressView(value: 0.7)
                            .progressViewStyle(.linear)
                            .tint(.white)
                            .frame(width: 120)
                        
                        Text("Volume")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding()
                    .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
                    
                    Spacer()
                }
                
                Spacer()
            }
            .padding()
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
            .animation(.easeInOut(duration: 0.3), value: isVisible)
        }
    }
}

#Preview {
    SystemHUDSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 800)
}