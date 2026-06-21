import SwiftUI

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
            VStack(alignment: .leading, spacing: 20) {
                SettingsPanelHeader(
                    icon: "link",
                    title: "Integrations",
                    subtitle: "Connect external services so the notch can notify them"
                )

                slackSection
            }
            .padding()
        }
        .onChange(of: settings.slackWebhookURL) { _ in
            if slackTestStatus != .idle { slackTestStatus = .idle }
        }
    }

    private var slackSection: some View {
        SettingsCard("Slack") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Incoming Webhook URL")
                    .font(.system(size: 13, weight: .medium))
                TextField(
                    "https://hooks.slack.com/services/…",
                    text: $settings.slackWebhookURL
                )
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

                Text("Create an incoming webhook at api.slack.com → Your Apps → Incoming Webhooks, then paste the URL here.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            SettingsRowDivider()

            SettingRow(
                toggle: "Send a message when a focus session ends",
                isOn: $settings.slackNotifyOnFocusComplete,
                isEnabled: !settings.slackWebhookURL.isEmpty
            )

            SettingsRowDivider()

            SettingRow(
                title: "Test connection",
                description: "Posts a sample message to the webhook URL above"
            ) {
                slackTestControl
            }
        }
    }

    @ViewBuilder
    private var slackTestControl: some View {
        HStack(spacing: 12) {
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
