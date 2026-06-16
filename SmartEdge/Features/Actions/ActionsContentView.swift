import SwiftUI

/// "Quick actions" panel shown inside the notch. Three side-by-side cards that
/// surface the most commonly used controls without making the user pick a
/// dedicated content type first.
@MainActor
struct ActionsContentView: View {
    @ObservedObject var pomodoro: PomodoroViewModel
    @ObservedObject var clipboard: ClipboardViewModel
    var onOpenClipboard: () -> Void
    var onOpenPomodoro: () -> Void
    var onOpenMusic: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            mediaCard
            pomodoroCard
            clipboardCard
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick actions")
    }

    // MARK: - Cards

    private var mediaCard: some View {
        ActionCard(
            icon: "music.note",
            tint: .pink,
            title: "Music",
            subtitle: "Open player",
            action: onOpenMusic
        )
    }

    private var pomodoroCard: some View {
        ActionCard(
            icon: pomodoro.isRunning ? "pause.fill" : "play.fill",
            tint: pomodoro.themeAccent ?? .blue,
            title: pomodoro.isRunning ? pomodoro.phaseTitle : "Focus",
            subtitle: pomodoro.isRunning ? pomodoro.formattedRemaining : "Start timer",
            action: {
                pomodoro.toggle()
                onOpenPomodoro()
            }
        )
    }

    private var clipboardCard: some View {
        ActionCard(
            icon: "doc.on.clipboard",
            tint: .indigo,
            title: "Clipboard",
            subtitle: clipboardSubtitle,
            action: onOpenClipboard
        )
    }

    private var clipboardSubtitle: String {
        guard let last = clipboard.history.first else { return "Empty" }
        switch last.content {
        case .text(let text):
            let cleaned = text.replacingOccurrences(of: "\n", with: " ")
            return cleaned.count > 18 ? String(cleaned.prefix(15)) + "…" : cleaned
        case .url(let url):
            return url.host ?? url.absoluteString
        case .file(let url):
            return url.lastPathComponent
        case .fileURLs(let urls):
            return "\(urls.count) files"
        case .image:
            return "Image"
        case .unknown:
            return "Open"
        }
    }
}

// MARK: - Action card

private struct ActionCard: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(subtitle)")
    }
}

#Preview {
    ActionsContentView(
        pomodoro: PomodoroViewModel(service: PomodoroService()),
        clipboard: ClipboardViewModel(service: ClipboardMonitorService()),
        onOpenClipboard: {},
        onOpenPomodoro: {},
        onOpenMusic: {}
    )
    .frame(width: 380, height: 90)
    .background(.ultraThinMaterial)
}
