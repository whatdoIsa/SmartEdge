import SwiftUI

/// Single source of truth for the notch overlay's visual language —
/// colors, corner radii, spacing, and shadow values. Mirrors the role
/// `NotchAnimation` plays for motion.
///
/// Why this exists: scattered hardcoded `Color.black.opacity(0.5)`,
/// `cornerRadius: 12`, `padding(.horizontal, 14)` literals across
/// NotchView, MusicPlayerView, ShelfView, etc. made tweaks
/// risky — change one and the others drift visually. Centralizing
/// them here lets us iterate on the "this feels like one cohesive
/// surface" gestalt without playing whack-a-mole.
///
/// Design philosophy notes from CLAUDE.md (TOSS / Airbnb / Tinder):
/// - TOSS: minimal, dead-black notch surface — no material overlays
///   that would tone the camera-housing color shift.
/// - Airbnb: soft warm accents on focus states (hover, drop targets),
///   never harsh primary colors.
/// - Tinder: snappy interactions with subtle bounce — handled in
///   `NotchAnimation`, but theme values like shadow opacity and
///   border weight need to read the same way.
enum NotchTheme {

    // MARK: - Surfaces

    /// The notch fill itself. Pure black to tonally match the hardware
    /// camera notch — anything else (even ultraThinMaterial) shifts the
    /// color a hair lighter and reads as a floating card.
    static let notchBackground: Color = .black

    /// Optional warm-tone fill used when the notch shows pomodoro/timer
    /// state. Resolved at call-site by mixing in over `notchBackground`.
    static let accentWarm: Color = Color(red: 0.95, green: 0.55, blue: 0.45)

    /// Cool accent for system/info states (calendar nudge).
    static let accentCool: Color = Color(red: 0.32, green: 0.58, blue: 0.96)

    // MARK: - Edges

    /// Border shown only on active drop targets. Idle / hover / theme
    /// states get `.clear` so the box reads as a seamless extension of
    /// the bezel — matches the user's "no pale outline" preference.
    static let dropTargetBorder: Color = .accentColor
    static let dropTargetBorderWidth: CGFloat = 2
    static let idleBorderWidth: CGFloat = 0

    /// Subtle 1px hairline used inside settings cards / overlays — NOT
    /// on the notch itself.
    static let cardBorder: Color = Color.white.opacity(0.06)

    // MARK: - Shadows

    /// Drop shadow opacity in dark mode. Light mode reduces it because
    /// the bright menubar makes the same shadow read as a smudge.
    static func shadowOpacity(isDark: Bool, isDropping: Bool = false) -> Double {
        let base: Double = isDark ? 0.5 : 0.2
        return isDropping ? base + 0.1 : base
    }

    /// Shadow radius by state. The values map: idle → smallest,
    /// theme-tinted → medium, hover → larger, drop-target → largest.
    /// Each step is ~50% larger than the previous so they read as
    /// distinct "elevation levels" rather than a continuous gradient.
    static let shadowRadiusIdle: CGFloat = 8
    static let shadowRadiusThemed: CGFloat = 12
    static let shadowRadiusHover: CGFloat = 18
    static let shadowRadiusDrop: CGFloat = 16

    // MARK: - Spacing

    /// Horizontal inset for content rows inside the expanded notch. Lets
    /// titles and controls breathe inside the curved corners without
    /// hugging them.
    static let contentHorizontalPadding: CGFloat = 14

    /// Bottom inset so the bottom row never sits flush against the
    /// notch's lower edge.
    static let contentBottomPadding: CGFloat = 10

    // MARK: - Visual State

    /// Brightness boost applied on hover so the cursor-over notch reads
    /// as "alive". Small enough to be subliminal — anything larger
    /// strobed during the expand animation.
    static let hoverBrightnessBoost: Double = 0.08

    /// Hover scale was 1.04 historically, but the collapsed pillow now
    /// hides behind the hardware notch, so the visible affordance is
    /// the expand itself. Keep these for theme tint pulses.
    static let dropScale: CGFloat = 1.05
    static let actionPulseDelta: CGFloat = 0.03

    // MARK: - Music Player (redesign tokens)
    //
    // Centralized so the notch music UI reads as one cohesive surface and
    // tweaks ripple everywhere. Values mirror the approved mockup direction:
    // rounded album art, clear title/artist hierarchy, a filled circular
    // play button flanked by light prev/next glyphs, slim progress bar.

    /// Album artwork edge length + corner radius. Sized so the expanded
    /// player fills the notch comfortably rather than sitting compact.
    static let artworkSize: CGFloat = 80
    static let artworkCornerRadius: CGFloat = 16

    /// Track-title / artist text. White-on-black inside the notch; artist is
    /// a dimmed white rather than `.secondary` so it stays legible on pure
    /// black (system secondary resolves too dark there).
    static let trackTitleSize: CGFloat = 17
    static let trackArtistSize: CGFloat = 13
    static let trackArtistOpacity: Double = 0.6

    /// Transport controls. The play/pause is a filled circle (inverted:
    /// white bg, black glyph) to read as the primary action; prev/next are
    /// plain light glyphs.
    static let playButtonDiameter: CGFloat = 46
    static let transportGlyphSize: CGFloat = 22
    static let playGlyphSize: CGFloat = 18

    /// Progress bar.
    static let progressBarHeight: CGFloat = 4
    static let progressTrackOpacity: Double = 0.18
    static let progressTimeOpacity: Double = 0.5

    // MARK: - Status Bar

    /// Clock / battery / bluetooth strip text.
    static let statusTextSize: CGFloat = 12

    // MARK: - Accents

    /// Warm brand accent (Airbnb-leaning coral) for artwork placeholder and
    /// focal highlights. Cool blue stays for system/info affordances.
    static let brandCoral = Color(red: 1.0, green: 0.42, blue: 0.42)
    static let brandPink = Color(red: 0.99, green: 0.47, blue: 0.66)
}
