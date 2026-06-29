import Foundation
import EventKit
import Combine

// NOTE: This entire file is disabled because all required mocks are defined
// in feature-local PreviewMock* (NotchView.swift, MusicPlayerView.swift)
// and the Mock* classes in ServiceProtocols.swift / per-protocol files.
// Re-enabling requires bringing each Mock back into conformance with the current protocols.

#if false

// MARK: - Mock MediaService
// NOTE: Commented out to avoid conflict with MockMediaService in ServiceProtocols.swift

/*
@MainActor
class MockMediaService: MediaServiceProtocol {
    weak var delegate: MediaServiceDelegate?
    var currentNowPlaying: NowPlayingInfo?
    var currentPlaybackState: MediaPlaybackState = .paused
    var isAvailable: Bool = true
    
    init() {
        // Set up mock data
        currentNowPlaying = NowPlayingInfo(
            title: "Mock Song",
            artist: "Mock Artist",
            album: "Mock Album",
            artworkData: nil,
            duration: 180,
            elapsedTime: 60,
            playbackRate: 1.0,
            playbackState: .paused,
            lastUpdated: Date()
        )
    }
    
    func startMonitoring() async throws {
        // Mock implementation
    }
    
    func stopMonitoring() async {
        // Mock implementation
    }
    
    func play() async throws {
        currentPlaybackState = .playing
    }
    
    func pause() async throws {
        currentPlaybackState = .paused
    }
    
    func togglePlayPause() async throws {
        if currentPlaybackState == .playing {
            try await pause()
        } else {
            try await play()
        }
    }
    
    func nextTrack() async throws {
        // Mock implementation
    }
    
    func previousTrack() async throws {
        // Mock implementation
    }

    func seek(to time: TimeInterval) async throws {
        // Mock implementation
    }

    func toggleShuffle() async throws {}
    func toggleRepeat() async throws {}
}
*/

// MARK: - Mock CalendarService

@MainActor
class MockCalendarService: ObservableObject, CalendarServiceProtocol {
    @Published var upcomingEvents: [CalendarEvent] = []
    var nextEvent: CalendarEvent? { upcomingEvents.first }
    var authorizationStatus: EKAuthorizationStatus = .authorized
    var isAuthorized: Bool = true
    
    func requestCalendarAccess() async -> Bool {
        return true
    }
    
    func refreshEvents() async {
        // Mock implementation
    }
    
    func joinMeeting(for event: CalendarEvent) async -> Bool {
        return true
    }
    
    func snoozeReminder(for event: CalendarEvent, minutes: Int) async {
        // Mock implementation
    }
    
    func createQuickEvent(title: String, startDate: Date, duration: TimeInterval) async -> Bool {
        return true
    }
}

// MARK: - Mock ShelfService

@MainActor
class MockShelfService: ObservableObject, ShelfServiceProtocol {
    var shelfItemsPublisher: Published<[ShelfItem]>.Publisher {
        $shelfItems
    }
    
    @Published private var shelfItems: [ShelfItem] = []
    
    func getAllItems() async throws -> [ShelfItem] {
        return shelfItems
    }
    
    func addItem(_ item: ShelfItem) async throws {
        shelfItems.append(item)
    }
    
    func removeItem(_ itemId: UUID) async throws {
        shelfItems.removeAll { $0.id == itemId }
    }
    
    func clearAllItems() async throws {
        shelfItems.removeAll()
    }
    
    func createShelfItem(from url: URL) async throws -> ShelfItem {
        return ShelfItem(
            name: url.lastPathComponent,
            fileURL: url,
            fileType: .document,
            dateAdded: Date(),
            thumbnail: nil
        )
    }
    
    func createShelfItem(from clipboardItem: ClipboardItem) async throws -> ShelfItem {
        return ShelfItem(
            name: "Clipboard Item",
            fileURL: nil,
            fileType: .document,
            dateAdded: clipboardItem.timestamp,
            thumbnail: nil
        )
    }
    
    func openItem(_ item: ShelfItem) async throws {
        // Mock implementation
    }
    
    func showInFinder(_ item: ShelfItem) async throws {
        // Mock implementation
    }
    
    func quickLookItem(_ item: ShelfItem) async throws {
        // Mock implementation
    }
    
    func shareItem(_ item: ShelfItem, using serviceType: NSSharingService.Name?) async throws {
        // Mock implementation
    }
    
    nonisolated func acceptsDroppedFiles(_ urls: [URL]) -> Bool {
        return true
    }
    
    func processDroppedFiles(_ urls: [URL]) async throws -> [ShelfItem] {
        return []
    }
    
    func getStorageUsage() async throws -> ShelfStorageInfo {
        return ShelfStorageInfo(
            totalSizeBytes: 0,
            itemCount: shelfItems.count,
            oldestItemDate: nil,
            maxSizeBytes: 1000000,
            isNearLimit: false
        )
    }
    
    func cleanupExpiredItems() async throws {
        // Mock implementation
    }

    var currentStorageLocationPath: String { "/tmp/MockShelf" }
    var isUsingCustomStorageLocation: Bool { false }
    func setStorageLocation(_ url: URL) async throws {}
    func resetStorageLocation() async throws {}
}

// MARK: - Mock BatteryService

@MainActor
class MockBatteryService: ObservableObject, BatteryServiceProtocol {
    @Published var batteryInfo = BatteryInfo(
        level: 0.85,
        isCharging: false,
        isCharged: false,
        timeUntilEmpty: 3600,
        timeUntilFull: nil,
        health: 90,
        cycleCount: 250,
        temperature: 35.0
    )
    
    func startMonitoring() async {
        // Mock implementation
    }
    
    func stopMonitoring() async {
        // Mock implementation
    }
    
    func getCurrentBatteryInfo() async -> BatteryInfo {
        return batteryInfo
    }
}

// MARK: - Mock BluetoothService

@MainActor
class MockBluetoothService: ObservableObject, BluetoothServiceProtocol {
    @Published var bluetoothInfo = BluetoothInfo(
        isPoweredOn: true,
        connectedDevices: []
    )
    
    func startMonitoring() async {
        // Mock implementation
    }
    
    func stopMonitoring() async {
        // Mock implementation
    }
    
    func getCurrentBluetoothInfo() async -> BluetoothInfo {
        return bluetoothInfo
    }
}

// MARK: - Mock SystemService

@MainActor
class MockSystemService: ObservableObject, SystemServiceProtocol {
    func getCurrentSystemInfo() async -> SystemInfo {
        return SystemInfo(
            macOSVersion: "14.0",
            deviceModel: "MacBook Pro",
            processorType: "Apple M1",
            memorySize: 16,
            storageSize: 512,
            uptime: 3600
        )
    }
    
    func startMonitoring() async {
        // Mock implementation
    }
    
    func stopMonitoring() async {
        // Mock implementation
    }
}

// MARK: - Mock MediaService

@MainActor
class MockMediaService: ObservableObject, MediaServiceProtocol {
    weak var delegate: MediaServiceDelegate?
    var currentNowPlaying: NowPlayingInfo?
    var currentPlaybackState: MediaPlaybackState = .paused
    var isAvailable: Bool = true
    
    init() {
        currentNowPlaying = NowPlayingInfo(
            title: "Mock Song",
            artist: "Mock Artist",
            album: "Mock Album",
            artworkData: nil,
            duration: 180,
            elapsedTime: 60,
            playbackRate: 1.0,
            playbackState: .paused,
            lastUpdated: Date()
        )
    }
    
    func startMonitoring() async throws {
        // Mock implementation
    }
    
    func stopMonitoring() async {
        // Mock implementation
    }
    
    func play() async throws {
        currentPlaybackState = .playing
    }
    
    func pause() async throws {
        currentPlaybackState = .paused
    }
    
    func togglePlayPause() async throws {
        if currentPlaybackState == .playing {
            try await pause()
        } else {
            try await play()
        }
    }
    
    func nextTrack() async throws {
        // Mock implementation
    }
    
    func previousTrack() async throws {
        // Mock implementation
    }

    func seek(to time: TimeInterval) async throws {
        // Mock implementation
    }

    func toggleShuffle() async throws {}
    func toggleRepeat() async throws {}
}
#endif
