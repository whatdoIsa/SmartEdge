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
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                panelHeader
                
                integrationSection
                
                Divider()
                
                displaySection
                
                Divider()
                
                refreshSection
                
                Divider()
                
                permissionsSection
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
    
    private var panelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text("Calendar")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            
            Text("Display upcoming events and meetings in the notch")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var integrationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Event Display")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show upcoming events", isOn: $settings.showUpcomingEvents)
                    .disabled(!CalendarService.statusGrantsReadAccess(calendarAccess))
                
                Toggle("Include all-day events", isOn: $settings.showAllDayEvents)
                    .disabled(!settings.showUpcomingEvents || !CalendarService.statusGrantsReadAccess(calendarAccess))
                
                if settings.showUpcomingEvents && CalendarService.statusGrantsReadAccess(calendarAccess) {
                    calendarPreview
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Display upcoming calendar events in the notch area with smart prioritization")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var calendarPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                // Next meeting preview
                calendarEventRow(
                    title: "Team Standup",
                    time: "2:00 PM - 2:30 PM",
                    isNext: true
                )
                
                // Upcoming event preview
                calendarEventRow(
                    title: "Project Review",
                    time: "Tomorrow 10:00 AM",
                    isNext: false
                )
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private func calendarEventRow(title: String, time: String, isNext: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isNext ? .green : .blue)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isNext ? .semibold : .medium)
                Text(time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isNext {
                Text("Next")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundColor(.green)
            }
        }
    }
    
    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Display Options")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Look-ahead Window")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Slider(value: $settings.eventLookAhead, in: 1...168, step: 1)
                            .disabled(!settings.showUpcomingEvents || !CalendarService.statusGrantsReadAccess(calendarAccess))
                        
                        Text("\(Int(settings.eventLookAhead))h")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 30)
                    }
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("How far ahead to look for upcoming events (1 hour to 1 week)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Synchronization")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Refresh Interval")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        Slider(value: $settings.calendarRefreshInterval, in: 60...3600, step: 60)
                            .disabled(!settings.showUpcomingEvents || !CalendarService.statusGrantsReadAccess(calendarAccess))
                        
                        Text(formatRefreshInterval(settings.calendarRefreshInterval))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(minWidth: 40)
                    }
                }
                
                HStack(spacing: 16) {
                    Button("Sync Now") {
                        syncCalendar()
                    }
                    .disabled(!settings.showUpcomingEvents || !CalendarService.statusGrantsReadAccess(calendarAccess))
                    .font(.caption)
                    
                    Spacer()
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("How often to check for calendar updates (1 minute to 1 hour)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(.leading, 8)
        }
    }
    
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calendar Access")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 12) {
                PermissionStatusView(
                    title: "Calendar Permission",
                    description: "Required to read upcoming events and meetings",
                    isGranted: CalendarService.statusGrantsReadAccess(calendarAccess),
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
            .padding(.leading, 8)
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