import Foundation
import AppKit

struct NowPlayingModel {
    let title: String?
    let artist: String?
    let album: String?
    let artwork: NSImage?
    let duration: TimeInterval
    let elapsedTime: TimeInterval
    let isPlaying: Bool
    let lastPositionUpdate: Date
    let artworkURL: URL? // Keep for potential future use
    
    init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        artwork: NSImage? = nil,
        duration: TimeInterval = 0,
        elapsedTime: TimeInterval = 0,
        isPlaying: Bool = false,
        lastPositionUpdate: Date = Date(),
        artworkURL: URL? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.isPlaying = isPlaying
        self.lastPositionUpdate = lastPositionUpdate
        self.artworkURL = artworkURL
    }
    
    // Convert from NowPlayingInfo if needed
    init(from info: NowPlayingInfo, isPlaying: Bool = false) {
        self.title = info.title
        self.artist = info.artist
        self.album = info.album
        self.duration = info.duration
        self.elapsedTime = info.elapsedTime
        self.isPlaying = isPlaying
        self.lastPositionUpdate = Date()
        self.artworkURL = nil // Would need to be set separately if available
        
        if let artworkData = info.artworkData {
            self.artwork = NSImage(data: artworkData)
        } else {
            self.artwork = nil
        }
    }
}