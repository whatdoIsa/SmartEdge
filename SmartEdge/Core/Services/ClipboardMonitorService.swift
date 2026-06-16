import Foundation
import Combine
import AppKit

@MainActor
final class ClipboardMonitorService: ObservableObject, ClipboardMonitorServiceProtocol {
    // MARK: - Private Properties
    private var monitorTimer: Timer?
    private var lastChangeCount: Int
    private let pasteboard = NSPasteboard.general
    private let pollInterval: TimeInterval = 0.7
    private let maxHistory = 30

    @Published private(set) var history: [ClipboardItem] = []

    // MARK: - Protocol Properties
    private let _clipboardUpdatesSubject = PassthroughSubject<ClipboardItem, Never>()
    var clipboardUpdatesPublisher: AnyPublisher<ClipboardItem, Never> {
        _clipboardUpdatesSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization
    init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    deinit {
        monitorTimer?.invalidate()
    }

    // MARK: - Public Methods
    func startMonitoring() async {
        await stopMonitoring()
        if let initial = readClipboard() {
            appendToHistory(initial)
        }
        monitorTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func stopMonitoring() async {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    func getCurrentClipboard() async -> ClipboardItem? {
        return history.first
    }

    func getClipboardHistory() async -> [ClipboardItem] {
        return history
    }

    func clearHistory() async {
        history.removeAll()
    }

    /// Restores the given clipboard item to the system pasteboard so the user
    /// can paste it again.
    func copyToPasteboard(_ item: ClipboardItem) {
        pasteboard.clearContents()
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .url(let url):
            pasteboard.writeObjects([url as NSURL])
        case .image(let image):
            pasteboard.writeObjects([image])
        case .file(let url):
            pasteboard.writeObjects([url as NSURL])
        case .fileURLs(let urls):
            pasteboard.writeObjects(urls.map { $0 as NSURL })
        case .unknown:
            break
        }
        lastChangeCount = pasteboard.changeCount
    }

    // MARK: - Private

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        guard let item = readClipboard() else { return }
        appendToHistory(item)
        _clipboardUpdatesSubject.send(item)
    }

    private func readClipboard() -> ClipboardItem? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            if urls.count == 1 {
                let url = urls[0]
                let content: ClipboardItem.ClipboardContent = url.isFileURL ? .file(url) : .url(url)
                return ClipboardItem(content: content, timestamp: Date(), source: nil)
            }
            return ClipboardItem(content: .fileURLs(urls), timestamp: Date(), source: nil)
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return ClipboardItem(content: .text(text), timestamp: Date(), source: nil)
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return ClipboardItem(content: .image(image), timestamp: Date(), source: nil)
        }
        return nil
    }

    private func appendToHistory(_ item: ClipboardItem) {
        if let last = history.first, isDuplicate(last.content, item.content) {
            return
        }
        history.insert(item, at: 0)
        if history.count > maxHistory {
            history = Array(history.prefix(maxHistory))
        }
    }

    /// Compares two clipboard contents for dedup purposes. For images, the
    /// default Equatable falls back to reference equality on NSImage, which
    /// misses cases where the same picture is copied twice as a new instance.
    /// We compare TIFF representations instead.
    private func isDuplicate(_ a: ClipboardItem.ClipboardContent, _ b: ClipboardItem.ClipboardContent) -> Bool {
        switch (a, b) {
        case (.image(let lhs), .image(let rhs)):
            let lhsData = lhs.tiffRepresentation
            let rhsData = rhs.tiffRepresentation
            return lhsData == rhsData
        default:
            return a == b
        }
    }
}
