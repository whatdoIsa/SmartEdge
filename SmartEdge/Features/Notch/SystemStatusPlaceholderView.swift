import SwiftUI

/// Slim, always-on status strip for the top of the expanded notch.
/// Time on the left, battery + bluetooth on the right. Renders above the
/// main notch content (music, etc.) so system info is persistently visible
/// rather than swapping the whole notch to a status-only view.
@MainActor
struct NotchStatusBar: View {
    let clock: String
    let battery: BatteryInfo?
    let bluetooth: BluetoothInfo?
    /// Width of the empty center gap reserved for the hardware camera notch,
    /// so the clock sits to its left and battery/bluetooth to its right —
    /// mirroring the real menu-bar-around-the-notch layout.
    var notchGap: CGFloat = 200

    var body: some View {
        HStack(spacing: 8) {
            Text(clock)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
                .monospacedDigit()

            // Reserve the center for the physical notch.
            Spacer(minLength: notchGap)

            if let battery = battery {
                BatteryStatusBadge(battery: battery)
            }
            if let bluetooth = bluetooth {
                BluetoothStatusBadge(bluetooth: bluetooth)
            }
        }
        .padding(.horizontal, 18)
        // Fill the notch-height band and center items vertically so they
        // line up with the system menu bar beside the camera notch.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("System status")
    }
}

@MainActor
struct NotchSystemStatusView: View {
    let battery: BatteryInfo?
    let bluetooth: BluetoothInfo?

    var body: some View {
        HStack(spacing: 10) {
            if let battery = battery {
                BatteryStatusBadge(battery: battery)
            }
            if let bluetooth = bluetooth {
                BluetoothStatusBadge(bluetooth: bluetooth)
            }
            if battery == nil && bluetooth == nil {
                Text("No system data")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts: [String] = []
        if let battery = battery {
            let chargingSuffix = battery.isCharging ? ", charging" : ""
            parts.append("Battery \(battery.levelPercentage) percent\(chargingSuffix)")
        }
        if let bluetooth = bluetooth {
            if bluetooth.isEnabled {
                parts.append("Bluetooth on, \(bluetooth.activeConnections) connected")
            } else {
                parts.append("Bluetooth off")
            }
        }
        return parts.joined(separator: ", ")
    }
}

@MainActor
private struct BatteryStatusBadge: View {
    let battery: BatteryInfo

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(iconColor)
                .symbolRenderingMode(.hierarchical)

            Text("\(battery.levelPercentage)%")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(textColor)
                .monospacedDigit()
        }
    }

    private var iconName: String {
        if battery.isCharging {
            return "bolt.fill"
        }
        if battery.level >= 0.875 { return "battery.100" }
        if battery.level >= 0.625 { return "battery.75" }
        if battery.level >= 0.375 { return "battery.50" }
        if battery.level >= 0.125 { return "battery.25" }
        return "battery.0"
    }

    private var iconColor: Color {
        if battery.isCharging { return .green }
        if battery.isCritical { return .red }
        if battery.isLow { return .orange }
        return .primary
    }

    private var textColor: Color {
        if battery.isCritical { return .red }
        if battery.isLow { return .orange }
        return .primary
    }
}

@MainActor
private struct BluetoothStatusBadge: View {
    let bluetooth: BluetoothInfo

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(iconColor)
                .symbolRenderingMode(.hierarchical)

            if bluetooth.isEnabled && bluetooth.activeConnections > 0 {
                Text("\(bluetooth.activeConnections)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }
        }
    }

    private var iconName: String {
        if !bluetooth.isEnabled {
            return "wave.3.right"
        }
        return bluetooth.activeConnections > 0
            ? "wave.3.right.circle.fill"
            : "wave.3.right.circle"
    }

    private var iconColor: Color {
        guard bluetooth.isEnabled else { return .secondary }
        return bluetooth.activeConnections > 0 ? .blue : .primary
    }
}

// MARK: - Preview
#Preview("Charging") {
    NotchSystemStatusView(
        battery: BatteryInfo(
            level: 0.65,
            isCharging: true,
            isPluggedIn: true,
            chargingState: .charging
        ),
        bluetooth: BluetoothInfo(
            connectedDevices: ["AirPods Pro", "Magic Mouse"],
            isEnabled: true,
            activeConnections: 2
        )
    )
    .padding()
    .background(Color.black)
}

#Preview("Low Battery") {
    NotchSystemStatusView(
        battery: BatteryInfo(level: 0.15, isCharging: false),
        bluetooth: BluetoothInfo(
            connectedDevices: [],
            isEnabled: true,
            activeConnections: 0
        )
    )
    .padding()
    .background(Color.black)
}

#Preview("Bluetooth Off") {
    NotchSystemStatusView(
        battery: BatteryInfo(level: 0.92, isCharging: false),
        bluetooth: BluetoothInfo(
            connectedDevices: [],
            isEnabled: false,
            activeConnections: 0
        )
    )
    .padding()
    .background(Color.black)
}
