import SwiftUI

@MainActor
struct PomodoroContentView: View {
    @ObservedObject var viewModel: PomodoroViewModel

    private var phaseColor: Color {
        switch viewModel.phase {
        case .idle: return .secondary
        case .focusing: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(phaseColor.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(phaseColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0), value: viewModel.progress)
                Image(systemName: viewModel.phase == .focusing ? "brain.head.profile" : "cup.and.saucer.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(phaseColor)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.phaseTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(viewModel.formattedRemaining)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 4)

            controls
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.phaseTitle): \(viewModel.formattedRemaining) remaining")
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.toggle()
            } label: {
                Image(systemName: viewModel.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .background(.quaternary, in: Circle())
            .accessibilityLabel(viewModel.isRunning ? "Pause timer" : "Start timer")

            Button {
                viewModel.skip()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .background(.quaternary, in: Circle())
            .accessibilityLabel("Skip phase")
        }
    }
}

#Preview {
    PomodoroContentView(viewModel: PomodoroViewModel(service: PomodoroService()))
        .frame(width: 360, height: 80)
        .background(.ultraThinMaterial)
}
