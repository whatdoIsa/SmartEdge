import Foundation
import AppKit
import Darwin

/// Streams system-wide Now Playing info via the bundled mediaremote-adapter
/// helper (https://github.com/ungive/mediaremote-adapter, BSD-3-Clause).
///
/// Background: as of macOS 15.4, calling MediaRemote.framework directly from
/// a third-party app returns "Operation not permitted" — Apple gated it to
/// system binaries. The helper works around this by invoking `/usr/bin/perl`
/// (a system binary that *does* hold the entitlement) and loading a small
/// adapter framework that prints NowPlaying updates to stdout as JSON.
///
/// What this gives us vs. the previous AppleScript polling approach:
/// - Real-time push (Music skip → notch updates in single-digit ms)
/// - **All sources**: Apple Music, Safari/Chrome/Arc YouTube, Spotify
///   desktop, anything that registers with the system NowPlaying. Browser
///   adapters become unnecessary because the browser already reports
///   playback to the system.
/// - Zero AppleScript permission prompt; perl is launched in-process.
///
/// Architecture:
/// - One long-lived `Process` running `perl mediaremote-adapter.pl stream`.
/// - stdout is a JSON Line stream (`{"type":"data","diff":bool,"payload":...}`).
/// - We accumulate bytes until newline, decode each line, and forward
///   the payload to a `MainActor` callback as a `NowPlayingInfo`.
/// - If the helper dies (crash, OS update, signature mismatch) we restart
///   it with exponential back-off so the notch self-heals.
@MainActor
final class MediaRemoteAdapterClient {

    // MARK: - Public

    /// Called whenever the helper emits a payload. Always invoked on the
    /// MainActor. `nil` means "nothing is playing" (helper emitted null).
    var onUpdate: ((NowPlayingInfo?) -> Void)?

    /// Starts the helper. Idempotent — calling twice is a no-op.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        launchHelper()
    }

    /// Stops the helper and prevents auto-restart.
    func stop() {
        isRunning = false
        terminateHelper()
    }

    /// Spawns a short-lived `perl ... get` to retrieve artwork bytes
    /// for the currently playing track. We do this out-of-band from
    /// the streaming connection because the stream now runs with
    /// `--no-artwork` so the metadata event is small and snappy. The
    /// `completion` runs on the MainActor with the artwork Data, or
    /// nil if there isn't any.
    ///
    /// Cost: ~80–150ms per call. We only call this when the track key
    /// (title|artist|album) actually changes, so a steady-state user
    /// rarely triggers it.
    func fetchArtworkSnapshot(completion: @escaping @MainActor (Data?) -> Void) {
        guard let resources = locateResources() else {
            Task { @MainActor in completion(nil) }
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [
            resources.scriptURL.path,
            resources.frameworkURL.path,
            "get"
        ]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        proc.terminationHandler = { _ in
            let data = out.fileHandleForReading.readDataToEndOfFile()
            // Try to parse just the artworkData base64 string out of the
            // single-object JSON. JSONSerialization would do too, but
            // this is a few lines lighter and avoids declaring another
            // Decodable that mirrors the whole `get` schema.
            var artwork: Data?
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let b64 = obj["artworkData"] as? String,
               let bytes = Data(base64Encoded: b64) {
                artwork = bytes
            }
            Task { @MainActor in completion(artwork) }
        }
        do {
            try proc.run()
        } catch {
            Task { @MainActor in completion(nil) }
        }
    }

    /// Sends a one-shot media command through the helper. Spawns a fresh
    /// short-lived perl process per call, because the streaming helper
    /// only reads stdin for shutdown — it doesn't multiplex commands.
    /// Cheap (~30ms) and keeps the streaming pipe untouched.
    ///
    /// Supported `command` values map 1:1 to mediaremote-adapter's CLI:
    /// `send N`, `seek <microseconds>`, `shuffle <mode>`, `repeat <mode>`.
    func sendCommand(_ command: String) {
        guard let resources = locateResources() else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        var args = [
            resources.scriptURL.path,
            resources.frameworkURL.path
        ]
        // Helper takes the command + any args as the final positional tokens.
        args.append(contentsOf: command.split(separator: " ").map(String.init))
        proc.arguments = args
        // We don't care about output; if we capture nothing the kernel
        // discards the writes.
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            AppLogger.media.warning("MediaRemoteAdapterClient.sendCommand(\(command, privacy: .public)) spawn failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private state

    /// Reused across every JSON line. Creating a new JSONDecoder per line
    /// incurs repeated heap allocation — at stream rate this is measurable.
    private let decoder = JSONDecoder()
    private var isRunning = false
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    /// Master end of the PTY we use for the streaming helper. The helper
    /// framework switches to fully-buffered stdout when its descriptor
    /// is a pipe (because `isatty()` returns false), which meant the
    /// 100KB+ artwork payloads were the only time we ever saw a line —
    /// and even those didn't arrive on time for a track change. Giving
    /// the child a PTY makes the framework treat its output as a TTY
    /// and line-buffer like a terminal would. The master FD is read by
    /// `readabilityHandler` exactly like a pipe.
    private var ptyMaster: FileHandle?
    private var lineBuffer = Data()
    private var restartAttempts = 0
    private var lastRestart: Date?

    /// Sticky state. The helper's `stream` command emits *delta* payloads
    /// (only the fields that changed) when `diff` is true, so a payload
    /// of `{ "playing": false }` doesn't mean "title/artist are now nil"
    /// — it means "everything else is unchanged, just the playing flag
    /// flipped". We accumulate field values across payloads and only
    /// reset them when we receive a `diff:false` (full) payload or an
    /// explicit empty-payload "nothing playing" signal.
    private var stickyTitle: String?
    private var stickyArtist: String?
    private var stickyAlbum: String?
    private var stickyDuration: Double = 0
    private var stickyElapsed: Double = 0
    private var stickyPlaying: Bool = false
    private var stickyArtwork: Data?

    // MARK: - Launching

    private func launchHelper() {
        guard let resources = locateResources() else {
            AppLogger.media.error("MediaRemoteAdapterClient: bundled helper files missing — falling back to no-op.")
            return
        }

        // Allocate a PTY so the helper sees a TTY on stdout (line-buffered)
        // instead of a pipe (block-buffered). On macOS `openpty(3)` is
        // declared in util.h and lives in libutil — Swift sees it through
        // the Darwin module.
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        if openpty(&masterFD, &slaveFD, nil, nil, nil) != 0 {
            AppLogger.media.error("MediaRemoteAdapterClient: openpty failed (errno=\(errno, privacy: .public))")
            scheduleRestart()
            return
        }

        let masterHandle = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        let slaveHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [
            resources.scriptURL.path,
            resources.frameworkURL.path,
            "stream",
            // `--no-diff`: full snapshot per change. We still sticky-merge
            // because delta payloads occasionally drop fields we depend on,
            // but with this flag every emission stands on its own.
            "--no-diff",
            // `--no-artwork`: drop the base64-encoded image from the stream.
            // It dominates payload size (a single envelope was ~130 KB on
            // an artwork-bearing track) and that's the bottleneck behind
            // the perceived "lag" between hitting next and the new title
            // showing up — the helper is *blocked* writing 130 KB through
            // a PTY before the next event can fire. Without artwork the
            // envelope is ~1 KB, transferred instantly. Artwork is fetched
            // separately by `fetchArtworkSnapshot()` below.
            "--no-artwork",
            // No debounce: we want the event the moment Music.app fires it.
            // The shotgun-burst problem `--debounce=100` was guarding
            // against is no longer present at small payload sizes.
            "--debounce=0"
        ]
        proc.standardOutput = slaveHandle
        // Send stderr through the same PTY so framework warnings show up
        // in the same readability stream; we filter them out via JSON
        // decode failures harmlessly. (Separating to its own pipe would
        // re-introduce the same buffering problem on the error channel.)
        proc.standardError = slaveHandle

        masterHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            Task { @MainActor [weak self] in
                self?.consume(chunk)
            }
        }

        proc.terminationHandler = { [weak self] terminated in
            // Crossing back to the main actor for restart bookkeeping.
            Task { @MainActor [weak self] in
                self?.handleTermination(status: terminated.terminationStatus)
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.ptyMaster = masterHandle
            // The slave is now duplicated into the child; close our copy
            // so the parent doesn't hold a stale FD that prevents EOF
            // propagation when the helper exits.
            try? slaveHandle.close()
            AppLogger.media.info("MediaRemoteAdapterClient: helper spawned via PTY (pid=\(proc.processIdentifier, privacy: .public))")
        } catch {
            AppLogger.media.error("MediaRemoteAdapterClient: spawn failed — \(error.localizedDescription, privacy: .public)")
            scheduleRestart()
        }
    }

    private func terminateHelper() {
        process?.terminationHandler = nil
        ptyMaster?.readabilityHandler = nil
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        ptyMaster = nil
        stdoutPipe = nil
        stderrPipe = nil
        lineBuffer.removeAll(keepingCapacity: false)
    }

    private func handleTermination(status: Int32) {
        process = nil
        AppLogger.media.warning("MediaRemoteAdapterClient: helper exited (status=\(status, privacy: .public))")
        guard isRunning else { return }
        scheduleRestart()
    }

    /// Exponential back-off restart so a misconfigured framework or
    /// repeatedly-crashing helper doesn't spin the CPU.
    private func scheduleRestart() {
        guard isRunning else { return }
        restartAttempts += 1
        let delay = min(pow(1.7, Double(min(restartAttempts, 8))), 30.0)
        AppLogger.media.notice("MediaRemoteAdapterClient: restarting in \(delay, format: .fixed(precision: 1), privacy: .public)s (attempt \(self.restartAttempts, privacy: .public))")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.launchHelper()
        }
    }

    // MARK: - Stream parsing

    /// Appends incoming bytes to the line buffer and emits a `decode(line:)`
    /// for each completed line (delimited by `\n`).
    ///
    /// Reworked from the previous prefix/removeSubrange pattern, which
    /// played badly with `Data`'s non-zero startIndex after removals and
    /// could leave lines stranded in the buffer. Now we sweep with an
    /// explicit cursor and trim once at the end.
    private func consume(_ chunk: Data) {
        lineBuffer.append(chunk)
        var cursor = lineBuffer.startIndex
        while cursor < lineBuffer.endIndex,
              let nl = lineBuffer[cursor...].firstIndex(of: 0x0A) {
            let line = Data(lineBuffer[cursor..<nl])
            decode(line)
            cursor = lineBuffer.index(after: nl)
        }
        if cursor > lineBuffer.startIndex {
            lineBuffer.removeSubrange(lineBuffer.startIndex..<cursor)
        }
    }

    // Envelope shapes lifted to type scope so the `isEmptyPayload` helper
    // (and future helpers) can reference `Envelope.Payload` by type.
    fileprivate struct Envelope: Decodable {
        let type: String
        let diff: Bool?
        let payload: Payload?
        struct Payload: Decodable {
            let bundleIdentifier: String?
            let title: String?
            let artist: String?
            let album: String?
            let playing: Bool?
            let duration: Double?
            let elapsedTime: Double?
            let artworkData: String?       // base64
            let artworkMimeType: String?
        }
    }

    private func decode(_ lineData: Data) {
        guard !lineData.isEmpty else { return }
        // Reset back-off as soon as the helper emits something usable —
        // proves it's healthy and any further crash starts the counter
        // from zero.
        restartAttempts = 0

        do {
            let env = try decoder.decode(Envelope.self, from: lineData)
            guard env.type == "data" else { return }
            let isDiff = env.diff ?? false
            AppLogger.media.info("MediaRemoteAdapterClient: decoded type=\(env.type, privacy: .public) diff=\(isDiff, privacy: .public) payload?=\(env.payload != nil, privacy: .public)")

            // Full snapshots reset the sticky state. Helper emits one of
            // these on connect and after a track changes wholesale.
            if !isDiff {
                stickyTitle = nil
                stickyArtist = nil
                stickyAlbum = nil
                stickyDuration = 0
                stickyElapsed = 0
                stickyPlaying = false
                stickyArtwork = nil
            }

            guard let payload = env.payload else {
                onUpdate?(nil)
                return
            }

            // Empty payload on a full snapshot = nothing playing.
            // (On a diff it just means nothing changed — fall through to
            // re-emit the sticky state so consumers don't see a flicker.)
            if !isDiff && isEmptyPayload(payload) {
                onUpdate?(nil)
                return
            }

            // Merge non-nil fields from the payload into sticky state.
            if let v = payload.title { stickyTitle = v }
            if let v = payload.artist { stickyArtist = v }
            if let v = payload.album { stickyAlbum = v }
            if let v = payload.duration { stickyDuration = v }
            if let v = payload.elapsedTime { stickyElapsed = v }
            if let v = payload.playing { stickyPlaying = v }
            if let s = payload.artworkData, let data = Data(base64Encoded: s) {
                stickyArtwork = data
            }

            // Need at least a title or artist to call it "playing
            // something" — guards against the empty-shell first frame.
            if (stickyTitle?.isEmpty ?? true) && (stickyArtist?.isEmpty ?? true) {
                onUpdate?(nil)
                return
            }

            let state: MediaPlaybackState = stickyPlaying ? .playing : .paused
            let info = NowPlayingInfo(
                title: stickyTitle,
                artist: stickyArtist,
                album: stickyAlbum,
                artworkData: stickyArtwork,
                duration: stickyDuration,
                elapsedTime: stickyElapsed,
                playbackRate: state == .playing ? 1 : 0,
                playbackState: state,
                lastUpdated: Date()
            )
            onUpdate?(info)
        } catch {
            // Helper occasionally emits informational lines that aren't
            // JSON envelopes — log at debug and move on rather than
            // killing the stream.
            AppLogger.media.debug("MediaRemoteAdapterClient: undecodable line (\(lineData.count, privacy: .public) bytes)")
        }
    }

    private func isEmptyPayload(_ p: Envelope.Payload) -> Bool {
        return p.bundleIdentifier == nil
            && p.title == nil
            && p.artist == nil
            && p.album == nil
            && p.playing == nil
            && p.duration == nil
            && p.elapsedTime == nil
            && p.artworkData == nil
    }

    // MARK: - Resource lookup

    private struct HelperPaths {
        let scriptURL: URL
        let frameworkURL: URL
    }

    /// The helper bundle is copied into `Resources/MediaRemoteAdapter/`
    /// by the SmartEdge build phase. perl needs absolute paths or it
    /// refuses to load the framework — `Bundle.main.resourceURL` gives
    /// us the correct one.
    private func locateResources() -> HelperPaths? {
        guard let resourcesURL = Bundle.main.resourceURL else { return nil }
        let dir = resourcesURL.appendingPathComponent("MediaRemoteAdapter", isDirectory: true)
        let script = dir.appendingPathComponent("mediaremote-adapter.pl")
        let framework = dir.appendingPathComponent("MediaRemoteAdapter.framework")
        let fm = FileManager.default
        guard fm.fileExists(atPath: script.path),
              fm.fileExists(atPath: framework.path) else {
            return nil
        }
        return HelperPaths(scriptURL: script, frameworkURL: framework)
    }
}

