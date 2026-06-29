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

        /// Default fallback only. The live values come from the user-configured
        /// `PomodoroService.duration(for:)`.
        var defaultMinutes: Int {
            switch self {
            case .idle: return 0
            case .focusing: return 25
            case .shortBreak: return 5
            case .longBreak: return 15
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var completedFocusSessions: Int = 0
    @Published private(set) var sessions: [PomodoroSession] = []

    // MARK: - Configurable durations (minutes)
    //
    // User-selectable so a session can be 15/25/50 min etc. Persisted in
    // UserDefaults and clamped to sane bounds. Changing a duration while idle
    // (or paused on that phase) updates the displayed countdown immediately.

    private enum Keys {
        static let focus = "pomodoro.focusMinutes"
        static let shortBreak = "pomodoro.shortBreakMinutes"
        static let longBreak = "pomodoro.longBreakMinutes"
    }

    @Published var focusMinutes: Int = Phase.focusing.defaultMinutes {
        didSet {
            focusMinutes = min(max(focusMinutes, 1), 120)
            UserDefaults.standard.set(focusMinutes, forKey: Keys.focus)
            syncRemainingToPhase()
        }
    }
    @Published var shortBreakMinutes: Int = Phase.shortBreak.defaultMinutes {
        didSet {
            shortBreakMinutes = min(max(shortBreakMinutes, 1), 60)
            UserDefaults.standard.set(shortBreakMinutes, forKey: Keys.shortBreak)
            syncRemainingToPhase()
        }
    }
    @Published var longBreakMinutes: Int = Phase.longBreak.defaultMinutes {
        didSet {
            longBreakMinutes = min(max(longBreakMinutes, 1), 60)
            UserDefaults.standard.set(longBreakMinutes, forKey: Keys.longBreak)
            syncRemainingToPhase()
        }
    }

    /// Live duration (seconds) for a phase, honoring the user's settings.
    func duration(for phase: Phase) -> TimeInterval {
        switch phase {
        case .idle: return 0
        case .focusing: return TimeInterval(focusMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
        }
    }

    /// When not actively counting down, reflect a duration change in the
    /// displayed `remaining` so the UI updates as the user picks a new length.
    private func syncRemainingToPhase() {
        guard !isRunning else { return }
        remaining = duration(for: phase)
    }

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

        let defaults = UserDefaults.standard
        if let f = defaults.object(forKey: Keys.focus) as? Int { focusMinutes = f }
        if let s = defaults.object(forKey: Keys.shortBreak) as? Int { shortBreakMinutes = s }
        if let l = defaults.object(forKey: Keys.longBreak) as? Int { longBreakMinutes = l }
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

    var totalDuration: TimeInterval { duration(for: phase) }

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

    /// Start a specific session type immediately — used when the user picks
    /// one of the focus/short-break/long-break cards in the notch.
    func startSession(_ phase: Phase) {
        enter(phase)
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
        remaining = duration(for: newPhase)
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
