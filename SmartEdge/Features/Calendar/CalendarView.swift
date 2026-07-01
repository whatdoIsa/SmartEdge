import SwiftUI
import EventKit

struct CalendarView: View {
    @StateObject private var viewModel: CalendarViewModel
    
    init(viewModel: CalendarViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }
    
    init() {
        // Default initializer for preview and testing
        self._viewModel = StateObject(wrappedValue: CalendarViewModel(
            calendarService: PreviewMockCalendarService(),
            quickActions: CalendarQuickActions(calendarService: PreviewMockCalendarService()),
            notificationService: EventNotificationService()
        ))
    }
    
    var body: some View {
        HStack(spacing: 16) {
            dateTimeSection
            upcomingEventsSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            Task {
                await viewModel.refreshData()
            }
        }
    }
    
    // MARK: - Private Views
    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.currentDate)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            
            Text(viewModel.currentTime)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            
            Text(viewModel.currentWeekday)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
        }
        .frame(width: 100, alignment: .leading)
    }
    
    private var upcomingEventsSection: some View {
        // Today-only agenda — the notch is a "what's left today" glance, so
        // tomorrow's events aren't mixed in (the rows show time without a date,
        // which made cross-day events ambiguous).
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.todayEvents.isEmpty {
                noEventsView
            } else {
                let events = Array(viewModel.todayEvents.prefix(3))
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    eventRow(event)
                    if index < events.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 0.5)
                            .padding(.leading, 8)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var noEventsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No events today")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text("Enjoy your free time")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
    
    private func eventRow(_ event: CalendarEvent) -> some View {
        // TOSS-minimal row: a thin app-coral bar + title/time, rows separated
        // by hairlines. The currently-happening timed event gets a coral tint
        // + "Now" badge so it stands out at a glance.
        let happening = event.isHappening && !event.isAllDay
        return HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 2)
                .fill(calendarColor(for: event))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if happening {
                        Text("Now")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NotchTheme.brandCoral)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(NotchTheme.brandCoral.opacity(0.20), in: Capsule())
                    }
                }

                eventSubtitle(event)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            happening ? NotchTheme.brandCoral.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9)
        )
    }

    @ViewBuilder
    private func eventSubtitle(_ event: CalendarEvent) -> some View {
        if event.isAllDay {
            // All-day events aren't time-specific — mark them with an icon
            // instead of a time range so they read differently from timed ones.
            HStack(spacing: 3) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 9))
                Text("All day")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        } else {
            Text("\(formatEventTime(event.startDate)) - \(formatEventTime(event.endDate))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helper Methods

    /// The event's own calendar color (as set in Calendar), falling back to the
    /// app accent when the color is unavailable.
    private func calendarColor(for event: CalendarEvent) -> Color {
        let rgba = event.calendar.colorComponents
        guard rgba.count >= 3 else { return NotchTheme.brandCoral }
        return Color(.sRGB, red: rgba[0], green: rgba[1], blue: rgba[2], opacity: rgba.count >= 4 ? rgba[3] : 1)
    }

    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        // With events
        CalendarView(viewModel: CalendarViewModel(
            calendarService: PreviewMockCalendarService(),
            quickActions: CalendarQuickActions(calendarService: PreviewMockCalendarService()),
            notificationService: EventNotificationService()
        ))
        
        // Without events
        CalendarView(viewModel: CalendarViewModel(
            calendarService: PreviewMockCalendarService(),
            quickActions: CalendarQuickActions(calendarService: PreviewMockCalendarService()),
            notificationService: EventNotificationService()
        ))
    }
    .frame(width: 400, height: 200)
    .background(.ultraThinMaterial)
    .cornerRadius(16)
}