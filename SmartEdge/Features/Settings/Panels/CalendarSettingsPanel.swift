import SwiftUI
import EventKit
import os

struct CalendarSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var calendarAccess: EKAuthorizationStatus = .notDetermined
    /// Resolved from the shared container so the panel uses the same
    /// EKEventStore (and authorization cache) that the notch and the
    /// permission guide use — otherwise three independent EKEventStores
    /// would each have to ask for permission separately.
    private let calendarService = ServiceContainer.shared.calendarService

    private var hasReadAccess: Bool {
        CalendarService.statusGrantsReadAccess(calendarAccess)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPanelHeader(
                    icon: "calendar",
                    title: "Calendar",
                    subtitle: "Display upcoming events and meetings in the notch",
                    tint: .blue
                )

                eventDisplaySection

                displayOptionsSection

                synchronizationSection

                calendarAccessSection
            }
            .padding()
        }
        .onAppear {
            checkCalendarAccess()
        }
        // Reactive: when the EventKit prompt fires (from this panel OR the
        // permission guide) and the user grants access, every consumer
        // refreshes without a manual relaunch.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkCalendarAccess()
        }
        .onReceive(calendarService.isAuthorizedPublisher) { _ in
            checkCalendarAccess()
        }
    }

    private var eventDisplaySection: some View {
        SettingsCard("Event Display") {
            SettingRow(
                toggle: "Show upcoming events",
                description: "Display upcoming calendar events in the notch area with smart prioritization",
                isOn: $settings.showUpcomingEvents,
                isEnabled: hasReadAccess
            )

            SettingsRowDivider()

            SettingRow(
                toggle: "Include all-day events",
                description: "Show events that span the entire day alongside timed events",
                isOn: $settings.showAllDayEvents,
                isEnabled: settings.showUpcomingEvents && hasReadAccess
            )
        }
    }

    private var displayOptionsSection: some View {
        SettingsCard("Display Options") {
            SettingRow(
                title: "Look-ahead window",
                description: "How far ahead to look for upcoming events (1 hour to 1 week)"
            ) {
                HStack(spacing: 10) {
                    Slider(value: $settings.eventLookAhead, in: 1...168, step: 1)
                        .frame(width: 130)
                        .disabled(!settings.showUpcomingEvents || !hasReadAccess)
                    Text("\(Int(settings.eventLookAhead))h")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    private var synchronizationSection: some View {
        SettingsCard("Synchronization") {
            SettingRow(
                title: "Refresh interval",
                description: "How often to check for calendar updates (1 minute to 1 hour)"
            ) {
                HStack(spacing: 10) {
                    Slider(value: $settings.calendarRefreshInterval, in: 60...3600, step: 60)
                        .frame(width: 130)
                        .disabled(!settings.showUpcomingEvents || !hasReadAccess)
                    Text(formatRefreshInterval(settings.calendarRefreshInterval))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            SettingsRowDivider()

            SettingRow(
                title: "Manual sync",
                description: "Fetch the latest events now instead of waiting for the next refresh"
            ) {
                Button("Sync Now") {
                    syncCalendar()
                }
                .disabled(!settings.showUpcomingEvents || !hasReadAccess)
            }
        }
    }

    private var calendarAccessSection: some View {
        SettingsCard("Calendar Access") {
            VStack(alignment: .leading, spacing: 12) {
                PermissionStatusView(
                    title: "Calendar Permission",
                    description: "Required to read upcoming events and meetings",
                    isGranted: hasReadAccess,
                    action: {
                        requestCalendarAccess()
                    }
                )

                if calendarAccess == .denied {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Calendar access was denied")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)

                            Text("Please enable calendar access in System Settings > Privacy & Security > Calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Open Settings") {
                            openPrivacySettings()
                        }
                        .font(.caption)
                    }
                    .padding()
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                } else if calendarAccess == .notDetermined {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Calendar permission not requested")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)

                            Text("SmartEdge will request calendar access when you enable event display")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func formatRefreshInterval(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            return "\(hours)h"
        }
    }

    private func checkCalendarAccess() {
        calendarAccess = EKEventStore.authorizationStatus(for: .event)
    }

    private func requestCalendarAccess() {
        // Delegate to the shared CalendarService instead of spinning up a
        // throwaway EKEventStore. That service already handles the macOS
        // 13 vs 14 branch (`requestAccess` vs `requestFullAccessToEvents`)
        // AND auto-runs an event refresh on success, so the user sees
        // their data in the notch within a few seconds of granting.
        Task { @MainActor in
            let granted = await calendarService.requestCalendarAccess()
            calendarAccess = EKEventStore.authorizationStatus(for: .event)
            if granted {
                settings.showUpcomingEvents = true
            }
        }
    }

    private func syncCalendar() {
        // Manual refresh — bypass the 5-minute timer. Useful when the user
        // just edited an event in Calendar.app and wants to see it on the
        // notch without waiting for the next polling tick.
        Task { @MainActor in
            await calendarService.refreshEvents()
            AppLogger.calendar.info("Calendar manual sync completed")
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    CalendarSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 800)
}
