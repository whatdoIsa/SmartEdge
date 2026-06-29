import SwiftUI

struct PomodoroSettingsPanel: View {
    // The pomodoro service is a shared singleton, so the panel can observe and
    // mutate its configurable durations directly. Changes persist via the
    // service's UserDefaults-backed setters and apply on the next session.
    @ObservedObject private var pomodoro = ServiceContainer.shared.pomodoroService

    private let focusPresets = [15, 20, 25, 30, 40, 45, 50, 60, 90]
    private let shortBreakPresets = [3, 5, 10, 15]
    private let longBreakPresets = [10, 15, 20, 30]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPanelHeader(
                    icon: "timer",
                    title: "Pomodoro",
                    subtitle: "집중·휴식 시간을 원하는 길이로 설정하세요"
                )

                SettingsCard("세션 길이") {
                    durationRow(
                        title: "집중 시간",
                        description: "한 번 집중하는 시간",
                        selection: $pomodoro.focusMinutes,
                        presets: focusPresets
                    )

                    SettingsRowDivider()

                    durationRow(
                        title: "짧은 휴식",
                        description: "집중 세션 사이의 휴식",
                        selection: $pomodoro.shortBreakMinutes,
                        presets: shortBreakPresets
                    )

                    SettingsRowDivider()

                    durationRow(
                        title: "긴 휴식",
                        description: "집중 4회마다 주어지는 휴식",
                        selection: $pomodoro.longBreakMinutes,
                        presets: longBreakPresets
                    )
                }

                Text("메뉴 막대 아이콘에서 뽀모도로를 시작할 수 있고, 실행 중에는 노치에 타이머가 유지됩니다.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
    }

    private func durationRow(
        title: String,
        description: String,
        selection: Binding<Int>,
        presets: [Int]
    ) -> some View {
        SettingRow(title: title, description: description) {
            Picker("", selection: selection) {
                ForEach(presets, id: \.self) { minutes in
                    Text("\(minutes)분").tag(minutes)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 90)
        }
    }
}

#Preview {
    PomodoroSettingsPanel()
        .frame(width: 600, height: 500)
}
