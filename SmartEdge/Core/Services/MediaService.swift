import Foundation
import AppKit
import Combine

/// System-wide Now Playing service, backed by the bundled
/// **mediaremote-adapter** helper (BSD-3-Clause).
///
/// History of this file:
///
/// 1. Original implementation called `MRMediaRemote*` C functions directly
///    via dynamic loading. This worked on older macOS but Apple gated the
///    framework to system binaries starting macOS 15.4, after which every
///    call returned "Operation not permitted" and the notch was permanently
///    stuck at "No Music Playing".
///
/// 2. A short-lived AppleScript-based source bridged the gap for Apple
///    Music specifically (a `Music` AppleScript polled every ~0.5s), but
///    it only covered Apple Music — YouTube in a browser, Spotify
///    desktop, etc. were invisible — and the synchronous polling caused
///    observable UI freezes when artwork fetches piled up. That file is
///    gone now; check git history if you need the implementation.
///
/// 3. (This file) Both of the above are gone. `MediaRemoteAdapterClient`
///    runs `/usr/bin/perl` as a child process, which holds the system
///    entitlement Apple revoked from third-party apps. The helper streams
///    NowPlayingInfo over stdout the moment anything changes — sub-ms
///    latency, no polling, and Apple Music + YouTube + Spotify all flow
///    through the same pipe.
///
/// Public surface (`MediaServiceProtocol`) is unchanged so call sites
/// don't need to know which source actually filled `currentTrack`.
@MainActor
final class MediaService: ObservableObject, MediaServiceProtocol {
    // MARK: - MediaServiceProtocol Properties
    weak var delegate: MediaServiceDelegate?
    var currentNowPlaying: NowPlayingInfo? { currentTrack }
    var currentPlaybackState: MediaPlaybackState { isPlaying ? .playing : .paused }
    var isAvailable: Bool { true }

    // MARK: - Published Properties
    @Published var currentTrack: NowPlayingInfo?
    @Published var isPlaying: Bool = false
    @Published var playbackTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    var isPlayingPublisher: AnyPublisher<Bool, Never> {
        $isPlaying.eraseToAnyPublisher()
    }

    var currentTrackPublisher: AnyPublisher<NowPlayingInfo?, Never> {
        $currentTrack.eraseToAnyPublisher()
    }

    // MARK: - Private

    private let adapter = MediaRemoteAdapterClient()
    /// Last (title|artist|album) we asked the helper to load artwork for.
    /// Stops us from re-fetching the same artwork every time a position
    /// update comes in for the same track.
    private var lastArtworkKey: String?

    // MARK: - Lifecycle

    init() {
        wireAdapter()
        adapter.start()
    }

    deinit {
        // `Process` is process-bound; if SmartEdge is torn down the perl
        // child gets SIGTERM via `terminate()`. Without this it would keep
        // running until macOS reaped it on app exit.
        Task { @MainActor [adapter] in
            adapter.stop()
        }
    }

    // MARK: - MediaServiceProtocol Implementation

    func initialize() async throws {
        // adapter is already started from init(); calling start() again is
        // idempotent (guarded by isRunning) but creates noise — skip it.
    }

    func startMonitoring() async throws {
        // Same rationale as initialize() above.
    }

    func stopMonitoring() async {
        adapter.stop()
    }

    // Transport controls are routed back through the same adapter helper.
    // The streaming process stays untouched; each command spawns a tiny
    // one-shot perl invocation (~30ms).
    //
    // The helper's `send` function takes a numeric MRCommand id — these
    // are the same constants the legacy `MRMediaRemoteSendCommand` C
    // function accepted (we used to call into it directly). 0=Play,
    // 1=Pause, 2=TogglePlayPause, 4=NextTrack, 5=PreviousTrack. Using
    // `send` (not `next`) is essential because `next` isn't one of the
    // function names the perl script recognizes — sending the wrong
    // form silently fails because the helper's stderr never reaches us.
    func play() async throws { adapter.sendCommand("send 0") }
    func pause() async throws { adapter.sendCommand("send 1") }
    func togglePlayPause() async throws { adapter.sendCommand("send 2") }
    func nextTrack() async throws { adapter.sendCommand("send 4") }
    func previousTrack() async throws { adapter.sendCommand("send 5") }
    func seek(to time: TimeInterval) async throws {
        // Helper expects microseconds.
        let micros = Int(time * 1_000_000)
        adapter.sendCommand("seek \(micros)")
    }
    // Mode constants match the MediaRemote.framework enum: 0=Off, 1=On.
    // We toggle by writing the opposite value; the helper doesn't expose
    // a get-current-mode, so this assumes a fresh "off" baseline.
    func toggleShuffle() async throws { adapter.sendCommand("shuffle 1") }
    func toggleRepeat() async throws { adapter.sendCommand("repeat 1") }

    func setVolume(_ volume: Float) {
        // System volume routing not implemented here — see HUDInterception.
    }

    // MARK: - Wiring

    private func wireAdapter() {
        adapter.onUpdate = { [weak self] info in
            self?.apply(info)
        }
    }

    /// Applies a helper-emitted NowPlayingInfo (or nil) to our published
    /// state, deduping every assignment. Same dedupe rules that fixed the
    /// EE1 AutoLayout pass-loop crash: a `@Published` reassignment with
    /// an unchanged value still triggers `objectWillChange`, which the
    /// notch's NSHostingView translates into another constraint pass.
    private func apply(_ info: NowPlayingInfo?) {
        guard let info = info else {
            if currentTrack != nil {
                currentTrack = nil
                delegate?.mediaService(self, didUpdatePlaybackState: .stopped)
            }
            if duration != 0 { duration = 0 }
            if playbackTime != 0 { playbackTime = 0 }
            if isPlaying { isPlaying = false }
            return
        }

        if currentTrack != info {
            currentTrack = info
            delegate?.mediaService(self, didUpdateNowPlaying: info)
            // Track key changed → fetch artwork out-of-band so the
            // notch first gets text-only metadata instantly, and the
            // image fills in 80–150 ms later. Without the gate we'd
            // re-fetch on every progress tick.
            let key = "\(info.title ?? "")|\(info.artist ?? "")|\(info.album ?? "")"
            if key != lastArtworkKey {
                lastArtworkKey = key
                adapter.fetchArtworkSnapshot { [weak self] data in
                    guard let self = self,
                          let data = data,
                          let existing = self.currentTrack,
                          // Make sure the user hasn't jumped to a different
                          // track during the ~100 ms fetch. If they did, the
                          // newer apply() call will issue its own request.
                          existing.title == info.title,
                          existing.artist == info.artist
                    else { return }
                    let updated = NowPlayingInfo(
                        title: existing.title,
                        artist: existing.artist,
                        album: existing.album,
                        artworkData: data,
                        duration: existing.duration,
                        elapsedTime: existing.elapsedTime,
                        playbackRate: existing.playbackRate,
                        playbackState: existing.playbackState,
                        lastUpdated: Date()
                    )
                    self.currentTrack = updated
                }
            }
        }
        if duration != info.duration { duration = info.duration }
        if playbackTime != info.elapsedTime { playbackTime = info.elapsedTime }
        if isPlaying != info.isPlaying {
            isPlaying = info.isPlaying
            delegate?.mediaService(self, didUpdatePlaybackState: info.playbackState)
        }
    }
}
