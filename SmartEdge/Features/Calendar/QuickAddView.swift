import SwiftUI

/// Natural-language quick-add: one field, a live "이렇게 추가돼요" preview, and
/// Return to add / Esc to close. Lives in its own key-able window (the notch
/// overlay can't take keyboard focus).
struct QuickAddView: View {
    @StateObject private var viewModel: QuickAddViewModel
    @FocusState private var isFocused: Bool

    private let accent = NotchTheme.brandCoral

    init(viewModel: QuickAddViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("빠른 일정 추가")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("무엇을 추가할까요?", text: $viewModel.text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isFocused)
                .onSubmit(submit)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(isFocused ? accent : Color.secondary.opacity(0.3),
                                      lineWidth: isFocused ? 1.5 : 1)
                )

            preview

            Button(action: submit) {
                Text(viewModel.isSaving ? "추가 중…" : "추가")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(accent, in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.parsed == nil || viewModel.isSaving)
            .opacity(viewModel.parsed == nil ? 0.5 : 1)

            Text("Return으로 추가 · Esc로 닫기")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(16)
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { isFocused = true }
        // Hidden Esc handler — the shortcut fires even while the field is focused.
        .background(
            Button("", action: { viewModel.dismiss?() })
                .keyboardShortcut(.cancelAction)
                .hidden()
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let parsed = viewModel.parsed {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 3, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(parsed.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "clock").font(.system(size: 11))
                        Text(previewTimeText(parsed))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accent)
            }
            .padding(11)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
        } else {
            Text("자연어로 입력하세요 · 예: \"점심 금요일 12시\"")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 6)
        }
    }

    private func previewTimeText(_ parsed: QuickAddViewModel.Parsed) -> String {
        let end = parsed.start.addingTimeInterval(parsed.duration)
        let dateTime = DateFormatter()
        dateTime.dateStyle = .medium
        dateTime.timeStyle = .short
        let timeOnly = DateFormatter()
        timeOnly.timeStyle = .short
        let range = "\(dateTime.string(from: parsed.start)) – \(timeOnly.string(from: end))"
        return parsed.dateDetected ? range : "지금부터 · \(range)"
    }

    private func submit() {
        guard viewModel.parsed != nil, !viewModel.isSaving else { return }
        Task {
            let saved = await viewModel.save()
            if saved { viewModel.dismiss?() }
        }
    }
}
