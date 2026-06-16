import Foundation
import UserNotifications
import Combine
import AppKit
import os

@MainActor
final class EventNotificationService: NSObject, ObservableObject {
    
    // MARK: - Published Properties

    @Published var notificationsEnabled: Bool = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Properties

    private let notificationCenter = UNUserNotificationCenter.current()
    private var cancellables = Set<AnyCancellable>()

    /// Set by AppCoordinator. When non-nil, incoming notifications are routed
    /// to the notch instead of (or in addition to) macOS banners.
    /// Parameters: title, body, optional SF Symbol name.
    var onNotificationPresented: ((String, String, String?) -> Void)?
    
    // MARK: - Notification Categories
    
    private let eventReminderCategory = "EVENT_REMINDER"
    private let eventStartCategory = "EVENT_START"
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        notificationCenter.delegate = self
        setupNotificationCategories()
        checkAuthorizationStatus()
    }
    
    // MARK: - Public Interface
    
    func requestNotificationPermission() async -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound, .badge, .provisional]
        
        do {
            let granted = try await notificationCenter.requestAuthorization(options: options)
            await updateAuthorizationStatus()
            return granted
        } catch {
            AppLogger.notifications.error("Notification permission request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    func scheduleEventReminder(for event: CalendarEvent, minutesBefore: Int) async {
        guard notificationsEnabled else { return }
        
        let identifier = "reminder_\(event.id)_\(minutesBefore)"
        let triggerDate = event.startDate.addingTimeInterval(-TimeInterval(minutesBefore * 60))
        
        // Don't schedule if trigger date is in the past
        guard triggerDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Upcoming Event"
        content.body = "\(event.title) starts in \(minutesBefore) minute\(minutesBefore == 1 ? "" : "s")"
        content.sound = .default
        content.categoryIdentifier = eventReminderCategory
        
        // Add meeting join action if available
        if event.meetingURL != nil {
            content.userInfo = [
                "eventId": event.id,
                "action": "joinMeeting",
                "meetingURL": event.meetingURL?.absoluteString ?? ""
            ]
        }
        
        let triggerDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDateComponents, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await notificationCenter.add(request)
        } catch {
            AppLogger.notifications.error("Failed to schedule event reminder: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func scheduleEventStartNotification(for event: CalendarEvent) async {
        guard notificationsEnabled else { return }
        
        let identifier = "start_\(event.id)"
        
        // Don't schedule if event start is in the past
        guard event.startDate > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Event Starting"
        content.body = "\(event.title) is starting now"
        
        if let location = event.location {
            content.subtitle = "📍 \(location)"
        }
        
        content.sound = .default
        content.categoryIdentifier = eventStartCategory
        content.userInfo = [
            "eventId": event.id,
            "action": "eventStart"
        ]
        
        let triggerDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: event.startDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDateComponents, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        do {
            try await notificationCenter.add(request)
        } catch {
            AppLogger.notifications.error("Failed to schedule event start notification: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func cancelNotifications(for eventId: String) async {
        let identifiersToRemove = [
            "reminder_\(eventId)_5",
            "reminder_\(eventId)_15",
            "reminder_\(eventId)_30",
            "start_\(eventId)"
        ]
        
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
    }
    
    func cancelAllEventNotifications() async {
        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let eventNotificationIds = pendingRequests
            .filter { request in
                request.identifier.hasPrefix("reminder_") || request.identifier.hasPrefix("start_")
            }
            .map { $0.identifier }
        
        notificationCenter.removePendingNotificationRequests(withIdentifiers: eventNotificationIds)
    }
    
    func getPendingNotifications() async -> [UNNotificationRequest] {
        return await notificationCenter.pendingNotificationRequests()
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationCategories() {
        // Event Reminder Category with Actions
        let joinMeetingAction = UNNotificationAction(
            identifier: "JOIN_MEETING",
            title: "Join Meeting",
            options: [.foreground]
        )
        
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_5",
            title: "Snooze 5 min",
            options: []
        )
        
        let reminderCategory = UNNotificationCategory(
            identifier: eventReminderCategory,
            actions: [joinMeetingAction, snoozeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        // Event Start Category
        let viewEventAction = UNNotificationAction(
            identifier: "VIEW_EVENT",
            title: "View Event",
            options: [.foreground]
        )
        
        let startCategory = UNNotificationCategory(
            identifier: eventStartCategory,
            actions: [joinMeetingAction, viewEventAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        
        notificationCenter.setNotificationCategories([reminderCategory, startCategory])
    }
    
    private func checkAuthorizationStatus() {
        Task {
            await updateAuthorizationStatus()
        }
    }
    
    private func updateAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        notificationsEnabled = settings.authorizationStatus == .authorized || 
                              settings.authorizationStatus == .provisional
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension EventNotificationService: @MainActor UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Route to the notch when a routing callback is registered.
        // Category determines the SF Symbol used in the notch banner.
        let content = notification.request.content
        let categoryIcon: String?
        switch content.categoryIdentifier {
        case "EVENT_REMINDER", "EVENT_START":
            categoryIcon = "calendar"
        default:
            categoryIcon = nil
        }
        let title = content.title.isEmpty ? "Notification" : content.title
        let body = content.body
        onNotificationPresented?(title, body, categoryIcon)

        // Also play sound; suppress macOS banner since the notch shows it.
        if onNotificationPresented != nil {
            completionHandler([.sound])
        } else {
            completionHandler([.banner, .sound])
        }
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        
        switch response.actionIdentifier {
        case "JOIN_MEETING":
            if let urlString = userInfo["meetingURL"] as? String,
               let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            
        case "SNOOZE_5":
            if let eventId = userInfo["eventId"] as? String {
                // Post notification to snooze the reminder
                NotificationCenter.default.post(
                    name: .snoozeEventReminder,
                    object: nil,
                    userInfo: ["eventId": eventId, "minutes": 5]
                )
            }
            
        case "VIEW_EVENT":
            if let eventId = userInfo["eventId"] as? String {
                // Post notification to show event details
                NotificationCenter.default.post(
                    name: .showEventDetails,
                    object: nil,
                    userInfo: ["eventId": eventId]
                )
            }
            
        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification without selecting an action
            if let eventId = userInfo["eventId"] as? String {
                NotificationCenter.default.post(
                    name: .showEventDetails,
                    object: nil,
                    userInfo: ["eventId": eventId]
                )
            }
            
        default:
            break
        }
        
        completionHandler()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let snoozeEventReminder = Notification.Name("snoozeEventReminder")
    static let showEventDetails = Notification.Name("showEventDetails")
}