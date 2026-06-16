import SwiftUI

// MARK: - Error Models
enum AppError: LocalizedError {
    case mediaServiceUnavailable
    case notchServiceFailed
    case permissionDenied
    case networkTimeout
    case unknownError(String)
    
    var errorDescription: String? {
        switch self {
        case .mediaServiceUnavailable:
            return "Music service unavailable"
        case .notchServiceFailed:
            return "Notch service initialization failed"
        case .permissionDenied:
            return "Permission required"
        case .networkTimeout:
            return "Network timeout"
        case .unknownError(let message):
            return message
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .mediaServiceUnavailable:
            return "Start playing music to see controls"
        case .notchServiceFailed:
            return "Restart the app to reinitialize"
        case .permissionDenied:
            return "Grant permission in System Preferences"
        case .networkTimeout:
            return "Check your internet connection"
        case .unknownError:
            return "Try again or restart the app"
        }
    }
}

// MARK: - Error Toast
struct ErrorToast: View {
    let error: AppError
    @State private var isVisible = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14, weight: .medium))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(error.localizedDescription)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                if let recovery = error.recoverySuggestion {
                    Text(recovery)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Full Error View
struct ErrorView: View {
    let error: AppError
    let retry: (() -> Void)?
    
    init(error: AppError, retry: (() -> Void)? = nil) {
        self.error = error
        self.retry = retry
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(error.localizedDescription)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                if let recovery = error.recoverySuggestion {
                    Text(recovery)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if let retry = retry {
                Button("Retry") {
                    retry()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.accentColor)
            }
        }
        .padding(24)
    }
}

// MARK: - Inline Error View
struct InlineErrorView: View {
    let message: String
    let isCompact: Bool
    
    init(_ message: String, compact: Bool = false) {
        self.message = message
        self.isCompact = compact
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: isCompact ? 12 : 14))
            
            Text(message)
                .font(.system(size: isCompact ? 11 : 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, isCompact ? 8 : 12)
        .padding(.vertical, isCompact ? 4 : 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}