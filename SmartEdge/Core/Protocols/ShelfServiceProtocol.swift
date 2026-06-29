import Foundation
import Combine
import AppKit

// MARK: - ShelfServiceProtocol

@MainActor
protocol ShelfServiceProtocol {
    var shelfItemsPublisher: Published<[ShelfItem]>.Publisher { get }

    // MARK: - Item Management
    func getAllItems() async throws -> [ShelfItem]
    func addItem(_ item: ShelfItem) async throws
    func removeItem(_ itemId: UUID) async throws
    func clearAllItems() async throws

    // MARK: - Item Creation
    func createShelfItem(from url: URL) async throws -> ShelfItem
    func createShelfItem(from clipboardItem: ClipboardItem) async throws -> ShelfItem

    // MARK: - File Operations
    func openItem(_ item: ShelfItem) async throws
    func showInFinder(_ item: ShelfItem) async throws
    func quickLookItem(_ item: ShelfItem) async throws
    func shareItem(_ item: ShelfItem, using serviceType: NSSharingService.Name?) async throws

    // MARK: - Drag & Drop
    nonisolated func acceptsDroppedFiles(_ urls: [URL]) -> Bool
    func processDroppedFiles(_ urls: [URL]) async throws -> [ShelfItem]

    // MARK: - Storage Management
    func getStorageUsage() async throws -> ShelfStorageInfo
    func cleanupExpiredItems() async throws

    // MARK: - Storage Location
    /// Filesystem path of the active storage directory (for display).
    var currentStorageLocationPath: String { get }
    /// True when files live in a user-chosen folder rather than the container.
    var isUsingCustomStorageLocation: Bool { get }
    /// Relocate storage to a user-chosen folder (migrates existing files).
    func setStorageLocation(_ url: URL) async throws
    /// Move storage back to the default container location.
    func resetStorageLocation() async throws
}

// ClipboardMonitorServiceProtocol is defined in ServiceProtocols.swift

// MARK: - FileSharingServiceProtocol

@MainActor
protocol FileSharingServiceProtocol {
    func shareItem(_ item: ShelfItem, using service: SharingServiceInfo) async throws
    func showSharingPicker(for item: ShelfItem, from view: NSView) async throws
}

// MARK: - Supporting Models

struct SharingServiceInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let displayName: String
    let icon: NSImage?
    let serviceType: NSSharingService.Name
    
    static func == (lhs: SharingServiceInfo, rhs: SharingServiceInfo) -> Bool {
        lhs.serviceType == rhs.serviceType
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(serviceType.rawValue)
    }
}

// ClipboardItem, ClipboardContent, ShelfStorageInfo are defined in ShelfModels.swift