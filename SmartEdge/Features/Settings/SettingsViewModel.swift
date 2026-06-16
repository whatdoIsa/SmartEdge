import SwiftUI
import Combine

enum SettingsPanel: String, CaseIterable, Identifiable {
    case general = "general"
    case pro = "pro"
    case notchDisplay = "notch"
    case musicPlayer = "music"
    case calendar = "calendar"
    case shelf = "shelf"
    case systemStatus = "status"
    case integrations = "integrations"
    case privacy = "privacy"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .pro: return "SmartEdge Pro"
        case .notchDisplay: return "Notch Display"
        case .musicPlayer: return "Music Player"
        case .calendar: return "Calendar"
        case .shelf: return "Shelf"
        case .systemStatus: return "System Status"
        case .integrations: return "Integrations"
        case .privacy: return "Privacy"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .pro: return "sparkles"
        case .notchDisplay: return "rectangle.and.hand.point.up.left"
        case .musicPlayer: return "music.note"
        case .calendar: return "calendar"
        case .shelf: return "folder"
        case .systemStatus: return "battery.100"
        case .integrations: return "link"
        case .privacy: return "hand.raised"
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    
    // MARK: - General Settings
    @AppStorage(SettingsKeys.launchAtLogin) var launchAtLogin = false
    @AppStorage(SettingsKeys.autoHideOnLostFocus) var autoHideOnLostFocus = true
    @AppStorage(SettingsKeys.checkUpdatesAutomatically) var checkUpdatesAutomatically = true
    @AppStorage(SettingsKeys.betaUpdates) var betaUpdates = false

    // MARK: - Notch Display Settings
    @AppStorage(SettingsKeys.notchContentPriority) var notchContentPriority = NotchPriorityPreset.music.rawValue
    @AppStorage(SettingsKeys.hoverBehavior) var hoverBehavior = HoverBehavior.expand.rawValue
    @AppStorage(SettingsKeys.animationSpeed) var animationSpeed: Double = 0.35
    @AppStorage(SettingsKeys.showNotchWhenInactive) var showNotchWhenInactive = true
    @AppStorage(SettingsKeys.cornerRadius) var cornerRadius: Double = 12
    /// When ON, the notch briefly auto-opens whenever the current track,
    /// play state, or first launch metadata changes so the user gets a
    /// glance without hovering. OFF means the notch only opens on hover.
    @AppStorage(SettingsKeys.notchPulseOnTrackChange) var notchPulseOnTrackChange = true
    /// Seconds the pulse stays visible before auto-collapsing. Clamped at
    /// the read site so a hand-edited UserDefaults value can't strand
    /// the notch open.
    @AppStorage(SettingsKeys.notchPulseDurationSeconds) var notchPulseDurationSeconds: Double = 4.0
    /// Kept for backward compatibility — migrated to `notchDisplayPolicy`
    /// on first launch of a build that knows about the new key. New code
    /// should never read this; bind UI to `notchDisplayPolicy` instead.
    @AppStorage(SettingsKeys.showOnNonNotchDisplays) var showOnNonNotchDisplays = true
    @AppStorage(SettingsKeys.notchDisplayPolicy) var notchDisplayPolicyRaw = NotchDisplayPolicy.allDisplays.rawValue

    // MARK: - Music Player Settings
    @AppStorage(SettingsKeys.showAlbumArt) var showAlbumArt = true
    @AppStorage(SettingsKeys.enableVisualizer) var enableVisualizer = true
    @AppStorage(SettingsKeys.visualizerStyle) var visualizerStyle = VisualizerStyle.bars.rawValue
    @AppStorage(SettingsKeys.musicControlsEnabled) var musicControlsEnabled = true
    @AppStorage(SettingsKeys.showMusicInNotch) var showMusicInNotch = true

    // MARK: - Calendar Settings
    @AppStorage(SettingsKeys.showUpcomingEvents) var showUpcomingEvents = true
    @AppStorage(SettingsKeys.eventLookAhead) var eventLookAhead: Double = 24
    @AppStorage(SettingsKeys.showAllDayEvents) var showAllDayEvents = true
    @AppStorage(SettingsKeys.calendarRefreshInterval) var calendarRefreshInterval: Double = 300

    // MARK: - Shelf Settings
    @AppStorage(SettingsKeys.shelfStorageLimit) var shelfStorageLimit: Double = 100
    @AppStorage(SettingsKeys.enableAirDropIntegration) var enableAirDropIntegration = true
    @AppStorage(SettingsKeys.autoDeleteOldFiles) var autoDeleteOldFiles = false
    @AppStorage(SettingsKeys.shelfRetentionDays) var shelfRetentionDays: Double = 30

    // MARK: - System Status Settings
    @AppStorage(SettingsKeys.showBatteryStatus) var showBatteryStatus = true
    @AppStorage(SettingsKeys.batteryLowThreshold) var batteryLowThreshold: Double = 20
    @AppStorage(SettingsKeys.showBluetoothStatus) var showBluetoothStatus = true
    @AppStorage(SettingsKeys.showWiFiStatus) var showWiFiStatus = false

    // MARK: - Privacy Settings
    @AppStorage(SettingsKeys.enableAnalytics) var enableAnalytics = false
    @AppStorage(SettingsKeys.enableCrashReporting) var enableCrashReporting = true
    @AppStorage(SettingsKeys.shareUsageData) var shareUsageData = false

    // MARK: - Integrations Settings
    @AppStorage(SettingsKeys.slackWebhookURL) var slackWebhookURL: String = ""
    @AppStorage(SettingsKeys.slackNotifyOnFocusComplete) var slackNotifyOnFocusComplete: Bool = false

    private var cancellables = Set<AnyCancellable>()
    
    init() {
        migrateLegacyDisplayPolicyIfNeeded()
        setupObservers()
    }

    /// Computed wrapper around the raw-string @AppStorage. SwiftUI views
    /// bind to this; reads/writes go through here so the enum stays the
    /// single source of truth for valid values.
    var notchDisplayPolicy: NotchDisplayPolicy {
        get { NotchDisplayPolicy(rawValue: notchDisplayPolicyRaw) ?? .allDisplays }
        set { notchDisplayPolicyRaw = newValue.rawValue }
    }

    /// One-time migration from the legacy `showOnNonNotchDisplays` Bool to
    /// the new `notchDisplayPolicy` enum. Idempotent: only writes the new
    /// key if it's missing, so subsequent launches no-op even if the old
    /// key still has a value.
    private func migrateLegacyDisplayPolicyIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: SettingsKeys.notchDisplayPolicy) == nil else { return }
        // Only honor the legacy bool if the user actually wrote to it.
        // Otherwise (fresh install) fall through to the enum default.
        guard defaults.object(forKey: SettingsKeys.showOnNonNotchDisplays) != nil else { return }

        let legacyValue = defaults.bool(forKey: SettingsKeys.showOnNonNotchDisplays)
        let migrated: NotchDisplayPolicy = legacyValue ? .allDisplays : .notchOnly
        defaults.set(migrated.rawValue, forKey: SettingsKeys.notchDisplayPolicy)
    }
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in
                self?.updateAccessibilitySettings()
            }
            .store(in: &cancellables)
    }
    
    private func updateAccessibilitySettings() {
        let workspace = NSWorkspace.shared
        if workspace.accessibilityDisplayShouldReduceMotion {
            UserDefaults.standard.set(true, forKey: SettingsKeys.reduceMotion)
        }
        if workspace.accessibilityDisplayShouldIncreaseContrast {
            UserDefaults.standard.set(true, forKey: SettingsKeys.enableHighContrast)
        }
    }

    func resetToDefaults() {
        let defaults = UserDefaults.standard
        for key in SettingsKeys.allUserSettings {
            defaults.removeObject(forKey: key)
        }
        objectWillChange.send()
    }
    
    func exportSettings() -> Data? {
        let settings: [String: Any] = [
            "version": "1.0",
            "general": [
                "launchAtLogin": launchAtLogin,
                "autoHideOnLostFocus": autoHideOnLostFocus,
                "checkUpdatesAutomatically": checkUpdatesAutomatically,
                "betaUpdates": betaUpdates
            ],
            "notchDisplay": [
                "contentPriority": notchContentPriority,
                "hoverBehavior": hoverBehavior,
                "animationSpeed": animationSpeed,
                "showWhenInactive": showNotchWhenInactive,
                "cornerRadius": cornerRadius
            ],
            "musicPlayer": [
                "showAlbumArt": showAlbumArt,
                "enableVisualizer": enableVisualizer,
                "visualizerStyle": visualizerStyle,
                "controlsEnabled": musicControlsEnabled,
                "showInNotch": showMusicInNotch
            ]
        ]
        
        return try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
    }
    
    func importSettings(from data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        
        if let general = json["general"] as? [String: Any] {
            launchAtLogin = general["launchAtLogin"] as? Bool ?? launchAtLogin
            autoHideOnLostFocus = general["autoHideOnLostFocus"] as? Bool ?? autoHideOnLostFocus
            checkUpdatesAutomatically = general["checkUpdatesAutomatically"] as? Bool ?? checkUpdatesAutomatically
            betaUpdates = general["betaUpdates"] as? Bool ?? betaUpdates
        }
        
        if let notchDisplay = json["notchDisplay"] as? [String: Any] {
            notchContentPriority = notchDisplay["contentPriority"] as? String ?? notchContentPriority
            hoverBehavior = notchDisplay["hoverBehavior"] as? String ?? hoverBehavior
            animationSpeed = notchDisplay["animationSpeed"] as? Double ?? animationSpeed
            showNotchWhenInactive = notchDisplay["showWhenInactive"] as? Bool ?? showNotchWhenInactive
            cornerRadius = notchDisplay["cornerRadius"] as? Double ?? cornerRadius
        }
        
        if let musicPlayer = json["musicPlayer"] as? [String: Any] {
            showAlbumArt = musicPlayer["showAlbumArt"] as? Bool ?? showAlbumArt
            enableVisualizer = musicPlayer["enableVisualizer"] as? Bool ?? enableVisualizer
            visualizerStyle = musicPlayer["visualizerStyle"] as? String ?? visualizerStyle
            musicControlsEnabled = musicPlayer["controlsEnabled"] as? Bool ?? musicControlsEnabled
            showMusicInNotch = musicPlayer["showInNotch"] as? Bool ?? showMusicInNotch
        }
        
        objectWillChange.send()
        return true
    }
}

// MARK: - Supporting Enums


enum HoverBehavior: String, CaseIterable {
    case expand = "expand"
    case showControls = "controls"
    case none = "none"
    
    var title: String {
        switch self {
        case .expand: return "Expand Content"
        case .showControls: return "Show Controls"
        case .none: return "No Action"
        }
    }
}

enum VisualizerStyle: String, CaseIterable {
    case bars = "bars"
    case wave = "wave"
    case circular = "circular"
    case minimal = "minimal"
    
    var title: String {
        switch self {
        case .bars: return "Bars"
        case .wave: return "Wave"
        case .circular: return "Circular"
        case .minimal: return "Minimal"
        }
    }
}


enum MultiMonitorBehavior: String, CaseIterable {
    case primary = "primary"
    case all = "all"
    case cursor = "cursor"
    
    var title: String {
        switch self {
        case .primary: return "Primary Monitor Only"
        case .all: return "All Monitors"
        case .cursor: return "Follow Cursor"
        }
    }
}