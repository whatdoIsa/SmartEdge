import Foundation
import EventKit
import AppKit

@MainActor
final class CalendarQuickActions: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isPerformingAction: Bool = false
    @Published var lastActionResult: ActionResult?
    
    // MARK: - Dependencies
    
    private let calendarService: any CalendarServiceProtocol
    private let eventStore = EKEventStore()
    
    // MARK: - Types
    
    enum ActionResult {
        case success(String)
        case failure(String)
        
        var message: String {
            switch self {
            case .success(let message), .failure(let message):
                return message
            }
        }
        
        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
    }
    
    enum QuickEventDuration: TimeInterval, CaseIterable {
        case fifteen = 900      // 15 minutes
        case thirty = 1800      // 30 minutes
        case hour = 3600        // 1 hour
        case twoHours = 7200    // 2 hours
        
        var displayName: String {
            switch self {
            case .fifteen: return "15 min"
            case .thirty: return "30 min"
            case .hour: return "1 hour"
            case .twoHours: return "2 hours"
            }
        }
    }
    
    // MARK: - Initialization
    
    init(calendarService: any CalendarServiceProtocol) {
        self.calendarService = calendarService
    }
    
    // MARK: - Meeting Actions
    
    func joinMeeting(for event: CalendarEvent) async -> Bool {
        isPerformingAction = true
        defer { isPerformingAction = false }
        
        let success = await calendarService.joinMeeting(for: event)
        
        if success {
            lastActionResult = .success("Joined \(event.title)")
        } else {
            lastActionResult = .failure("Could not join meeting for \(event.title)")
        }
        
        return success
    }
    
    func openMeetingInBrowser(for event: CalendarEvent) async -> Bool {
        guard let meetingURL = event.meetingURL else {
            lastActionResult = .failure("No meeting URL found for \(event.title)")
            return false
        }
        
        isPerformingAction = true
        defer { isPerformingAction = false }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let success = NSWorkspace.shared.open(meetingURL)
                if success {
                    self.lastActionResult = .success("Opened meeting in browser")
                } else {
                    self.lastActionResult = .failure("Failed to open meeting URL")
                }
                continuation.resume(returning: success)
            }
        }
    }
    
    func copyMeetingURL(for event: CalendarEvent) -> Bool {
        guard let meetingURL = event.meetingURL else {
            lastActionResult = .failure("No meeting URL found for \(event.title)")
            return false
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(meetingURL.absoluteString, forType: .string)
        
        if success {
            lastActionResult = .success("Meeting URL copied to clipboard")
        } else {
            lastActionResult = .failure("Failed to copy meeting URL")
        }
        
        return success
    }
    
    // MARK: - Event Management Actions
    
    func snoozeReminder(for event: CalendarEvent, minutes: Int) async {
        isPerformingAction = true
        defer { isPerformingAction = false }
        
        await calendarService.snoozeReminder(for: event, minutes: minutes)
        lastActionResult = .success("Reminder snoozed for \(minutes) minute\(minutes == 1 ? "" : "s")")
    }
    
    func markEventAsCompleted(for event: CalendarEvent) async -> Bool {
        guard findEKEvent(for: event) != nil else {
            lastActionResult = .failure("Could not find event in calendar")
            return false
        }

        isPerformingAction = true
        defer { isPerformingAction = false }

        // EKEvent does not support a completion flag; reminders must be fetched
        // via fetchReminders(matching:) on the EKEventStore, which is not wired
        // up here. Treat calendar events as not completable.
        lastActionResult = .failure("This action is only available for tasks")
        return false
    }
    
    func openInCalendarApp(for event: CalendarEvent) -> Bool {
        // Create a calendar URL to open the specific event
        let calendarURL = URL(string: "calshow:\(event.startDate.timeIntervalSinceReferenceDate)")
        
        guard let url = calendarURL else {
            lastActionResult = .failure("Could not create calendar URL")
            return false
        }
        
        let success = NSWorkspace.shared.open(url)
        
        if success {
            lastActionResult = .success("Opened in Calendar app")
        } else {
            lastActionResult = .failure("Failed to open Calendar app")
        }
        
        return success
    }
    
    // MARK: - Quick Event Creation
    
    func createQuickEvent(
        title: String,
        startDate: Date = Date(),
        duration: QuickEventDuration = .thirty,
        location: String? = nil,
        notes: String? = nil
    ) async -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastActionResult = .failure("Event title cannot be empty")
            return false
        }
        
        isPerformingAction = true
        defer { isPerformingAction = false }
        
        let success = await calendarService.createQuickEvent(
            title: title,
            startDate: startDate,
            duration: duration.rawValue
        )
        
        if success {
            lastActionResult = .success("Created event: \(title)")
        } else {
            lastActionResult = .failure("Failed to create event: \(title)")
        }
        
        return success
    }
    
    func createMeetingFromTemplate(
        type: MeetingType,
        title: String? = nil,
        startDate: Date = Date(),
        duration: QuickEventDuration = .hour
    ) async -> Bool {
        let eventTitle = title ?? type.defaultTitle
        let eventNotes = type.defaultNotes
        
        isPerformingAction = true
        defer { isPerformingAction = false }
        
        let ekEvent = EKEvent(eventStore: eventStore)
        ekEvent.title = eventTitle
        ekEvent.startDate = startDate
        ekEvent.endDate = startDate.addingTimeInterval(duration.rawValue)
        ekEvent.calendar = eventStore.defaultCalendarForNewEvents
        ekEvent.notes = eventNotes
        
        // Add meeting URL if applicable
        if let meetingURL = generateMeetingURL(for: type) {
            if ekEvent.notes == nil {
                ekEvent.notes = meetingURL.absoluteString
            } else {
                ekEvent.notes! += "\n\n\(meetingURL.absoluteString)"
            }
        }
        
        do {
            try eventStore.save(ekEvent, span: .thisEvent)
            lastActionResult = .success("Created \(type.displayName): \(eventTitle)")
            return true
        } catch {
            lastActionResult = .failure("Failed to create meeting: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Calendar Integration
    
    func exportEventToICS(for event: CalendarEvent) -> Bool {
        guard let ekEvent = findEKEvent(for: event) else {
            lastActionResult = .failure("Could not find event in calendar")
            return false
        }
        
        // Create ICS data
        let icsData = generateICSData(for: ekEvent)
        
        // Save to desktop
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let fileName = "\(event.title.replacingOccurrences(of: " ", with: "_")).ics"
        let fileURL = desktop.appendingPathComponent(fileName)
        
        do {
            try icsData.write(to: fileURL, atomically: true, encoding: .utf8)
            lastActionResult = .success("Exported to \(fileName)")
            return true
        } catch {
            lastActionResult = .failure("Failed to export event: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Private Helper Methods
    
    private func findEKEvent(for event: CalendarEvent) -> EKEvent? {
        let startDate = event.startDate.addingTimeInterval(-60) // 1 minute buffer
        let endDate = event.startDate.addingTimeInterval(60)
        
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )
        
        let events = eventStore.events(matching: predicate)
        return events.first { $0.eventIdentifier == event.id }
    }
    
    private func generateMeetingURL(for type: MeetingType) -> URL? {
        switch type {
        case .zoom:
            return URL(string: "https://zoom.us/start/videomeeting")
        case .teams:
            return URL(string: "https://teams.microsoft.com/")
        case .meet:
            return URL(string: "https://meet.google.com/new")
        case .facetime:
            return URL(string: "facetime://")
        case .generic:
            return nil
        }
    }
    
    private func generateICSData(for event: EKEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        
        let startDate = formatter.string(from: event.startDate)
        let endDate = formatter.string(from: event.endDate)
        let created = formatter.string(from: event.creationDate ?? Date())
        
        var icsContent = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//SmartEdge//Calendar Export//EN
        BEGIN:VEVENT
        UID:\(event.eventIdentifier ?? UUID().uuidString)
        DTSTART:\(startDate)
        DTEND:\(endDate)
        DTSTAMP:\(created)
        SUMMARY:\(event.title ?? "Untitled Event")
        """
        
        if let location = event.location {
            icsContent += "\nLOCATION:\(location)"
        }
        
        if let notes = event.notes {
            icsContent += "\nDESCRIPTION:\(notes.replacingOccurrences(of: "\n", with: "\\n"))"
        }
        
        if let url = event.url {
            icsContent += "\nURL:\(url.absoluteString)"
        }
        
        icsContent += """
        \nSTATUS:CONFIRMED
        END:VEVENT
        END:VCALENDAR
        """
        
        return icsContent
    }
}

// MARK: - Supporting Types

enum MeetingType: CaseIterable {
    case zoom
    case teams
    case meet
    case facetime
    case generic
    
    var displayName: String {
        switch self {
        case .zoom: return "Zoom Meeting"
        case .teams: return "Teams Meeting" 
        case .meet: return "Google Meet"
        case .facetime: return "FaceTime Call"
        case .generic: return "Meeting"
        }
    }
    
    var defaultTitle: String {
        switch self {
        case .zoom: return "Zoom Meeting"
        case .teams: return "Microsoft Teams Meeting"
        case .meet: return "Google Meet"
        case .facetime: return "FaceTime Call"
        case .generic: return "Quick Meeting"
        }
    }
    
    var defaultNotes: String? {
        switch self {
        case .zoom:
            return "Join Zoom Meeting\nMeeting ID will be provided"
        case .teams:
            return "Microsoft Teams meeting invite"
        case .meet:
            return "Google Meet video call"
        case .facetime:
            return "FaceTime video call"
        case .generic:
            return nil
        }
    }
}