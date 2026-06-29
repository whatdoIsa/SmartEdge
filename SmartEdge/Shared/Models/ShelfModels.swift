import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ShelfItem Model

struct ShelfItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    /// var so a storage relocation can repoint the file in place while
    /// preserving `id` (selection/identity stay stable across a move).
    var fileURL: URL?
    let fileType: FileType
    let dateAdded: Date
    let thumbnail: NSImage?
    var isSelected: Bool = false
    
    var systemIcon: String {
        fileType.systemIcon
    }
    
    var iconColor: Color {
        fileType.iconColor
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id
    }
    
    static func from(fileURL: URL) -> ShelfItem {
        let name = fileURL.lastPathComponent
        let fileType = FileType.from(fileExtension: fileURL.pathExtension)
        
        return ShelfItem(
            name: name,
            fileURL: fileURL,
            fileType: fileType,
            dateAdded: Date(),
            thumbnail: nil,
            isSelected: false
        )
    }
}

// MARK: - FileType
enum FileType: String, CaseIterable, Codable {
    case document = "document"
    case image = "image"
    case video = "video"
    case audio = "audio"
    case archive = "archive"
    case application = "application"
    case folder = "folder"
    case unknown = "unknown"
    
    var systemIcon: String {
        switch self {
        case .document: return "doc.text.fill"
        case .image: return "photo.fill"
        case .video: return "video.fill"
        case .audio: return "music.note"
        case .archive: return "archivebox.fill"
        case .application: return "app.fill"
        case .folder: return "folder.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .document: return .blue
        case .image: return .green
        case .video: return .red
        case .audio: return .purple
        case .archive: return .orange
        case .application: return .gray
        case .folder: return .blue
        case .unknown: return .gray
        }
    }
    
    static func from(fileExtension: String) -> FileType {
        let ext = fileExtension.lowercased()
        switch ext {
        case "txt", "rtf", "pdf", "doc", "docx", "pages":
            return .document
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic":
            return .image
        case "mp4", "mov", "avi", "mkv", "wmv":
            return .video
        case "mp3", "wav", "aac", "flac", "m4a":
            return .audio
        case "zip", "rar", "7z", "tar", "gz":
            return .archive
        case "app", "dmg", "pkg":
            return .application
        default:
            return .unknown
        }
    }
}

// MARK: - Shelf Errors
enum ShelfError: LocalizedError {
    case invalidDropItem
    case storageQuotaExceeded
    case fileNotFound
    case accessDenied
    case unsupportedFileType
    case networkError
    case shelfFull
    case persistenceFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidDropItem:
            return "Invalid item dropped"
        case .storageQuotaExceeded:
            return "Storage quota exceeded"
        case .fileNotFound:
            return "File not found"
        case .accessDenied:
            return "Access denied"
        case .unsupportedFileType:
            return "Unsupported file type"
        case .networkError:
            return "Network error"
        case .shelfFull:
            return "Shelf is full"
        case .persistenceFailed:
            return "Failed to save data"
        }
    }
}

// MARK: - Storage Info
struct ShelfStorageInfo {
    let totalSizeBytes: Int64
    let itemCount: Int
    let oldestItemDate: Date?
    let maxSizeBytes: Int64
    let isNearLimit: Bool
    
    var usagePercentage: Double {
        guard maxSizeBytes > 0 else { return 0 }
        return Double(totalSizeBytes) / Double(maxSizeBytes) * 100
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
    
    var formattedMaxSize: String {
        ByteCountFormatter.string(fromByteCount: maxSizeBytes, countStyle: .file)
    }
}

// MARK: - ClipboardItem
struct ClipboardItem: Identifiable, Hashable {
    let id = UUID()
    let content: ClipboardContent
    let timestamp: Date
    let source: String?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
    
    enum ClipboardContent: Hashable {
        case text(String)
        case image(NSImage)
        case file(URL)
        case url(URL)
        case fileURLs([URL])
        case unknown
        
        var displayText: String {
            switch self {
            case .text(let text):
                return text.prefix(100).description
            case .url(let url):
                return url.absoluteString
            case .image:
                return "Image"
            case .file(let url):
                return url.lastPathComponent
            case .fileURLs(let urls):
                return urls.map(\.lastPathComponent).joined(separator: ", ")
            case .unknown:
                return "Unknown content"
            }
        }
        
        var contentType: String {
            switch self {
            case .text:
                return "Text"
            case .url:
                return "URL"
            case .image:
                return "Image"
            case .file:
                return "File"
            case .fileURLs:
                return "Files"
            case .unknown:
                return "Unknown"
            }
        }
    }
}

// MARK: - Extensions

extension ShelfItem {
    // MARK: - Additional Properties for Service Layer
    
    var fileSize: Int64? {
        guard let fileURL = fileURL else { return nil }
        
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            return Int64(resourceValues.fileSize ?? 0)
        } catch {
            return nil
        }
    }
    
    var lastModified: Date? {
        guard let fileURL = fileURL else { return nil }
        
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            return resourceValues.contentModificationDate
        } catch {
            return nil
        }
    }
    
    var isAccessible: Bool {
        guard let fileURL = fileURL else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    var utType: UTType {
        guard let fileURL = fileURL else { return .data }
        
        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.contentTypeKey])
            return resourceValues.contentType ?? .data
        } catch {
            return UTType(filenameExtension: fileURL.pathExtension) ?? .data
        }
    }
    
    // MARK: - Convenience Initializers
    
    static func from(fileURL: URL, thumbnail: NSImage? = nil) -> ShelfItem {
        let name = fileURL.lastPathComponent
        let fileType = FileType.from(fileExtension: fileURL.pathExtension)
        
        return ShelfItem(
            name: name,
            fileURL: fileURL,
            fileType: fileType,
            dateAdded: Date(),
            thumbnail: thumbnail
        )
    }
    
    static func from(clipboardItem: ClipboardItem) -> ShelfItem? {
        switch clipboardItem.content {
        case .text:
            return ShelfItem(
                name: "Clipboard Text",
                fileURL: nil,
                fileType: .document,
                dateAdded: clipboardItem.timestamp,
                thumbnail: nil
            )
            
        case .url(let url):
            return ShelfItem(
                name: url.lastPathComponent.isEmpty ? url.host ?? "Link" : url.lastPathComponent,
                fileURL: url,
                fileType: url.isFileURL ? FileType.from(fileExtension: url.pathExtension) : .document,
                dateAdded: clipboardItem.timestamp,
                thumbnail: nil
            )
            
        case .file(let url):
            return ShelfItem(
                name: url.lastPathComponent,
                fileURL: url,
                fileType: FileType.from(fileExtension: url.pathExtension),
                dateAdded: clipboardItem.timestamp,
                thumbnail: nil
            )
            
        case .fileURLs(let urls):
            guard let firstURL = urls.first else { return nil }
            let name = urls.count > 1 ? "\(urls.count) Files" : firstURL.lastPathComponent
            return ShelfItem(
                name: name,
                fileURL: firstURL,
                fileType: FileType.from(fileExtension: firstURL.pathExtension),
                dateAdded: clipboardItem.timestamp,
                thumbnail: nil
            )
            
        case .image:
            return ShelfItem(
                name: "Clipboard Image",
                fileURL: nil,
                fileType: .image,
                dateAdded: clipboardItem.timestamp,
                thumbnail: nil
            )
            
        case .unknown:
            return nil
        }
    }
}

// MARK: - FileType Extensions

extension FileType {
    var allowedUTTypes: [UTType] {
        switch self {
        case .document:
            return [.text, .pdf, .rtf, .html, .xml, .json]
        case .image:
            return [.image, .jpeg, .png, .gif, .bmp, .tiff, .heic, .webP]
        case .video:
            return [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi]
        case .audio:
            return [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        case .archive:
            return [.zip, .gzip, .bz2]
        case .application:
            return [.application, .executable]
        case .folder:
            return [.folder, .directory]
        case .unknown:
            return [.data, .item]
        }
    }
    
    var maxFileSize: Int64 {
        switch self {
        case .image:
            return 50 * 1024 * 1024  // 50MB for images
        case .video:
            return 500 * 1024 * 1024 // 500MB for videos
        case .audio:
            return 100 * 1024 * 1024 // 100MB for audio
        case .document:
            return 20 * 1024 * 1024  // 20MB for documents
        case .archive:
            return 200 * 1024 * 1024 // 200MB for archives
        case .application:
            return 1024 * 1024 * 1024 // 1GB for applications
        case .folder:
            return Int64.max // No limit for folders (size calculated differently)
        case .unknown:
            return 10 * 1024 * 1024  // 10MB for unknown files
        }
    }
    
    static func canAccept(utType: UTType) -> Bool {
        return FileType.allCases.contains { fileType in
            fileType.allowedUTTypes.contains { $0.conforms(to: utType) }
        }
    }
}

// MARK: - Shelf Configuration

struct ShelfConfiguration {
    let maxItems: Int
    let maxTotalSize: Int64
    let itemExpiryDays: Int
    let tempDirectoryName: String
    let allowedFileTypes: Set<FileType>
    let autoCleanupEnabled: Bool
    
    static let `default` = ShelfConfiguration(
        maxItems: 20,
        maxTotalSize: 2 * 1024 * 1024 * 1024, // 2GB total
        itemExpiryDays: 30,
        tempDirectoryName: "SmartEdgeShelf",
        allowedFileTypes: Set(FileType.allCases.filter { $0 != .unknown }),
        autoCleanupEnabled: true
    )
}

// MARK: - Shelf Events

enum ShelfEvent {
    case itemAdded(ShelfItem)
    case itemRemoved(UUID)
    case itemOpened(ShelfItem)
    case storageNearLimit(ShelfStorageInfo)
    case cleanupPerformed(removedCount: Int)
    case errorOccurred(ShelfError)
}

// MARK: - Extended ShelfError

extension ShelfError {
    var recoverySuggestion: String? {
        switch self {
        case .invalidDropItem:
            return "Try dropping a supported file type"
        case .fileNotFound:
            return "Ensure the file still exists and is accessible"
        case .unsupportedFileType:
            return "Check the list of supported file types in settings"
        case .shelfFull:
            return "Remove old items or increase the shelf size limit"
        case .persistenceFailed:
            return "Check disk space and file permissions"
        case .storageQuotaExceeded:
            return "Free up space or increase storage quota"
        case .accessDenied:
            return "Check file permissions and security settings"
        case .networkError:
            return "Check your network connection and try again"
        }
    }
}

// MARK: - Thumbnail Generation

struct ThumbnailGenerator {
    static func generateThumbnail(for item: ShelfItem, size: CGSize = CGSize(width: 64, height: 64)) async -> NSImage? {
        guard let fileURL = item.fileURL, item.isAccessible else { return nil }
        
        switch item.fileType {
        case .image:
            return await generateImageThumbnail(url: fileURL, size: size)
        case .video:
            return await generateVideoThumbnail(url: fileURL, size: size)
        case .document:
            return await generateDocumentThumbnail(url: fileURL, size: size)
        default:
            return generateIconThumbnail(for: item.fileType, size: size)
        }
    }
    
    private static func generateImageThumbnail(url: URL, size: CGSize) async -> NSImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return resizeImage(image, to: size)
    }
    
    private static func generateVideoThumbnail(url: URL, size: CGSize) async -> NSImage? {
        // For now, return a video icon. In a full implementation, we'd use AVAssetImageGenerator
        return generateIconThumbnail(for: .video, size: size)
    }
    
    private static func generateDocumentThumbnail(url: URL, size: CGSize) async -> NSImage? {
        // For now, return a document icon. In a full implementation, we'd use QLThumbnailGenerator
        return generateIconThumbnail(for: .document, size: size)
    }
    
    private static func generateIconThumbnail(for fileType: FileType, size: CGSize) -> NSImage? {
        let iconName = fileType.systemIcon
        guard let systemImage = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) else {
            return nil
        }
        
        return resizeImage(systemImage, to: size)
    }
    
    private static func resizeImage(_ image: NSImage, to size: CGSize) -> NSImage {
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        resizedImage.unlockFocus()
        return resizedImage
    }
}

// MARK: - File Security

struct FileSecurityManager {
    static func isFileAccessible(_ url: URL) -> Bool {
        guard url.isFileURL else { return true } // Non-file URLs are considered accessible
        
        return FileManager.default.fileExists(atPath: url.path) &&
               FileManager.default.isReadableFile(atPath: url.path)
    }
    
    static func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalidCharacters).joined(separator: "_")
    }
    
    static func isFileSizeAcceptable(_ url: URL, for fileType: FileType) -> Bool {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return false
        }
        
        return Int64(fileSize) <= fileType.maxFileSize
    }
    
    static func secureDeleteFile(at url: URL) throws {
        // For enhanced security, we could overwrite the file before deletion
        // For now, just use standard deletion
        try FileManager.default.removeItem(at: url)
    }
}