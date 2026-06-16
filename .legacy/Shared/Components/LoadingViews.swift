import SwiftUI

// MARK: - Loading Spinner
struct LoadingSpinner: View {
    let size: CGFloat
    let lineWidth: CGFloat
    
    @State private var rotation = 0.0
    
    init(size: CGFloat = 16, lineWidth: CGFloat = 2) {
        self.size = size
        self.lineWidth = lineWidth
    }
    
    var body: some View {
        Circle()
            .trim(from: 0.0, to: 0.75)
            .stroke(
                Color.accentColor,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = 360.0
                }
            }
    }
}

// MARK: - Skeleton View
struct SkeletonView: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    
    @State private var shimmerOffset: CGFloat = -200
    
    init(width: CGFloat? = nil, height: CGFloat = 16, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.4),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: shimmerOffset)
                    .animation(
                        .linear(duration: 1.5)
                        .repeatForever(autoreverses: false),
                        value: shimmerOffset
                    )
            )
            .onAppear {
                shimmerOffset = 200
            }
    }
}

// MARK: - Music Player Skeleton
struct MusicPlayerSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            // Album art placeholder
            SkeletonView(width: 48, height: 48, cornerRadius: 8)
            
            VStack(alignment: .leading, spacing: 4) {
                // Track title placeholder
                SkeletonView(width: 120, height: 14, cornerRadius: 4)
                
                // Artist name placeholder
                SkeletonView(width: 80, height: 12, cornerRadius: 4)
            }
            
            Spacer()
            
            // Control buttons placeholder
            HStack(spacing: 8) {
                SkeletonView(width: 24, height: 24, cornerRadius: 12)
                SkeletonView(width: 28, height: 28, cornerRadius: 14)
                SkeletonView(width: 24, height: 24, cornerRadius: 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Progress Indicator with Text
struct LoadingIndicator: View {
    let message: String
    let isCompact: Bool
    
    init(_ message: String = "Loading...", compact: Bool = false) {
        self.message = message
        self.isCompact = compact
    }
    
    var body: some View {
        HStack(spacing: 12) {
            LoadingSpinner(size: isCompact ? 14 : 16)
            
            Text(message)
                .font(.system(size: isCompact ? 11 : 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, isCompact ? 8 : 12)
        .padding(.vertical, isCompact ? 6 : 8)
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String?
    let action: (() -> Void)?
    let actionTitle: String?
    
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if let action = action, let actionTitle = actionTitle {
                Button(actionTitle) {
                    action()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.accentColor)
            }
        }
        .padding(24)
    }
}

// MARK: - Fade Transition Modifier
extension View {
    func fadeTransition() -> some View {
        self.transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}