import SwiftUI

@MainActor
struct NotificationContentView: View {
    let title: String
    let message: String
    let icon: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon ?? "bell.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notification: \(title). \(message)")
    }
}

#Preview {
    NotificationContentView(
        title: "Team Meeting",
        message: "Starting in 5 minutes",
        icon: "calendar"
    )
    .frame(width: 360, height: 80)
    .background(.ultraThinMaterial)
}
