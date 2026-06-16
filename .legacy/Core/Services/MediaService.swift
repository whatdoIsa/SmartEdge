import Foundation
import MediaPlayer
import Combine

protocol MediaServiceDelegate: AnyObject {
    func mediaService(_ service: MediaService, didUpdateNowPlaying info: MediaInfo?)
    func mediaService(_ service: MediaService, didUpdatePlaybackState isPlaying: Bool)
}

@MainActor
final class MediaService: ObservableObject {
    // MARK: - Published Properties
    
    @Published var currentTrack: MediaInfo?
    @Published var isPlaying: Bool = false
    @Published var playbackTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    // MARK: - Properties
    
    weak var delegate: MediaServiceDelegate?
    private var cancellables = Set<AnyCancellable>()
    private var playbackObserver: Any?
    
    // MARK: - Types
    
    struct MediaInfo {
        let title: String
        let artist: String
        let album: String
        let albumArt: NSImage?
        let duration: TimeInterval
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupMediaPlayerNotifications()
        setupPlaybackTimeObserver()
    }
    
    // MARK: - Public Methods
    
    func playPause() {
        Task {
            await performMediaCommand(.togglePlayPause)
        }
    }
    
    func nextTrack() {
        Task {
            await performMediaCommand(.nextTrack)
        }
    }
    
    func previousTrack() {
        Task {
            await performMediaCommand(.previousTrack)
        }
    }
    
    func seek(to time: TimeInterval) {
        Task {
            await performSeek(to: time)
        }
    }
    
    func setVolume(_ volume: Float) {
        MPVolumeView.setVolume(volume)
    }
    
    // MARK: - Private Methods
    
    private func setupMediaPlayerNotifications() {
        let center = NotificationCenter.default
        
        // Listen for now playing info changes
        center.publisher(for: .MPMusicPlayerControllerNowPlayingItemDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.updateNowPlayingInfo()
                }
            }
            .store(in: &cancellables)
        
        // Listen for playback state changes
        center.publisher(for: .MPMusicPlayerControllerPlaybackStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.updatePlaybackState()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupPlaybackTimeObserver() {
        // Setup periodic time observer for playback progress
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        playbackObserver = AVPlayerLayer.shared.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.playbackTime = time.seconds
            }
        }
    }
    
    private func updateNowPlayingInfo() async {
        let player = MPMusicPlayerController.systemMusicPlayer
        
        guard let nowPlayingItem = player.nowPlayingItem else {
            currentTrack = nil
            delegate?.mediaService(self, didUpdateNowPlaying: nil)
            return
        }
        
        let title = nowPlayingItem.title ?? "Unknown Title"
        let artist = nowPlayingItem.artist ?? "Unknown Artist"
        let album = nowPlayingItem.albumTitle ?? "Unknown Album"
        let duration = nowPlayingItem.playbackDuration
        
        var albumArt: NSImage?
        if let artwork = nowPlayingItem.artwork {
            albumArt = artwork.image(at: CGSize(width: 300, height: 300))
        }
        
        let mediaInfo = MediaInfo(
            title: title,
            artist: artist,
            album: album,
            albumArt: albumArt,
            duration: duration
        )
        
        currentTrack = mediaInfo
        self.duration = duration
        delegate?.mediaService(self, didUpdateNowPlaying: mediaInfo)
    }
    
    private func updatePlaybackState() async {
        let player = MPMusicPlayerController.systemMusicPlayer
        let playing = player.playbackState == .playing
        
        isPlaying = playing
        delegate?.mediaService(self, didUpdatePlaybackState: playing)
    }
    
    private func performMediaCommand(_ command: MediaCommand) async {
        let center = MPRemoteCommandCenter.shared()
        
        switch command {
        case .togglePlayPause:
            if isPlaying {
                _ = center.pauseCommand.perform()
            } else {
                _ = center.playCommand.perform()
            }
        case .nextTrack:
            _ = center.nextTrackCommand.perform()
        case .previousTrack:
            _ = center.previousTrackCommand.perform()
        }
        
        // Update state after command
        await updatePlaybackState()
    }
    
    private func performSeek(to time: TimeInterval) async {
        let player = MPMusicPlayerController.systemMusicPlayer
        player.currentPlaybackTime = time
        
        // Update UI immediately for responsiveness
        await MainActor.run {
            playbackTime = time
        }
    }
    
    // MARK: - Types
    
    private enum MediaCommand {
        case togglePlayPause
        case nextTrack
        case previousTrack
    }
    
    deinit {
        if let observer = playbackObserver {
            AVPlayerLayer.shared.removeTimeObserver(observer)
        }
    }
}

// MARK: - NSImage Extension

private extension MPMediaItemArtwork {
    func image(at size: CGSize) -> NSImage? {
        return self.image(at: size) as? NSImage
    }
}

// MARK: - Volume Extension

private extension MPVolumeView {
    static func setVolume(_ volume: Float) {
        // Implementation would use private APIs or AudioUnit framework
        // This is a placeholder for the actual volume control implementation
    }
}