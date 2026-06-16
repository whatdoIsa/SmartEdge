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
                viewModel: viewModel
            )
        })
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 600)
        .background(.windowBackground)
        .searchable(text: $searchText, placement: .sidebar)
        .environmentObject(viewModel)
    }
}

@MainActor
struct SettingsDetailView: View {
    let selectedPanel: SettingsPanel
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        Group {
            switch selectedPanel {
            case .general:
                GeneralSettingsPanel()
            case .notchDisplay:
                NotchSettingsPanel()
            case .musicPlayer:
                MusicPlayerSettingsPanel()
            case .systemHUD:
                SystemHUDSettingsPanel()
            case .calendar:
                CalendarSettingsPanel()
            case .shelf:
                ShelfSettingsPanel()
            case .systemStatus:
                SystemStatusSettingsPanel()
            case .privacy:
                PrivacySettingsPanel()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.windowBackground)
    }
}

#Preview {
    SettingsView()
}