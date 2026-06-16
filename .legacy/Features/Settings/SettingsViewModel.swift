import SwiftUI
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var isLaunchAtLoginEnabled: Bool = false
    @Published var autoHideDelay: Double = 3.0
    @Published var enableHUDInterception: Bool = true
    @Published var enableMusicPlayer: Bool = true
    @Published var enableShelf: Bool = true
    @Published var enableCalendar: Bool = true
    @Published var notchBehavior: NotchBehavior = .hover
    @Published var theme: AppTheme = .system
    @Published var musicPlayerPosition: PlayerPosition = .center
    @Published var hudOpacity: Double = 0.9
    @Published var animationSpeed: AnimationSpeed = .normal
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let userDefaults = UserDefaults.standard
    
    // MARK: - Types
    
    enum NotchBehavior: String, CaseIterable {
        case hover = "hover"
        case click = "click"
        case automatic = "automatic"
        
        var displayName: String {
            switch self {
            case .hover: return "Hover to Expand"
            case .click: return "Click to Expand"
            case .automatic: return "Automatic"
            }
        }
    }
    
    enum AppTheme: String, CaseIterable {
        case system = "system"
        case light = "light"
        case dark = "dark"
        
        var displayName: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }
    
    enum PlayerPosition: String, CaseIterable {
        case left = "left"
        case center = "center"
        case right = "right"
        
        var displayName: String {
            switch self {
            case .left: return "Left"
            case .center: return "Center"
            case .right: return "Right"
            }
        }
    }
    
    enum AnimationSpeed: String, CaseIterable {
        case slow = "slow"
        case normal = "normal"
        case fast = "fast"
        
        var displayName: String {
            switch self {
            case .slow: return "Slow"
            case .normal: return "Normal"
            case .fast: return "Fast"
            }
        }
        
        var duration: Double {
            switch self {
            case .slow: return 0.6
            case .normal: return 0.35
            case .fast: return 0.2
            }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        loadSettings()
        setupObservers()
    }
    
    // MARK: - Public Methods
    
    func resetToDefaults() {
        isLaunchAtLoginEnabled = false
        autoHideDelay = 3.0
        enableHUDInterception = true
        enableMusicPlayer = true
        enableShelf = true
        enableCalendar = true
        notchBehavior = .hover
        theme = .system
        musicPlayerPosition = .center
        hudOpacity = 0.9
        animationSpeed = .normal
        
        saveSettings()
    }
    
    func toggleLaunchAtLogin() {
        Task {
            await updateLaunchAtLoginStatus(!isLaunchAtLoginEnabled)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadSettings() {
        isLaunchAtLoginEnabled = userDefaults.bool(forKey: "launchAtLogin")
        autoHideDelay = userDefaults.double(forKey: "autoHideDelay")
        enableHUDInterception = userDefaults.bool(forKey: "enableHUDInterception")
        enableMusicPlayer = userDefaults.bool(forKey: "enableMusicPlayer")
        enableShelf = userDefaults.bool(forKey: "enableShelf")
        enableCalendar = userDefaults.bool(forKey: "enableCalendar")
        hudOpacity = userDefaults.double(forKey: "hudOpacity")
        
        if let behaviorString = userDefaults.string(forKey: "notchBehavior"),
           let behavior = NotchBehavior(rawValue: behaviorString) {
            notchBehavior = behavior
        }
        
        if let themeString = userDefaults.string(forKey: "theme"),
           let appTheme = AppTheme(rawValue: themeString) {
            theme = appTheme
        }
        
        if let positionString = userDefaults.string(forKey: "musicPlayerPosition"),
           let position = PlayerPosition(rawValue: positionString) {
            musicPlayerPosition = position
        }
        
        if let speedString = userDefaults.string(forKey: "animationSpeed"),
           let speed = AnimationSpeed(rawValue: speedString) {
            animationSpeed = speed
        }
        
        // Set default values if not found
        if autoHideDelay == 0 { autoHideDelay = 3.0 }
        if hudOpacity == 0 { hudOpacity = 0.9 }
    }
    
    private func setupObservers() {
        // Observe setting changes and save automatically
        Publishers.CombineLatest4(
            $isLaunchAtLoginEnabled,
            $autoHideDelay,
            $enableHUDInterception,
            $enableMusicPlayer
        )
        .dropFirst() // Skip initial values
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveSettings()
            }
        }
        .store(in: &cancellables)
        
        Publishers.CombineLatest4(
            $enableShelf,
            $enableCalendar,
            $notchBehavior,
            $theme
        )
        .dropFirst()
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveSettings()
            }
        }
        .store(in: &cancellables)
        
        Publishers.CombineLatest3(
            $musicPlayerPosition,
            $hudOpacity,
            $animationSpeed
        )
        .dropFirst()
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveSettings()
            }
        }
        .store(in: &cancellables)
    }
    
    private func saveSettings() {
        userDefaults.set(isLaunchAtLoginEnabled, forKey: "launchAtLogin")
        userDefaults.set(autoHideDelay, forKey: "autoHideDelay")
        userDefaults.set(enableHUDInterception, forKey: "enableHUDInterception")
        userDefaults.set(enableMusicPlayer, forKey: "enableMusicPlayer")
        userDefaults.set(enableShelf, forKey: "enableShelf")
        userDefaults.set(enableCalendar, forKey: "enableCalendar")
        userDefaults.set(notchBehavior.rawValue, forKey: "notchBehavior")
        userDefaults.set(theme.rawValue, forKey: "theme")
        userDefaults.set(musicPlayerPosition.rawValue, forKey: "musicPlayerPosition")
        userDefaults.set(hudOpacity, forKey: "hudOpacity")
        userDefaults.set(animationSpeed.rawValue, forKey: "animationSpeed")
    }
    
    private func updateLaunchAtLoginStatus(_ enabled: Bool) async {
        // Implementation would use ServiceManagement framework
        // to add/remove app from login items
        await MainActor.run {
            isLaunchAtLoginEnabled = enabled
            saveSettings()
        }
    }
}