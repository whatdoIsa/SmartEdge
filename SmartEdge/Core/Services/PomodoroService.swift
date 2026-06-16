import Foundation
import Combine

struct PomodoroSession: Identifiable, Codable, Hashable {
    let id: UUID
    let startedAt: Date
    let duration: TimeInterval  // seconds actually focused (counts even if user skipped early)

    init(id: UUID = UUID(), startedAt: Date, duration: TimeInterval) {
        self.id = id
        self.startedAt = startedAt
        self.duration = duration
    }
}

@MainActor
final class PomodoroService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case focusing
        case shortBreak
        case longBreak

        var title: String {
            switch self {
            case .idle: return "Idle"
            case .focusing: return "Focus"
            case .shortBreak: return "Short Break"
            case .longBreak: return "Long Break"
            }
        }

        var duration: TimeInterval {
            switch self {
            case .idle: return 0
            case .focusing: return 25 * 60
            case .shortBreak: return 5 * 60
            case .longBreak: return 15 * 60
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var completedFocusSessions: Int = 0
    @Published private(set) var sessions: [PomodoroSession] = []

    /// Fired after a focus session is recorded to history (≥30s). Used by
    /// the AppCoordinator to send Slack-style webhook notifications.
    var onFocusCompleted: ((PomodoroSession) -> Void)?

    private var timer: Timer?
    private let longBreakInterval = 4

    // Session recording
    private var currentFocusStartedAt: Date?
    private let maxStoredSessions = 500
    private let store: PomodoroSessionStore

    // MARK: - Persistence

    init(store: PomodoroSessionStore = .default) {
        self.store = store
        // One-time migration: pull any sessions that previously lived in
        // UserDefaults under the old "pomodoro.sessions.v1" key into the
        // Application Support file, then clear the key so we don't double-load.
        store.migrateFromUserDefaultsIfNeeded()
        sessions = store.load()
    }

    deinit {
        timer?.invalidate()
    }

    private func saveSessions() {
        // Cap storage to avoid unbounded growth.
        if sessions.count > maxStoredSessions {
            sessions = Array(sessions.suffix(maxStoredSessions))
        }
        store.save(sessions)
    }

    private func recordCompletedFocus() {
        guard let startedAt = currentFocusStartedAt else { return }
        let elapsed = Date().timeIntervalSince(startedAt)
        // Ignore trivial sessions (< 30s) — usually user resets immediately
        guard elapsed >= 30 else {
            currentFocusStartedAt = nil
            return
        }
        let session = PomodoroSession(startedAt: startedAt, duration: elapsed)
        sessions.append(session)
        saveSessions()
        currentFocusStartedAt = nil
        onFocusCompleted?(session)
    }

    /// Flushes any in-progress focus session to history. Called by the
    /// AppCoordinator on app termination so partial work isn't lost when the
    /// user quits while a focus is running but not yet "phase-advanced".
    func flushInProgressSession() {
        recordCompletedFocus()
    }

    var totalDuration: TimeInterval { phase.duration }

    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1 - (remaining / totalDuration)
    }

    func start() {
        if phase == .idle {
            enter(.focusing)
        }
        guard !isRunning else { return }
        isRunning = true
        scheduleTimer()
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        if phase == .focusing {
            recordCompletedFocus()
        }
        phase = .idle
        remaining = 0
        completedFocusSessions = 0
        currentFocusStartedAt = nil
    }

    /// Skips to the next phase without waiting for the timer.
    func skip() {
        timer?.invalidate()
        timer = nil
        advancePhase()
        if isRunning {
            scheduleTimer()
        }
    }

    // MARK: - Private

    private func enter(_ newPhase: Phase) {
        // Record an in-progress focus session before leaving it.
        if phase == .focusing && newPhase != .focusing {
            recordCompletedFocus()
        }
        phase = newPhase
        remaining = newPhase.duration
        if newPhase == .focusing {
            currentFocusStartedAt = Date()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard isRunning else { return }
        remaining = max(0, remaining - 1)
        if remaining <= 0 {
            advancePhase()
        }
    }

    private func advancePhase() {
        switch phase {
        case .idle:
            enter(.focusing)
        case .focusing:
            completedFocusSessions += 1
            let next: Phase = (completedFocusSessions % longBreakInterval == 0) ? .longBreak : .shortBreak
            enter(next)
        case .shortBreak, .longBreak:
            enter(.focusing)
        }
    }
}
