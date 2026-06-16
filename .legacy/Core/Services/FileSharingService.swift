import Foundation
import AppKit
import UniformTypeIdentifiers

actor FileSharingService: FileSharingServiceProtocol {
    
    // MARK: - Public Methods
    
    func getAvailableSharingServices(for item: ShelfItem) async -> [SharingServiceInfo] {
        guard let fileURL = item.fileURL else { return [] }
        
        return await MainActor.run {
            let sharingServices = NSSharingService.sharingServices(forItems: [fileURL])
            
            return sharingServices.compactMap { service in
                SharingServiceInfo(
                    name: service.title,
                    displayName: service.title,
                    icon: service.image,
                    serviceType: NSSharingService.Name(service.title)
                )
            }
        }
    }
    
    func shareItem(_ item: ShelfItem, using service: SharingServiceInfo) async throws {
        guard let fileURL = item.fileURL else {
            throw FileSharingError.invalidItem
        }
        
        await MainActor.run {
            guard let sharingService = NSSharingService(named: service.serviceType) else {
                return
            }
            
            sharingService.perform(withItems: [fileURL])
        }
    }
    
    func showSharingPicker(for item: ShelfItem, from view: NSView) async throws {
        guard let fileURL = item.fileURL else {
            throw FileSharingError.invalidItem
        }
        
        await MainActor.run {
            let picker = NSSharingServicePicker(items: [fileURL])
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        }
    }
    
    // MARK: - Convenience Methods
    
    func shareViaAirDrop(_ item: ShelfItem) async throws {
        let airDropService = SharingServiceInfo(
            name: "AirDrop",
            displayName: "AirDrop",
            icon: nil,
            serviceType: .sendViaAirDrop
        )
        
        try await shareItem(item, using: airDropService)
    }
    
    func shareViaMessages(_ item: ShelfItem) async throws {
        let messagesService = SharingServiceInfo(
            name: "Messages",
            displayName: "Messages",
            icon: nil,
            serviceType: .composeMessage
        )
        
        try await shareItem(item, using: messagesService)
    }
    
    func shareViaEmail(_ item: ShelfItem) async throws {
        let emailService = SharingServiceInfo(
            name: "Mail",
            displayName: "Mail", 
            icon: nil,
            serviceType: .composeEmail
        )
        
        try await shareItem(item, using: emailService)
    }
    
    func copyToClipboard(_ item: ShelfItem) async throws {
        guard let fileURL = item.fileURL else {
            throw FileSharingError.invalidItem
        }
        
        await MainActor.run {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([fileURL as NSURL])
        }
    }
    
    // MARK: - Quick Actions
    
    func getQuickShareActions(for item: ShelfItem) async -> [QuickShareAction] {
        var actions: [QuickShareAction] = []
        
        // Add standard quick actions
        actions.append(.init(
            title: "AirDrop",
            icon: "airplay",
            action: { [weak self] in
                try await self?.shareViaAirDrop(item)
            }
        ))
        
        actions.append(.init(
            title: "Messages",
            icon: "message",
            action: { [weak self] in
                try await self?.shareViaMessages(item)
            }
        ))
        
        actions.append(.init(
            title: "Mail",
            icon: "envelope",
            action: { [weak self] in
                try await self?.shareViaEmail(item)
            }
        ))
        
        actions.append(.init(
            title: "Copy",
            icon: "doc.on.clipboard",
            action: { [weak self] in
                try await self?.copyToClipboard(item)
            }
        ))
        
        return actions
    }
    
    // MARK: - Recent Destinations
    
    private var recentDestinations: [SharingDestination] = []
    private let maxRecentDestinations = 5
    
    func getRecentSharingDestinations() async -> [SharingDestination] {
        return recentDestinations
    }
    
    func addToRecentDestinations(_ destination: SharingDestination) async {
        // Remove if already exists
        recentDestinations.removeAll { $0.id == destination.id }
        
        // Add to front
        recentDestinations.insert(destination, at: 0)
        
        // Trim to max size
        if recentDestinations.count > maxRecentDestinations {
            recentDestinations.removeLast()
        }
    }
    
    func clearRecentDestinations() async {
        recentDestinations.removeAll()
    }
}

// MARK: - Supporting Models

struct QuickShareAction {
    let title: String
    let icon: String
    let action: () async throws -> Void
}

struct SharingDestination: Identifiable, Codable {
    let id = UUID()
    let name: String
    let type: SharingDestinationType
    let lastUsed: Date
    let usageCount: Int
    
    enum SharingDestinationType: String, Codable, CaseIterable {
        case airdrop = "airdrop"
        case messages = "messages"
        case mail = "mail"
        case copy = "copy"
        case other = "other"
        
        var displayName: String {
            switch self {
            case .airdrop:
                return "AirDrop"
            case .messages:
                return "Messages"
            case .mail:
                return "Mail"
            case .copy:
                return "Copy"
            case .other:
                return "Other"
            }
        }
        
        var icon: String {
            switch self {
            case .airdrop:
                return "airplay"
            case .messages:
                return "message"
            case .mail:
                return "envelope"
            case .copy:
                return "doc.on.clipboard"
            case .other:
                return "square.and.arrow.up"
            }
        }
    }
}

// MARK: - FileSharingError

enum FileSharingError: Error, LocalizedError {
    case invalidItem
    case serviceUnavailable
    case sharingFailed
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .invalidItem:
            return "Cannot share this item"
        case .serviceUnavailable:
            return "Sharing service is not available"
        case .sharingFailed:
            return "Failed to share the item"
        case .permissionDenied:
            return "Permission denied for sharing"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidItem:
            return "Ensure the item has a valid file URL"
        case .serviceUnavailable:
            return "Check that the sharing service is installed and available"
        case .sharingFailed:
            return "Try sharing again or use a different sharing method"
        case .permissionDenied:
            return "Grant necessary permissions in System Preferences"
        }
    }
}

// MARK: - NSSharingService.Name Extensions

extension NSSharingService.Name {
    static let sendViaAirDrop = NSSharingService.Name("com.apple.share.AirDrop.send")
    static let composeMessage = NSSharingService.Name("com.apple.share.Messages.compose")
    static let composeEmail = NSSharingService.Name("com.apple.share.Mail.compose")
    static let addToPhotos = NSSharingService.Name("com.apple.share.Photos.add")
    static let copyToPasteboard = NSSharingService.Name("com.apple.share.System.add-to-pasteboard")
}