import SwiftUI

struct SystemHUDSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel
    // Permission state mirrors `SystemPermissionManager` so the row reflects
    // reality, not a hard-coded `false`. The manager polls every 1s, which
    // is plenty for a settings pane the user is staring at.
    @ObservedObject private var permissionManager = ServiceContainer.shared.systemPermissionManager
    
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

                // Inline warning when the user has the toggle ON but the OS
                // hasn't granted Accessibility yet. Without this banner the
                // toggle silently does nothing and the user assumes the
                // feature is broken. Permission row below this section is
                // the actual fix-it path; this is the breadcrumb pointing
                // them there.
                if settings.interceptSystemHUD && !permissionManager.hasAccessibilityPermission {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Accessibility permission required")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Grant access in System Settings → Privacy & Security → Accessibility to enable HUD interception.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
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
                    description: permissionManager.hasAccessibilityPermission
                        ? "Granted — HUD interception will activate when you enable it above."
                        : "Required to intercept system HUD events. Click to open System Settings.",
                    isGranted: permissionManager.hasAccessibilityPermission,
                    action: {
                        Task { @MainActor in
                            await permissionManager.requestAccessibilityPermission()
                            // If the prompt didn't appear (already-denied),
                            // open the settings pane directly as a fallback.
                            if !permissionManager.hasAccessibilityPermission {
                                permissionManager.openAccessibilityPreferencesPane()
                            }
                        }
                    }
                )

                PermissionStatusView(
                    title: "Input Monitoring",
                    description: permissionManager.hasInputMonitoringPermission
                        ? "Granted."
                        : "Recommended for full key coverage. Click to open System Settings.",
                    isGranted: permissionManager.hasInputMonitoringPermission,
                    action: {
                        permissionManager.openInputMonitoringPreferencesPane()
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
    
    // testHUD() / HUDDemoOverlay / showingHUDDemo were a placeholder demo
    // that never rendered (the overlay was never mounted in the panel
    // tree). With the real HUD intercept landing, the panel's preview
    // section already provides live visual confirmation, so the demo
    // scaffold was removed alongside the dead overlay struct.
    //
    // openAccessibilitySettings() also lived here — the permissionsSection
    // now delegates to `SystemPermissionManager`, which is the single
    // source of truth for opening privacy panes.
}

#Preview {
    SystemHUDSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 800)
}