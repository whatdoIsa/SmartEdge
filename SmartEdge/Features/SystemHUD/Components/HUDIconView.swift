import SwiftUI

struct HUDIconView: View {
    let hudType: SystemHUDType
    let value: Double
    let isMuted: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private var iconName: String {
        // Mute always wins. Previously this delegated to `hudType.iconName`,
        // which only returned `speaker.slash.fill` when `level == 0` —
        // meaning a typical "mute pressed at 50% volume" state showed a
        // perfectly normal speaker.2.fill with no visible cue that audio
        // was silenced. Forcing slash whenever isMuted is the macOS
        // system HUD's own behavior and matches user expectation.
        if case .volume = hudType, isMuted {
            return "speaker.slash.fill"
        }

        // Dynamic icon based on value for volume
        if case .volume(let volumeLevel) = hudType {
            if volumeLevel == 0 {
                return "speaker.fill"
            } else if volumeLevel < 0.33 {
                return "speaker.1.fill"
            } else if value < 0.66 {
                return "speaker.2.fill"
            } else {
                return "speaker.3.fill"
            }
        }

        return hudType.iconName
    }

    private var iconColor: Color {
        // Muted state gets the dedicated muted color (typically a
        // desaturated / orange-ish tint) so the slash icon AND the color
        // shift together communicate "audio is off." Two-channel
        // redundancy avoids the edge case where a color-blind user can't
        // distinguish the muted hue.
        isMuted ? HUDIconStyle.mutedColor : HUDIconStyle.primaryColor
    }
    
    private var iconSize: CGFloat {
        HUDIconStyle.dynamicSize(for: dynamicTypeSize)
    }
    
    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: iconSize, weight: HUDIconStyle.weight, design: .rounded))
            .foregroundStyle(iconColor)
            .symbolRenderingMode(.hierarchical)
            .animation(.easeInOut(duration: 0.2), value: iconName)
            .animation(.easeInOut(duration: 0.15), value: isMuted)
            .accessibility(label: Text(accessibilityLabel))
            .accessibility(value: Text(accessibilityValue))
    }
    
    private var accessibilityLabel: String {
        if isMuted {
            return "\(hudType.title) muted"
        }
        return hudType.title
    }
    
    private var accessibilityValue: String {
        let percentage = Int(value * 100)
        if isMuted {
            return "Muted"
        }
        return "\(percentage) percent"
    }
}

#if DEBUG
#Preview("Volume Icons") {
    VStack(spacing: 20) {
        Group {
            HUDIconView(hudType: .volume(0.0), value: 0.0, isMuted: false)
            HUDIconView(hudType: .volume(0.25), value: 0.25, isMuted: false)
            HUDIconView(hudType: .volume(0.5), value: 0.5, isMuted: false)
            HUDIconView(hudType: .volume(0.75), value: 0.75, isMuted: false)
            HUDIconView(hudType: .volume(1.0), value: 1.0, isMuted: false)
            HUDIconView(hudType: .volume(0.5), value: 0.5, isMuted: true)
        }
    }
    .padding()
    .background(.regularMaterial)
}

#Preview("All HUD Types") {
    HStack(spacing: 30) {
        VStack(spacing: 16) {
            Text("Normal")
                .font(.caption)
            HUDIconView(hudType: .volume(0.6), value: 0.6, isMuted: false)
            HUDIconView(hudType: .brightness(0.8), value: 0.8, isMuted: false)
            HUDIconView(hudType: .keyboardBacklight(0.4), value: 0.4, isMuted: false)
        }
        
        VStack(spacing: 16) {
            Text("Muted/Min")
                .font(.caption)
            HUDIconView(hudType: .volume(0.6), value: 0.6, isMuted: true)
            HUDIconView(hudType: .brightness(0.0), value: 0.0, isMuted: false)
            HUDIconView(hudType: .keyboardBacklight(0.0), value: 0.0, isMuted: false)
        }
    }
    .padding()
    .background(.regularMaterial)
}

#Preview("Dark Mode") {
    VStack(spacing: 20) {
        HUDIconView(hudType: .volume(0.5), value: 0.5, isMuted: false)
        HUDIconView(hudType: .brightness(0.7), value: 0.7, isMuted: false)
        HUDIconView(hudType: .volume(0.5), value: 0.5, isMuted: true)
    }
    .padding()
    .background(.regularMaterial)
    .preferredColorScheme(.dark)
}
#endif