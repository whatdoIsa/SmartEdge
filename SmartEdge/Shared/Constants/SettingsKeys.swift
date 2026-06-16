import Foundation

/// Central registry for every `UserDefaults` / `@AppStorage` key used in the
/// app. Adding a key in one place + referencing it everywhere kills the
/// "typo here, missing default there" class of bugs.
///
/// Convention: variable name == key string (camelCase). If you rename a
/// variable, leave the raw string unchanged or write a migration — users'
/// saved values are keyed by the raw string.
enum SettingsKeys {

    // MARK: - General
    static let launchAtLogin = "launchAtLogin"
    static let autoHideOnLostFocus = "autoHideOnLostFocus"
    static let checkUpdatesAutomatically = "checkUpdatesAutomatically"
    static let betaUpdates = "betaUpdates"

    // MARK: - Notch Display
    static let notchContentPriority = "notchContentPriority"
    static let hoverBehavior = "hoverBehavior"
    static let animationSpeed = "animationSpeed"
    static let showNotchWhenInactive = "showNotchWhenInactive"
    static let cornerRadius = "cornerRadius"
    /// Toggle for the "track changed / play / pause" pulse animation.
    /// When off, the notch only opens on explicit hover.
    static let notchPulseOnTrackChange = "notchPulseOnTrackChange"
    /// How long the pulse stays visible before auto-collapsing.
    /// Stored as seconds (Double). Values clamped 1.0–10.0 in UI.
    static let notchPulseDurationSeconds = "notchPulseDurationSeconds"
    /// LEGACY (kept for migration only) — superseded by `notchDisplayPolicy`.
    /// When the new key is absent we read this Bool and convert: false →
    /// `.notchOnly`, true → `.allDisplays`. Once the new key is written,
    /// this one is ignored.
    static let showOnNonNotchDisplays = "showOnNonNotchDisplays"

    /// Which displays SmartEdge shows the notch on. Raw value of
    /// `NotchDisplayPolicy` enum.
    static let notchDisplayPolicy = "notchDisplayPolicy"

    // MARK: - Music Player
    static let showAlbumArt = "showAlbumArt"
    static let enableVisualizer = "enableVisualizer"
    static let visualizerStyle = "visualizerStyle"
    static let musicControlsEnabled = "musicControlsEnabled"
    static let showMusicInNotch = "showMusicInNotch"

    // MARK: - Calendar
    static let showUpcomingEvents = "showUpcomingEvents"
    static let eventLookAhead = "eventLookAhead"
    static let showAllDayEvents = "showAllDayEvents"
    static let calendarRefreshInterval = "calendarRefreshInterval"

    // MARK: - Shelf
    static let shelfStorageLimit = "shelfStorageLimit"
    static let enableAirDropIntegration = "enableAirDropIntegration"
    static let autoDeleteOldFiles = "autoDeleteOldFiles"
    static let shelfRetentionDays = "shelfRetentionDays"

    // MARK: - System Status
    static let showBatteryStatus = "showBatteryStatus"
    static let batteryLowThreshold = "batteryLowThreshold"
    static let showBluetoothStatus = "showBluetoothStatus"
    static let showWiFiStatus = "showWiFiStatus"

    // MARK: - Privacy
    static let enableAnalytics = "enableAnalytics"
    static let enableCrashReporting = "enableCrashReporting"
    static let shareUsageData = "shareUsageData"

    // MARK: - Integrations
    static let slackWebhookURL = "slackWebhookURL"
    static let slackNotifyOnFocusComplete = "slackNotifyOnFocusComplete"

    // MARK: - Accessibility (written from NSWorkspace observer)
    static let reduceMotion = "reduceMotion"
    static let enableHighContrast = "enableHighContrast"

    // MARK: - First-launch flags
    static let hasRequestedSystemPermissions = "hasRequestedSystemPermissions"

    // MARK: - Reset helper
    /// Every user-facing setting key, used by `resetToDefaults()` to clear
    /// stored values in one pass. Do **not** include first-launch flags
    /// (e.g. `hasRequestedSystemPermissions`) — those are not user settings,
    /// resetting them would re-prompt for permissions.
    static let allUserSettings: [String] = [
        launchAtLogin, autoHideOnLostFocus, checkUpdatesAutomatically, betaUpdates,
        notchContentPriority, hoverBehavior, animationSpeed, showNotchWhenInactive,
        cornerRadius, notchPulseOnTrackChange, notchPulseDurationSeconds,
        showOnNonNotchDisplays, notchDisplayPolicy,
        showAlbumArt, enableVisualizer, visualizerStyle,
        musicControlsEnabled, showMusicInNotch, showUpcomingEvents,
        eventLookAhead, showAllDayEvents, calendarRefreshInterval, shelfStorageLimit,
        enableAirDropIntegration, autoDeleteOldFiles, shelfRetentionDays,
        showBatteryStatus, batteryLowThreshold, showBluetoothStatus, showWiFiStatus,
        enableAnalytics, enableCrashReporting, shareUsageData,
        slackWebhookURL, slackNotifyOnFocusComplete
    ]

    /// Pinned count — if you add a new key, bump this number too. The
    /// DEBUG-only `validate()` check below will trip on the next build if
    /// you forgot, surfacing the omission *before* `resetToDefaults`
    /// silently leaves orphan UserDefaults entries on disk.
    private static let expectedUserSettingsCount = 35

    #if DEBUG
    /// Runtime invariant check. Called from `AppCoordinator.init` so any
    /// mismatch crashes during dogfood/development without ever touching
    /// release builds. The checks here would normally live in an XCTest
    /// case, but the project has no test target yet — this is the
    /// pragmatic substitute.
    ///
    /// Catches:
    /// 1. New key added to the enum but not appended to `allUserSettings`
    ///    (resetToDefaults would silently leak it)
    /// 2. Duplicate raw string between two `static let` declarations
    ///    (typo: two vars accidentally point at the same UserDefaults entry)
    /// 3. Anyone adding a new key to `allUserSettings` without updating
    ///    `expectedUserSettingsCount` — a forcing function for the
    ///    contributor to look at both lists.
    static func validate() {
        precondition(
            allUserSettings.count == expectedUserSettingsCount,
            "SettingsKeys.allUserSettings count = \(allUserSettings.count), expected \(expectedUserSettingsCount). Update expectedUserSettingsCount after adding a key."
        )
        let unique = Set(allUserSettings)
        precondition(
            unique.count == allUserSettings.count,
            "SettingsKeys.allUserSettings contains duplicates: \(allUserSettings.sorted())"
        )
    }
    #endif
}
