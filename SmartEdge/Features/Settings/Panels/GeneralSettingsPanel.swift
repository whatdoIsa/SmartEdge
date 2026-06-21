import SwiftUI

struct GeneralSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPanelHeader(
                    icon: "gearshape",
                    title: "General",
                    subtitle: "Configure basic app behavior and startup preferences"
                )

                startupSection

                behaviorSection

                updatesSection

                aboutSection
            }
            .padding()
        }
    }

    private var startupSection: some View {
        SettingsCard("Startup") {
            SettingRow(
                toggle: "Launch SmartEdge at login",
                description: "Automatically start SmartEdge when you log in",
                isOn: $settings.launchAtLogin
            )
            .onChange(of: settings.launchAtLogin) { newValue in
                configureLaunchAtLogin(newValue)
            }
        }
    }

    private var behaviorSection: some View {
        SettingsCard("Behavior") {
            SettingRow(
                toggle: "Auto-hide when app loses focus",
                description: "Automatically hide notch when switching to other applications",
                isOn: $settings.autoHideOnLostFocus
            )
        }
    }

    private var updatesSection: some View {
        SettingsCard("Updates") {
            SettingRow(
                toggle: "Check for updates automatically",
                isOn: $settings.checkUpdatesAutomatically
            )

            SettingsRowDivider()

            SettingRow(
                toggle: "Include beta updates",
                isOn: $settings.betaUpdates,
                isEnabled: settings.checkUpdatesAutomatically
            )

            SettingsRowDivider()

            SettingRow(title: "Check for updates now") {
                Button("Check Now") { checkForUpdates() }
                    .disabled(!settings.checkUpdatesAutomatically)
            }
        }
    }

    private var aboutSection: some View {
        SettingsCard("About") {
            SettingRow(
                title: "SmartEdge",
                description: "Version 1.0.0 (Build 1) — a powerful notch utility for macOS"
            ) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            SettingsRowDivider()

            SettingRow(title: "Links") {
                HStack(spacing: 12) {
                    Button("Website") { openURL("https://smartedge.app") }
                    Button("Report Issue") { openURL("https://github.com/smartedge/issues") }
                    Button("Release Notes") { openURL("https://github.com/smartedge/releases") }
                }
            }
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