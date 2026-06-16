import SwiftUI
import Combine
import EventKit
import Foundation

@MainActor
final class CalendarViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var currentDate = ""
    @Published private(set) var currentTime = ""
    @Published private(set) var currentWeekday = ""
    @Published private(set) var upcomingEvents: [CalendarEvent] = []
    @Published private(set) var nextEvent: CalendarEvent?
    @Published private(set) var isLoading = false
    @Published private(set) var lastRefreshTime = Date()
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published private(set) var isAuthorized = false
    @Published var showingEventDetails = false
    @Published var selectedEvent: CalendarEvent?
    
    // MARK: - Dependencies
    
    private let calendarService: any CalendarServiceProtocol
    private let quickActions: CalendarQuickActions
    private let notificationService: EventNotificationService
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var timeUpdateTimer: Timer?
    private var eventRefreshTimer: Timer?
    
    // MARK: - Formatters
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    private let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
    
    // MARK: - Computed Properties
    
    var hasUpcomingEvents: Bool {
        !upcomingEvents.isEmpty
    }
    
    var nextMeetingWithinHour: CalendarEvent? {
        upcomingEvents.first { event in
            event.timeUntilStart > 0 && event.timeUntilStart <= 3600 // Within 1 hour
        }
    }
    
    var todayEvents: [CalendarEvent] {
        upcomingEvents.filter { $0.isToday }
    }
    
    var tomorrowEvents: [CalendarEvent] {
        upcomingEvents.filter { $0.isTomorrow }
    }
    
    // MARK: - Initialization
    
    init(
        calendarService: any CalendarServiceProtocol,
        quickActions: CalendarQuickActions,
        notificationService: EventNotificationService
    ) {
        self.calendarService = calendarService
        self.quickActions = quickActions
        self.notificationService = notificationService
        
        setupBindings()
        startTimeUpdates()
        updateDateTime()
        
        Task {
            await requestCalendarAccessIfNeeded()
        }
    }
    
    deinit {
        cancellables.removeAll()
        timeUpdateTimer?.invalidate()
        eventRefreshTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func refreshData() async {
        updateDateTime()
        await loadEvents()
    }
    
    func requestCalendarAccess() async {
        isLoading = true
        
        let granted = await calendarService.requestCalendarAccess()
        
        isLoading = false
        isAuthorized = granted
        authorizationStatus = calendarService.authorizationStatus
        
        if granted {
            await loadEvents()
            await setupNotifications()
        }
    }
    
    func joinMeeting(for event: CalendarEvent) async {
        _ = await quickActions.joinMeeting(for: event)
    }
    
    func snoozeReminder(for event: CalendarEvent, minutes: Int = 5) async {
        await quickActions.snoozeReminder(for: event, minutes: minutes)
    }
    
    func createQuickEvent(title: String, duration: CalendarQuickActions.QuickEventDuration = .thirty) async {
        let success = await calendarService.createQuickEvent(
            title: title,
            startDate: Date(),
            duration: duration.rawValue
        )
        
        if success {
            await loadEvents()
        }
    }
    
    func showEventDetails(for event: CalendarEvent) {
        selectedEvent = event
        showingEventDetails = true
    }
    
    func dismissEventDetails() {
        selectedEvent = nil
        showingEventDetails = false
    }
    
    // MARK: - Private Methods
    
    private func requestCalendarAccessIfNeeded() async {
        if calendarService.authorizationStatus == .notDetermined {
            await requestCalendarAccess()
        } else {
            isAuthorized = calendarService.isAuthorized
            authorizationStatus = calendarService.authorizationStatus
            
            if isAuthorized {
                await loadEvents()
                await setupNotifications()
            }
        }
    }
    
    private func loadEvents() async {
        guard isAuthorized else { return }
        
        isLoading = true
        
        await calendarService.refreshEvents()
        
        upcomingEvents = calendarService.upcomingEvents
        nextEvent = calendarService.nextEvent
        lastRefreshTime = Date()
        isLoading = false
    }
    
    private func setupNotifications() async {
        let permissionGranted = await notificationService.requestNotificationPermission()
        
        guard permissionGranted else { return }
        
        // Schedule notifications for upcoming events
        for event in upcomingEvents {
            // Schedule reminders for 5, 15, and 30 minutes before
            await notificationService.scheduleEventReminder(for: event, minutesBefore: 5)
            await notificationService.scheduleEventReminder(for: event, minutesBefore: 15)
            await notificationService.scheduleEventReminder(for: event, minutesBefore: 30)
            
            // Schedule event start notification
            await notificationService.scheduleEventStartNotification(for: event)
        }
    }
    
    private func setupBindings() {
        // Calendar service updates
        //         calendarService.objectWillChange
        //             .receive(on: DispatchQueue.main)
        //             .sink { [weak self] in
        //                 self?.objectWillChange.send()
        //             }
        //             .store(in: &cancellables)
        
        // Notification center observers for quick actions
        NotificationCenter.default.publisher(for: .snoozeEventReminder)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let eventId = notification.userInfo?["eventId"] as? String,
                      let minutes = notification.userInfo?["minutes"] as? Int,
                      let event = self.upcomingEvents.first(where: { $0.id == eventId }) else {
                    return
                }
                
                Task {
                    await self.snoozeReminder(for: event, minutes: minutes)
                }
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .showEventDetails)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let eventId = notification.userInfo?["eventId"] as? String,
                      let event = self.upcomingEvents.first(where: { $0.id == eventId }) else {
                    return
                }
                
                self.showEventDetails(for: event)
            }
            .store(in: &cancellables)
    }
    
    private func startTimeUpdates() {
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDateTime()
            }
        }
        
        // Refresh events every 5 minutes
        eventRefreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.loadEvents()
            }
        }
    }
    
    private func updateDateTime() {
        let now = Date()
        currentDate = dateFormatter.string(from: now)
        currentTime = timeFormatter.string(from: now)
        currentWeekday = weekdayFormatter.string(from: now)
    }
}

// MARK: - CalendarServiceDelegate

extension CalendarViewModel: CalendarServiceDelegate {
    
    func calendarService(_ service: any CalendarServiceProtocol, didUpdateEvents events: [CalendarEvent]) {
        upcomingEvents = events
        nextEvent = events.first
        
        Task {
            await setupNotifications()
        }
    }
    
    func calendarService(_ service: any CalendarServiceProtocol, didReceiveUpcomingEventAlert event: CalendarEvent, minutesUntil: Int) {
        // This can be used to show an in-app alert or update UI for upcoming events
        // For now, the EventNotificationService handles system notifications
    }
    
    func calendarService(_ service: any CalendarServiceProtocol, didChangeAuthorizationStatus status: EKAuthorizationStatus) {
        authorizationStatus = status
        isAuthorized = status == .authorized
        
        if isAuthorized {
            Task {
                await loadEvents()
                await setupNotifications()
            }
        }
    }
}