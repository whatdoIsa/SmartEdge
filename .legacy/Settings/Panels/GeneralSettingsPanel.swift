import SwiftUI

struct GeneralSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                panelHeader
                
                startupSection
                
                Divider()
                
                behaviorSection
                
                Divider()
                
                updatesSection
                
                Divider()
                
                aboutSection
            }
            .padding()
        }
    }
    
    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("General")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            
            Text("Configure basic app behavior and startup preferences")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Startup")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch SmartEdge at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { newValue in
                        configureLaunchAtLogin(newValue)
                    }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically start SmartEdge when you log in")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Behavior")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-hide when app loses focus", isOn: $settings.autoHideOnLostFocus)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically hide notch when switching to other applications")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Updates")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Check for updates automatically", isOn: $settings.checkUpdatesAutomatically)
                
                Toggle("Include beta updates", isOn: $settings.betaUpdates)
                    .disabled(!settings.checkUpdatesAutomatically)
                
                HStack {
                    Button("Check Now") {
                        checkForUpdates()
                    }
                    .disabled(!settings.checkUpdatesAutomatically)
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(.leading, 8)
        }
    }
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "app.badge")
                            .font(.title)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SmartEdge")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text("Version 1.0.0 (Build 1)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("A powerful notch utility for macOS")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            
            HStack(spacing: 16) {
                Button("Visit Website") {
                    openURL("https://smartedge.app")
                }
                
                Button("Report Issue") {
                    openURL("https://github.com/smartedge/issues")
                }
                
                Button("Release Notes") {
                    openURL("https://github.com/smartedge/releases")
                }
                
                Spacer()
            }
            .padding(.leading, 8)
        }
    }
    
    private func configureLaunchAtLogin(_ enabled: Bool) {
        // Configure launch at login using ServiceManagement
        // This would need proper implementation with SMAppService
    }
    
    private func checkForUpdates() {
        // Implement update checking logic
        let alert = NSAlert()
        alert.messageText = "No Updates Available"
        alert.informativeText = "You are running the latest version of SmartEdge."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    GeneralSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 700)
}