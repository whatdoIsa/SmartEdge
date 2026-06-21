import SwiftUI

@MainActor
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var selectedPanel: SettingsPanel = .general
    @State private var searchText = ""
    
    var body: some View {
        NavigationSplitView(sidebar: {
            SettingsSidebar(
                selectedPanel: $selectedPanel,
                searchText: $searchText
            )
        }, detail: {
            SettingsDetailView(
                selectedPanel: selectedPanel,
                viewModel: viewModel,
                onShowPro: { selectedPanel = .pro }
            )
        })
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .searchable(text: $searchText, placement: .sidebar)
        .environmentObject(viewModel)
    }
}

@MainActor
struct SettingsDetailView: View {
    let selectedPanel: SettingsPanel
    @ObservedObject var viewModel: SettingsViewModel
    let onShowPro: () -> Void

    var body: some View {
        Group {
            switch selectedPanel {
            case .general:
                GeneralSettingsPanel()
            case .pro:
                ProSettingsPanel()
            case .notchDisplay:
                NotchSettingsPanel()
            case .musicPlayer:
                MusicPlayerSettingsPanel()
            case .calendar:
                ProLockGate(featureName: "캘린더", onUnlock: onShowPro) {
                    CalendarSettingsPanel()
                }
            case .shelf:
                ProLockGate(featureName: "선반", onUnlock: onShowPro) {
                    ShelfSettingsPanel()
                }
            case .systemStatus:
                SystemStatusSettingsPanel()
            case .integrations:
                IntegrationsSettingsPanel()
            case .privacy:
                PrivacySettingsPanel()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#Preview {
    SettingsView()
}