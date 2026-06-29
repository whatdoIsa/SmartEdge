import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import os

@MainActor
final class ShelfViewModel: ObservableObject {
    // MARK: - Published Properties (All UI State)
    @Published private(set) var shelfItems: [ShelfItem] = []
    @Published private(set) var selectedItems: Set<ShelfItem.ID> = []
    @Published private(set) var isDropTargeted = false
    @Published private(set) var isProcessing = false
    @Published private(set) var lastUpdatedTime = Date()
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private let shelfService: ShelfServiceProtocol
    private let fileSharingService: any FileSharingServiceProtocol
    private let maxShelfItems = 10

    // MARK: - Initialization
    // Default value for `fileSharingService` would be cleaner but
    // `ServiceContainer.shared` is @MainActor-isolated and Swift 6 forbids
    // referencing it from a nonisolated default-argument expression. The
    // factory in `ServiceContainer.createShelfViewModel()` injects it
    // explicitly instead.
    init(
        shelfService: ShelfServiceProtocol,
        fileSharingService: any FileSharingServiceProtocol
    ) {
        self.shelfService = shelfService
        self.fileSharingService = fileSharingService
        setupBindings()
        loadShelfItems()
    }
    
    // MARK: - Public Methods
    /// Add files dropped via the AppKit drag destination (the notch overlay).
    /// Wraps the URLs as item providers so they flow through the same
    /// validate → copy-to-container → persist pipeline as a SwiftUI drop.
    func handleDroppedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let providers = urls.map { NSItemProvider(object: $0 as NSURL) }
        _ = handleDrop(providers: providers)
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        
        isProcessing = true
        
        Task {
            do {
                let newItems = try await processDroppedItems(providers)
                await MainActor.run {
                    addItems(newItems)
                    isProcessing = false
                    isDropTargeted = false
                }
            } catch {
                await MainActor.run {
                    AppLogger.shelf.error("Failed to process dropped items: \(error.localizedDescription, privacy: .public)")
                    isProcessing = false
                    isDropTargeted = false
                }
            }
        }
        
        return true
    }
    
    func selectItem(_ item: ShelfItem) {
        if selectedItems.contains(item.id) {
            selectedItems.remove(item.id)
        } else {
            selectedItems.insert(item.id)
        }
        
        updateItemSelection()
    }
    
    func openItem(_ item: ShelfItem) {
        Task {
            do {
                try await shelfService.openItem(item)
            } catch {
                AppLogger.shelf.error("Failed to open item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func showInFinder(_ item: ShelfItem) {
        Task {
            do {
                try await shelfService.showInFinder(item)
            } catch {
                AppLogger.shelf.error("Failed to show item in Finder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func quickLookItem(_ item: ShelfItem) {
        Task {
            do {
                try await shelfService.quickLookItem(item)
            } catch {
                AppLogger.shelf.error("Failed to Quick Look item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func removeItem(_ item: ShelfItem) {
        Task {
            do {
                try await shelfService.removeItem(item.id)
                await MainActor.run {
                    shelfItems.removeAll { $0.id == item.id }
                    selectedItems.remove(item.id)
                    lastUpdatedTime = Date()
                }
            } catch {
                AppLogger.shelf.error("Failed to remove item: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Sharing
    //
    // These thin wrappers route every share path through the shared
    // `FileSharingService`, which centralises NSSharingService usage so
    // policy changes (e.g. switch from AirDrop direct-perform to the
    // NSSharingServicePicker that shows all options) only touch one site.
    // All three return immediately because NSSharingService.perform is
    // fire-and-forget — the macOS sharing UI takes over from there.

    func shareViaAirDrop(_ item: ShelfItem) {
        Task { @MainActor [weak self] in
            do {
                try await self?.fileSharingService.shareItem(item, using: SharingServiceInfo(
                    name: "AirDrop",
                    displayName: "AirDrop",
                    icon: nil,
                    serviceType: .sendViaAirDrop
                ))
            } catch {
                AppLogger.shelf.error("AirDrop share failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func shareViaMessages(_ item: ShelfItem) {
        Task { @MainActor [weak self] in
            do {
                try await self?.fileSharingService.shareItem(item, using: SharingServiceInfo(
                    name: "Messages",
                    displayName: "Messages",
                    icon: nil,
                    serviceType: .composeMessage
                ))
            } catch {
                AppLogger.shelf.error("Messages share failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func copyToClipboard(_ item: ShelfItem) {
        guard let url = item.fileURL else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }
    
    func clearAllItems() {
        Task {
            do {
                try await shelfService.clearAllItems()
                await MainActor.run {
                    shelfItems.removeAll()
                    selectedItems.removeAll()
                    lastUpdatedTime = Date()
                }
            } catch {
                AppLogger.shelf.error("Failed to clear all items: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func createDragItem(for item: ShelfItem) -> NSItemProvider {
        let itemProvider = NSItemProvider()
        
        if let url = item.fileURL {
            itemProvider.registerFileRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                fileOptions: [],
                visibility: .all
            ) { completion in
                completion(url, true, nil)
                return nil
            }
        }
        
        return itemProvider
    }
    
    func refreshShelf() {
        loadShelfItems()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Listen to shelf service changes
        shelfService.shelfItemsPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$shelfItems)
    }
    
    private func loadShelfItems() {
        Task {
            do {
                let items = try await shelfService.getAllItems()
                await MainActor.run {
                    shelfItems = Array(items.prefix(maxShelfItems))
                    lastUpdatedTime = Date()
                }
            } catch {
                AppLogger.shelf.error("Failed to load shelf items: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func processDroppedItems(_ providers: [NSItemProvider]) async throws -> [ShelfItem] {
        var newItems: [ShelfItem] = []

        for provider in providers {
            // Respect task cancellation between providers so a slow drop doesn't
            // wedge the UI if the user dismisses the shelf mid-flight.
            try Task.checkCancellation()

            guard provider.canLoadObject(ofClass: URL.self) else { continue }

            // Per-provider partial failure: one bad URL shouldn't lose the rest.
            do {
                let url = try await loadURL(from: provider)
                let item = try await shelfService.createShelfItem(from: url)
                newItems.append(item)
            } catch {
                AppLogger.shelf.error(
                    "Failed to add dropped item: \(error.localizedDescription, privacy: .public)"
                )
                continue
            }
        }

        return newItems
    }

    /// Wraps NSItemProvider's completion-based `loadObject(ofClass: URL.self)`
    /// in async/await with safe continuation resume (exactly once).
    private func loadURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            // Guard against the SDK invoking the completion handler twice
            // (rare but documented for some provider sources).
            let state = ResumeOnce()
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                state.resume {
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else if let url = url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: ShelfError.invalidDropItem)
                    }
                }
            }
        }
    }

    /// Tiny helper that ensures a continuation resume runs at most once,
    /// even if the underlying completion handler fires multiple times.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func resume(_ work: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            work()
        }
    }
    
    private func addItems(_ newItems: [ShelfItem]) {
        let availableSlots = maxShelfItems - shelfItems.count
        let itemsToAdd = Array(newItems.prefix(availableSlots))
        
        shelfItems.append(contentsOf: itemsToAdd)
        lastUpdatedTime = Date()
        
        // Persist to service
        Task {
            do {
                for item in itemsToAdd {
                    try await shelfService.addItem(item)
                }
            } catch {
                AppLogger.shelf.error("Failed to persist shelf items: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func updateItemSelection() {
        for i in 0..<shelfItems.count {
            shelfItems[i].isSelected = selectedItems.contains(shelfItems[i].id)
        }
    }
    
    deinit {
        // Cancel all Combine subscriptions
        cancellables.removeAll()
        
        // Cancel any ongoing file operations by releasing references
        // The Task-based async operations will be cancelled when the view model is deallocated
    }
}

// MARK: - Supporting Types
// ShelfItem, FileType, and ShelfError are defined in ShelfModels.swift