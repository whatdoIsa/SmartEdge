import Foundation

enum SmartEdgeError: Error, LocalizedError {
    case mediaUnavailable
    case mediaControlFailed
    case permissionDenied
    case windowCreationFailed
    case serviceInitializationFailed
    case networkError
    case systemAccess(SystemAccessError)
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .mediaUnavailable:
            return "Media service is unavailable"
        case .mediaControlFailed:
            return "Failed to control media playback"
        case .permissionDenied:
            return "Permission denied for required system access"
        case .windowCreationFailed:
            return "Failed to create application window"
        case .serviceInitializationFailed:
            return "Failed to initialize required services"
        case .networkError:
            return "Network connection error"
        case .systemAccess(let systemError):
            return systemError.localizedDescription
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

enum SystemAccessError: Error, LocalizedError {
    case notAuthorized
    case permissionDenied(String)
    case operationFailed(String)
    case serviceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "System access not authorized"
        case .permissionDenied(let details):
            return "Permission denied: \(details)"
        case .operationFailed(let details):
            return "Operation failed: \(details)"
        case .serviceUnavailable:
            return "System service unavailable"
        }
    }
}