import Foundation
import SwiftUI
import Combine
import EventKit
import CoreBluetooth
import AppKit

@MainActor
class PreviewMockMediaService: MediaServiceProtocol {
    weak var delegate: MediaServiceDelegate?
    var currentNowPlaying: NowPlayingInfo?
    var currentPlaybackState: MediaPlaybackState = .paused
    var isAvailable: Bool = true
    var isPlayingPublisher: AnyPublisher<Bool, Never> = Just(false).eraseToAnyPublisher()
    var currentTrackPublisher: AnyPublisher<NowPlayingInfo?, Never> = Just(nil).eraseToAnyPublisher()
    var authorizationStatus: MediaAuthorizationStatus = .authorized
    var authorizationStatusPublisher: AnyPublisher<MediaAuthorizationStatus, Never> = Just(.authorized).eraseToAnyPublisher()

    init() {
        currentNowPlaying = NowPlayingInfo(
            title: "Sample Song",
            artist: "Sample Artist",
            album: "Sample Album",
            artworkData: nil,
            duration: 240,
            elapsedTime: 75,
            playbackRate: 1.0,
            playbackState: .paused,
            lastUpdated: Date()
        )
    }

    func initialize() async throws {}
    func startMonitoring() async throws {}
    func stopMonitoring() async {}
    func play() async throws {}
    func pause() async throws {}
    func togglePlayPause() async throws {}
    func nextTrack() async throws {}
    func previousTrack() async throws {}
    func seek(to time: TimeInterval) async throws {}
    func toggleShuffle() async throws {}
    func toggleRepeat() async throws {}
    func requestMusicAuthorization() async {}
}

@MainActor
class PreviewMockSystemService: SystemServiceProtocol {
    var systemEventPublisher: AnyPublisher<SystemEvent, Never> {
        Empty().eraseToAnyPublisher()
    }
    func initialize() async throws {}
    func requestAllPermissions() async throws -> Bool { true }
    func startMonitoring() async {}
    func stopMonitoring() async {}
}

@MainActor
class PreviewMockCalendarService: CalendarServiceProtocol, ObservableObject {
    @Published var upcomingEvents: [CalendarEvent] = [
        CalendarEvent(
            id: "preview-1",
            title: "Daily Standup",
            notes: "Team sync meeting",
            location: "Conference Room",
            startDate: Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date(),
            endDate: Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date(),
            isAllDay: false,
            calendar: CalendarInfo(
                id: "cal-work",
                title: "Work",
                color: .blue,
                isSubscribed: false,
                allowsContentModifications: true,
                source: .local
            ),
            attendees: [],
            url: nil,
            meetingURL: nil,
            status: .confirmed,
            availability: .busy,
            recurrenceRule: nil,
            hasAlarms: true
        ),
        CalendarEvent(
            id: "preview-2",
            title: "Project Review",
            notes: "Quarterly review",
            location: nil,
            startDate: Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date(),
            endDate: Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date(),
            isAllDay: false,
            calendar: CalendarInfo(
                id: "cal-projects",
                title: "Projects",
                color: .orange,
                isSubscribed: false,
                allowsContentModifications: true,
                source: .local
            ),
            attendees: [],
            url: nil,
            meetingURL: nil,
            status: .confirmed,
            availability: .busy,
            recurrenceRule: nil,
            hasAlarms: false
        )
    ]

    var nextEvent: CalendarEvent? { upcomingEvents.first }
    var authorizationStatus: EKAuthorizationStatus = .authorized
    var isAuthorized: Bool = true

    var upcomingEventsPublisher: AnyPublisher<[CalendarEvent], Never> {
        $upcomingEvents.eraseToAnyPublisher()
    }
    var isAuthorizedPublisher: AnyPublisher<Bool, Never> {
        Just(true).eraseToAnyPublisher()
    }

    func requestCalendarAccess() async -> Bool { true }
    func refreshEvents() async {}
    func joinMeeting(for event: CalendarEvent) async -> Bool { true }
    func snoozeReminder(for event: CalendarEvent, minutes: Int) async {}
    func createQuickEvent(title: String, startDate: Date, duration: TimeInterval) async -> Bool { true }
}

@MainActor
class PreviewMockShelfService: ShelfServiceProtocol {
    var shelfItemsPublisher: Published<[ShelfItem]>.Publisher { $shelfItems }
    @Published private var shelfItems: [ShelfItem] = []

    nonisolated func acceptsDroppedFiles(_ urls: [URL]) -> Bool { true }
    func processDroppedFiles(_ urls: [URL]) async throws -> [ShelfItem] { [] }
    func removeItem(_ itemId: UUID) async throws {}
    func clearAllItems() async throws {}
    func getAllItems() async throws -> [ShelfItem] { [] }
    func addItem(_ item: ShelfItem) async throws {}
    func getStorageUsage() async throws -> ShelfStorageInfo {
        ShelfStorageInfo(
            totalSizeBytes: 0,
            itemCount: 0,
            oldestItemDate: nil,
            maxSizeBytes: 1_000_000,
            isNearLimit: false
        )
    }
    func cleanupExpiredItems() async throws {}
    var currentStorageLocationPath: String { "/tmp/PreviewShelf" }
    var isUsingCustomStorageLocation: Bool { false }
    func setStorageLocation(_ url: URL) async throws {}
    func resetStorageLocation() async throws {}
    func createShelfItem(from url: URL) async throws -> ShelfItem {
        ShelfItem.from(fileURL: url)
    }
    func createShelfItem(from clipboardItem: ClipboardItem) async throws -> ShelfItem {
        ShelfItem.from(clipboardItem: clipboardItem) ?? ShelfItem(
            name: "Unknown",
            fileURL: nil,
            fileType: .unknown,
            dateAdded: Date(),
            thumbnail: nil
        )
    }
    func openItem(_ item: ShelfItem) async throws {}
    func showInFinder(_ item: ShelfItem) async throws {}
    func quickLookItem(_ item: ShelfItem) async throws {}
    func shareItem(_ item: ShelfItem, using serviceType: NSSharingService.Name?) async throws {}
}

/// Stub `FileSharingService` for previews and tests. Swallows every share
/// request silently so a preview doesn't accidentally pop the real macOS
/// AirDrop / Messages UI while the user is editing layout.
@MainActor
class PreviewMockFileSharingService: FileSharingServiceProtocol {
    func shareItem(_ item: ShelfItem, using service: SharingServiceInfo) async throws {}
    func showSharingPicker(for item: ShelfItem, from view: NSView) async throws {}
}

@MainActor
class PreviewMockBatteryService: BatteryServiceProtocol {
    @Published private var publishedBatteryInfo: BatteryInfo = BatteryInfo(
        level: 0.8,
        isCharging: false,
        isPluggedIn: true,
        timeRemaining: 7200,
        temperature: 25.0,
        powerSourceType: .acPower,
        chargingState: .notCharging,
        lastUpdated: Date()
    )

    var batteryInfo: BatteryInfo { publishedBatteryInfo }
    var batteryInfoPublisher: Published<BatteryInfo>.Publisher { $publishedBatteryInfo }
    var batteryLevel: Double { batteryInfo.level }
    var isCharging: Bool { batteryInfo.isCharging }
    var timeRemaining: TimeInterval { batteryInfo.timeRemaining }
    var isPluggedIn: Bool { batteryInfo.isPluggedIn }

    func startMonitoring() async {}
    func stopMonitoring() async {}
    func refreshBatteryInfo() async {}
    func getBatteryHealth() async -> BatteryHealth? { nil }
    func isLowPowerModeEnabled() async -> Bool { false }
}

@MainActor
class PreviewMockBluetoothService: BluetoothServiceProtocol {
    var bluetoothState: CBManagerState = .poweredOn
    var connectedDevices: [BluetoothDevice] = []
    var availableDevices: [BluetoothDevice] = []
    var isScanning: Bool = false
    var isBluetoothAvailable: Bool = true
    var connectedDevicesPublisher: Published<[BluetoothDevice]>.Publisher { $publishedConnectedDevices }
    var bluetoothStatePublisher: Published<CBManagerState>.Publisher { $publishedBluetoothState }
    @Published private var publishedConnectedDevices: [BluetoothDevice] = []
    @Published private var publishedBluetoothState: CBManagerState = .poweredOn

    func startScanning() async {}
    func stopScanning() async {}
    func connect(to device: BluetoothDevice) async throws {}
    func disconnect(from device: BluetoothDevice) async throws {}
    func refreshConnectedDevices() async {}
    func getBatteryLevel(for device: BluetoothDevice) async -> Double? { nil }
    func getSignalStrength(for device: BluetoothDevice) async -> Int? { nil }
    func supportsBatteryLevel(_ device: BluetoothDevice) async -> Bool { false }
}
