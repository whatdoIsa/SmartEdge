import SwiftUI
import AppKit
import Combine

/// Per-display diagnostic readout for the Notch Settings panel.
///
/// Why this exists: the multi-display logic in `NotchWindowManager`
/// (screen origin offset, hardware-notch detection, `displayID` sticky
/// pinning) can't be unit-tested without real hardware. Surfacing the raw
/// inputs here lets the user verify in real time what SmartEdge sees when
/// they plug/unplug a monitor.
///
/// Auto-refreshes when the screen configuration changes (cable
/// connect/disconnect, resolution change, display arrangement edit).
struct DisplayDiagnosticsSection: View {
    @State private var snapshots: [DisplaySnapshot] = []
    @State private var refreshTrigger = UUID()

    @State private var copyFeedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Display Diagnostics")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    copySnapshotToPasteboard()
                } label: {
                    Label("Copy snapshot", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy a markdown-formatted snapshot of every screen + settings to the clipboard. Paste it into a bug report.")
                Button {
                    snapshots = DisplaySnapshot.collectAll()
                    refreshTrigger = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh diagnostics")
            }

            Text("Live snapshot of every attached screen, used to debug multi-display notch placement. Notch is preferred on the display with a non-zero safe-area top (the hardware notch).")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let copyFeedback = copyFeedback {
                Label(copyFeedback, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if snapshots.isEmpty {
                Text("No screens detected.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshots) { snapshot in
                        DisplayRow(snapshot: snapshot)
                    }
                }
            }
        }
        .onAppear { snapshots = DisplaySnapshot.collectAll() }
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSApplication.didChangeScreenParametersNotification)
        ) { _ in
            snapshots = DisplaySnapshot.collectAll()
            refreshTrigger = UUID()
        }
    }

    /// Builds a markdown report capturing everything a maintainer would want
    /// to see when triaging a multi-display bug:
    /// - All attached screens (size, origin, safeAreaTop, scale)
    /// - Relevant settings (showOnNonNotchDisplays toggle)
    /// - App version + macOS version
    /// Copies to the system pasteboard so the user can paste into an issue.
    private func copySnapshotToPasteboard() {
        let snapshot = DiagnosticSnapshot.build(displays: snapshots)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot, forType: .string)
        copyFeedback = "Copied snapshot to clipboard."
        // Clear feedback after 2s so the label doesn't linger forever.
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copyFeedback = nil
        }
    }
}

// MARK: - Snapshot composer

@MainActor
private enum DiagnosticSnapshot {
    static func build(displays: [DisplaySnapshot]) -> String {
        var lines: [String] = []
        lines.append("# SmartEdge Diagnostic Snapshot")
        lines.append("")
        lines.append("- Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("- App version: \(appVersion())")
        lines.append("- macOS: \(osVersion())")
        lines.append("")

        lines.append("## Settings")
        let showNonNotch = UserDefaults.standard.object(forKey: SettingsKeys.showOnNonNotchDisplays) as? Bool ?? true
        let slackWebhookConfigured = !(UserDefaults.standard.string(forKey: SettingsKeys.slackWebhookURL) ?? "").isEmpty
        let slackEnabled = UserDefaults.standard.bool(forKey: SettingsKeys.slackNotifyOnFocusComplete)
        lines.append("- showOnNonNotchDisplays: \(showNonNotch)")
        lines.append("- slackWebhookURL configured: \(slackWebhookConfigured)")
        lines.append("- slackNotifyOnFocusComplete: \(slackEnabled)")
        lines.append("")

        lines.append("## Displays (\(displays.count))")
        for d in displays {
            lines.append("### \(d.name) \(d.isMain ? "[main]" : "") \(d.hasHardwareNotch ? "[notch]" : "")")
            lines.append("- displayID: \(d.displayID)")
            lines.append("- frame: \(NSStringFromRect(d.frame))")
            lines.append("- visibleFrame: \(NSStringFromRect(d.visibleFrame))")
            lines.append("- safeAreaTop: \(d.safeAreaTop)")
            lines.append("- backingScaleFactor: \(d.backingScaleFactor)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private static func appVersion() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private static func osVersion() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

// MARK: - Row

private struct DisplayRow: View {
    let snapshot: DisplaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: snapshot.hasHardwareNotch ? "macbook" : "display")
                    .foregroundColor(snapshot.hasHardwareNotch ? .green : .secondary)
                Text(snapshot.name)
                    .font(.system(size: 12, weight: .semibold))
                if snapshot.isMain {
                    Text("main")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                        .foregroundColor(.blue)
                }
                if snapshot.hasHardwareNotch {
                    Text("notch")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                        .foregroundColor(.green)
                }
            }
            attributesGrid
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var attributesGrid: some View {
        // Plain text rows — keeps a stable layout across light/dark mode
        // and ignores monitor name length variability.
        VStack(alignment: .leading, spacing: 1) {
            row("Display ID", "\(snapshot.displayID)")
            row("Frame", "\(snapshot.frame)")
            row("Visible frame", "\(snapshot.visibleFrame)")
            row("Safe area top", String(format: "%.1f pt", snapshot.safeAreaTop))
            row("Scale", String(format: "%.2fx", snapshot.backingScaleFactor))
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.leading, 22)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key).frame(width: 90, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
    }
}

// MARK: - Snapshot model

private struct DisplaySnapshot: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let displayID: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaTop: CGFloat
    let backingScaleFactor: CGFloat
    let isMain: Bool

    var hasHardwareNotch: Bool { safeAreaTop > 0 }

    static func collectAll() -> [DisplaySnapshot] {
        let mainID = mainScreenDisplayID()
        return NSScreen.screens.map { screen -> DisplaySnapshot in
            let id = screenDisplayID(screen)
            let safeAreaTop: CGFloat
            if #available(macOS 12.0, *) {
                safeAreaTop = screen.safeAreaInsets.top
            } else {
                safeAreaTop = 0
            }
            // Mirror the canonical NSScreen names ("Built-in Retina Display")
            // rather than the locale-aware version because the latter can
            // be stale or empty on freshly-attached displays.
            let name: String
            if #available(macOS 10.15, *) {
                name = screen.localizedName.isEmpty ? "Display \(id)" : screen.localizedName
            } else {
                name = "Display \(id)"
            }
            return DisplaySnapshot(
                id: id,
                displayID: id,
                name: name,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                safeAreaTop: safeAreaTop,
                backingScaleFactor: screen.backingScaleFactor,
                isMain: id == mainID
            )
        }
    }

    private static func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    private static func mainScreenDisplayID() -> CGDirectDisplayID {
        guard let main = NSScreen.main else { return 0 }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (main.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}

#Preview {
    DisplayDiagnosticsSection()
        .padding()
        .frame(width: 600)
}
