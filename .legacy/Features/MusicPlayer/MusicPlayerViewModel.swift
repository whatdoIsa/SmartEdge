import SwiftUI
import Combine

@MainActor
final class MusicPlayerViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var nowPlaying: NowPlayingInfo?
    @Published var isLoading = false
    @Published var isControlLoading = false
    @Published var error: AppError?
    @Published var transientError: AppError?
    
    // MARK: - Private Properties
    private let mediaService: MediaServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var transientErrorTimer: Timer?
    
    // MARK: - Initialization
    init(mediaService: MediaServiceProtocol = MediaService.shared) {
        self.mediaService = mediaService
        setupBindings()
    }
    
    deinit {
        transientErrorTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    func initialize() async {
        isLoading = true
        error = nil
        
        do {
            try await mediaService.initialize()
            await refreshPlayerState()
            setupNotificationObservers()
        } catch {
            await handleError(.mediaServiceUnavailable, transient: false)
        }
        
        isLoading = false
    }
    
    func refreshPlayerState() async {
        do {
            nowPlaying = try await mediaService.getCurrentTrack()
            error = nil
        } catch {
            await handleError(.mediaServiceUnavailable, transient: false)
        }
    }
    
    func togglePlayPause() async {
        await performControlAction {
            try await mediaService.togglePlayPause()
        }
    }
    
    func nextTrack() async {
        await performControlAction {
            try await mediaService.nextTrack()
        }
    }
    
    func previousTrack() async {
        await performControlAction {
            try await mediaService.previousTrack()
        }
    }
    
    func toggleShuffle() async {
        await performControlAction {
            try await mediaService.toggleShuffle()
        }
    }
    
    func toggleRepeat() async {
        await performControlAction {
            try await mediaService.toggleRepeat()
        }
    }
    
    func openMusicApp() {
        NSWorkspace.shared.launchApplication("Music")
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Listen for media service changes
        mediaService.nowPlayingPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] nowPlaying in
                self?.nowPlaying = nowPlaying
                self?.error = nil
            }
            .store(in: &cancellables)
        
        // Listen for media service errors
        mediaService.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                Task { @MainActor in
                    await self?.handleError(.unknownError(error.localizedDescription), transient: true)
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .musicPlayerStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshPlayerState()
            }
        }
    }
    
    private func performControlAction(_ action: () async throws -> Void) async {
        isControlLoading = true
        
        do {
            try await action()
            await refreshPlayerState()
        } catch {
            await handleError(.unknownError("Control action failed"), transient: true)
        }
        
        isControlLoading = false
    }
    
    private func handleError(_ appError: AppError, transient: Bool) async {
        if transient {
            transientError = appError
            scheduleTransientErrorDismissal()
        } else {
            error = appError
        }
    }
    
    private func scheduleTransientErrorDismissal() {
        transientErrorTimer?.invalidate()
        transientErrorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.transientError = nil
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let musicPlayerStateChanged = Notification.Name("musicPlayerStateChanged")
}

// MARK: - NowPlayingInfo Model
struct NowPlayingInfo {
    let title: String
    let artist: String
    let album: String?
    let artwork: NSImage?
    let isPlaying: Bool
    let progress: TimeInterval?
    let duration: TimeInterval?
    
    static let placeholder = NowPlayingInfo(
        title: "Unknown Track",
        artist: "Unknown Artist", 
        album: nil,
        artwork: nil,
        isPlaying: false,
        progress: nil,
        duration: nil
    )
}

// MARK: - MediaService Protocol
protocol MediaServiceProtocol {
    var nowPlayingPublisher: AnyPublisher<NowPlayingInfo?, Never> { get }
    var errorPublisher: AnyPublisher<Error, Never> { get }
    
    func initialize() async throws
    func getCurrentTrack() async throws -> NowPlayingInfo?
    func togglePlayPause() async throws
    func nextTrack() async throws
    func previousTrack() async throws
    func toggleShuffle() async throws
    func toggleRepeat() async throws
}

// MARK: - Mock MediaService for Preview/Testing
final class MockMediaService: MediaServiceProtocol {
    private let nowPlayingSubject = CurrentValueSubject<NowPlayingInfo?, Never>(nil)
    private let errorSubject = PassthroughSubject<Error, Never>()
    
    var nowPlayingPublisher: AnyPublisher<NowPlayingInfo?, Never> {
        nowPlayingSubject.eraseToAnyPublisher()
    }
    
    var errorPublisher: AnyPublisher<Error, Never> {
        errorSubject.eraseToAnyPublisher()
    }
    
    func initialize() async throws {
        // Simulate initialization delay
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        // Simulate having music playing
        let mockTrack = NowPlayingInfo(
            title: "Sample Track",
            artist: "Sample Artist",
            album: "Sample Album",
            artwork: nil,
            isPlaying: true,
            progress: 45.0,
            duration: 180.0
        )
        nowPlayingSubject.send(mockTrack)
    }
    
    func getCurrentTrack() async throws -> NowPlayingInfo? {
        return nowPlayingSubject.value
    }
    
    func togglePlayPause() async throws {
        guard var current = nowPlayingSubject.value else { return }
        current = NowPlayingInfo(
            title: current.title,
            artist: current.artist,
            album: current.album,
            artwork: current.artwork,
            isPlaying: !current.isPlaying,
            progress: current.progress,
            duration: current.duration
        )
        nowPlayingSubject.send(current)
    }
    
    func nextTrack() async throws {
        // Simulate track change
        let newTrack = NowPlayingInfo(
            title: "Next Track",
            artist: "Sample Artist",
            album: "Sample Album",
            artwork: nil,
            isPlaying: true,
            progress: 0.0,
            duration: 200.0
        )
        nowPlayingSubject.send(newTrack)
    }
    
    func previousTrack() async throws {
        // Simulate track change
        let newTrack = NowPlayingInfo(
            title: "Previous Track",
            artist: "Sample Artist",
            album: "Sample Album",
            artwork: nil,
            isPlaying: true,
            progress: 0.0,
            duration: 160.0
        )
        nowPlayingSubject.send(newTrack)
    }
    
    func toggleShuffle() async throws {
        // No-op for mock
    }
    
    func toggleRepeat() async throws {
        // No-op for mock
    }
}