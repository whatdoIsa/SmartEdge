import Foundation
import Combine

// Import the protocol definition
typealias NotchMediaServiceDelegate = MediaServiceDelegate

@MainActor
final class MediaServiceAdapter: MediaServiceProtocol {
    
    weak var notchDelegate: NotchMediaServiceDelegate?
    private let mediaService: MediaService
    
    init(mediaService: MediaService) {
        self.mediaService = mediaService
        mediaService.delegate = self
    }
    
    // MARK: - MediaServiceProtocol Implementation
    
    weak var delegate: MediaServiceDelegate?
    
    var currentNowPlaying: NowPlayingInfo? {
        mediaService.currentNowPlaying
    }
    
    var currentPlaybackState: MediaPlaybackState {
        mediaService.currentPlaybackState
    }
    
    var isAvailable: Bool {
        mediaService.isAvailable
    }
    
    var isPlayingPublisher: AnyPublisher<Bool, Never> {
        mediaService.isPlayingPublisher
    }
    
    var currentTrackPublisher: AnyPublisher<NowPlayingInfo?, Never> {
        mediaService.currentTrackPublisher
    }
    
    func initialize() async throws {
        try await mediaService.initialize()
    }
    
    func startMonitoring() async throws {
        try await mediaService.startMonitoring()
    }
    
    func stopMonitoring() async {
        await mediaService.stopMonitoring()
    }
    
    func play() async throws {
        try await mediaService.play()
    }
    
    func pause() async throws {
        try await mediaService.pause()
    }
    
    func togglePlayPause() async throws {
        try await mediaService.togglePlayPause()
    }
    
    func nextTrack() async throws {
        try await mediaService.nextTrack()
    }
    
    func previousTrack() async throws {
        try await mediaService.previousTrack()
    }
    
    func seek(to time: TimeInterval) async throws {
        try await mediaService.seek(to: time)
    }

    func toggleShuffle() async throws {
        try await mediaService.toggleShuffle()
    }

    func toggleRepeat() async throws {
        try await mediaService.toggleRepeat()
    }

    // MARK: - NotchViewModel Bridge API
    
    func setNotchDelegate(_ delegate: NotchMediaServiceDelegate?) {
        notchDelegate = delegate
    }
    
    var currentMediaData: NowPlayingInfo? {
        return currentNowPlaying
    }
}

// MARK: - MediaServiceDelegate Implementation

extension MediaServiceAdapter: MediaServiceDelegate {
    
    nonisolated func mediaService(_ service: MediaServiceProtocol, didUpdateNowPlaying info: NowPlayingInfo?) {
        Task { @MainActor in
            delegate?.mediaService(service, didUpdateNowPlaying: info)
        }
    }
    
    nonisolated func mediaService(_ service: MediaServiceProtocol, didUpdatePlaybackState state: MediaPlaybackState) {
        Task { @MainActor in
            delegate?.mediaService(service, didUpdatePlaybackState: state)
        }
    }
    
    nonisolated func mediaService(_ service: MediaServiceProtocol, didUpdateVolume volume: Float) {
        // Not used in Phase 1
    }
}

// MARK: - Enhanced MediaService

extension MediaService {
    
    func createAdapter() -> MediaServiceAdapter {
        return MediaServiceAdapter(mediaService: self)
    }
}