import SwiftUI

struct PrivacySettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPanelHeader(
                    icon: "hand.raised",
                    title: "Privacy",
                    subtitle: "Control data collection and privacy settings",
                    tint: .blue
                )

                dataCollectionSection

                collectionDetailSection

                dataStorageSection

                securitySection
            }
            .padding()
        }
    }

    private var dataCollectionSection: some View {
        SettingsCard("Data Collection") {
            SettingRow(
                toggle: "Enable analytics",
                description: "Collect anonymous usage statistics to help improve the app",
                isOn: $settings.enableAnalytics
            )

            SettingsRowDivider()

            SettingRow(
                toggle: "Enable crash reporting",
                description: "Send crash reports and error logs to diagnose problems",
                isOn: $settings.enableCrashReporting
            )

            SettingsRowDivider()

            SettingRow(
                toggle: "Share anonymous usage data",
                description: "Share macOS version and hardware type to guide development",
                isOn: $settings.shareUsageData,
                isEnabled: settings.enableAnalytics
            )
        }
    }

    private var collectionDetailSection: some View {
        SettingsCard("What Is Collected") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Data collected may include:")
                    .font(.system(size: 12, weight: .medium))

                VStack(alignment: .leading, spacing: 6) {
                    dataItem("Feature usage frequency", isCollected: settings.enableAnalytics)
                    dataItem("App performance metrics", isCollected: settings.enableAnalytics)
                    dataItem("Crash reports and error logs", isCollected: settings.enableCrashReporting)
                    dataItem("macOS version and hardware type", isCollected: settings.shareUsageData)
                }

                Text("Data never collected:")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    dataItem("Personal files or content", isCollected: false, isNeverCollected: true)
                    dataItem("Calendar events or details", isCollected: false, isNeverCollected: true)
                    dataItem("Music library or playlists", isCollected: false, isNeverCollected: true)
                    dataItem("Browsing history or personal data", isCollected: false, isNeverCollected: true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func dataItem(_ text: String, isCollected: Bool, isNeverCollected: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isNeverCollected ? "xmark.circle" : (isCollected ? "checkmark.circle" : "circle"))
                .font(.system(size: 11))
                .foregroundColor(isNeverCollected ? .red : (isCollected ? .green : .gray))

            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private var dataStorageSection: some View {
        SettingsCard("Data Management") {
            SettingRow(
                title: "Application Support",
                description: "App preferences and settings"
            ) {
                storageButton("~/Library/Application Support/SmartEdge/")
            }

            SettingsRowDivider()

            SettingRow(
                title: "Shelf Storage",
                description: "Files stored on the shelf"
            ) {
                storageButton("~/Library/Application Support/SmartEdge/Shelf/")
            }

            SettingsRowDivider()

            SettingRow(
                title: "Cache",
                description: "Temporary cache files"
            ) {
                storageButton("~/Library/Caches/SmartEdge/")
            }

            SettingsRowDivider()

            SettingRow(
                title: "Reset all data",
                description: "Permanently delete settings, shelf files, and cache. This cannot be undone."
            ) {
                Button("Reset All Data") {
                    resetAllData()
                }
                .foregroundColor(.red)
            }
        }
    }

    private func storageButton(_ path: String) -> some View {
        Button("Show in Finder") {
            openPath(path)
        }
    }

    private var securitySection: some View {
        SettingsCard("Security") {
            VStack(alignment: .leading, spacing: 12) {
                Text("SmartEdge does not connect to external servers or transmit personal data over the internet.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                securityFeature(
                    icon: "network.slash",
                    title: "No Network Access",
                    description: "App operates entirely offline"
                )

                securityFeature(
                    icon: "lock.shield",
                    title: "Local Data Only",
                    description: "All data stays on your Mac"
                )

                securityFeature(
                    icon: "checkmark.shield",
                    title: "Sandboxed Environment",
                    description: "Runs in protected macOS sandbox"
                )

                securityFeature(
                    icon: "key",
                    title: "System Keychain",
                    description: "Secure storage for sensitive data"
                )

                HStack {
                    Button("Open Privacy & Security Settings") {
                        openSystemPrivacySettings()
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func securityFeature(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.green)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private func openSystemPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?General") {
            NSWorkspace.shared.open(url)
        }
    }

    private func resetAllData() {
        let alert = NSAlert()
        alert.messageText = "Reset All Data"
        alert.informativeText = "This will permanently delete all SmartEdge data, including settings, shelf files, and cache. This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Reset All Data")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            settings.resetToDefaults()
        }
    }

    private func openPath(_ path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    PrivacySettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 900)
}
