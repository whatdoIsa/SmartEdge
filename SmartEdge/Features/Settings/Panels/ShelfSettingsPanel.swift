import SwiftUI
import AppKit

struct ShelfSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var storageLocationPath: String = ""
    @State private var isCustomLocation: Bool = false

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
        .onAppear { refreshStorageInfo() }
    }

    private var storageSection: some View {
        SettingsCard("Storage") {
            SettingRow(
                title: "Storage capacity",
                description: "Holds up to 50 files (5 GB). The oldest files are cleared automatically if it ever fills up."
            ) {
                Text("5 GB")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
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
                title: "Storage location",
                description: storageLocationPath.isEmpty ? "Default (inside app container)" : storageLocationPath
            ) {
                HStack(spacing: 8) {
                    Button("Change…") {
                        changeStorageLocation()
                    }
                    if isCustomLocation {
                        Button("Reset") {
                            resetStorageLocation()
                        }
                    }
                }
            }

            SettingsRowDivider()

            SettingRow(
                title: "Open storage folder",
                description: "Reveal the Shelf folder in Finder"
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

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            try? await ServiceContainer.shared.shelfService.clearAllItems()
        }
    }

    @MainActor
    private func openShelfInFinder() {
        // Open whatever directory the Shelf is actually using right now
        // (default container or a user-chosen folder).
        let path = ServiceContainer.shared.shelfService.currentStorageLocationPath
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path), withIntermediateDirectories: true
        )
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    @MainActor
    private func refreshStorageInfo() {
        let service = ServiceContainer.shared.shelfService
        storageLocationPath = service.currentStorageLocationPath
        isCustomLocation = service.isUsingCustomStorageLocation
    }

    @MainActor
    private func changeStorageLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose Shelf Storage Folder"
        panel.message = "Pick a folder where the Shelf will keep your files."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                try await ServiceContainer.shared.shelfService.setStorageLocation(url)
            } catch {
                presentStorageError("Couldn't move the Shelf to that folder. \(error.localizedDescription)")
            }
            refreshStorageInfo()
        }
    }

    @MainActor
    private func resetStorageLocation() {
        Task { @MainActor in
            do {
                try await ServiceContainer.shared.shelfService.resetStorageLocation()
            } catch {
                presentStorageError("Couldn't reset the Shelf location. \(error.localizedDescription)")
            }
            refreshStorageInfo()
        }
    }

    private func presentStorageError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Shelf Storage"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

}

#Preview {
    ShelfSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 800)
}
