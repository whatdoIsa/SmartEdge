import SwiftUI

struct HUDProgressBar: View {
    let value: Double
    let animationProgress: Double
    let isMuted: Bool
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    
    private var barWidth: CGFloat {
        HUDProgressBarStyle.dynamicWidth(for: dynamicTypeSize)
    }
    
    private var barHeight: CGFloat {
        HUDProgressBarStyle.dynamicHeight(for: dynamicTypeSize)
    }
    
    private var fillColor: Color {
        isMuted ? HUDProgressBarStyle.mutedColor : HUDProgressBarStyle.fillColor
    }
    
    private var trackColor: Color {
        HUDProgressBarStyle.trackColor
    }
    
    private var cornerRadius: CGFloat {
        barHeight / 2
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(trackColor)
                    .frame(width: barWidth, height: barHeight)

                // Fill
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(fillColor)
                    .frame(
                        width: max(0, min(barWidth * animationProgress, barWidth)),
                        height: barHeight
                    )
                    .animation(.easeInOut(duration: 0.2), value: animationProgress)
                    .animation(.easeInOut(duration: 0.15), value: isMuted)

                // Subtle inner shadow for depth
                if animationProgress > 0 && !isMuted {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.1),
                                    Color.clear,
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(
                            width: max(0, min(barWidth * animationProgress, barWidth)),
                            height: barHeight
                        )
                        .blendMode(.overlay)
                }
                // The diagonal slash overlay that used to sit here was
                // removed at the user's request — the speaker.slash.fill
                // icon swap above the bar is enough of a cue on its own,
                // and the bar slash read as visual noise on top.
            }
            .frame(width: barWidth, height: barHeight)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: barWidth, height: barHeight)
        .accessibility(label: Text("Progress"))
        .accessibility(value: Text(accessibilityValue))
        .accessibilityAdjustableAction { direction in
            // This would be handled by the parent view/viewmodel
        }
    }
    
    private var accessibilityValue: String {
        let percentage = Int(value * 100)
        if isMuted {
            return "Muted"
        }
        return "\(percentage) percent"
    }
}

// MARK: - Tick Marks (Alternative Style)
struct HUDProgressBarWithTicks: View {
    let value: Double
    let animationProgress: Double
    let isMuted: Bool
    let tickCount: Int = 16
    
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private var barWidth: CGFloat {
        HUDProgressBarStyle.dynamicWidth(for: dynamicTypeSize)
    }
    
    private var barHeight: CGFloat {
        HUDProgressBarStyle.dynamicHeight(for: dynamicTypeSize)
    }
    
    private var tickWidth: CGFloat {
        (barWidth - CGFloat(tickCount - 1) * 1) / CGFloat(tickCount)
    }
    
    private var activeTicks: Int {
        Int(animationProgress * Double(tickCount))
    }
    
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<tickCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barHeight / 4)
                    .fill(tickColor(for: index))
                    .frame(width: tickWidth, height: barHeight)
                    .animation(
                        .easeInOut(duration: 0.1).delay(Double(index) * 0.01),
                        value: activeTicks
                    )
            }
        }
        .frame(width: barWidth, height: barHeight)
    }
    
    private func tickColor(for index: Int) -> Color {
        if index < activeTicks {
            return isMuted ? HUDProgressBarStyle.mutedColor : HUDProgressBarStyle.fillColor
        } else {
            return HUDProgressBarStyle.trackColor
        }
    }
}

#if DEBUG
#Preview("Progress Bar States") {
    VStack(spacing: 24) {
            HUDProgressBar(value: 0.0, animationProgress: 0.0, isMuted: false)
            HUDProgressBar(value: 0.25, animationProgress: 0.25, isMuted: false)
            HUDProgressBar(value: 0.5, animationProgress: 0.5, isMuted: false)
            HUDProgressBar(value: 0.75, animationProgress: 0.75, isMuted: false)
            HUDProgressBar(value: 1.0, animationProgress: 1.0, isMuted: false)
            HUDProgressBar(value: 0.5, animationProgress: 0.5, isMuted: true)
    }
    .padding(40)
    .background(.regularMaterial)
}

#Preview("Tick Style") {
    VStack(spacing: 24) {
        HUDProgressBarWithTicks(value: 0.0, animationProgress: 0.0, isMuted: false)
        HUDProgressBarWithTicks(value: 0.25, animationProgress: 0.25, isMuted: false)
        HUDProgressBarWithTicks(value: 0.5, animationProgress: 0.5, isMuted: false)
        HUDProgressBarWithTicks(value: 0.75, animationProgress: 0.75, isMuted: false)
        HUDProgressBarWithTicks(value: 1.0, animationProgress: 1.0, isMuted: false)
        HUDProgressBarWithTicks(value: 0.5, animationProgress: 0.5, isMuted: true)
    }
    .padding(40)
    .background(.regularMaterial)
}

#Preview("Dark Mode") {
    VStack(spacing: 24) {
        HUDProgressBar(value: 0.3, animationProgress: 0.3, isMuted: false)
        HUDProgressBar(value: 0.7, animationProgress: 0.7, isMuted: false)
        HUDProgressBar(value: 0.5, animationProgress: 0.5, isMuted: true)
    }
    .padding(40)
    .background(.regularMaterial)
    .preferredColorScheme(.dark)
}

#Preview("Accessibility Sizes") {
    VStack(spacing: 16) {
            HUDProgressBar(value: 0.6, animationProgress: 0.6, isMuted: false)
                .environment(\.dynamicTypeSize, .small)
            
            HUDProgressBar(value: 0.6, animationProgress: 0.6, isMuted: false)
                .environment(\.dynamicTypeSize, .medium)
            
            HUDProgressBar(value: 0.6, animationProgress: 0.6, isMuted: false)
                .environment(\.dynamicTypeSize, .xLarge)
            
            HUDProgressBar(value: 0.6, animationProgress: 0.6, isMuted: false)
                .environment(\.dynamicTypeSize, .accessibility3)
    }
    .padding(40)
    .background(.regularMaterial)
}
#endif