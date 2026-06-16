import Foundation

/// Lightweight wrapper around URLSession for fire-and-forget POST notifications
/// to incoming webhooks (Slack, Discord-compatible Slack format, etc).
///
/// Two surfaces:
/// - `sendSlackMessage(_:to:)` — fire-and-forget, used by automated triggers
///   like "send when a focus session ends". Failures are logged, never thrown.
/// - `postSlackMessage(_:to:)` — typed result, used when the UI wants to show
///   "Sent ✓" vs "Failed: 404" to the user (e.g. a "Send Test" button).
@MainActor
final class WebhookService {

    enum SendResult: Equatable {
        case success
        case invalidURL
        case encodingFailed
        case httpStatus(Int)
        case transportError(String)
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fire-and-forget variant for automated triggers (pomodoro complete, etc.).
    /// Errors are logged to AppLogger and dropped.
    func sendSlackMessage(_ text: String, to urlString: String) async {
        _ = await postSlackMessage(text, to: urlString)
    }

    /// Returns a typed result for UI use ("Send Test Message" buttons, etc.).
    /// Logs every failure to AppLogger.general so silent debugging still works.
    @discardableResult
    func postSlackMessage(_ text: String, to urlString: String) async -> SendResult {
        guard let url = URL(string: urlString), url.scheme == "https" else {
            AppLogger.general.error(
                "Webhook URL invalid or not https: \(urlString, privacy: .public)"
            )
            return .invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let body = try JSONEncoder().encode(["text": text])
            request.httpBody = body
        } catch {
            AppLogger.general.error(
                "Failed to encode webhook payload: \(error.localizedDescription, privacy: .public)"
            )
            return .encodingFailed
        }

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                // For https URLs URLSession always returns HTTPURLResponse,
                // but bail loudly rather than silently returning .success
                // on the unexpected case.
                AppLogger.general.error("Webhook returned non-HTTP response.")
                return .transportError("Non-HTTP response")
            }
            if (200..<300).contains(http.statusCode) {
                return .success
            }
            AppLogger.general.error(
                "Webhook returned non-2xx status: \(http.statusCode, privacy: .public)"
            )
            return .httpStatus(http.statusCode)
        } catch {
            AppLogger.general.error(
                "Webhook request failed: \(error.localizedDescription, privacy: .public)"
            )
            return .transportError(error.localizedDescription)
        }
    }
}
