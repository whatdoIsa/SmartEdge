import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
final class ShelfViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var draggedItems: [ShelfItem] = []
    @Published var isDropTargetActive: Bool = false
    @Published var recentFiles: [ShelfItem] = []
    @Published var favoriteItems: [ShelfItem] = []
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var fileMonitor: FileMonitor?
    
    // MARK: - Types
    
    struct ShelfItem: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let url: URL
        let type: ItemType
        let icon: NSImage
        let dateAdded: Date
        
        enum ItemType {
            case file
            case folder
            case application
            case image
            case document
        }
    }
    
    // MARK: - Initialization
    
    init() {
        loadRecentFiles()
        setupFileMonitoring()
    }
    
    // MARK: - Public Methods
    
    func handleDrop(providers: [NSItemProvider]) {
        Task {
            await processDroppedItems(providers: providers)
        }
    }
    
    func openItem(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }
    
    func removeItem(_ item: ShelfItem) {
        recentFiles.removeAll { $0.id == item.id }
        favoriteItems.removeAll { $0.id == item.id }
    }
    
    func addToFavorites(_ item: ShelfItem) {
        if !favoriteItems.contains(item) {
            favoriteItems.append(item)
        }
    }
    
    func setDropTargetActive(_ active: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isDropTargetActive = active
        }
    }
    
    // MARK: - Private Methods
    
    private func processDroppedItems(providers: [NSItemProvider]) async {
        var newItems: [ShelfItem] = []
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                do {
                    let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        let shelfItem = createShelfItem(from: url)
                        newItems.append(shelfItem)
                    }
                } catch {
                    print("Error loading dropped item: \(error)")
                }
            }
        }
        
        await MainActor.run {
            for item in newItems {
                if !recentFiles.contains(item) {
                    recentFiles.insert(item, at: 0)
                }
            }
            
            // Keep only the most recent 20 items
            if recentFiles.count > 20 {
                recentFiles = Array(recentFiles.prefix(20))
            }
            
            setDropTargetActive(false)
        }
    }
    
    private func createShelfItem(from url: URL) -> ShelfItem {
        let resourceValues = try? url.resourceValues(forKeys: [.typeIdentifierKey, .effectiveIconKey])
        let icon = resourceValues?.effectiveIcon as? NSImage ?? NSWorkspace.shared.icon(forFile: url.path)
        let type = determineItemType(from: url)
        
        return ShelfItem(
            name: url.lastPathComponent,
            url: url,
            type: type,
            icon: icon,
            dateAdded: Date()
        )
    }
    
    private func determineItemType(from url: URL) -> ShelfItem.ItemType {
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isApplicationKey])
        
        if resourceValues?.isDirectory == true {
            return .folder
        } else if resourceValues?.isApplication == true {
            return .application
        } else if url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "png" {
            return .image
        } else {
            return .file
        }
    }
    
    private func loadRecentFiles() {
        // Load recent files from UserDefaults or file system
        // This would be implemented to restore state
    }
    
    private func setupFileMonitoring() {
        // Setup file system monitoring for changes
        // This would use FileManager or FSEvents for real-time updates
    }
    
    deinit {
        fileMonitor = nil
    }
}

// MARK: - File Monitoring Helper

private class FileMonitor {
    // Implementation for monitoring file system changes
    // This would use FSEvents or similar APIs
}