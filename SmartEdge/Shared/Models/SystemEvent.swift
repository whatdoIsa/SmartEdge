import Foundation

enum SystemEvent: Equatable {
    case mediaPlaybackChanged(Bool)
    case systemSleep
    case systemWake
    case screenParametersChanged
}
