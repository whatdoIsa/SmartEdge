import Foundation
import AppKit

struct Track {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let artwork: NSImage?
    let duration: TimeInterval
    
    init(
        id: String = UUID().uuidString,
        title: String,
        artist: String,
        album: String? = nil,
        artwork: NSImage? = nil,
        duration: TimeInterval = 0
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.duration = duration
    }
}

enum RepeatMode: String, CaseIterable {
    case off = "off"
    case one = "one"
    case all = "all"
}