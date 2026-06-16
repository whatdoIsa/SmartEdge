import Foundation
import Combine

/// View-facing surface for clipboard history. Wraps `ClipboardMonitorService`
/// so SwiftUI views never touch the service container directly.
@MainActor
final class ClipboardViewModel: ObservableObject {
    private let service: ClipboardMonitorService

    @Published private(set) var history: [ClipboardItem] = []

    init(service: ClipboardMonitorService) {
        self.service = service
        service.$history.assign(to: &$history)
    }

    /// Copies the chosen entry back to the system pasteboard so the user can
    /// paste it with ⌘V into any app.
    func copy(_ item: ClipboardItem) {
        service.copyToPasteboard(item)
    }

    func clearHistory() {
        Task { [weak service] in
            await service?.clearHistory()
        }
    }

    /// Convenience for views that only want the most recent N items.
    func recent(_ count: Int) -> [ClipboardItem] {
        Array(history.prefix(count))
    }
}
