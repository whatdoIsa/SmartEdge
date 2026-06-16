import Foundation
import Combine

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
    
    // Publishers for reactive programming
    var isPlayingPublisher: AnyPublisher<Bool, Never> { get }
    var currentTrackPublisher: AnyPublisher<NowPlayingInfo?, Never> { get }
    
    func initialize() async throws
    func startMonitoring() async throws
    func stopMonitoring() async
    
    func play() async throws
    func pause() async throws
    func togglePlayPause() async throws
    func nextTrack() async throws
    func previousTrack() async throws
    func seek(to time: TimeInterval) async throws
    func toggleShuffle() async throws
    func toggleRepeat() async throws
}