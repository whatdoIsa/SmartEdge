import SwiftUI

// Shared building blocks so every settings panel reads as one design system:
// a consistent title header, grouped "cards", and uniform rows with an
// optional description. Replaces the per-panel ad-hoc pattern of
// `Text(.headline)` + bare `Toggle` + a `.padding(.leading, 8)` caption,
// which drifted visually from panel to panel.

/// Panel title block: a tinted icon chip, the panel name, and a one-line
/// subtitle. One per panel, at the top.
struct SettingsPanelHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.system(size: 24, weight: .bold))
            }

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

/// A titled group of rows rendered as a single card surface. Pass rows as the
/// content, separating them with `SettingsRowDivider()`.
struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }

            VStack(spacing: 0) {
                content
            }
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 0.5))
        }
    }
}

/// A single row inside a `SettingsCard`: title (+ optional description) on the
/// left, a trailing control. Use `SettingsRowDivider()` between rows.
struct SettingRow<Trailing: View>: View {
    let title: String
    var description: String?
    @ViewBuilder let trailing: Trailing

    init(
        title: String,
        description: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.description = description
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                if let description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// Convenience for the most common row: a label + description with a trailing
/// switch. Keeps call sites from repeating `Toggle("", isOn:).labelsHidden()`.
extension SettingRow where Trailing == AnyView {
    init(toggle title: String, description: String? = nil, isOn: Binding<Bool>, isEnabled: Bool = true) {
        self.init(title: title, description: description) {
            AnyView(
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!isEnabled)
            )
        }
    }
}

/// Inset divider between rows in a `SettingsCard`.
struct SettingsRowDivider: View {
    var body: some View {
        Divider().padding(.leading, 14)
    }
}
