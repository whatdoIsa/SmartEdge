import Foundation

enum SystemEvent: Equatable {
    case volumeChanged(Float)
    case brightnessChanged(Float)
    case mediaPlaybackChanged(Bool)
    case systemSleep
    case systemWake
    case screenParametersChanged
}
