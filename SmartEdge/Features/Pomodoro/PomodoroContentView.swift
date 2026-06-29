import SwiftUI

@MainActor
struct PomodoroContentView: View {
    @ObservedObject var viewModel: PomodoroViewModel

    var body: some View {
        VStack(spacing: 10) {
            // All three session types, pickable. Tapping one starts it.
            HStack(spacing: 8) {
                sessionCard(phase: .focusing, title: "집중", icon: "brain.head.profile", color: .red)
                sessionCard(phase: .shortBreak, title: "짧은 휴식", icon: "cup.and.saucer.fill", color: .green)
                sessionCard(phase: .longBreak, title: "긴 휴식", icon: "moon.zzz.fill", color: .blue)
            }

            // Controls for the active session appear once one is selected.
            if viewModel.phase != .idle {
                activeControlRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func sessionCard(phase: PomodoroService.Phase, title: String, icon: String, color: Color) -> some View {
        let isActive = viewModel.phase == phase
        return Button {
            viewModel.startSession(phase)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Text(viewModel.durationText(for: phase))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isActive ? color.opacity(0.18) : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isActive ? color.opacity(0.7) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(viewModel.durationText(for: phase)) 시작")
    }

    private var activeControlRow: some View {
        HStack(spacing: 10) {
            Text(viewModel.formattedRemaining)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)

            Spacer(minLength: 4)

            Button {
                viewModel.toggle()
            } label: {
                Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .background(.quaternary, in: Circle())
            .accessibilityLabel(viewModel.isRunning ? "일시정지" : "시작")

            Button {
                viewModel.skip()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .background(.quaternary, in: Circle())
            .accessibilityLabel("다음 단계")
        }
    }
}

#Preview {
    PomodoroContentView(viewModel: PomodoroViewModel(service: PomodoroService()))
        .frame(width: 440, height: 160)
        .background(.black)
}
