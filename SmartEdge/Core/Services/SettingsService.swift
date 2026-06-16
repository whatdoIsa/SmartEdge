import Foundation
import Combine
import os

@MainActor
final class SettingsService: SettingsServiceProtocol {
    private let settingsSubject = CurrentValueSubject<AppSettings, Never>(AppSettings())
    private let userDefaults = UserDefaults.standard
    
    var settingsPublisher: AnyPublisher<AppSettings, Never> {
        settingsSubject.eraseToAnyPublisher()
    }
    
    func initialize() async throws {
        await loadSettings()
    }
    
    func getCurrentSettings() async -> AppSettings {
        return settingsSubject.value
    }
    
    func updateSetting<T>(_ keyPath: WritableKeyPath<AppSettings, T>, value: T) async {
        var currentSettings = settingsSubject.value
        currentSettings[keyPath: keyPath] = value
        settingsSubject.send(currentSettings)
        await saveSettings(currentSettings)
    }
    
    func resetToDefaults() async {
        let defaultSettings = AppSettings()
        settingsSubject.send(defaultSettings)
        await saveSettings(defaultSettings)
    }
    
    func exportSettings() async throws -> Data {
        let settings = settingsSubject.value
        return try JSONEncoder().encode(settings)
    }
    
    func importSettings(_ data: Data) async throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        settingsSubject.send(settings)
        await saveSettings(settings)
    }
    
    private func loadSettings() async {
        let loaded: AppSettings
        if let data = userDefaults.data(forKey: "app_settings"),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            loaded = decoded
        } else {
            loaded = AppSettings()
        }
        settingsSubject.send(loaded)
    }
    
    private func saveSettings(_ settings: AppSettings) async {
        do {
            let data = try JSONEncoder().encode(settings)
            userDefaults.set(data, forKey: "app_settings")
        } catch {
            AppLogger.settings.error("Failed to encode settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}