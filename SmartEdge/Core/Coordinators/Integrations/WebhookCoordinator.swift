import Foundation

/// Wires PomodoroService completion events to outbound webhook integrations.
/// Currently fires a Slack-style POST when a focus session finishes, gated
/// by `slackNotifyOnFocusComplete` + `slackWebhookURL` in UserDefaults.
///
/// Owns the `PomodoroService.onFocusCompleted` callback slot. The slot is a
/// single closure (not a Combine publisher), so only one coordinator may
/// install on it at a time — that's fine today since this is the only
/// consumer. If a second consumer ever appears, swap PomodoroService to a
/// publisher first.
@MainActor
final class WebhookCoordinator {
    private let pomodoroService: PomodoroService
    private let webhookService: WebhookService

    init(pomodoroService: PomodoroService, webhookService: WebhookService) {
        self.pomodoroService = pomodoroService
        self.webhookService = webhookService
    }

    func start() {
        let webhookService = self.webhookService
        pomodoroService.onFocusCompleted = { session in
            // Read settings on each fire so toggling them in Settings takes
            // effect immediately — no restart required.
            let defaults = UserDefaults.standard
            let enabled = defaults.bool(forKey: SettingsKeys.slackNotifyOnFocusComplete)
            let url = defaults.string(forKey: SettingsKeys.slackWebhookURL) ?? ""
            guard enabled, !url.isEmpty else { return }

            let minutes = Int(session.duration / 60)
            let text = "Focus session complete: \(minutes) min of deep work."
            // Detached from the coordinator's lifetime intentionally — the
            // user may quit before the POST completes; we accept best-effort
            // delivery rather than blocking shutdown.
            Task {
                await webhookService.sendSlackMessage(text, to: url)
            }
        }
    }

    /// Clears the closure so a future re-wire (or coordinator swap) doesn't
    /// fire a stale handler. Safe to call multiple times.
    func stop() {
        pomodoroService.onFocusCompleted = nil
    }

    deinit {
        // Can't touch @MainActor state from deinit, but the closure captures
        // only the webhookService (not self), so leaving it installed is
        // memory-safe. AppCoordinator should call stop() on shutdown if
        // immediate teardown matters.
    }
}
