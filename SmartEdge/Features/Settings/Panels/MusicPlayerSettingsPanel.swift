import SwiftUI

struct MusicPlayerSettingsPanel: View {
    @EnvironmentObject var settings: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPanelHeader(
                    icon: "music.note",
                    title: "Music Player",
                    subtitle: "Configure how Apple Music and Spotify appear in the notch"
                )

                integrationSection

                permissionSection

                pulseSection

                displaySection
            }
            .padding()
        }
    }

    /// Apple Music / Spotify are read via macOS Automation, which needs a
    /// one-time user grant. Surface it here so the user can trigger the prompt
    /// or jump to System Settings if they dismissed it.
    private var permissionSection: some View {
        SettingsCard("권한") {
            SettingRow(
                title: "음악 앱 제어",
                description: "Apple Music · Spotify의 재생 정보를 노치에 표시하려면 자동화 권한이 필요합니다"
            ) {
                Button("권한 요청") {
                    Task { await ServiceContainer.shared.mediaService.requestMusicAuthorization() }
                }
            }

            SettingsRowDivider()

            SettingRow(
                title: "권한이 보이지 않나요?",
                description: "시스템 설정 → 개인정보 보호 및 보안 → 자동화에서 직접 켤 수 있습니다"
            ) {
                Button("시스템 설정 열기") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private var integrationSection: some View {
        SettingsCard("Integration") {
            SettingRow(
                toggle: "Show music player in notch",
                description: "Display the currently playing track and controls in the notch",
                isOn: $settings.showMusicInNotch
            )

            SettingsRowDivider()

            SettingRow(
                toggle: "Enable playback controls",
                description: "Show previous / play-pause / next controls in the notch",
                isOn: $settings.musicControlsEnabled,
                isEnabled: settings.showMusicInNotch
            )
        }
    }

    private var displaySection: some View {
        SettingsCard("Display") {
            SettingRow(
                toggle: "Show album artwork",
                description: "Display album cover art alongside track information",
                isOn: $settings.showAlbumArt,
                isEnabled: settings.showMusicInNotch
            )
        }
    }

    /// Track-change pulse: briefly open the notch on song / play / pause
    /// change. The duration slider is disabled when the toggle is off so it
    /// visually reflects that it has no effect.
    private var pulseSection: some View {
        SettingsCard("Notifications") {
            SettingRow(
                toggle: "Pulse notch on track change",
                description: "Briefly open the notch when the song changes or you press play/pause",
                isOn: $settings.notchPulseOnTrackChange
            )

            SettingsRowDivider()

            SettingRow(
                title: "Pulse duration",
                description: "How long the notch stays open after a change"
            ) {
                HStack(spacing: 10) {
                    Slider(value: $settings.notchPulseDurationSeconds, in: 1.0...10.0, step: 0.5)
                        .frame(width: 130)
                        .disabled(!settings.notchPulseOnTrackChange)
                    Text(String(format: "%.1fs", settings.notchPulseDurationSeconds))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }
}

#Preview {
    MusicPlayerSettingsPanel()
        .environmentObject(SettingsViewModel())
        .frame(width: 600, height: 700)
}
