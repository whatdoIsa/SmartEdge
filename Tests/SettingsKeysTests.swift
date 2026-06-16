import XCTest
@testable import SmartEdge

/// SettingsKeys invariants. The production code also has a DEBUG-only
/// `validate()` call from AppCoordinator.init, but having them here as
/// real XCTests means they run in Release too and surface in test reports.
final class SettingsKeysTests: XCTestCase {

    func testAllUserSettingsHasNoDuplicates() {
        let unique = Set(SettingsKeys.allUserSettings)
        XCTAssertEqual(
            unique.count, SettingsKeys.allUserSettings.count,
            "Duplicate raw string in SettingsKeys.allUserSettings — two vars point at the same UserDefaults entry."
        )
    }

    func testAllUserSettingsCountMatchesExpected() {
        // Mirror of the pinned count in SettingsKeys.swift. This catches the
        // "added a key but forgot to append it" mistake, which would cause
        // resetToDefaults to silently leave the new key on disk.
        XCTAssertEqual(SettingsKeys.allUserSettings.count, 40)
    }

    func testNonUserKeysNotInAllUserSettings() {
        // First-launch / accessibility-mirror keys aren't user settings;
        // resetToDefaults must leave them alone so we don't re-prompt for
        // permissions or lose reduce-motion preference.
        XCTAssertFalse(SettingsKeys.allUserSettings.contains(SettingsKeys.hasRequestedSystemPermissions))
        XCTAssertFalse(SettingsKeys.allUserSettings.contains(SettingsKeys.reduceMotion))
        XCTAssertFalse(SettingsKeys.allUserSettings.contains(SettingsKeys.enableHighContrast))
    }

    func testKeyStringsAreStable() {
        // Locking down the raw values so a rename doesn't accidentally
        // orphan every existing user's saved settings. If you intentionally
        // change a key, write a migration and update this test.
        XCTAssertEqual(SettingsKeys.spotifyClientID, "spotifyClientID")
        XCTAssertEqual(SettingsKeys.slackWebhookURL, "slackWebhookURL")
        XCTAssertEqual(SettingsKeys.slackNotifyOnFocusComplete, "slackNotifyOnFocusComplete")
        XCTAssertEqual(SettingsKeys.showOnNonNotchDisplays, "showOnNonNotchDisplays")
        XCTAssertEqual(SettingsKeys.hasRequestedSystemPermissions, "hasRequestedSystemPermissions")
    }
}
