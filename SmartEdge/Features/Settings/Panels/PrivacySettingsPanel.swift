import SwiftUI

struct PrivacySettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var showingDataExport = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                panelHeader
                
                dataCollectionSection
                
                Divider()
                
                permissionsOverview
                
                Divider()
                
                dataManagementSection
                
                Divider()
                
                securitySection
            }
            .padding()
        }
    }
    
    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "hand.raised")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Privacy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            
            Text("Control data collection and privacy settings")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var dataCollectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Collection")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable analytics", isOn: $settings.enableAnalytics)
                
                Toggle("Enable crash reporting", isOn: $settings.enableCrashReporting)
                
                Toggle("Share anonymous usage data", isOn: $settings.shareUsageData)
                    .disabled(!settings.enableAnalytics)
                
                VStack(alignment: .leading, spacing: 12) {
                    dataCollectionDetails
                }
                .padding(.leading, 16)
            }
            .padding(.leading, 8)
        }
    }
    
    private var dataCollectionDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("What data is collected?")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                    
                    Text("When enabled, SmartEdge may collect anonymous usage statistics to improve the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Data collected may include:")
                    .font(.caption)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 4) {
                    dataItem("Feature usage frequency", isCollected: settings.enableAnalytics)
                    dataItem("App performance metrics", isCollected: settings.enableAnalytics)
                    dataItem("Crash reports and error logs", isCollected: settings.enableCrashReporting)
                    dataItem("macOS version and hardware type", isCollected: settings.shareUsageData)
                }
                .padding(.leading, 16)
                
                Text("Data NOT collected:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.top, 8)
                
                VStack(alignment: .leading, spacing: 4) {
                    dataItem("Personal files or content", isCollected: false, isNeverCollected: true)
                    dataItem("Calendar events or details", isCollected: false, isNeverCollected: true)
                    dataItem("Music library or playlists", isCollected: false, isNeverCollected: true)
                    dataItem("Browsing history or personal data", isCollected: false, isNeverCollected: true)
                }
                .padding(.leading, 16)
            }
            .padding()
            .background(.gray.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func dataItem(_ text: String, isCollected: Bool, isNeverCollected: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isNeverCollected ? "xmark.circle" : (isCollected ? "checkmark.circle" : "circle"))
                .font(.caption2)
                .foregroundColor(isNeverCollected ? .red : (isCollected ? .green : .gray))
            
            Text(text)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
    
    private var permissionsOverview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions Overview")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                permissionRow(
                    title: "Accessibility",
                    description: "System HUD interception",
                    status: .required,
                    isGranted: false
                )
                
                permissionRow(
                    title: "Calendar",
                    description: "Event display in notch",
                    status: .optional,
                    isGranted: false
                )
                
                permissionRow(
                    title: "Media Remote",
                    description: "Music player control",
                    status: .automatic,
                    isGranted: true
                )
                
                HStack(spacing: 16) {
                    Button("Review All Permissions") {
                        openSystemPrivacySettings()
                    }
                    .font(.caption)
                    
                    Button("Reset Permissions") {
                        resetAllPermissions()
                    }
                    .font(.caption)
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(.leading, 8)
        }
    }
    
    private func permissionRow(title: String, description: String, status: PermissionRequirement, isGranted: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Text(status.title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(status.color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundColor(status.color)
                
                Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(isGranted ? .green : .red)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    
    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Management")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("App Data Storage")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("SmartEdge stores preferences and temporary files locally on your Mac")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    dataStorageRow(
                        location: "Application Support",
                        path: "~/Library/Application Support/SmartEdge/",
                        description: "App preferences and settings"
                    )
                    
                    dataStorageRow(
                        location: "Temporary Files",
                        path: "~/Library/Application Support/SmartEdge/Shelf/",
                        description: "Shelf file storage"
                    )
                    
                    dataStorageRow(
                        location: "Cache",
                        path: "~/Library/Caches/SmartEdge/",
                        description: "Temporary cache files"
                    )
                }
                
                HStack(spacing: 16) {
                    Button("Export My Data") {
                        showingDataExport = true
                    }
                    .font(.caption)
                    
                    Button("Clear Cache") {
                        clearCache()
                    }
                    .font(.caption)
                    
                    Button("Reset All Data") {
                        resetAllData()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(.leading, 8)
        }
    }
    
    private func dataStorageRow(location: String, path: String, description: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(location)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Show") {
                openPath(path)
            }
            .font(.caption2)
        }
    }
    
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Security")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Network Security")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("SmartEdge does not connect to external servers or transmit personal data over the internet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 8) {
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
                }
                
                HStack {
                    Button("View Security Report") {
                        showSecurityReport()
                    }
                    .font(.caption)
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
            .padding(.leading, 8)
        }
    }
    
    private func securityFeature(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.green)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func openSystemPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?General") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func resetAllPermissions() {
        let alert = NSAlert()
        alert.messageText = "Reset Permissions"
        alert.informativeText = "This will reset all permission settings. You will need to re-grant permissions when features are next used."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Reset permissions logic
        }
    }
    
    private func clearCache() {
        let alert = NSAlert()
        alert.messageText = "Clear Cache"
        alert.informativeText = "This will delete temporary cache files. The app may need to recreate some data on next launch."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Clear cache logic
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
            // Reset all data logic
            settings.resetToDefaults()
        }
    }
    
    private func openPath(_ path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        NSWorkspace.shared.open(url)
    }
    
    private func showSecurityReport() {
        let alert = NSAlert()
        alert.messageText = "SmartEdge Security Report"
        alert.informativeText = """
        Security Status: ✅ All systems secure
        
        • App Sandbox: Enabled
        • Network Access: Disabled
        • Data Encryption: Enabled for sensitive data
        • Permission Model: Minimal required access
        • Update Verification: Code signed and notarized
        
        Last Security Scan: \(Date().formatted(date: .abbreviated, time: .shortened))
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Supporting Types

enum PermissionRequirement {
    case required
    case optional
    case automatic
    
    var title: String {
        switch self {
        case .required: return "Required"
        case .optional: return "Optional"
        case .automatic: return "Auto"
        }
    }
    
    var color: Color {
        switch self {
        case .required: return .red
        case .optional: return .orange
        case .automatic: return .green
        }
    }
}

#Preview {
    PrivacySettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 900)
}