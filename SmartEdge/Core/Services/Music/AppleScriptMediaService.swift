import Foundation
import AppKit
import Combine

/// Now-Playing service backed by AppleScript control of Apple Music and
/// Spotify desktop apps. This is the App-Store-compatible replacement for
/// the old perl-based adapter (MediaRemote private framework),
/// which the sandbox + App Review prohibit.
///
/// Trade-offs vs the old approach (documented for honesty):
/// - Coverage: Apple Music + Spotify only. Browser/YouTube and system-wide
///   Now Playing are gone — there's no sandbox-legal way to read them.
/// - Latency: polling (~1.5s) instead of push. A track change can take up
///   to one poll interval to surface. Acceptable for a glanceable notch.
/// - Permission: requires the user's one-time Automation grant per target
///   app (macOS prompts on first script send).
///
/// Public surface (`MediaServiceProtocol`) is unchanged so NotchViewModel /
/// MusicPlayerViewModel don't know which backend fills `currentTrack`.
@MainActor
final class AppleScriptMediaService: ObservableObject, MediaServiceProtocol {

    // MARK: - MediaServiceProtocol

    weak var delegate: MediaServiceDelegate?
    var currentNowPlaying: NowPlayingInfo? { currentTrack }
    var currentPlaybackState: MediaPlaybackState { isPlaying ? .playing : .paused }
    var isAvailable: Bool { true }

    @Published private var currentTrack: NowPlayingInfo?
    @Published private var isPlaying: Bool = false
    @Published private var authorization: MediaAuthorizationStatus = .unknown

    var authorizationStatus: MediaAuthorizationStatus { authorization }

    var isPlayingPublisher: AnyPublisher<Bool, Never> { $isPlaying.eraseToAnyPublisher() }
    var currentTrackPublisher: AnyPublisher<NowPlayingInfo?, Never> { $currentTrack.eraseToAnyPublisher() }
    var authorizationStatusPublisher: AnyPublisher<MediaAuthorizationStatus, Never> {
        $authorization.removeDuplicates().eraseToAnyPublisher()
    }

    // MARK: - Private

    /// Which app currently owns playback. Controls (play/pause/next) are
    /// routed to this app. Recomputed each poll: a *playing* app wins; if
    /// none is playing, the most recently seen paused app holds focus so
    /// the controls still work on whatever the user last touched.
    private enum Source { case appleMusic, spotify }
    private var activeSource: Source?

    private let runner = AppleScriptRunner()
    private var pollTimer: Timer?
    /// Bundle IDs we've confirmed Automation permission for.
    private var automationGranted: Set<String> = []
    /// We auto-show the system prompt at most once per session (for
    /// discoverability on first run); after that the user re-triggers it
    /// from the in-app "grant access" button so we never nag in the
    /// background.
    private var didAutoPrompt = false
    /// (title|artist|album) of the track we last fetched artwork for, so we
    /// don't re-download / re-read the image on every 1.5s poll.
    private var lastArtworkKey: String?

    private let appleMusicBundleID = "com.apple.Music"
    private let spotifyBundleID = "com.spotify.client"
    private let pollInterval: TimeInterval = 1.5

    // RS (ASCII 30) — never appears in track metadata, so it's a safe field
    // delimiter for the AppleScript return strings.
    private let fieldSeparator = "\u{1e}"

    // MARK: - Lifecycle

    init() {}

    deinit { pollTimer?.invalidate() }

    func initialize() async throws { startPolling() }
    func startMonitoring() async throws { startPolling() }
    func stopMonitoring() async {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.poll() }
        }
        // Kick an immediate poll so the notch fills in without waiting a
        // full interval after launch.
        Task { @MainActor [weak self] in await self?.poll() }
    }

    // MARK: - Polling

    private func poll() async {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        let musicRunning = running.contains(appleMusicBundleID)
        let spotifyRunning = running.contains(spotifyBundleID)

        guard musicRunning || spotifyRunning else {
            authorization = .noPlayerRunning
            activeSource = nil
            apply(nil)
            return
        }

        // Non-blocking status check — never shows UI, so the poll can't stall.
        await refreshAuthorization(musicRunning: musicRunning, spotifyRunning: spotifyRunning)

        if authorization != .authorized {
            // First run with a player open: surface the system prompt once so
            // the permission is discoverable without the user hunting for it.
            // After that, the in-app "grant access" button is the path.
            if authorization == .needsPermission && !didAutoPrompt {
                await promptForRunningPlayers(activate: false)
                return
            }
            activeSource = nil
            apply(nil)
            return
        }

        // Query only apps that are running AND authorized. Querying a
        // non-running app would launch it (never do that).
        let musicAllowed = musicRunning && automationGranted.contains(appleMusicBundleID)
        let spotifyAllowed = spotifyRunning && automationGranted.contains(spotifyBundleID)
        async let music = musicAllowed ? queryAppleMusic() : nil
        async let spotify = spotifyAllowed ? querySpotify() : nil
        let musicSnap = await music
        let spotifySnap = await spotify

        // Pick the active source: a playing app beats a paused one. If both
        // play (rare), Apple Music wins by convention.
        let chosen = pickActive(music: musicSnap, spotify: spotifySnap)

        guard let (source, snap) = chosen else {
            activeSource = nil
            apply(nil)
            return
        }
        activeSource = source
        await applySnapshot(snap, source: source)
    }

    /// Read (without prompting) the Automation status for each running player
    /// and fold it into `authorization` + `automationGranted`. Polling uses
    /// this so background ticks never block on or trigger a system prompt;
    /// toggling the System Settings switch is picked up here too.
    private func refreshAuthorization(musicRunning: Bool, spotifyRunning: Bool) async {
        var anyAuthorized = false

        if musicRunning {
            let p = await runner.automationPermission(bundleID: appleMusicBundleID, prompt: false)
            if p == .granted { automationGranted.insert(appleMusicBundleID); anyAuthorized = true }
            else { automationGranted.remove(appleMusicBundleID) }
        }
        if spotifyRunning {
            let p = await runner.automationPermission(bundleID: spotifyBundleID, prompt: false)
            if p == .granted { automationGranted.insert(spotifyBundleID); anyAuthorized = true }
            else { automationGranted.remove(spotifyBundleID) }
        }

        authorization = anyAuthorized ? .authorized : .needsPermission
    }

    /// Show the system Automation prompt for every running supported player.
    /// Marks `didAutoPrompt` so the background poll won't auto-show it again,
    /// then re-polls to reflect the user's choice immediately.
    private func promptForRunningPlayers(activate: Bool) async {
        didAutoPrompt = true
        if activate { NSApp.activate(ignoringOtherApps: true) }

        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        if running.contains(appleMusicBundleID) {
            _ = await runner.automationPermission(bundleID: appleMusicBundleID, prompt: true)
        }
        if running.contains(spotifyBundleID) {
            _ = await runner.automationPermission(bundleID: spotifyBundleID, prompt: true)
        }
        await poll()
    }

    func requestMusicAuthorization() async {
        await promptForRunningPlayers(activate: true)
    }

    private func pickActive(music: Snapshot?, spotify: Snapshot?) -> (Source, Snapshot)? {
        // Playing takes priority.
        if let m = music, m.state == .playing { return (.appleMusic, m) }
        if let s = spotify, s.state == .playing { return (.spotify, s) }
        // Otherwise whichever has a loaded (paused) track.
        if let m = music { return (.appleMusic, m) }
        if let s = spotify { return (.spotify, s) }
        return nil
    }

    private func applySnapshot(_ snap: Snapshot, source: Source) async {
        let key = "\(snap.title)|\(snap.artist)|\(snap.album)"
        var artwork: Data? = currentTrack?.artworkData

        // Only refetch artwork when the track key changes — artwork I/O is
        // the expensive part and must not run every poll.
        if key != lastArtworkKey {
            lastArtworkKey = key
            artwork = await fetchArtwork(for: source, snap: snap)
        }

        let info = NowPlayingInfo(
            title: snap.title,
            artist: snap.artist,
            album: snap.album,
            artworkData: artwork,
            duration: snap.duration,
            elapsedTime: snap.position,
            playbackRate: snap.state == .playing ? 1.0 : 0.0,
            playbackState: snap.state,
            lastUpdated: Date()
        )
        apply(info)
    }

    /// Dedupe + publish. Matches the old MediaService.apply semantics so a
    /// no-op poll doesn't churn `objectWillChange`.
    private func apply(_ info: NowPlayingInfo?) {
        guard let info else {
            if currentTrack != nil {
                currentTrack = nil
                lastArtworkKey = nil
                delegate?.mediaService(self, didUpdatePlaybackState: .stopped)
            }
            if isPlaying { isPlaying = false }
            return
        }
        if currentTrack != info {
            currentTrack = info
            delegate?.mediaService(self, didUpdateNowPlaying: info)
        }
        if isPlaying != info.isPlaying {
            isPlaying = info.isPlaying
            delegate?.mediaService(self, didUpdatePlaybackState: info.playbackState)
        }
    }

    // MARK: - AppleScript Queries

    private struct Snapshot {
        let state: MediaPlaybackState
        let title: String
        let artist: String
        let album: String
        let duration: TimeInterval
        let position: TimeInterval
    }

    private func queryAppleMusic() async -> Snapshot? {
        let d = fieldSeparator
        let script = """
        tell application "Music"
            set dlm to (ASCII character 30)
            set ps to player state as string
            if ps is "stopped" then return "stopped"
            try
                set t to current track
                return ps & dlm & (name of t) & dlm & (artist of t) & dlm & (album of t) & dlm & ((duration of t) as string) & dlm & ((player position) as string)
            on error
                return "stopped"
            end try
        end tell
        """
        guard let raw = await runner.runString(script) else { return nil }
        return parse(raw, delimiter: d, durationInMillis: false)
    }

    private func querySpotify() async -> Snapshot? {
        let d = fieldSeparator
        // Spotify reports duration in milliseconds; player position in
        // seconds (float). We normalize duration to seconds in `parse`.
        let script = """
        tell application "Spotify"
            set dlm to (ASCII character 30)
            set ps to player state as string
            if ps is "stopped" then return "stopped"
            try
                set t to current track
                return ps & dlm & (name of t) & dlm & (artist of t) & dlm & (album of t) & dlm & ((duration of t) as string) & dlm & ((player position) as string)
            on error
                return "stopped"
            end try
        end tell
        """
        guard let raw = await runner.runString(script) else { return nil }
        return parse(raw, delimiter: d, durationInMillis: true)
    }

    private func parse(_ raw: String, delimiter: String, durationInMillis: Bool) -> Snapshot? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "stopped" || trimmed.isEmpty { return nil }
        let parts = trimmed.components(separatedBy: delimiter)
        guard parts.count == 6 else { return nil }

        let state: MediaPlaybackState
        switch parts[0] {
        case "playing": state = .playing
        case "paused": state = .paused
        default: state = .paused  // fast forwarding / rewinding → treat as playing-ish paused
        }

        let rawDuration = Double(parts[4]) ?? 0
        let duration = durationInMillis ? rawDuration / 1000.0 : rawDuration
        let position = Double(parts[5]) ?? 0

        return Snapshot(
            state: state,
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: duration,
            position: position
        )
    }

    // MARK: - Artwork

    private func fetchArtwork(for source: Source, snap: Snapshot) async -> Data? {
        switch source {
        case .appleMusic:
            // Apple Music artwork is local image data exposed via AppleScript.
            let script = """
            tell application "Music"
                try
                    return data of artwork 1 of current track
                on error
                    return ""
                end try
            end tell
            """
            return await runner.runData(script)

        case .spotify:
            // Spotify exposes an https artwork URL; download it (needs the
            // network entitlement, which we keep for MAS).
            let script = """
            tell application "Spotify"
                try
                    return artwork url of current track
                on error
                    return ""
                end try
            end tell
            """
            guard let urlString = await runner.runString(script)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !urlString.isEmpty,
                  let url = URL(string: urlString) else { return nil }
            return try? await URLSession.shared.data(from: url).0
        }
    }

    // MARK: - Controls

    // Each control targets the active source. If we don't know the active
    // source yet (no poll has resolved one), the command is a no-op rather
    // than guessing and risking launching an app.

    func play() async throws { sendControl(music: "play", spotify: "play") }
    func pause() async throws { sendControl(music: "pause", spotify: "pause") }
    func togglePlayPause() async throws { sendControl(music: "playpause", spotify: "playpause") }
    func nextTrack() async throws { sendControl(music: "next track", spotify: "next track") }
    func previousTrack() async throws { sendControl(music: "previous track", spotify: "previous track") }

    func seek(to time: TimeInterval) async throws {
        guard let source = activeSource else { return }
        let app = source == .appleMusic ? "Music" : "Spotify"
        runner.runCommand("tell application \"\(app)\" to set player position to \(time)")
        // Reflect immediately; next poll will reconcile.
        await poll()
    }

    // Shuffle / repeat: both apps expose these but with different property
    // shapes. Toggling generically across both isn't reliable, so we flip
    // Apple Music's boolean and Spotify's boolean where available.
    func toggleShuffle() async throws {
        guard let source = activeSource else { return }
        switch source {
        case .appleMusic:
            runner.runCommand("tell application \"Music\" to set shuffle enabled to not (shuffle enabled)")
        case .spotify:
            runner.runCommand("tell application \"Spotify\" to set shuffling to not shuffling")
        }
    }

    func toggleRepeat() async throws {
        guard let source = activeSource else { return }
        switch source {
        case .appleMusic:
            runner.runCommand("tell application \"Music\" to set song repeat to (if song repeat is off then all else off)")
        case .spotify:
            runner.runCommand("tell application \"Spotify\" to set repeating to not repeating")
        }
    }

    private func sendControl(music: String, spotify: String) {
        guard let source = activeSource else { return }
        switch source {
        case .appleMusic:
            runner.runCommand("tell application \"Music\" to \(music)")
        case .spotify:
            runner.runCommand("tell application \"Spotify\" to \(spotify)")
        }
        // Poll soon so the UI reflects the new state quickly rather than
        // waiting up to a full interval.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            await self?.poll()
        }
    }
}
