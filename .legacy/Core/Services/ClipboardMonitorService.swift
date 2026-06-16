import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

actor ClipboardMonitorService: ClipboardMonitorServiceProtocol {
    // MARK: - Published Properties
    private let _clipboardUpdates = PassthroughSubject<ClipboardItem, Never>()
    nonisolated var clipboardUpdatesPublisher: AnyPublisher<ClipboardItem, Never> {
        _clipboardUpdates.eraseToAnyPublisher()
    }
    
    // MARK: - Private Properties
    private var monitorTimer: Timer?
    private var lastChangeCount: Int
    private var clipboardHistory: [ClipboardItem] = []
    private let maxHistoryItems = 50
    private let pasteboard = NSPasteboard.general
    
    // MARK: - Initialization
    init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() async {
        await stopMonitoring() // Ensure no duplicate monitoring
        
        await MainActor.run {
            monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    await self?.checkClipboardChanges()
                }
            }
        }
    }
    
    func stopMonitoring() async {
        await MainActor.run {
            monitorTimer?.invalidate()
            monitorTimer = nil
        }
    }
    
    func getCurrentClipboard() async -> ClipboardItem? {
        return await extractClipboardContent()
    }
    
    func getClipboardHistory() async -> [ClipboardItem] {
        return clipboardHistory
    }
    
    func clearHistory() async {
        clipboardHistory.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func checkClipboardChanges() async {
        let currentChangeCount = await MainActor.run { pasteboard.changeCount }
        
        guard currentChangeCount != lastChangeCount else { return }
        
        lastChangeCount = currentChangeCount
        
        guard let clipboardItem = await extractClipboardContent() else { return }
        
        // Add to history
        clipboardHistory.insert(clipboardItem, at: 0)
        if clipboardHistory.count > maxHistoryItems {
            clipboardHistory.removeLast()
        }
        
        // Notify subscribers
        _clipboardUpdates.send(clipboardItem)
    }
    
    @MainActor
    private func extractClipboardContent() async -> ClipboardItem? {
        guard let types = pasteboard.types, !types.isEmpty else { return nil }
        
        let content = extractContent(from: pasteboard, types: types)
        
        return ClipboardItem(
            timestamp: Date(),
            content: content,
            source: extractSourceApplication()
        )
    }
    
    @MainActor
    private func extractContent(from pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> ClipboardContent {
        // Priority order: Files > URLs > Images > Text > Unknown
        
        // Check for file URLs first
        if types.contains(.fileURL) {
            if let fileURLs = extractFileURLs(from: pasteboard), !fileURLs.isEmpty {
                return .fileURLs(fileURLs)
            }
        }
        
        // Check for URLs
        if types.contains(.URL) {
            if let urlString = pasteboard.string(forType: .URL),
               let url = URL(string: urlString) {
                return .url(url)
            }
        }
        
        // Check for images
        if types.contains(.png) || types.contains(.tiff) {
            if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
               let image = NSImage(data: imageData) {
                return .image(image)
            }
        }
        
        // Check for text
        if types.contains(.string) {
            if let string = pasteboard.string(forType: .string), !string.isEmpty {
                // Check if it's a URL in text form
                if let url = URL(string: string), url.scheme != nil {
                    return .url(url)
                }
                return .text(string)
            }
        }
        
        return .unknown
    }
    
    @MainActor
    private func extractFileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        guard let propertyList = pasteboard.propertyList(forType: .fileURL) as? [String] else {
            return nil
        }
        
        let urls = propertyList.compactMap { URL(string: $0) }
        return urls.isEmpty ? nil : urls
    }
    
    private func extractSourceApplication() -> String? {
        // Note: Getting the source application requires private APIs or accessibility permissions
        // For now, return nil. In a full implementation, we could use:
        // - Accessibility APIs to get the frontmost application
        // - NSWorkspace shared workspace notifications
        // - System events monitoring
        return nil
    }
    
    deinit {
        Task { @MainActor in
            monitorTimer?.invalidate()
        }
    }
}

// MARK: - NSPasteboard.PasteboardType Extensions

extension NSPasteboard.PasteboardType {
    static let fileURL = NSPasteboard.PasteboardType("public.file-url")
    static let URL = NSPasteboard.PasteboardType(kUTTypeURL as String)
}

// MARK: - ClipboardContent Extensions for Pasteboard

extension ClipboardContent {
    func writeToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch self {
        case .text(let string):
            pasteboard.setString(string, forType: .string)
            
        case .url(let url):
            pasteboard.setString(url.absoluteString, forType: .URL)
            if url.isFileURL {
                pasteboard.setPropertyList([url.absoluteString], forType: .fileURL)
            }
            
        case .image(let image):
            if let tiffData = image.tiffRepresentation {
                pasteboard.setData(tiffData, forType: .tiff)
            }
            
        case .fileURLs(let urls):
            let urlStrings = urls.map(\.absoluteString)
            pasteboard.setPropertyList(urlStrings, forType: .fileURL)
            
        case .unknown:
            break // Cannot write unknown content
        }
    }
    
    var canWriteToClipboard: Bool {
        switch self {
        case .text, .url, .image, .fileURLs:
            return true
        case .unknown:
            return false
        }
    }
}