import Foundation
import EventKit
import Combine

@MainActor
protocol CalendarServiceProtocol: ObservableObject {
    var upcomingEvents: [CalendarEvent] { get }
    var nextEvent: CalendarEvent? { get }
    var authorizationStatus: EKAuthorizationStatus { get }
    var isAuthorized: Bool { get }

    /// Publisher fired every time the cached event list is refreshed.
    /// NotchViewModel subscribes to this to drive the notch's calendar
    /// preview — without it `handleCalendarEvents` was dead code because
    /// `Calendar service doesn't define a required publisher` (literal
    /// comment that used to live in NotchViewModel).
    var upcomingEventsPublisher: AnyPublisher<[CalendarEvent], Never> { get }

    /// Publisher mirroring `isAuthorized`. Settings panels and the
    /// permission guide observe this so granting Calendar in System
    /// Settings reactively unlocks the rest of the calendar UX without
    /// requiring a relaunch.
    var isAuthorizedPublisher: AnyPublisher<Bool, Never> { get }

    func requestCalendarAccess() async -> Bool
    func refreshEvents() async
    func joinMeeting(for event: CalendarEvent) async -> Bool
    func snoozeReminder(for event: CalendarEvent, minutes: Int) async
    func createQuickEvent(title: String, startDate: Date, duration: TimeInterval) async -> Bool
}

@MainActor
protocol CalendarServiceDelegate: AnyObject {
    func calendarService(_ service: any CalendarServiceProtocol, didUpdateEvents events: [CalendarEvent])
    func calendarService(_ service: any CalendarServiceProtocol, didReceiveUpcomingEventAlert event: CalendarEvent, minutesUntil: Int)
    func calendarService(_ service: any CalendarServiceProtocol, didChangeAuthorizationStatus status: EKAuthorizationStatus)
}