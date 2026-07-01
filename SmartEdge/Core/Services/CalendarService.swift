import Foundation
import EventKit
import Combine
import AppKit
import os

@MainActor
final class CalendarService: ObservableObject, CalendarServiceProtocol {
    
    // MARK: - Published Properties
    
    @Published var upcomingEvents: [CalendarEvent] = []
    @Published var nextEvent: CalendarEvent? = nil
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var isAuthorized: Bool = false

    // MARK: - Publishers (Protocol Conformance)

    var upcomingEventsPublisher: AnyPublisher<[CalendarEvent], Never> {
        $upcomingEvents.eraseToAnyPublisher()
    }

    var isAuthorizedPublisher: AnyPublisher<Bool, Never> {
        $isAuthorized.eraseToAnyPublisher()
    }
    
    // MARK: - Properties
    
    weak var delegate: CalendarServiceDelegate?
    
    private let eventStore = EKEventStore()
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var notificationObserver: NSObjectProtocol?
    private var reminderTimers: [String: Timer] = [:]
    
    // MARK: - Configuration
    
    private let maxEventsToFetch: Int = 20
    private let eventFetchPeriod: TimeInterval = 24 * 60 * 60 // 24 hours
    private let refreshInterval: TimeInterval = 5 * 60 // 5 minutes
    private let reminderIntervals: [Int] = [5, 15, 30] // minutes before event
    
    // MARK: - Initialization
    
    init() {
        setupNotifications()
        checkAuthorizationStatus()
        setupRefreshTimer()
    }
    
    deinit {
        refreshTimer?.invalidate()
        reminderTimers.values.forEach { $0.invalidate() }
        
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Public Interface
    
    func requestCalendarAccess() async -> Bool {
        guard !isAuthorized else { return true }

        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            await updateAuthorizationStatus()

            if granted {
                await refreshEvents()
            }

            return granted
        } catch {
            AppLogger.calendar.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    func refreshEvents() async {
        guard isAuthorized else { return }
        
        do {
            let events = try await fetchUpcomingEvents()
            
            upcomingEvents = events
            nextEvent = events.first
            
            delegate?.calendarService(self, didUpdateEvents: events)
            setupEventReminders(for: events)
            
        } catch {
            AppLogger.calendar.error("Failed to refresh calendar events: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func joinMeeting(for event: CalendarEvent) async -> Bool {
        guard let meetingURL = event.meetingURL else {
            return false
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let success = NSWorkspace.shared.open(meetingURL)
                continuation.resume(returning: success)
            }
        }
    }
    
    func snoozeReminder(for event: CalendarEvent, minutes: Int) async {
        let snoozeDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        setupReminderTimer(for: event, alertDate: snoozeDate)
    }
    
    func createQuickEvent(title: String, startDate: Date, duration: TimeInterval) async -> Bool {
        guard isAuthorized else { return false }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(duration)
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)
            await refreshEvents()
            return true
        } catch {
            AppLogger.calendar.error("Failed to create quick event: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.refreshEvents()
            }
        }
    }
    
    private func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = status
        isAuthorized = Self.statusGrantsReadAccess(status)

        delegate?.calendarService(self, didChangeAuthorizationStatus: status)

        if isAuthorized {
            Task { [weak self] in
                await self?.refreshEvents()
            }
        }
    }

    private func updateAuthorizationStatus() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorizationStatus = status
        isAuthorized = Self.statusGrantsReadAccess(status)

        delegate?.calendarService(self, didChangeAuthorizationStatus: status)
    }

    /// True when the user has granted any access that allows reading events.
    /// macOS 13: `.authorized`. macOS 14+: `.fullAccess` (or legacy `.authorized`).
    /// `.writeOnly` does not grant read access.
    static func statusGrantsReadAccess(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .fullAccess || status == .authorized
        }
        return status == .authorized
    }
    
    private func setupRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshEvents()
            }
        }
    }
    
    private func fetchUpcomingEvents() async throws -> [CalendarEvent] {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(eventFetchPeriod)
        
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )
        
        let ekEvents = eventStore.events(matching: predicate)
        
        let calendarEvents = ekEvents.compactMap { ekEvent -> CalendarEvent? in
            return convertEKEventToCalendarEvent(ekEvent)
        }
        
        // Sort by start date and limit results
        let sortedEvents = calendarEvents
            .sorted { $0.startDate < $1.startDate }
            .prefix(maxEventsToFetch)
        
        return Array(sortedEvents)
    }
    
    private func convertEKEventToCalendarEvent(_ ekEvent: EKEvent) -> CalendarEvent? {
        guard let eventId = ekEvent.eventIdentifier else { return nil }
        
        let calendarInfo = CalendarInfo(
            id: ekEvent.calendar.calendarIdentifier,
            title: ekEvent.calendar.title,
            color: convertCalendarColor(ekEvent.calendar.cgColor),
            colorComponents: rgbaComponents(from: ekEvent.calendar.cgColor),
            isSubscribed: ekEvent.calendar.isSubscribed,
            allowsContentModifications: ekEvent.calendar.allowsContentModifications,
            source: convertCalendarSource(ekEvent.calendar.source.sourceType)
        )
        
        let attendees = ekEvent.attendees?.compactMap { participant in
            convertEKParticipantToAttendee(participant)
        } ?? []
        
        let meetingURL = extractMeetingURL(from: ekEvent)
        
        return CalendarEvent(
            id: eventId,
            title: ekEvent.title ?? "Untitled Event",
            notes: ekEvent.notes,
            location: ekEvent.location,
            startDate: ekEvent.startDate,
            endDate: ekEvent.endDate,
            isAllDay: ekEvent.isAllDay,
            calendar: calendarInfo,
            attendees: attendees,
            url: ekEvent.url,
            meetingURL: meetingURL,
            status: convertEventStatus(ekEvent.status),
            availability: convertEventAvailability(ekEvent.availability),
            recurrenceRule: ekEvent.recurrenceRules?.first?.description,
            hasAlarms: !(ekEvent.alarms?.isEmpty ?? true)
        )
    }
    
    private func convertEKParticipantToAttendee(_ participant: EKParticipant) -> EventAttendee {
        return EventAttendee(
            id: participant.url.absoluteString,
            name: participant.name,
            emailAddress: participant.url.absoluteString,
            participantRole: convertParticipantRole(participant.participantRole),
            participantStatus: convertParticipantStatus(participant.participantStatus),
            isCurrentUser: participant.isCurrentUser
        )
    }
    
    private func extractMeetingURL(from event: EKEvent) -> URL? {
        // Check for common meeting URL patterns in notes and location
        let textToSearch = [event.notes, event.location, event.url?.absoluteString]
            .compactMap { $0 }
            .joined(separator: " ")
        
        let meetingPatterns = [
            "https://[\\w.-]*zoom\\.us/j/[\\d]+",
            "https://teams\\.microsoft\\.com/l/meetup-join/[\\w%.-]+",
            "https://meet\\.google\\.com/[\\w-]+",
            "https://[\\w.-]*webex\\.com/[\\w/.-]+",
            "https://[\\w.-]*gotomeeting\\.com/join/[\\d]+"
        ]
        
        for pattern in meetingPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(textToSearch.startIndex..., in: textToSearch)
                if let match = regex.firstMatch(in: textToSearch, options: [], range: range) {
                    let matchRange = Range(match.range, in: textToSearch)!
                    let urlString = String(textToSearch[matchRange])
                    return URL(string: urlString)
                }
            }
        }
        
        return event.url
    }
    
    private func setupEventReminders(for events: [CalendarEvent]) {
        // Clear existing reminders
        reminderTimers.values.forEach { $0.invalidate() }
        reminderTimers.removeAll()
        
        let now = Date()
        
        for event in events {
            guard event.isUpcoming else { continue }
            
            for reminderMinutes in reminderIntervals {
                let alertTime = event.startDate.addingTimeInterval(-TimeInterval(reminderMinutes * 60))
                
                guard alertTime > now else { continue }
                
                setupReminderTimer(for: event, alertDate: alertTime, minutesUntil: reminderMinutes)
            }
        }
    }
    
    private func setupReminderTimer(for event: CalendarEvent, alertDate: Date, minutesUntil: Int? = nil) {
        let timerKey = "\(event.id)_\(alertDate.timeIntervalSince1970)"
        
        let timer = Timer(fireAt: alertDate, interval: 0, target: self, selector: #selector(fireEventReminder(_:)), userInfo: [
            "event": event,
            "minutesUntil": minutesUntil ?? Int(event.startDate.timeIntervalSince(alertDate) / 60)
        ], repeats: false)
        
        reminderTimers[timerKey] = timer
        RunLoop.main.add(timer, forMode: .default)
    }
    
    @objc private func fireEventReminder(_ timer: Timer) {
        guard let userInfo = timer.userInfo as? [String: Any],
              let event = userInfo["event"] as? CalendarEvent,
              let minutesUntil = userInfo["minutesUntil"] as? Int else {
            return
        }
        
        delegate?.calendarService(self, didReceiveUpcomingEventAlert: event, minutesUntil: minutesUntil)
        
        // Remove the timer
        if let key = reminderTimers.first(where: { $0.value === timer })?.key {
            reminderTimers.removeValue(forKey: key)
        }
    }
    
    // MARK: - Helper Conversion Methods
    
    /// The calendar's true color as normalized [r, g, b, a], handling both RGB
    /// and grayscale `cgColor` component layouts. Empty when unavailable so the
    /// view can fall back to the app accent.
    private func rgbaComponents(from cgColor: CGColor?) -> [Double] {
        guard let components = cgColor?.components, !components.isEmpty else { return [] }
        if components.count >= 3 {
            let alpha = components.count >= 4 ? components[3] : 1
            return [Double(components[0]), Double(components[1]), Double(components[2]), Double(alpha)]
        }
        // Grayscale: [white, alpha]
        let white = Double(components[0])
        let alpha = components.count >= 2 ? Double(components[1]) : 1
        return [white, white, white, alpha]
    }

    private func convertCalendarColor(_ cgColor: CGColor?) -> CalendarColor {
        guard let cgColor = cgColor else { return .gray }
        
        let components = cgColor.components ?? []
        guard components.count >= 3 else { return .gray }
        
        let red = components[0]
        let green = components[1] 
        let blue = components[2]
        
        // Simple color matching based on RGB values
        switch (red, green, blue) {
        case (let r, let g, let b) where r > 0.8 && g < 0.3 && b < 0.3:
            return .red
        case (let r, let g, let b) where r > 0.8 && g > 0.5 && b < 0.3:
            return .orange
        case (let r, let g, let b) where r > 0.8 && g > 0.8 && b < 0.3:
            return .yellow
        case (let r, let g, let b) where r < 0.3 && g > 0.5 && b < 0.3:
            return .green
        case (let r, let g, let b) where r < 0.3 && g < 0.3 && b > 0.5:
            return .blue
        case (let r, let g, let b) where r > 0.5 && g < 0.3 && b > 0.5:
            return .purple
        case (let r, let g, let b) where r > 0.4 && r < 0.7 && g > 0.2 && g < 0.5 && b > 0.1 && b < 0.4:
            return .brown
        default:
            return .gray
        }
    }
    
    private func convertCalendarSource(_ sourceType: EKSourceType) -> CalendarSource {
        switch sourceType {
        case .local:
            return .local
        case .exchange:
            return .exchange
        case .calDAV:
            return .caldav
        case .mobileMe:
            return .mobileme
        case .subscribed:
            return .subscribed
        case .birthdays:
            return .birthdays
        @unknown default:
            return .local
        }
    }
    
    private func convertEventStatus(_ status: EKEventStatus) -> EventStatus {
        switch status {
        case .none:
            return .none
        case .confirmed:
            return .confirmed
        case .tentative:
            return .tentative
        case .canceled:
            return .canceled
        @unknown default:
            return .none
        }
    }
    
    private func convertEventAvailability(_ availability: EKEventAvailability) -> EventAvailability {
        switch availability {
        case .notSupported:
            return .notSupported
        case .busy:
            return .busy
        case .free:
            return .free
        case .tentative:
            return .tentative
        case .unavailable:
            return .unavailable
        @unknown default:
            return .notSupported
        }
    }
    
    private func convertParticipantRole(_ role: EKParticipantRole) -> AttendeeRole {
        switch role {
        case .unknown:
            return .unknown
        case .required:
            return .required
        case .optional:
            return .optional
        case .chair:
            return .chair
        case .nonParticipant:
            return .nonParticipant
        @unknown default:
            return .unknown
        }
    }
    
    private func convertParticipantStatus(_ status: EKParticipantStatus) -> AttendeeStatus {
        switch status {
        case .unknown:
            return .unknown
        case .pending:
            return .pending
        case .accepted:
            return .accepted
        case .declined:
            return .declined
        case .tentative:
            return .tentative
        case .delegated:
            return .delegated
        case .completed:
            return .completed
        case .inProcess:
            return .inProcess
        @unknown default:
            return .unknown
        }
    }
}