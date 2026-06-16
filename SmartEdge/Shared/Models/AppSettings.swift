import Foundation

// Note: NotchContent is defined in NotchModels.swift

struct AppSettings: Codable {
    // Notch Settings
    var notchEnabled: Bool = true
    var autoHideDelay: Double = 3.0
    var expandOnHover: Bool = true
    var defaultNotchContentType: String = "music"
    
    // Music Player Settings
    var showAlbumArt: Bool = true
    var showProgressBar: Bool = true
    var enableMusicNotifications: Bool = true

    // Calendar Settings
    var calendarEnabled: Bool = false
    var showUpcomingEvents: Bool = true
    var maxEventsToShow: Int = 3
    
    // Shelf Settings
    var shelfEnabled: Bool = false
    var maxShelfItems: Int = 10
    var autoCleanupShelf: Bool = true
    
    // Appearance Settings
    var useSystemAppearance: Bool = true
    var forceDarkMode: Bool = false
    var accentColor: String = "blue"
    var animationSpeed: Double = 1.0
    
    // Privacy Settings
    var allowTelemetry: Bool = false
    var shareUsageData: Bool = false
    
    // Advanced Settings
    var enableDebugMode: Bool = false
    var logLevel: String = "info"
    
    init() {}
}

// NotchContent conversion will be handled in the view models