import SwiftUI

struct SettingsSidebar: View {
    @Binding var selectedPanel: SettingsPanel
    @Binding var searchText: String
    /// Drives the Pro lock badges — they disappear the moment Pro is purchased.
    @ObservedObject private var store = ServiceContainer.shared.storeService
    
    private var filteredPanels: [SettingsPanel] {
        if searchText.isEmpty {
            return SettingsPanel.allCases
        } else {
            return SettingsPanel.allCases.filter { panel in
                panel.title.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
            
            Divider()
                .padding(.horizontal)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredPanels) { panel in
                        sidebarItem(for: panel)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            sidebarFooter
        }
        .frame(minWidth: 200, idealWidth: 220)
        .background(.regularMaterial, in: Rectangle())
    }
    
    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gearshape.2")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)
        }
    }
    
    private func sidebarItem(for panel: SettingsPanel) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPanel = panel
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: panel.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(selectedPanel == panel ? .white : .secondary)
                    .frame(width: 20, height: 20)
                
                Text(panel.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(selectedPanel == panel ? .white : .primary)

                Spacer()

                // Pro lock badge — shown on gated panels until purchase.
                if panel.requiresPro && !store.isPro {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(selectedPanel == panel ? .white.opacity(0.9) : .secondary)
                        .accessibilityLabel("Pro 잠금")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedPanel == panel ? .blue : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
    
    private var sidebarFooter: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal)
            
            HStack {
                Button("Reset All") {
                    showResetConfirmation()
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Menu {
                    Button("Export Settings") {
                        exportSettings()
                    }
                    Button("Import Settings") {
                        importSettings()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }
    
    private func showResetConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Reset All Settings"
        alert.informativeText = "This will reset all SmartEdge settings to their default values. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let viewModel = findSettingsViewModel() {
                viewModel.resetToDefaults()
            }
        }
    }
    
    private func exportSettings() {
        guard let viewModel = findSettingsViewModel(),
              let data = viewModel.exportSettings() else { return }
        
        let savePanel = NSSavePanel()
        savePanel.title = "Export Settings"
        savePanel.nameFieldStringValue = "SmartEdge Settings.json"
        savePanel.allowedContentTypes = [.json]
        
        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            try? data.write(to: url)
        }
    }
    
    private func importSettings() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Settings"
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        
        let response = openPanel.runModal()
        if response == .OK, 
           let url = openPanel.url,
           let data = try? Data(contentsOf: url),
           let viewModel = findSettingsViewModel() {
            
            let success = viewModel.importSettings(from: data)
            
            let alert = NSAlert()
            alert.messageText = success ? "Settings Imported" : "Import Failed"
            alert.informativeText = success ? "Settings have been successfully imported." : "The selected file could not be imported. Please check the file format."
            alert.alertStyle = success ? .informational : .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    private func findSettingsViewModel() -> SettingsViewModel? {
        if let window = NSApplication.shared.keyWindow,
           let contentView = window.contentView,
           let hostingController = contentView.subviews.first(where: { $0 is NSHostingView<SettingsView> }) as? NSHostingView<SettingsView> {
            
            let mirror = Mirror(reflecting: hostingController.rootView)
            for child in mirror.children {
                if let viewModel = child.value as? SettingsViewModel {
                    return viewModel
                }
            }
        }
        return nil
    }
}

#Preview {
    SettingsSidebar(
        selectedPanel: .constant(.general),
        searchText: .constant("")
    )
    .frame(width: 220, height: 500)
}