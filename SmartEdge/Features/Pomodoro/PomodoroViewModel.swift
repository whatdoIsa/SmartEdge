import Foundation
import Combine
import SwiftUI

/// Surface for pomodoro-related views. Wraps `PomodoroService` so SwiftUI
/// views never reach into the service container directly, making them easy
/// to preview and unit-test with a stub service.
@MainActor
final class PomodoroViewModel: ObservableObject {
    private let service: PomodoroService
    private var cancellables = Set<AnyCancellable>()

    // Mirrors of service state — published so views observe this VM only.
    @Published private(set) var phase: PomodoroService.Phase = .idle
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var completedFocusSessions: Int = 0
    @Published private(set) var sessions: [PomodoroSession] = []

    init(service: PomodoroService) {
        self.service = service
        bind(to: service)
    }

    // MARK: - View-friendly accessors

    var formattedRemaining: String {
        let total = max(0, Int(remaining))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var phaseTitle: String {
        switch phase {
        case .idle: return "Ready"
        case .focusing: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }

    var progress: Double {
        let total = phase.duration
        guard total > 0 else { return 0 }
        return 1.0 - max(0, remaining) / total
    }

    /// Theme color for the notch border during pomodoro. Returns nil when
    /// idle so the notch falls back to its default styling.
    var themeAccent: Color? {
        guard isRunning else { return nil }
        switch phase {
        case .focusing: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        case .idle: return nil
        }
    }

    // MARK: - Actions

    func start() { service.start() }
    func pause() { service.pause() }
    func reset() { service.reset() }
    func skip() { service.skip() }

    func toggle() {
        if isRunning {
            service.pause()
        } else {
            service.start()
        }
    }

    // MARK: - Statistics

    struct DailyBucket: Identifiable {
        let id: Date
        let label: String
        let minutes: Int
        let count: Int
    }

    /// Returns bucketed totals for the last `days` days (inclusive of today).
    func dailyBuckets(days: Int, calendar: Calendar = .current) -> [DailyBucket] {
        let today = calendar.startOfDay(for: Date())
        var buckets: [DailyBucket] = []
        let formatter = DateFormatter()
        formatter.dateFormat = days <= 7 ? "EEE" : "M/d"

        for offset in (0..<days).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let sessionsForDay = sessions.filter { $0.startedAt >= day && $0.startedAt < dayEnd }
            let totalSeconds = sessionsForDay.reduce(0.0) { $0 + $1.duration }
            buckets.append(DailyBucket(
                id: day,
                label: formatter.string(from: day),
                minutes: Int(totalSeconds / 60),
                count: sessionsForDay.count
            ))
        }
        return buckets
    }

    // MARK: - Private

    private func bind(to service: PomodoroService) {
        service.$phase.assign(to: &$phase)
        service.$remaining.assign(to: &$remaining)
        service.$isRunning.assign(to: &$isRunning)
        service.$completedFocusSessions.assign(to: &$completedFocusSessions)
        service.$sessions.assign(to: &$sessions)
    }
}
