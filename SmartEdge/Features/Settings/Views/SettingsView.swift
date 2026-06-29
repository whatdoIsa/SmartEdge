import SwiftUI

@MainActor
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var selectedPanel: SettingsPanel = .general
    @State private var searchText = ""
    
    var body: some View {
        // Plain HStack instead of NavigationSplitView. NavigationSplitView's
        // sidebar uses a `.behindWindow` vibrancy material that samples the
        // desktop / other windows *through* the window — which read as the
        // settings screen overlapping other apps, and couldn't be fully
        // suppressed even with an opaque window. A hand-built HStack with
        // solid backgrounds is fully opaque and deterministic.
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchField
                SettingsSidebar(
                    selectedPanel: $selectedPanel,
                    searchText: $searchText
                )
            }
            .frame(width: 240)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            SettingsDetailView(
                selectedPanel: selectedPanel,
                viewModel: viewModel,
                onShowPro: { selectedPanel = .pro }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .environmentObject(viewModel)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            TextField("검색", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
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
            case .pomodoro:
                ProLockGate(featureName: "뽀모도로", onUnlock: onShowPro) {
                    PomodoroSettingsPanel()
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