import SwiftUI

struct NativeHUDStyle: ViewModifier {
    let cornerRadius: CGFloat = 14
    let shadowRadius: CGFloat = 20
    let materialThickness: CGFloat = 1
    
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.15), radius: shadowRadius, x: 0, y: 8)
            )
    }
}

struct HUDProgressBarStyle {
    static let height: CGFloat = 4
    static let cornerRadius: CGFloat = 2
    static let width: CGFloat = 120
    
    static var trackColor: Color {
        Color.primary.opacity(0.2)
    }
    
    static var fillColor: Color {
        Color.primary.opacity(0.8)
    }
    
    static var mutedColor: Color {
        Color.red.opacity(0.7)
    }
}

struct HUDIconStyle {
    static let size: CGFloat = 16
    static let weight: Font.Weight = .medium
    
    static var primaryColor: Color {
        Color.primary.opacity(0.8)
    }
    
    static var mutedColor: Color {
        Color.red.opacity(0.7)
    }
}

struct HUDAnimations {
    static let showTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .top).combined(with: .opacity),
        removal: .opacity
    )
    
    static let slideSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let valueChange = Animation.easeInOut(duration: 0.15)
    static let hide = Animation.easeInOut(duration: 0.3)
}

extension View {
    func nativeHUDStyle() -> some View {
        modifier(NativeHUDStyle())
    }
}

// MARK: - Dynamic Type Support
extension HUDIconStyle {
    static func dynamicSize(for sizeCategory: DynamicTypeSize) -> CGFloat {
        switch sizeCategory {
        case .xSmall, .small:
            return 14
        case .medium:
            return 16
        case .large, .xLarge:
            return 18
        case .xxLarge:
            return 20
        case .xxxLarge:
            return 22
        case .accessibility1:
            return 24
        case .accessibility2:
            return 26
        case .accessibility3:
            return 28
        case .accessibility4:
            return 30
        case .accessibility5:
            return 32
        @unknown default:
            return 16
        }
    }
}

extension HUDProgressBarStyle {
    static func dynamicWidth(for sizeCategory: DynamicTypeSize) -> CGFloat {
        switch sizeCategory {
        case .xSmall, .small:
            return 100
        case .medium:
            return 120
        case .large, .xLarge:
            return 140
        case .xxLarge:
            return 160
        case .xxxLarge:
            return 180
        case .accessibility1:
            return 200
        case .accessibility2:
            return 220
        case .accessibility3:
            return 240
        case .accessibility4:
            return 260
        case .accessibility5:
            return 280
        @unknown default:
            return 120
        }
    }
    
    static func dynamicHeight(for sizeCategory: DynamicTypeSize) -> CGFloat {
        switch sizeCategory {
        case .xSmall, .small:
            return 3
        case .medium:
            return 4
        case .large, .xLarge:
            return 5
        case .xxLarge:
            return 6
        case .xxxLarge:
            return 7
        case .accessibility1:
            return 8
        case .accessibility2:
            return 9
        case .accessibility3:
            return 10
        case .accessibility4:
            return 11
        case .accessibility5:
            return 12
        @unknown default:
            return 4
        }
    }
}