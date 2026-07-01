import Foundation
import EventKit

// MARK: - CalendarEvent

struct CalendarEvent: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let notes: String?
    let location: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendar: CalendarInfo
    let attendees: [EventAttendee]
    let url: URL?
    let meetingURL: URL?
    let status: EventStatus
    let availability: EventAvailability
    let recurrenceRule: String?
    let hasAlarms: Bool
    
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }
    
    var isToday: Bool {
        Calendar.current.isDateInToday(startDate)
    }
    
    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(startDate)
    }
    
    var isUpcoming: Bool {
        startDate > Date()
    }
    
    var isHappening: Bool {
        let now = Date()
        return now >= startDate && now <= endDate
    }
    
    var timeUntilStart: TimeInterval {
        startDate.timeIntervalSince(Date())
    }
    
    var formattedTimeRange: String {
        if isAllDay {
            return "All Day"
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        } else {
            formatter.dateStyle = .short
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
    }
    
    static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CalendarInfo

struct CalendarInfo: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let color: CalendarColor
    /// The calendar's true color as normalized [r, g, b, a] (0...1), captured
    /// straight from `EKCalendar.cgColor` so the notch can mirror the exact
    /// color the user set in Calendar. Empty when unavailable.
    var colorComponents: [Double] = []
    let isSubscribed: Bool
    let allowsContentModifications: Bool
    let source: CalendarSource
    
    static func == (lhs: CalendarInfo, rhs: CalendarInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - EventAttendee

struct EventAttendee: Identifiable, Equatable, Hashable {
    let id: String
    let name: String?
    let emailAddress: String?
    let participantRole: AttendeeRole
    let participantStatus: AttendeeStatus
    let isCurrentUser: Bool
    
    static func == (lhs: EventAttendee, rhs: EventAttendee) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - EventReminder

struct EventReminder: Identifiable, Equatable {
    let id: UUID = UUID()
    let event: CalendarEvent
    let alertDate: Date
    let minutesBeforeEvent: Int
    let type: ReminderType
    
    static func == (lhs: EventReminder, rhs: EventReminder) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Supporting Enums

enum EventStatus: String, CaseIterable {
    case none = "none"
    case confirmed = "confirmed"
    case tentative = "tentative"
    case canceled = "canceled"
    
    var displayName: String {
        switch self {
        case .none: return "No Response"
        case .confirmed: return "Confirmed"
        case .tentative: return "Tentative"
        case .canceled: return "Canceled"
        }
    }
}

enum EventAvailability: String, CaseIterable {
    case notSupported = "notSupported"
    case busy = "busy"
    case free = "free"
    case tentative = "tentative"
    case unavailable = "unavailable"
    
    var displayName: String {
        switch self {
        case .notSupported: return "Unknown"
        case .busy: return "Busy"
        case .free: return "Free"
        case .tentative: return "Tentative"
        case .unavailable: return "Unavailable"
        }
    }
}

enum AttendeeRole: String, CaseIterable {
    case unknown = "unknown"
    case required = "required"
    case optional = "optional"
    case chair = "chair"
    case nonParticipant = "nonParticipant"
    
    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .required: return "Required"
        case .optional: return "Optional"
        case .chair: return "Chair"
        case .nonParticipant: return "Non-Participant"
        }
    }
}

enum AttendeeStatus: String, CaseIterable {
    case unknown = "unknown"
    case pending = "pending"
    case accepted = "accepted"
    case declined = "declined"
    case tentative = "tentative"
    case delegated = "delegated"
    case completed = "completed"
    case inProcess = "inProcess"
    
    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .tentative: return "Tentative"
        case .delegated: return "Delegated"
        case .completed: return "Completed"
        case .inProcess: return "In Process"
        }
    }
}

enum CalendarColor: String, CaseIterable {
    case red = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case blue = "blue"
    case purple = "purple"
    case brown = "brown"
    case gray = "gray"
    
    var displayName: String {
        rawValue.capitalized
    }
}

enum CalendarSource: String, CaseIterable {
    case local = "local"
    case exchange = "exchange"
    case caldav = "caldav"
    case mobileme = "mobileme"
    case subscribed = "subscribed"
    case birthdays = "birthdays"
    
    var displayName: String {
        switch self {
        case .local: return "Local"
        case .exchange: return "Exchange"
        case .caldav: return "CalDAV"
        case .mobileme: return "iCloud"
        case .subscribed: return "Subscribed"
        case .birthdays: return "Birthdays"
        }
    }
}

enum ReminderType: String, CaseIterable {
    case notification = "notification"
    case email = "email"
    case display = "display"
    
    var displayName: String {
        switch self {
        case .notification: return "Notification"
        case .email: return "Email"
        case .display: return "Display"
        }
    }
}

// MARK: - Calendar Service Errors

enum CalendarServiceError: Error, LocalizedError {
    case authorizationDenied
    case authorizationRestricted
    case eventStoreUnavailable
    case eventNotFound
    case invalidEventData
    case meetingURLNotFound
    case quickActionFailed
    case reminderSetupFailed
    case calendarAccessRevoked
    case unsupportedOperation
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Calendar access was denied. Please grant permission in System Preferences."
        case .authorizationRestricted:
            return "Calendar access is restricted by system policy."
        case .eventStoreUnavailable:
            return "Calendar data is temporarily unavailable."
        case .eventNotFound:
            return "The requested event could not be found."
        case .invalidEventData:
            return "Event data is invalid or corrupted."
        case .meetingURLNotFound:
            return "No meeting URL found for this event."
        case .quickActionFailed:
            return "Quick action could not be completed."
        case .reminderSetupFailed:
            return "Failed to set up event reminder."
        case .calendarAccessRevoked:
            return "Calendar access has been revoked."
        case .unsupportedOperation:
            return "This operation is not supported."
        }
    }
    
    var failureReason: String? {
        switch self {
        case .authorizationDenied, .authorizationRestricted:
            return "Calendar permissions are required to display upcoming events."
        case .eventStoreUnavailable:
            return "System calendar service is temporarily unavailable."
        case .calendarAccessRevoked:
            return "User revoked calendar access in system settings."
        default:
            return errorDescription
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .authorizationDenied, .calendarAccessRevoked:
            return "Open System Preferences > Privacy & Security > Calendar and grant access to this app."
        case .authorizationRestricted:
            return "Contact your system administrator to allow calendar access."
        case .eventStoreUnavailable:
            return "Try again in a few moments."
        default:
            return "Please try again or contact support if the problem persists."
        }
    }
}