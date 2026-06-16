import Foundation
import AppKit

struct NowPlayingInfo: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let duration: TimeInterval
    let elapsedTime: TimeInterval
    let playbackRate: Double
    let playbackState: MediaPlaybackState
    let lastUpdated: Date
    let artwork: NSImage?

    init(
        title: String?,
        artist: String?,
        album: String?,
        artworkData: Data?,
        duration: TimeInterval,
        elapsedTime: TimeInterval,
        playbackRate: Double,
        playbackState: MediaPlaybackState,
        lastUpdated: Date
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.playbackRate = playbackRate
        self.playbackState = playbackState
        self.lastUpdated = lastUpdated
        self.artwork = artworkData.flatMap(NSImage.init(data:))
    }

    var isPlaying: Bool {
        playbackState == .playing
    }

    var progress: TimeInterval? {
        guard duration > 0 else { return nil }
        return min(max(elapsedTime, 0), duration)
    }

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        return lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.duration == rhs.duration
            && lhs.playbackRate == rhs.playbackRate
            && lhs.playbackState == rhs.playbackState
            && lhs.artworkData?.count == rhs.artworkData?.count
    }
}

enum MediaPlaybackState: Equatable {
    case unknown
    case playing
    case paused
    case stopped
}

enum MediaServiceError: Error, LocalizedError {
    case mediaRemoteUnavailable
    case functionNotFound(String)
    case functionNotImplemented(String)
    case commandFailed(String)
    case operationFailed
    case invalidState
    case unsupportedMacOSVersion
    case frameworkLoadFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .mediaRemoteUnavailable:
            return "MediaRemote framework is not available on this system"
        case .functionNotFound(let function):
            return "MediaRemote function '\(function)' could not be found"
        case .functionNotImplemented(let function):
            return "Media function '\(function)' is not implemented yet"
        case .commandFailed(let command):
            return "Media command '\(command)' failed to execute"
        case .operationFailed:
            return "Media operation failed to execute"
        case .invalidState:
            return "Media service is in an invalid state for this operation"
        case .unsupportedMacOSVersion:
            return "MediaRemote requires macOS 10.15 or later"
        case .frameworkLoadFailed:
            return "Failed to load MediaRemote framework"
        case .timeout:
            return "Media operation timed out"
        }
    }
}