import SwiftUI

struct NotchSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPanelHeader(
                    icon: "rectangle.and.hand.point.up.left",
                    title: "Notch Display",
                    subtitle: "Customize how content appears in the notch area"
                )

                contentPrioritySection

                appearanceSection

                behaviorSection

                animationSection

                DisplayDiagnosticsSection()
            }
            .padding()
        }
    }

    private var contentPrioritySection: some View {
        SettingsCard("Content Priority") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $settings.notchContentPriority) {
                    ForEach(NotchPriorityPreset.allCases, id: \.self) { priority in
                        Text(priority.title).tag(priority.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text(priorityDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var priorityDescription: String {
        guard let priority = NotchPriorityPreset(rawValue: settings.notchContentPriority) else {
            return "Choose how content is prioritized when multiple items compete for space."
        }

        switch priority {
        case .music:
            return "Music player controls always take priority over other content."
        case .calendar:
            return "Calendar events and upcoming meetings take priority."
        case .system:
            return "System status indicators take priority."
        case .balanced:
            return "Content rotates based on activity and user interaction."
        }
    }

    private var appearanceSection: some View {
        SettingsCard("Appearance") {
            SettingRow(
                toggle: "Show notch when inactive",
                description: "Keep the notch surface visible even when no content is playing",
                isOn: $settings.showNotchWhenInactive
            )

            SettingsRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Show notch on")
                    .font(.system(size: 13, weight: .medium))
                Picker("", selection: Binding(
                    get: { settings.notchDisplayPolicy },
                    set: { settings.notchDisplayPolicy = $0 }
                )) {
                    ForEach(NotchDisplayPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Text(settings.notchDisplayPolicy.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsRowDivider()

            SettingRow(
                title: "Corner radius",
                description: "Adjust the rounded corners of the notch display"
            ) {
                HStack(spacing: 10) {
                    Slider(value: $settings.cornerRadius, in: 6...20, step: 1)
                        .frame(width: 130)
                    Text("\(Int(settings.cornerRadius))px")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    private var behaviorSection: some View {
        SettingsCard("Hover Behavior") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("", selection: $settings.hoverBehavior) {
                    ForEach(HoverBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.title).tag(behavior.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)

                Text(hoverDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var hoverDescription: String {
        guard let behavior = HoverBehavior(rawValue: settings.hoverBehavior) else {
            return "Choose what happens when you hover over the notch."
        }

        switch behavior {
        case .expand:
            return "The notch expands to show more content and controls."
        case .showControls:
            return "Additional control buttons appear without expanding."
        case .none:
            return "No action is taken when hovering over the notch."
        }
    }

    private var animationSection: some View {
        SettingsCard("Animations") {
            SettingRow(
                title: "Animation speed",
                description: "Controls the speed of notch expand / collapse animations"
            ) {
                HStack(spacing: 10) {
                    Slider(value: $settings.animationSpeed, in: 0.1...1.0, step: 0.05)
                        .frame(width: 130)
                    Text(String(format: "%.2fx", settings.animationSpeed))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}

#Preview {
    NotchSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 800)
}
