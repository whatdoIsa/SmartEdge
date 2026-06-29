import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers
import Quartz
import os

@MainActor
final class ShelfService: ObservableObject, ShelfServiceProtocol {
    // MARK: - Published Properties
    @Published private var shelfItems: [ShelfItem] = []
    
    nonisolated var shelfItemsPublisher: Published<[ShelfItem]>.Publisher {
        MainActor.assumeIsolated { $shelfItems }
    }
    
    // MARK: - Private Properties
    private let configuration: ShelfConfiguration
    /// Default storage inside the sandbox container — also where metadata
    /// always lives, and the target when the user resets the location.
    private let containerShelfDirectory: URL
    /// Where dropped files are actually copied. Defaults to
    /// `containerShelfDirectory`; may point at a user-chosen folder resolved
    /// from a security-scoped bookmark.
    private var filesDirectory: URL
    /// Held while a user-chosen (out-of-container) folder is active, so we can
    /// balance `startAccessingSecurityScopedResource` on change / teardown.
    private var securityScopedURL: URL?
    private let metadataURL: URL
    private let clipboardMonitor: ClipboardMonitorServiceProtocol
    private let fileSharingService: FileSharingServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    /// 1-hour periodic cleanup. Without it `cleanupExpiredItems` only ran
    /// on `addItem` — a user who hadn't dropped anything new in days could
    /// accumulate stale items past their retention window. 1h cadence is
    /// well-aligned with day-grained expiry (retention is in days).
    private var cleanupTimer: Timer?
    
    // Storage management
    private var storageInfo: ShelfStorageInfo = ShelfStorageInfo(
        totalSizeBytes: 0,
        itemCount: 0,
        oldestItemDate: nil,
        maxSizeBytes: ShelfConfiguration.default.maxTotalSize,
        isNearLimit: false
    )
    
    // MARK: - Initialization
    
    init(
        configuration: ShelfConfiguration = .default,
        clipboardMonitor: ClipboardMonitorServiceProtocol? = nil,
        fileSharingService: FileSharingServiceProtocol? = nil
    ) {
        self.configuration = configuration
        
        // Setup directories
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let containerDir = appSupportDir.appendingPathComponent(configuration.tempDirectoryName)
        self.containerShelfDirectory = containerDir
        // Metadata is an internal index — keep it in the container as a hidden
        // dotfile so a user-opened storage folder shows only their files.
        self.metadataURL = containerDir.appendingPathComponent(".shelf_metadata.json")
        // Provisionally default; resolved from the bookmark below (needs self).
        self.filesDirectory = containerDir

        // Initialize services
        self.clipboardMonitor = clipboardMonitor ?? ClipboardMonitorService()
        self.fileSharingService = fileSharingService ?? FileSharingService()

        self.filesDirectory = resolveStorageDirectory()
        migrateMetadataLocationIfNeeded()
        setupDirectories()
        setupBindings()
        loadShelfItems()
        startPeriodicCleanup()
    }

    /// Resolves the active files directory from a stored security-scoped
    /// bookmark, falling back to the container on any failure (and clearing the
    /// bad bookmark so we don't retry forever).
    private func resolveStorageDirectory() -> URL {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.shelfStorageBookmark) else {
            return containerShelfDirectory
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ), url.startAccessingSecurityScopedResource() else {
            AppLogger.shelf.error("Shelf storage bookmark unresolvable — using container")
            UserDefaults.standard.removeObject(forKey: SettingsKeys.shelfStorageBookmark)
            return containerShelfDirectory
        }
        securityScopedURL = url
        if isStale {
            if let fresh = try? url.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: SettingsKeys.shelfStorageBookmark)
            } else {
                AppLogger.shelf.error("Shelf storage bookmark is stale and could not be refreshed")
            }
        }
        return url
    }

    /// One-time rename of the legacy visible metadata file to the hidden name.
    private func migrateMetadataLocationIfNeeded() {
        let legacy = containerShelfDirectory.appendingPathComponent("shelf_metadata.json")
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: legacy.path),
              !fileManager.fileExists(atPath: metadataURL.path) else { return }
        try? fileManager.moveItem(at: legacy, to: metadataURL)
    }

    /// 1-hour periodic cleanup tick. Cheap — runs `cleanupExpiredItems`
    /// which is a date-filter + remove on a typically-small array, plus
    /// the size-based trim when storage is near cap.
    private func startPeriodicCleanup() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.configuration.autoCleanupEnabled else { return }
                await self.performAutoCleanup()
            }
        }
    }
    
    // MARK: - Public Methods - Item Management
    
    func getAllItems() async throws -> [ShelfItem] {
        return shelfItems
    }
    
    func addItem(_ item: ShelfItem) async throws {
        // Check if shelf is full
        guard shelfItems.count < configuration.maxItems else {
            throw ShelfError.shelfFull
        }
        
        // Check for duplicates
        if shelfItems.contains(where: { $0.fileURL == item.fileURL }) {
            return // Don't add duplicates
        }
        
        // Copy file to temp directory if it's a file URL
        let processedItem = try await processItemForStorage(item)
        
        // Add to shelf
        shelfItems.insert(processedItem, at: 0)
        
        // Update storage info
        await updateStorageInfo()
        
        // Persist changes
        try await persistShelfMetadata()
        
        // Auto-cleanup if needed
        if configuration.autoCleanupEnabled {
            await performAutoCleanup()
        }
    }
    
    func removeItem(_ itemId: UUID) async throws {
        guard let index = shelfItems.firstIndex(where: { $0.id == itemId }) else {
            return // Item not found, nothing to do
        }
        
        let item = shelfItems[index]
        
        // Remove the file if it's in our storage directory
        if let fileURL = item.fileURL, isInStorageDirectory(fileURL) {
            try? FileSecurityManager.secureDeleteFile(at: fileURL)
        }
        
        // Remove from shelf
        shelfItems.remove(at: index)
        
        // Update storage info
        await updateStorageInfo()
        
        // Persist changes
        try await persistShelfMetadata()
    }
    
    func clearAllItems() async throws {
        // Delete only the files the Shelf itself owns — never enumerate and
        // wipe the whole directory, which in a user-chosen folder would also
        // destroy the user's unrelated files (and the metadata index).
        for item in shelfItems {
            if let url = item.fileURL, isInStorageDirectory(url) {
                try? FileSecurityManager.secureDeleteFile(at: url)
            }
        }

        // Clear the shelf
        shelfItems.removeAll()
        
        // Update storage info
        await updateStorageInfo()
        
        // Persist changes
        try await persistShelfMetadata()
    }
    
    // MARK: - Public Methods - Item Creation
    
    func createShelfItem(from url: URL) async throws -> ShelfItem {
        // Validate file
        guard FileSecurityManager.isFileAccessible(url) else {
            throw ShelfError.fileNotFound
        }
        
        let fileType = FileType.from(fileExtension: url.pathExtension)
        
        // Check if file type is allowed
        guard configuration.allowedFileTypes.contains(fileType) else {
            throw ShelfError.unsupportedFileType
        }
        
        // Check file size
        guard FileSecurityManager.isFileSizeAcceptable(url, for: fileType) else {
            throw ShelfError.unsupportedFileType
        }
        
        // Generate thumbnail
        let thumbnail = await ThumbnailGenerator.generateThumbnail(
            for: ShelfItem.from(fileURL: url),
            size: CGSize(width: 64, height: 64)
        )
        
        return ShelfItem.from(fileURL: url, thumbnail: thumbnail)
    }
    
    func createShelfItem(from clipboardItem: ClipboardItem) async throws -> ShelfItem {
        guard let item = ShelfItem.from(clipboardItem: clipboardItem) else {
            throw ShelfError.invalidDropItem
        }
        
        // For clipboard items without file URLs, we might need to create temporary files
        switch clipboardItem.content {
        case .text(let text):
            let tempURL = try await createTemporaryFile(for: text, withExtension: "txt")
            return ShelfItem(
                name: "Clipboard Text",
                fileURL: tempURL,
                fileType: .document,
                dateAdded: clipboardItem.timestamp,
                thumbnail: await ThumbnailGenerator.generateThumbnail(
                    for: item,
                    size: CGSize(width: 64, height: 64)
                )
            )
            
        case .image(let image):
            let tempURL = try await createTemporaryFile(for: image)
            return ShelfItem(
                name: "Clipboard Image",
                fileURL: tempURL,
                fileType: .image,
                dateAdded: clipboardItem.timestamp,
                thumbnail: await ThumbnailGenerator.generateThumbnail(
                    for: item,
                    size: CGSize(width: 64, height: 64)
                )
            )
            
        default:
            return item
        }
    }
    
    // MARK: - Public Methods - File Operations
    
    func openItem(_ item: ShelfItem) async throws {
        guard let fileURL = item.fileURL else {
            throw ShelfError.fileNotFound
        }
        
        guard FileSecurityManager.isFileAccessible(fileURL) else {
            throw ShelfError.fileNotFound
        }
        
        _ = await MainActor.run {
            NSWorkspace.shared.open(fileURL)
        }
    }

    func showInFinder(_ item: ShelfItem) async throws {
        guard let fileURL = item.fileURL else {
            throw ShelfError.fileNotFound
        }

        guard FileSecurityManager.isFileAccessible(fileURL) else {
            throw ShelfError.fileNotFound
        }

        _ = await MainActor.run {
            NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
        }
    }
    
    func quickLookItem(_ item: ShelfItem) async throws {
        guard let fileURL = item.fileURL else {
            throw ShelfError.fileNotFound
        }
        
        guard FileSecurityManager.isFileAccessible(fileURL) else {
            throw ShelfError.fileNotFound
        }
        
        _ = await MainActor.run {
            _ = QLPreviewPanel.shared
            NSWorkspace.shared.open(fileURL)
        }
    }
    
    func shareItem(_ item: ShelfItem, using serviceType: NSSharingService.Name?) async throws {
        if let serviceType = serviceType {
            let service = SharingServiceInfo(
                name: serviceType.rawValue,
                displayName: serviceType.rawValue,
                icon: nil,
                serviceType: serviceType
            )
            try await fileSharingService.shareItem(item, using: service)
        } else {
            // Show sharing picker - would need a view reference
            throw ShelfError.invalidDropItem
        }
    }
    
    // MARK: - Public Methods - Drag & Drop
    
    func acceptsDroppedFiles(_ urls: [URL]) -> Bool {
        return urls.allSatisfy { url in
            let fileType = FileType.from(fileExtension: url.pathExtension)
            return configuration.allowedFileTypes.contains(fileType) &&
                   FileSecurityManager.isFileAccessible(url) &&
                   FileSecurityManager.isFileSizeAcceptable(url, for: fileType)
        }
    }
    
    func processDroppedFiles(_ urls: [URL]) async throws -> [ShelfItem] {
        var processedItems: [ShelfItem] = []
        
        for url in urls {
            guard acceptsDroppedFiles([url]) else { continue }
            
            let item = try await createShelfItem(from: url)
            processedItems.append(item)
        }
        
        return processedItems
    }
    
    // MARK: - Public Methods - Storage Management

    var currentStorageLocationPath: String { filesDirectory.path }

    /// Source of truth is the persisted bookmark, not the in-memory access
    /// flag — so the UI offers "Reset" whenever a custom folder is configured.
    var isUsingCustomStorageLocation: Bool {
        UserDefaults.standard.data(forKey: SettingsKeys.shelfStorageBookmark) != nil
    }

    /// Point the Shelf at a user-chosen folder. Existing files are copied over
    /// (collision-safe, never overwriting unrelated files), metadata is
    /// committed to the new locations BEFORE originals are removed, and access
    /// is persisted via a security-scoped bookmark so it survives relaunches.
    func setStorageLocation(_ url: URL) async throws {
        guard url.standardizedFileURL != filesDirectory.standardizedFileURL else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
            )
            try await commitRelocation(to: url, bookmark: bookmark, keepingAccessTo: accessing ? url : nil)
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    /// Move the Shelf back to the default container location.
    func resetStorageLocation() async throws {
        guard isUsingCustomStorageLocation else { return }
        try FileManager.default.createDirectory(at: containerShelfDirectory, withIntermediateDirectories: true)
        try await commitRelocation(to: containerShelfDirectory, bookmark: nil, keepingAccessTo: nil)
    }

    /// Shared relocation pipeline: copy → persist metadata → delete originals.
    /// `bookmark == nil` resets to the container; otherwise persists the
    /// bookmark. `keepingAccessTo` becomes the held security scope on success.
    private func commitRelocation(to newDir: URL, bookmark: Data?, keepingAccessTo newScope: URL?) async throws {
        let oldDir = filesDirectory
        let oldItems = shelfItems
        let migrated = try copyItems(oldItems, into: newDir)

        // Commit metadata pointing at the new locations BEFORE deleting
        // originals — a crash/throw here must not orphan every file.
        shelfItems = migrated
        do {
            try await persistShelfMetadata()
        } catch {
            shelfItems = oldItems
            for item in migrated { if let u = item.fileURL { try? FileManager.default.removeItem(at: u) } }
            throw error
        }

        if let bookmark {
            UserDefaults.standard.set(bookmark, forKey: SettingsKeys.shelfStorageBookmark)
        } else {
            UserDefaults.standard.removeObject(forKey: SettingsKeys.shelfStorageBookmark)
        }
        // Delete originals while the OLD scope is still active, then swap.
        deleteOriginals(oldItems, in: oldDir)
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = newScope
        filesDirectory = newDir
        await updateStorageInfo()
    }

    /// Copies each item's file into `dir` with collision-safe names, returning
    /// items repointed to their actual new URLs (id preserved). Never deletes
    /// or overwrites a file it didn't create. Does NOT remove originals.
    private func copyItems(_ items: [ShelfItem], into dir: URL) throws -> [ShelfItem] {
        let fileManager = FileManager.default
        return try items.map { item in
            guard let oldURL = item.fileURL, fileManager.fileExists(atPath: oldURL.path) else { return item }
            if oldURL.deletingLastPathComponent().standardizedFileURL == dir.standardizedFileURL {
                return item // already in the destination
            }
            let dest = uniqueDestinationURL(forName: oldURL.lastPathComponent, in: dir)
            try fileManager.copyItem(at: oldURL, to: dest)
            var moved = item
            moved.fileURL = dest
            return moved
        }
    }

    /// Removes the given items' files if they live directly in `oldDir`.
    private func deleteOriginals(_ items: [ShelfItem], in oldDir: URL) {
        let base = oldDir.standardizedFileURL.path
        for item in items {
            guard let url = item.fileURL,
                  url.deletingLastPathComponent().standardizedFileURL.path == base else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// A non-colliding URL in `dir` for `name`, suffixing "-1", "-2"… if taken.
    private func uniqueDestinationURL(forName name: String, in dir: URL) -> URL {
        let fileManager = FileManager.default
        var candidate = dir.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 1
        repeat {
            let suffixed = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            candidate = dir.appendingPathComponent(suffixed)
            index += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    /// True when `url` lives inside the active storage directory (proper path
    /// prefix, not a fragile substring match).
    private func isInStorageDirectory(_ url: URL) -> Bool {
        let base = filesDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == base || path.hasPrefix(base + "/")
    }

    func getStorageUsage() async throws -> ShelfStorageInfo {
        await updateStorageInfo()
        return storageInfo
    }
    
    func cleanupExpiredItems() async throws {
        // Settings override the static configuration default. Honors the
        // user's "Automatically delete old files" toggle — if they've
        // turned it off, expired-by-age items are kept indefinitely (size
        // cap still applies via `performAutoCleanup`'s 25% trim).
        let autoDelete = UserDefaults.standard.object(forKey: SettingsKeys.autoDeleteOldFiles) as? Bool ?? true
        guard autoDelete else { return }

        let retentionDays = UserDefaults.standard.double(forKey: SettingsKeys.shelfRetentionDays)
        let days = retentionDays > 0 ? Int(retentionDays) : configuration.itemExpiryDays

        let expiryDate = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: Date()
        ) ?? Date()

        let expiredItems = shelfItems.filter { $0.dateAdded < expiryDate }

        for item in expiredItems {
            try await removeItem(item.id)
        }
    }
    
    // MARK: - Private Methods - Setup
    
    private func setupDirectories() {
        let fileManager = FileManager.default
        // Both the active files dir AND the container dir must exist — metadata
        // always lives in the container even when files are stored elsewhere.
        for dir in Set([filesDirectory.path, containerShelfDirectory.path]).map({ URL(fileURLWithPath: $0) }) {
            do {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                AppLogger.shelf.error("Failed to create shelf directory: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func setupBindings() {
        // Monitor clipboard changes
        Task {
            await clipboardMonitor.startMonitoring()
        }
        
        // Optional: Auto-add clipboard items
        // clipboardMonitor.clipboardUpdatesPublisher
        //     .sink { [weak self] clipboardItem in
        //         Task { @MainActor in
        //             // Auto-add clipboard items if desired
        //         }
        //     }
        //     .store(in: &cancellables)
    }
    
    // MARK: - Private Methods - Storage Management
    
    private func processItemForStorage(_ item: ShelfItem) async throws -> ShelfItem {
        guard let fileURL = item.fileURL else { return item }
        
        // If file is already in our storage directory, don't copy
        if isInStorageDirectory(fileURL) {
            return item
        }

        // Collision-safe destination in the storage directory.
        let filename = FileSecurityManager.sanitizeFileName(item.name)
        let destinationURL = uniqueDestinationURL(forName: filename, in: filesDirectory)

        // Copy file into the storage directory
        try FileManager.default.copyItem(at: fileURL, to: destinationURL)

        // Return updated item with new URL
        return ShelfItem(
            name: item.name,
            fileURL: destinationURL,
            fileType: item.fileType,
            dateAdded: item.dateAdded,
            thumbnail: item.thumbnail
        )
    }
    
    private func createTemporaryFile(for text: String, withExtension ext: String) async throws -> URL {
        let filename = "clipboard_\(UUID().uuidString).\(ext)"
        let tempURL = filesDirectory.appendingPathComponent(filename)

        try text.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    private func createTemporaryFile(for image: NSImage) async throws -> URL {
        let filename = "clipboard_\(UUID().uuidString).png"
        let tempURL = filesDirectory.appendingPathComponent(filename)
        
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw ShelfError.persistenceFailed
        }
        
        try pngData.write(to: tempURL)
        return tempURL
    }
    
    private func updateStorageInfo() async {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0
        var oldestDate: Date?
        
        for item in shelfItems {
            if let fileURL = item.fileURL,
               let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path) {
                if let fileSize = attributes[.size] as? Int64 {
                    totalSize += fileSize
                }
            }
            
            if oldestDate == nil || item.dateAdded < oldestDate! {
                oldestDate = item.dateAdded
            }
        }
        
        // Fixed, generous cap — the Shelf is a convenience holding area, not a
        // metered store, so we don't expose an adjustable limit. Auto-cleanup
        // trims the oldest items only if this ceiling is ever approached.
        let effectiveMaxBytes = configuration.maxTotalSize

        storageInfo = ShelfStorageInfo(
            totalSizeBytes: totalSize,
            itemCount: shelfItems.count,
            oldestItemDate: oldestDate,
            maxSizeBytes: effectiveMaxBytes,
            isNearLimit: totalSize > (effectiveMaxBytes * 80 / 100) // 80% threshold
        )
    }
    
    private func performAutoCleanup() async {
        // Remove expired items
        try? await cleanupExpiredItems()
        
        // If still near limit, remove oldest items
        if storageInfo.isNearLimit && !shelfItems.isEmpty {
            let sortedItems = shelfItems.sorted { $0.dateAdded < $1.dateAdded }
            let itemsToRemove = sortedItems.prefix(max(1, shelfItems.count / 4)) // Remove 25% of oldest items
            
            for item in itemsToRemove {
                try? await removeItem(item.id)
            }
        }
    }
    
    // MARK: - Private Methods - Persistence
    
    private func loadShelfItems() {
        guard FileManager.default.fileExists(atPath: metadataURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: metadataURL)
            let metadata = try JSONDecoder().decode(ShelfMetadata.self, from: data)
            
            // Validate that files still exist
            let validItems = metadata.items.filter { item in
                guard let fileURL = item.fileURL else { return true }
                return FileSecurityManager.isFileAccessible(fileURL)
            }
            
            self.shelfItems = validItems
            
            Task {
                await updateStorageInfo()
            }
        } catch {
            AppLogger.shelf.error("Failed to load shelf metadata: \(error.localizedDescription, privacy: .public)")
            self.shelfItems = []
        }
    }
    
    private func persistShelfMetadata() async throws {
        let metadata = ShelfMetadata(items: shelfItems, lastUpdated: Date())
        
        do {
            let data = try JSONEncoder().encode(metadata)
            try data.write(to: metadataURL)
        } catch {
            throw ShelfError.persistenceFailed
        }
    }
    
    deinit {
        cleanupTimer?.invalidate()
        cancellables.removeAll()
        securityScopedURL?.stopAccessingSecurityScopedResource()
        let monitor = clipboardMonitor
        Task {
            await monitor.stopMonitoring()
        }
    }
}

// MARK: - Supporting Models

private struct ShelfMetadata: Codable {
    let items: [ShelfItem]
    let lastUpdated: Date
}

// Make ShelfItem Codable for persistence
extension ShelfItem: Codable {
    enum CodingKeys: String, CodingKey {
        case name, fileURL, fileType, dateAdded
        // Note: NSImage (thumbnail) is not easily Codable, so we skip it
        // Thumbnails will be regenerated when needed
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(fileURL, forKey: .fileURL)
        try container.encode(fileType, forKey: .fileType)
        try container.encode(dateAdded, forKey: .dateAdded)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        fileURL = try container.decode(URL?.self, forKey: .fileURL)
        fileType = try container.decode(FileType.self, forKey: .fileType)
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        thumbnail = nil // Will be generated when needed
        isSelected = false
    }
}