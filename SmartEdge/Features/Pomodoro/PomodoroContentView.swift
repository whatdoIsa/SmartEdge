import SwiftUI

@MainActor
struct PomodoroContentView: View {
    @ObservedObject var viewModel: PomodoroViewModel

    /// The prominent session: the active one if a session is running, else
    /// focus as the default-to-start.
    private var bigPhase: PomodoroService.Phase {
        viewModel.phase == .idle ? .focusing : viewModel.phase
    }

    private var smallPhases: [PomodoroService.Phase] {
        [.focusing, .shortBreak, .longBreak].filter { $0 != bigPhase }
    }

    var body: some View {
        HStack(spacing: 10) {
            bigCard
            VStack(spacing: 8) {
                smallCard(smallPhases[0])
                smallCard(smallPhases[1])
            }
            .frame(width: 134)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Big (active) card

    private var bigCard: some View {
        let phase = bigPhase
        let isActive = viewModel.phase == phase && viewModel.phase != .idle
        let isRunning = isActive && viewModel.isRunning
        return Button {
            if isActive { viewModel.toggle() } else { viewModel.startSession(phase) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: icon(phase))
                        .font(.system(size: 16, weight: .medium))
                    Text(title(phase))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 4)
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white)

                Spacer(minLength: 2)

                Text(isActive ? viewModel.formattedRemaining : viewModel.durationText(for: phase))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.3)).frame(height: 4)
                        Capsule().fill(.white)
                            .frame(width: geo.size.width * (isActive ? viewModel.progress : 0), height: 4)
                            .animation(.linear(duration: 1.0), value: viewModel.progress)
                    }
                }
                .frame(height: 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(color(phase), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title(phase)) \(isActive ? viewModel.formattedRemaining : viewModel.durationText(for: phase)), \(isRunning ? "일시정지" : "시작")")
    }

    // MARK: - Small (switch) cards

    private func smallCard(_ phase: PomodoroService.Phase) -> some View {
        Button {
            viewModel.startSession(phase)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: icon(phase))
                        .font(.system(size: 13))
                        .foregroundStyle(color(phase))
                    Text(title(phase))
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
                Text(viewModel.durationText(for: phase))
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(color(phase).opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title(phase)) \(viewModel.durationText(for: phase)) 시작")
    }

    // MARK: - Phase metadata

    private func title(_ phase: PomodoroService.Phase) -> String {
        switch phase {
        case .idle, .focusing: return "집중"
        case .shortBreak: return "짧은 휴식"
        case .longBreak: return "긴 휴식"
        }
    }

    private func icon(_ phase: PomodoroService.Phase) -> String {
        switch phase {
        case .idle, .focusing: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak: return "moon.zzz.fill"
        }
    }

    private func color(_ phase: PomodoroService.Phase) -> Color {
        switch phase {
        case .idle, .focusing: return Color(red: 1.0, green: 0.27, blue: 0.35)
        case .shortBreak: return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .longBreak: return Color(red: 0.04, green: 0.52, blue: 1.0)
        }
    }
}

#Preview {
    PomodoroContentView(viewModel: PomodoroViewModel(service: PomodoroService()))
        .frame(width: 440, height: 160)
        .background(.black)
}
