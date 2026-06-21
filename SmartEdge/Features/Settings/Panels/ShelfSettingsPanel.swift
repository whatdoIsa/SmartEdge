import SwiftUI
import os

struct ShelfSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPanelHeader(
                    icon: "folder",
                    title: "Shelf",
                    subtitle: "Temporary file storage and sharing hub"
                )

                storageSection

                integrationSection

                managementSection

                securitySection
            }
            .padding()
        }
    }

    private var storageSection: some View {
        SettingsCard("Storage") {
            SettingRow(
                title: "Storage limit",
                description: "Maximum space the Shelf may use before old files are pruned"
            ) {
                HStack(spacing: 10) {
                    Slider(value: $settings.shelfStorageLimit, in: 50...1000, step: 50)
                        .frame(width: 130)
                    Text("\(String(format: "%.0f", settings.shelfStorageLimit)) MB")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }

            SettingsRowDivider()

            SettingRow(
                title: "Clear all files",
                description: "Permanently delete every file currently stored in the Shelf"
            ) {
                Button("Clear All") {
                    clearAllFiles()
                }
            }

            SettingsRowDivider()

            SettingRow(
                title: "Open storage folder",
                description: "Reveal the Shelf directory in Finder"
            ) {
                Button("Open in Finder") {
                    openShelfInFinder()
                }
            }
        }
    }

    private var integrationSection: some View {
        SettingsCard("System Integration") {
            SettingRow(
                toggle: "Enable AirDrop integration",
                description: "Automatically save AirDrop files to the Shelf for quick access",
                isOn: $settings.enableAirDropIntegration
            )
        }
    }

    private var managementSection: some View {
        SettingsCard("Automatic Management") {
            SettingRow(
                toggle: "Automatically delete old files",
                description: "Clean up old files to keep storage usage under control",
                isOn: $settings.autoDeleteOldFiles
            )

            if settings.autoDeleteOldFiles {
                SettingsRowDivider()

                SettingRow(
                    title: "Delete files older than",
                    description: "Files past this age are removed during cleanup"
                ) {
                    HStack(spacing: 10) {
                        Slider(value: $settings.shelfRetentionDays, in: 1...90, step: 1)
                            .frame(width: 130)
                        Text("\(Int(settings.shelfRetentionDays)) days")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var securitySection: some View {
        SettingsCard("Security & Privacy") {
            SettingRow(
                title: "Storage location",
                description: "~/Library/Application Support/SmartEdge/Shelf/"
            ) {
                Button("Change") {
                    changeStorageLocation()
                }
            }

            SettingsRowDivider()

            SettingRow(
                title: "Encrypt files",
                description: "Require a password to access files stored in the Shelf"
            ) {
                Button("Encrypt") {
                    showEncryptionOptions()
                }
            }

            SettingsRowDivider()

            SettingRow(
                title: "Export files",
                description: "Save all Shelf files to a zip archive"
            ) {
                Button("Export") {
                    exportFiles()
                }
            }

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Files are stored locally on your Mac and are not uploaded to any servers. AirDrop integration only saves files locally for quick access through the notch interface.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func clearAllFiles() {
        let alert = NSAlert()
        alert.messageText = "Clear All Shelf Files"
        alert.informativeText = "This will permanently delete all files currently stored in the Shelf. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")

        alert.runModal()
    }

    private func openShelfInFinder() {
        let shelfPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("SmartEdge/Shelf")

        if let url = shelfPath {
            NSWorkspace.shared.open(url)
        }
    }

    private func changeStorageLocation() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Storage Location"
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.allowsMultipleSelection = false

        let response = openPanel.runModal()
        if response == .OK, let url = openPanel.url {
            AppLogger.settings.info("New storage location: \(url.path, privacy: .public)")
        }
    }

    private func showEncryptionOptions() {
        let alert = NSAlert()
        alert.messageText = "File Encryption"
        alert.informativeText = "Enable encryption for files stored in the Shelf. This will require a password to access files."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Enable Encryption")
        alert.addButton(withTitle: "Cancel")

        alert.runModal()
    }

    private func exportFiles() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Shelf Files"
        savePanel.nameFieldStringValue = "Shelf Export.zip"
        savePanel.allowedContentTypes = [.zip]

        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            AppLogger.settings.info("Exporting to: \(url.path, privacy: .public)")
        }
    }
}

#Preview {
    ShelfSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 800)
}
