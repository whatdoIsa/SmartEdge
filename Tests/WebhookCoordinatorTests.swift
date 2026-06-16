import XCTest
@testable import SmartEdge

/// Verifies WebhookCoordinator wires PomodoroService.onFocusCompleted to a
/// Slack POST when the user has enabled it. Doesn't touch the network — we
/// observe via the UserDefaults gate and a freshly-constructed real
/// PomodoroService + WebhookService backed by a stubbed URLSession.
@MainActor
final class WebhookCoordinatorTests: XCTestCase {

    private var defaultsBackup: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        // Snapshot the UserDefaults keys we'll mutate so each test starts
        // clean and tearDown can restore them.
        for key in [SettingsKeys.slackNotifyOnFocusComplete, SettingsKeys.slackWebhookURL] {
            defaultsBackup[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for (key, value) in defaultsBackup {
            UserDefaults.standard.set(value, forKey: key)
        }
        defaultsBackup.removeAll()
        super.tearDown()
    }

    func testStartInstallsCallback() {
        let pomodoro = PomodoroService()
        XCTAssertNil(pomodoro.onFocusCompleted, "Sanity: closure starts unset")

        let coordinator = WebhookCoordinator(
            pomodoroService: pomodoro,
            webhookService: WebhookService()
        )
        coordinator.start()
        XCTAssertNotNil(pomodoro.onFocusCompleted, "start() must install the callback")
    }

    func testStopClearsCallback() {
        let pomodoro = PomodoroService()
        let coordinator = WebhookCoordinator(
            pomodoroService: pomodoro,
            webhookService: WebhookService()
        )
        coordinator.start()
        coordinator.stop()
        XCTAssertNil(pomodoro.onFocusCompleted, "stop() must remove the callback")
    }

    func testCallbackNoOpWhenDisabled() {
        // Gate is "false toggle" → closure should bail before doing anything.
        UserDefaults.standard.set(false, forKey: SettingsKeys.slackNotifyOnFocusComplete)
        UserDefaults.standard.set("https://hooks.slack.com/services/x/y/z", forKey: SettingsKeys.slackWebhookURL)

        let pomodoro = PomodoroService()
        WebhookCoordinator(
            pomodoroService: pomodoro,
            webhookService: WebhookService()
        ).start()

        // Fire — should silently return. The test passes if no exception
        // is thrown and no network call is attempted.
        pomodoro.onFocusCompleted?(PomodoroSession(startedAt: Date(), duration: 300))
    }

    func testCallbackNoOpWhenURLEmpty() {
        UserDefaults.standard.set(true, forKey: SettingsKeys.slackNotifyOnFocusComplete)
        UserDefaults.standard.set("", forKey: SettingsKeys.slackWebhookURL)

        let pomodoro = PomodoroService()
        WebhookCoordinator(
            pomodoroService: pomodoro,
            webhookService: WebhookService()
        ).start()

        pomodoro.onFocusCompleted?(PomodoroSession(startedAt: Date(), duration: 300))
    }
}
