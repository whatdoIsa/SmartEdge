import SwiftUI

struct SystemHUDView: View {
    @StateObject private var viewModel = SystemHUDViewModel()
    let showPercentage: Bool
    
    init(showPercentage: Bool = false) {
        self.showPercentage = showPercentage
    }
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    
    private var percentageText: String {
        if viewModel.isMuted {
            return "—"
        }
        return "\(Int(viewModel.value * 100))%"
    }
    
    private var shouldShowPercentage: Bool {
        showPercentage && dynamicTypeSize.isAccessibilitySize == false
    }
    
    var body: some View {
        Group {
            if viewModel.isVisible {
                hudContent
                    .transition(
                        reduceMotion ? .opacity : HUDAnimations.showTransition
                    )
                    .animation(
                        reduceMotion ? .easeInOut(duration: 0.3) : HUDAnimations.slideSpring,
                        value: viewModel.isVisible
                    )
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.hudType)
        .animation(.easeInOut(duration: 0.15), value: viewModel.value)
        .animation(.easeInOut(duration: 0.15), value: viewModel.isMuted)
        .animation(.easeInOut(duration: 0.2), value: viewModel.animationProgress)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private var hudContent: some View {
        VStack(spacing: 0) {
            hudBody
                .nativeHUDStyle()
        }
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var hudBody: some View {
        if shouldShowPercentage {
            // Horizontal layout with percentage
            HStack(spacing: 12) {
                HUDIconView(
                    hudType: viewModel.hudType,
                    value: viewModel.value,
                    isMuted: viewModel.isMuted
                )
                
                HUDProgressBar(
                    value: viewModel.value,
                    animationProgress: viewModel.animationProgress,
                    isMuted: viewModel.isMuted
                )
                
                Text(percentageText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
                    .animation(.easeInOut(duration: 0.15), value: percentageText)
            }
        } else {
            // Vertical layout without percentage (more compact)
            VStack(spacing: 8) {
                HUDIconView(
                    hudType: viewModel.hudType,
                    value: viewModel.value,
                    isMuted: viewModel.isMuted
                )
                
                HUDProgressBar(
                    value: viewModel.value,
                    animationProgress: viewModel.animationProgress,
                    isMuted: viewModel.isMuted
                )
            }
        }
    }
}

// MARK: - Accessibility Size Detection
extension DynamicTypeSize {
    var isAccessibilitySize: Bool {
        switch self {
        case .accessibility1, .accessibility2, .accessibility3,
             .accessibility4, .accessibility5:
            return true
        default:
            return false
        }
    }
}

// MARK: - HUD Display Modifiers
extension View {
    func systemHUDOverlay(showPercentage: Bool = false) -> some View {
        overlay(
            SystemHUDView(showPercentage: showPercentage),
            alignment: .top
        )
    }
}

// MARK: - Test Interface (for debugging)
extension SystemHUDView {
    func showTestHUD(_ type: SystemHUDType, value: Double, isMuted: Bool = false) {
        viewModel.showHUD(type: type, value: value, isMuted: isMuted)
    }
    
    func hideTestHUD() {
        viewModel.hideHUD()
    }
}

#if DEBUG
#Preview("Volume HUD") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        SystemHUDView(showPercentage: true)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: .systemHUDDidShow,
                        object: nil,
                        userInfo: [
                            "type": "volume",
                            "value": 0.6,
                            "isMuted": false
                        ]
                    )
                }
            }
    }
    .frame(width: 400, height: 300)
}

#Preview("Brightness HUD") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        SystemHUDView(showPercentage: false)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: .systemHUDDidShow,
                        object: nil,
                        userInfo: [
                            "type": "brightness",
                            "value": 0.8,
                            "isMuted": false
                        ]
                    )
                }
            }
    }
    .frame(width: 400, height: 300)
}

#Preview("Muted Volume HUD") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        SystemHUDView(showPercentage: true)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: .systemHUDDidShow,
                        object: nil,
                        userInfo: [
                            "type": "volume",
                            "value": 0.0,
                            "isMuted": true
                        ]
                    )
                }
            }
    }
    .frame(width: 400, height: 300)
}

#Preview("Keyboard Brightness HUD") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        SystemHUDView(showPercentage: false)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: .systemHUDDidShow,
                        object: nil,
                        userInfo: [
                            "type": "keyboardBacklight",
                            "value": 0.3,
                            "isMuted": false
                        ]
                    )
                }
            }
    }
    .frame(width: 400, height: 300)
}

#Preview("Accessibility Large") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        SystemHUDView(showPercentage: true)
            .environment(\.dynamicTypeSize, .accessibility3)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: .systemHUDDidShow,
                        object: nil,
                        userInfo: [
                            "type": "volume",
                            "value": 0.7,
                            "isMuted": false
                        ]
                    )
                }
            }
    }
    .frame(width: 500, height: 400)
}

#Preview("Dark Mode") {
    ZStack {
        Color.gray.ignoresSafeArea()
        
        SystemHUDView(showPercentage: true)
            .preferredColorScheme(.dark)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: .systemHUDDidShow,
                        object: nil,
                        userInfo: [
                            "type": "volume",
                            "value": 0.4,
                            "isMuted": false
                        ]
                    )
                }
            }
    }
    .frame(width: 400, height: 300)
}
#endif