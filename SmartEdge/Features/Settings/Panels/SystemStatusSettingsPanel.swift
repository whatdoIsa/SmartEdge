import SwiftUI

struct SystemStatusSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPanelHeader(
                    icon: "battery.100",
                    title: "System Status",
                    subtitle: "Monitor and display system status indicators in the notch"
                )

                batterySection

                bluetoothSection

                networkSection

                displaySection
            }
            .padding()
        }
    }

    private var batterySection: some View {
        SettingsCard("Battery") {
            SettingRow(
                toggle: "Show battery status",
                description: "Display battery percentage and charging status in the notch",
                isOn: $settings.showBatteryStatus
            )

            if settings.showBatteryStatus {
                SettingsRowDivider()

                SettingRow(
                    title: "Low battery alert threshold",
                    description: "Warn when the battery drops to this level"
                ) {
                    HStack(spacing: 10) {
                        Slider(value: $settings.batteryLowThreshold, in: 5...50, step: 5)
                            .frame(width: 130)
                        Text("\(Int(settings.batteryLowThreshold))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var bluetoothSection: some View {
        SettingsCard("Bluetooth") {
            SettingRow(
                toggle: "Show Bluetooth status",
                description: "Monitor Bluetooth connectivity and connected device count",
                isOn: $settings.showBluetoothStatus
            )
        }
    }

    private var networkSection: some View {
        SettingsCard("Network") {
            SettingRow(
                toggle: "Show Wi-Fi status",
                description: "Display Wi-Fi network name and signal strength",
                isOn: $settings.showWiFiStatus
            )
        }
    }

    private var displaySection: some View {
        SettingsCard("Display Priority") {
            VStack(alignment: .leading, spacing: 10) {
                Text("When multiple indicators are active they appear in this order. They automatically hide when the notch is full so music and calendar take priority.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                priorityItem(number: 1, title: "Battery (when low or charging)", isActive: settings.showBatteryStatus)
                priorityItem(number: 2, title: "Bluetooth connections", isActive: settings.showBluetoothStatus)
                priorityItem(number: 3, title: "Wi-Fi network", isActive: settings.showWiFiStatus)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func priorityItem(number: Int, title: String, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(isActive ? Color.accentColor : .gray.opacity(0.5), in: Circle())

            Text(title)
                .font(.system(size: 12))
                .foregroundColor(isActive ? .primary : .secondary)

            Spacer()
        }
    }
}

#Preview {
    SystemStatusSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 800)
}
