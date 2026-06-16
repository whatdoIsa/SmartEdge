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
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.upcomingEvents.isEmpty {
                noEventsView
            } else {
                ForEach(viewModel.upcomingEvents.prefix(3)) { event in
                    eventRow(event)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var noEventsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No Events")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            Text("Enjoy your free time")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
    
    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 8) {
            // Event time indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(colorForEvent(event))
                .frame(width: 3, height: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 4) {
                    Text(formatEventTime(event.startDate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    if event.isAllDay {
                        Text("All Day")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.secondary.opacity(0.2))
                            .clipShape(Capsule())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("- \(formatEventTime(event.endDate))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if event.isUpcoming {
                Text(timeUntilEvent(event.startDate))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .animation(.easeInOut(duration: 0.2), value: event.isUpcoming)
    }
    
    // MARK: - Helper Methods
    private func colorForEvent(_ event: CalendarEvent) -> Color {
        // Use calendar color or default based on availability
        switch event.calendar.color {
        case .red:
            return .red
        case .orange:
            return .orange
        case .blue:
            return .blue
        case .green:
            return .green
        case .purple:
            return .purple
        default:
            return .blue
        }
    }
    
    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func timeUntilEvent(_ date: Date) -> String {
        let timeInterval = date.timeIntervalSinceNow
        
        if timeInterval < 0 {
            return "Now"
        } else if timeInterval < 3600 { // Less than 1 hour
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m"
        } else if timeInterval < 86400 { // Less than 1 day
            let hours = Int(timeInterval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days)d"
        }
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