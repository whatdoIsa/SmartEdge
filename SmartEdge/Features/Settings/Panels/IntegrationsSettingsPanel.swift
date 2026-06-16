import SwiftUI

/// Settings panel for third-party integrations. Keeps credentials in
/// @AppStorage for now — move to Keychain before shipping a public release.
struct IntegrationsSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel

    private enum SlackTestStatus: Equatable {
        case idle
        case sending
        case success
        case failure(String)
    }

    @State private var slackTestStatus: SlackTestStatus = .idle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                slackSection
            }
            .padding()
        }
        .onChange(of: settings.slackWebhookURL) { _ in
            // Clear any stale "Sent ✓ / Failed: 404" feedback when the user
            // edits the URL — otherwise the success label looks like it
            // applies to the new URL they're typing.
            if slackTestStatus != .idle { slackTestStatus = .idle }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "link")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Integrations")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            Text("Connect external services so the notch can notify them.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Slack

    private var slackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Slack")
                .font(.headline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Incoming Webhook URL")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField(
                    "https://hooks.slack.com/services/…",
                    text: $settings.slackWebhookURL
                )
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

                Text("Create an incoming webhook at api.slack.com → Your Apps → Incoming Webhooks, then paste the URL here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(
                "Send a message when a focus session ends",
                isOn: $settings.slackNotifyOnFocusComplete
            )
            .disabled(settings.slackWebhookURL.isEmpty)

            slackTestRow
        }
    }

    @ViewBuilder
    private var slackTestRow: some View {
        HStack(spacing: 12) {
            Button {
                sendSlackTestMessage()
            } label: {
                if case .sending = slackTestStatus {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Sending…")
                    }
                } else {
                    Text("Send Test Message")
                }
            }
            .disabled(settings.slackWebhookURL.isEmpty || slackTestStatus == .sending)

            switch slackTestStatus {
            case .idle, .sending:
                EmptyView()
            case .success:
                Label("Sent successfully.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    private func sendSlackTestMessage() {
        let url = settings.slackWebhookURL
        guard !url.isEmpty else { return }
        slackTestStatus = .sending
        Task {
            let result = await ServiceContainer.shared.webhookService.postSlackMessage(
                "SmartEdge test message: integrations are wired up correctly.",
                to: url
            )
            switch result {
            case .success:
                slackTestStatus = .success
            case .invalidURL:
                slackTestStatus = .failure("URL must start with https://")
            case .encodingFailed:
                slackTestStatus = .failure("Could not encode the payload.")
            case .httpStatus(let code):
                slackTestStatus = .failure("Slack rejected the request (HTTP \(code)).")
            case .transportError(let message):
                slackTestStatus = .failure("Network error: \(message)")
            }
        }
    }
}

#Preview {
    IntegrationsSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 480)
}
