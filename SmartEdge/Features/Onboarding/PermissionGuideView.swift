import SwiftUI
import EventKit
import Combine

@MainActor
struct PermissionGuideView: View {
    @ObservedObject var permissionManager: SystemPermissionManager
    @State private var calendarStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    /// Calendar service for triggering the EventKit permission prompt.
    /// Resolved from the shared container rather than injected so the
    /// preview can stand on its own without wiring up a full service stack.
    private let calendarService = ServiceContainer.shared.calendarService

    var onContinue: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            Divider()
            permissionRow(
                title: "Accessibility",
                description: permissionManager.hasAccessibilityPermission
                    ? "Granted."
                    : "Required to intercept media key presses. If you've already enabled the toggle and still see this, the previous build's permission may be stale — toggle SmartEdge OFF then ON in Accessibility.",
                isGranted: permissionManager.hasAccessibilityPermission,
                action: requestAccessibilityAndOpen
            )
            permissionRow(
                title: "Input Monitoring",
                description: permissionManager.hasInputMonitoringPermission
                    ? "Granted."
                    : "Required to read function key events.",
                isGranted: permissionManager.hasInputMonitoringPermission,
                action: permissionManager.openInputMonitoringPreferencesPane
            )
            permissionRow(
                title: "Calendar",
                description: CalendarService.statusGrantsReadAccess(calendarStatus)
                    ? "Granted — upcoming events will surface in the notch."
                    : "Required to display upcoming events. Click to request access.",
                isGranted: CalendarService.statusGrantsReadAccess(calendarStatus),
                action: requestCalendarAndOpen
            )
            Spacer(minLength: 12)
            footer
        }
        .padding(24)
        .frame(width: 480, height: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { refreshCalendarStatus() }
        // Re-check calendar status whenever the user comes back from System
        // Settings so toggling permission auto-reflects in the UI.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshCalendarStatus()
        }
        // CalendarService publishes after a successful EventKit grant; this
        // catches the moment the user clicks "OK" on the macOS prompt even
        // without needing the app to re-activate.
        .onReceive(calendarService.isAuthorizedPublisher) { _ in
            refreshCalendarStatus()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Permissions Required")
                .font(.title2)
                .fontWeight(.semibold)
            Text("SmartEdge needs the following permissions to work properly. Grant them in System Settings, then come back here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(
        title: String,
        description: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(isGranted ? Color.green : Color.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isGranted {
                Button("Open Settings", action: action)
                    .controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Continue") {
                refreshCalendarStatus()
                onContinue?()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func refreshCalendarStatus() {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
    }

    /// Triggers the EventKit permission prompt (macOS 14+ full-access form,
    /// macOS 13 fallback handled inside CalendarService) and opens the
    /// System Settings pane in parallel. The prompt only fires the first
    /// time per process — after that, the pane is the user's recovery path.
    private func requestCalendarAndOpen() {
        Task { @MainActor in
            _ = await calendarService.requestCalendarAccess()
            refreshCalendarStatus()
            // Open the pane even if the prompt fired so the user can verify
            // / re-toggle without leaving the guide.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// Triggers the OS-level Accessibility permission prompt (only fires
    /// once per app launch) and opens the System Settings pane in parallel.
    /// The prompt forces TCC to re-read the binary's current code-signing
    /// identity — useful after an Xcode rebuild invalidates the cached
    /// trust, when the System Settings toggle still *displays* as ON but
    /// `AXIsProcessTrusted()` returns false.
    private func requestAccessibilityAndOpen() {
        Task { @MainActor in
            await permissionManager.requestAccessibilityPermission()
            // Even if the prompt was suppressed (already-asked-this-launch),
            // opening the pane gives the user a one-click recovery path.
            permissionManager.openAccessibilityPreferencesPane()
        }
    }
}

#Preview {
    PermissionGuideView(
        permissionManager: SystemPermissionManager()
    )
}
