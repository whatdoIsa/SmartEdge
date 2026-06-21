import Foundation
import Combine

/// Whether the app can read Now Playing from a supported desktop player.
/// Drives the in-app permission affordance: only `.needsPermission` surfaces
/// the "grant access" UI; the other cases map to the normal empty state.
enum MediaAuthorizationStatus: Hashable {
    /// Not yet evaluated this session (initial value before the first poll).
    case unknown
    /// Neither Apple Music nor Spotify is open — nothing to authorize.
    case noPlayerRunning
    /// A supported player is open but macOS Automation isn't granted yet.
    case needsPermission
    /// Authorized to control a running supported player.
    case authorized
}

@MainActor
protocol MediaServiceDelegate: AnyObject {
    func mediaService(_ service: MediaServiceProtocol, didUpdateNowPlaying info: NowPlayingInfo?)
    func mediaService(_ service: MediaServiceProtocol, didUpdatePlaybackState state: MediaPlaybackState)
    func mediaService(_ service: MediaServiceProtocol, didUpdateVolume volume: Float)
}

@MainActor
protocol MediaServiceProtocol {
    var delegate: MediaServiceDelegate? { get set }
    var currentNowPlaying: NowPlayingInfo? { get }
    var currentPlaybackState: MediaPlaybackState { get }
    var isAvailable: Bool { get }
    
    /// Current ability to read Now Playing. Updated every poll.
    var authorizationStatus: MediaAuthorizationStatus { get }

    // Publishers for reactive programming
    var isPlayingPublisher: AnyPublisher<Bool, Never> { get }
    var currentTrackPublisher: AnyPublisher<NowPlayingInfo?, Never> { get }
    var authorizationStatusPublisher: AnyPublisher<MediaAuthorizationStatus, Never> { get }

    func initialize() async throws
    func startMonitoring() async throws
    func stopMonitoring() async

    /// Explicitly prompt the user for Automation permission for any running
    /// supported player, bringing the app forward so the system prompt is
    /// visible. Safe no-op when no supported player is running.
    func requestMusicAuthorization() async
    
    func play() async throws
    func pause() async throws
    func togglePlayPause() async throws
    func nextTrack() async throws
    func previousTrack() async throws
    func seek(to time: TimeInterval) async throws
    func toggleShuffle() async throws
    func toggleRepeat() async throws
}