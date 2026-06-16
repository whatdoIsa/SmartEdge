import Foundation

/// File-backed persistence for `PomodoroSession` history. Lives in
/// `~/Library/Application Support/<bundle>/pomodoro-sessions.json` so the JSON
/// doesn't bloat UserDefaults. Writes are atomic (temp file + rename) to avoid
/// corruption on crash, and a corrupt file is renamed `*.corrupt-<timestamp>`
/// instead of being silently discarded.
struct PomodoroSessionStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let legacyKey: String

    static let `default` = PomodoroSessionStore()

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        legacyKey: String = "pomodoro.sessions.v1"
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.legacyKey = legacyKey

        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL(fileManager: fileManager)
        }
    }

    // MARK: - Public API

    /// Reads sessions from disk. Returns an empty array if no file exists.
    /// On decode failure, the broken file is preserved under a
    /// `pomodoro-sessions.json.corrupt-<timestamp>` name and `[]` is returned.
    func load() -> [PomodoroSession] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([PomodoroSession].self, from: data)
        } catch {
            AppLogger.general.error(
                "Pomodoro session file unreadable, backing it up: \(error.localizedDescription, privacy: .public)"
            )
            quarantineCorruptFile()
            return []
        }
    }

    /// Atomically persists the given sessions to disk.
    func save(_ sessions: [PomodoroSession]) {
        ensureDirectoryExists()
        do {
            let data = try JSONEncoder().encode(sessions)
            // .atomic ⇒ Foundation writes to a temp file and renames it in
            // place, which means an interrupted write can't corrupt the
            // existing data.
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            AppLogger.general.error(
                "Failed to persist pomodoro sessions: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Reads any data stored under the legacy UserDefaults key, merges it into
    /// the on-disk file once, then removes the key. Subsequent launches see
    /// no-op behavior.
    func migrateFromUserDefaultsIfNeeded() {
        guard let legacyData = userDefaults.data(forKey: legacyKey) else { return }

        // Decode the legacy blob; if it fails, drop the key anyway so we
        // don't keep retrying a hopelessly broken payload forever.
        let legacySessions: [PomodoroSession]
        do {
            legacySessions = try JSONDecoder().decode([PomodoroSession].self, from: legacyData)
        } catch {
            AppLogger.general.error(
                "Legacy pomodoro sessions in UserDefaults were unreadable, dropping: \(error.localizedDescription, privacy: .public)"
            )
            userDefaults.removeObject(forKey: legacyKey)
            return
        }

        // Merge with whatever is already on disk so we don't lose data if a
        // user installed twice and the file already has fresh content.
        let existing = load()
        let merged = mergeKeepingNewer(existing, legacySessions)
        save(merged)
        userDefaults.removeObject(forKey: legacyKey)
    }

    // MARK: - Private

    private static func defaultFileURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let bundleID = Bundle.main.bundleIdentifier ?? "com.smartedge.app"
        let directory = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        return directory.appendingPathComponent("pomodoro-sessions.json")
    }

    private func ensureDirectoryExists() {
        let directory = fileURL.deletingLastPathComponent()
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            AppLogger.general.error(
                "Could not create pomodoro storage directory: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func quarantineCorruptFile() {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupURL = fileURL.appendingPathExtension("corrupt-\(timestamp)")
        do {
            try fileManager.moveItem(at: fileURL, to: backupURL)
        } catch {
            AppLogger.general.error(
                "Could not quarantine corrupt pomodoro file: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Combines two session arrays, deduplicating by id while keeping the
    /// entry with the latest startedAt when both have the same id.
    private func mergeKeepingNewer(
        _ lhs: [PomodoroSession],
        _ rhs: [PomodoroSession]
    ) -> [PomodoroSession] {
        var byID: [UUID: PomodoroSession] = [:]
        for session in lhs + rhs {
            if let existing = byID[session.id] {
                byID[session.id] = existing.startedAt >= session.startedAt ? existing : session
            } else {
                byID[session.id] = session
            }
        }
        return byID.values.sorted { $0.startedAt < $1.startedAt }
    }
}
