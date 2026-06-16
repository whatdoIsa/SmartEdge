import SwiftUI
import os

struct ShelfSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var currentStorageUsage: Double = 45.2
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                panelHeader
                
                storageSection
                
                Divider()
                
                integrationSection
                
                Divider()
                
                managementSection
                
                Divider()
                
                securitySection
            }
            .padding()
        }
    }
    
    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Shelf")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Open Shelf") {
                    openShelf()
                }
                .font(.caption)
            }
            
            Text("Temporary file storage and sharing hub")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage Management")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                // Storage usage indicator
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Storage Used")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("\(String(format: "%.1f", currentStorageUsage)) / \(String(format: "%.0f", settings.shelfStorageLimit)) MB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ProgressView(value: currentStorageUsage / settings.shelfStorageLimit)
                        .progressViewStyle(.linear)
                        .tint(storageColor)
                }
                
                // Storage limit slider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Storage Limit")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Slider(value: $settings.shelfStorageLimit, in: 50...1000, step: 50)
                        
                        Text("\(String(format: "%.0f", settings.shelfStorageLimit)) MB")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 50)
                    }
                }
                
                HStack(spacing: 12) {
                    Button("Clear All Files") {
                        clearAllFiles()
                    }
                    .font(.caption)
                    
                    Button("Open in Finder") {
                        openShelfInFinder()
                    }
                    .font(.caption)
                    
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var storageColor: Color {
        let usage = currentStorageUsage / settings.shelfStorageLimit
        if usage > 0.9 {
            return .red
        } else if usage > 0.7 {
            return .orange
        } else {
            return .blue
        }
    }
    
    private var integrationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Integration")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable AirDrop integration", isOn: $settings.enableAirDropIntegration)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatically save AirDrop files to Shelf for quick access")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    
                    if settings.enableAirDropIntegration {
                        airdropPreview
                    }
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var airdropPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent AirDrop Files")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            VStack(spacing: 6) {
                fileRow(name: "Document.pdf", size: "2.3 MB", type: "PDF", isRecent: true)
                fileRow(name: "Image.jpg", size: "1.8 MB", type: "JPEG", isRecent: false)
                fileRow(name: "Presentation.key", size: "12.4 MB", type: "Keynote", isRecent: false)
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func fileRow(name: String, size: String, type: String, isRecent: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: fileIcon(for: type))
                .font(.caption)
                .foregroundColor(fileColor(for: type))
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption)
                    .fontWeight(isRecent ? .semibold : .regular)
                Text(size)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isRecent {
                Circle()
                    .fill(.blue)
                    .frame(width: 6, height: 6)
            }
        }
    }
    
    private func fileIcon(for type: String) -> String {
        switch type {
        case "PDF": return "doc.richtext"
        case "JPEG": return "photo"
        case "Keynote": return "rectangle.on.rectangle"
        default: return "doc"
        }
    }
    
    private func fileColor(for type: String) -> Color {
        switch type {
        case "PDF": return .red
        case "JPEG": return .green
        case "Keynote": return .orange
        default: return .blue
        }
    }
    
    private var managementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Automatic Management")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Automatically delete old files", isOn: $settings.autoDeleteOldFiles)
                
                if settings.autoDeleteOldFiles {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Delete files older than")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Slider(value: $settings.shelfRetentionDays, in: 1...90, step: 1)
                            
                            Text("\(Int(settings.shelfRetentionDays)) days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 50)
                        }
                    }
                    .padding(.leading, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically clean up old files to manage storage space")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Security & Privacy")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("File Storage Location")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("~/Library/Application Support/SmartEdge/Shelf/")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    
                    Spacer()
                    
                    Button("Change") {
                        changeStorageLocation()
                    }
                    .font(.caption)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files are stored locally on your Mac and are not uploaded to any servers. AirDrop integration only saves files locally for quick access through the notch interface.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                
                HStack(spacing: 16) {
                    Button("Encrypt Files") {
                        showEncryptionOptions()
                    }
                    .font(.caption)
                    
                    Button("Export Files") {
                        exportFiles()
                    }
                    .font(.caption)
                    
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private func openShelf() {
        // Open the Shelf interface - could be a popover or separate window
    }
    
    private func clearAllFiles() {
        let alert = NSAlert()
        alert.messageText = "Clear All Shelf Files"
        alert.informativeText = "This will permanently delete all files currently stored in the Shelf. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Clear all files
            currentStorageUsage = 0
        }
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
            // Update storage location
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
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Show encryption setup
        }
    }
    
    private func exportFiles() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Shelf Files"
        savePanel.nameFieldStringValue = "Shelf Export.zip"
        savePanel.allowedContentTypes = [.zip]
        
        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            // Export files as zip archive
            AppLogger.settings.info("Exporting to: \(url.path, privacy: .public)")
        }
    }
}

#Preview {
    ShelfSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 900)
}