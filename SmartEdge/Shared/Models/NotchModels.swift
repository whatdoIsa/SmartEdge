import Foundation
import EventKit
import SwiftUI

enum NotchContent: Equatable {
    case collapsed
    case musicPlayer(isPlaying: Bool, title: String?, artist: String?)
    case calendar(event: CalendarEvent?)
    case shelf(operation: ShelfOperation)
    case systemStatus(battery: BatteryInfo?, bluetooth: BluetoothInfo?)
    case notification(title: String, body: String, icon: String?)
    case pomodoro
    case clipboardHistory
    case actions
    case settings

    static func == (lhs: NotchContent, rhs: NotchContent) -> Bool {
        switch (lhs, rhs) {
        case (.collapsed, .collapsed), (.settings, .settings), (.pomodoro, .pomodoro), (.clipboardHistory, .clipboardHistory), (.actions, .actions):
            return true
        case let (.musicPlayer(lhsPlaying, lhsTitle, lhsArtist), .musicPlayer(rhsPlaying, rhsTitle, rhsArtist)):
            return lhsPlaying == rhsPlaying && lhsTitle == rhsTitle && lhsArtist == rhsArtist
        case let (.calendar(lhsEvent), .calendar(rhsEvent)):
            return lhsEvent == rhsEvent
        case let (.shelf(lhsOperation), .shelf(rhsOperation)):
            return lhsOperation == rhsOperation
        case let (.systemStatus(lhsBattery, lhsBluetooth), .systemStatus(rhsBattery, rhsBluetooth)):
            return lhsBattery == rhsBattery && lhsBluetooth == rhsBluetooth
        case let (.notification(lhsTitle, lhsBody, lhsIcon), .notification(rhsTitle, rhsBody, rhsIcon)):
            return lhsTitle == rhsTitle && lhsBody == rhsBody && lhsIcon == rhsIcon
        default:
            return false
        }
    }
}

enum NotchState: Equatable {
    case collapsed
    case expanded
    case transitioning
}

struct NotchConfiguration {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let animationDuration: TimeInterval
    
    // Idle dimensions match the MacBook Pro 14"/16" hardware notch
    // (~200×32 pt) so the collapsed overlay tucks invisibly *behind* the
    // physical camera housing. Users see nothing extra when nothing's
    // happening — exactly like Apple's own Dynamic Island treatment.
    // Hover then blooms it into the expanded box (below) which is large
    // enough to host real UI.
    static let `default` = NotchConfiguration(
        width: 200,
        height: 32,
        cornerRadius: 10,
        animationDuration: 0.35
    )

    // Expanded dimensions: comfortably larger than the hardware notch on
    // every side so the bloom feels deliberate rather than incremental.
    //
    // Height accounting: the top `default.height` (32pt) is reserved as a
    // visual gutter for the hardware camera notch — `NotchView` insets the
    // content area by exactly that amount so titles/controls never sit
    // behind the camera. We therefore budget 32pt for the gutter PLUS
    // ~210pt for content (album art + track info + transport controls +
    // breathing room). Earlier we used 180 total, but with the gutter
    // applied that left only 148pt for content and clipped the "Open Music
    // App" CTA at the bottom.
    static let expanded = NotchConfiguration(
        width: 480,
        height: 252,
        cornerRadius: 22,
        animationDuration: 0.35
    )

    // Resting state while a pomodoro session counts down: same width as the
    // idle notch (so it still tucks behind the camera housing) but taller, so
    // a slim countdown strip hangs *below* the camera and stays glanceable
    // without the full bloom. Collapses back to `default` when the session ends.
    static let pomodoroResting = NotchConfiguration(
        width: 200,
        height: 62,
        cornerRadius: 14,
        animationDuration: 0.35
    )
}

struct NotchPosition {
    let x: CGFloat
    let y: CGFloat
    
    static let center = NotchPosition(x: 0, y: 0)
}

// MARK: - Content Priority System
enum NotchContentPriority: Int, CaseIterable, Comparable {
    case calendar = 80        // High priority - meeting reminders
    case shelf = 60           // Medium priority - file operations
    case musicPlayer = 40     // Normal priority - default content
    case systemStatus = 20    // Low priority - when idle
    case settings = 10        // Lowest priority - user-initiated

    static func < (lhs: NotchContentPriority, rhs: NotchContentPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - User Priority Preset
enum NotchPriorityPreset: String, CaseIterable, Hashable, Identifiable {
    case music
    case calendar
    case system
    case balanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: return "Music"
        case .calendar: return "Calendar"
        case .system: return "System"
        case .balanced: return "Balanced"
        }
    }
}

extension NotchContent {
    var priority: NotchContentPriority {
        switch self {
        case .collapsed:
            return .settings
        case .musicPlayer:
            return .musicPlayer
        case .calendar:
            return .calendar
        case .shelf:
            return .shelf
        case .systemStatus:
            return .systemStatus
        case .notification:
            // Notifications interrupt at high priority but auto-hide quickly.
            return .calendar
        case .pomodoro:
            // Persistent — sits between music and system status priority.
            return .musicPlayer
        case .clipboardHistory:
            // User-initiated quick access; mid priority.
            return .shelf
        case .actions:
            // Quick actions panel — user-initiated, mid priority.
            return .shelf
        case .settings:
            return .settings
        }
    }

    var isTemporary: Bool {
        switch self {
        case .calendar, .systemStatus, .notification:
            return true  // These disappear after timeout
        case .collapsed, .musicPlayer, .shelf, .pomodoro, .clipboardHistory, .actions, .settings:
            return false
        }
    }

    var autoHideDelay: TimeInterval? {
        switch self {
        case .calendar:
            return 5.0  // Longer display for events
        case .systemStatus:
            return 3.0  // Brief status display
        case .notification:
            return 4.0  // Read-and-glance window for incoming notifications
        case .clipboardHistory:
            return 8.0  // Stay visible long enough to make a selection
        case .actions:
            return 6.0  // Quick action panel: long enough to react, short enough to dismiss
        case .collapsed, .musicPlayer, .shelf, .pomodoro, .settings:
            return nil  // No auto-hide
        }
    }
}

// MARK: - Supporting Models

// CalendarEvent is defined in CalendarModels.swift - using that definition

struct ShelfOperation: Equatable {
    let type: ShelfOperationType
    let fileName: String?
    let progress: Double?
    let isActive: Bool
    
    enum ShelfOperationType: Equatable {
        case dragHover
        case fileTransfer
        case airdropReceiving
    }
}

// BatteryInfo is defined in BatteryServiceProtocol.swift

struct BluetoothInfo: Equatable {
    let connectedDevices: [String]
    let isEnabled: Bool
    let activeConnections: Int
}

// MARK: - Content Request System

struct NotchContentRequest: Equatable {
    let id: UUID = UUID()
    let content: NotchContent
    let priority: NotchContentPriority
    let timestamp: Date
    let duration: TimeInterval?
    let source: ContentSource
    
    init(content: NotchContent, source: ContentSource = .service, duration: TimeInterval? = nil) {
        self.content = content
        self.priority = content.priority
        self.timestamp = Date()
        self.duration = duration
        self.source = source
    }
    
    static func == (lhs: NotchContentRequest, rhs: NotchContentRequest) -> Bool {
        lhs.id == rhs.id
    }
}

enum ContentSource: CaseIterable {
    case user
    case service
    case system
}