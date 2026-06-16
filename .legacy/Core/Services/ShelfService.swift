import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers
import QuickLook

@MainActor
final class ShelfService: ObservableObject, ShelfServiceProtocol {
    // MARK: - Published Properties
    @Published private var shelfItems: [ShelfItem] = []
    
    nonisolated var shelfItemsPublisher: Published<[ShelfItem]>.Publisher {
        $shelfItems
    }
    
    // MARK: - Private Properties
    private let configuration: ShelfConfiguration
    private let tempDirectory: URL
    private let metadataURL: URL
    private let clipboardMonitor: ClipboardMonitorServiceProtocol
    private let fileSharingService: FileSharingServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
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
        let shelfDir = appSupportDir.appendingPathComponent(configuration.tempDirectoryName)
        self.tempDirectory = shelfDir
        self.metadataURL = shelfDir.appendingPathComponent("shelf_metadata.json")
        
        // Initialize services
        self.clipboardMonitor = clipboardMonitor ?? ClipboardMonitorService()
        self.fileSharingService = fileSharingService ?? FileSharingService()
        
        setupDirectories()
        setupBindings()
        loadShelfItems()
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
        
        // Remove the file if it's in our temp directory
        if let fileURL = item.fileURL, fileURL.path.contains(tempDirectory.path) {
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
        // Remove all files in temp directory
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: tempDirectory.path) {
            let contents = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for url in contents where url.lastPathComponent != "shelf_metadata.json" {
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
        
        let fileType = FileType.from(url: url)
        
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
        
        await MainActor.run {
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
        
        await MainActor.run {
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
        
        await MainActor.run {
            let quickLookPanel = QLPreviewPanel.shared()
            // Note: Proper Quick Look implementation would require setting up a data source
            // For now, we'll fall back to opening the file
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
            let fileType = FileType.from(url: url)
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
    
    func getStorageUsage() async throws -> ShelfStorageInfo {
        await updateStorageInfo()
        return storageInfo
    }
    
    func cleanupExpiredItems() async throws {
        let expiryDate = Calendar.current.date(
            byAdding: .day,
            value: -configuration.itemExpiryDays,
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
        
        do {
            try fileManager.createDirectory(
                at: tempDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("Failed to create shelf directory: \(error)")
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
        
        // If file is already in our temp directory, don't copy
        if fileURL.path.contains(tempDirectory.path) {
            return item
        }
        
        // Create a unique filename in temp directory
        let filename = FileSecurityManager.sanitizeFileName(item.name)
        let tempFileURL = tempDirectory.appendingPathComponent(filename)
        
        // Copy file to temp directory
        try FileManager.default.copyItem(at: fileURL, to: tempFileURL)
        
        // Return updated item with new URL
        return ShelfItem(
            name: item.name,
            fileURL: tempFileURL,
            fileType: item.fileType,
            dateAdded: item.dateAdded,
            thumbnail: item.thumbnail
        )
    }
    
    private func createTemporaryFile(for text: String, withExtension ext: String) async throws -> URL {
        let filename = "clipboard_\(UUID().uuidString).\(ext)"
        let tempURL = tempDirectory.appendingPathComponent(filename)
        
        try text.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
    
    private func createTemporaryFile(for image: NSImage) async throws -> URL {
        let filename = "clipboard_\(UUID().uuidString).png"
        let tempURL = tempDirectory.appendingPathComponent(filename)
        
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
        
        storageInfo = ShelfStorageInfo(
            totalSizeBytes: totalSize,
            itemCount: shelfItems.count,
            oldestItemDate: oldestDate,
            maxSizeBytes: configuration.maxTotalSize,
            isNearLimit: totalSize > (configuration.maxTotalSize * 80 / 100) // 80% threshold
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
            print("Failed to load shelf metadata: \(error)")
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
        cancellables.removeAll()
        Task {
            await clipboardMonitor.stopMonitoring()
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