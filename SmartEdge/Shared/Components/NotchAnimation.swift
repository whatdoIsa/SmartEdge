import SwiftUI

/// Single source of truth for the notch overlay's motion language.
///
/// Five scattered `.animation(.spring(...))` modifiers used to live inside
/// `NotchView.body`, each with hand-tuned response/damping pairs. Pulling
/// them out here means a tweak ripples to every animated state and the
/// values stay consistent — important for the "this feels like one
/// physical object" perception that good notch utilities depend on.
///
/// Curves are intentionally on the snappy-but-soft side:
/// - `expand`: medium response, well-damped — the panel grows smoothly
///   into place without overshoot that would clip into the menu bar.
/// - `contentSwap`: a touch faster + slightly springier so transitions
///   between content types feel responsive without being jittery.
/// - `hover`: linear-ish ease for the subtle 1.02× nudge.
/// - `drop`: faster + more elastic to reinforce the "you just dropped
///   something" feedback.
/// - `theme`: long ease so pomodoro phase color changes don't feel like
///   they're competing with structural motion.
enum NotchAnimation {
    /// Expand ↔ collapse frame morph. Tuned for a visible "bloom" — the
    /// idle pillow lives invisibly behind the hardware notch (200×32),
    /// so the expand needs to feel like a deliberate event, not a
    /// hairline grow. Slightly slower response + slightly less damping
    /// gives the size change room to read; raising damping much further
    /// makes the expand feel mechanical, lowering it makes it bounce
    /// past the menu bar.
    static let expand = Animation.spring(response: 0.42, dampingFraction: 0.78)

    /// Switching between content types (.musicPlayer → .pomodoro etc).
    static let contentSwap = Animation.spring(response: 0.32, dampingFraction: 0.78)

    /// Hover scale-up on collapsed notch — keep this short so the cursor
    /// barely passes through before the visual lands.
    static let hover = Animation.easeInOut(duration: 0.18)

    /// Drag-and-drop highlight. More elastic on purpose: this is the one
    /// place where a tiny bounce reads as "got it".
    static let drop = Animation.spring(response: 0.26, dampingFraction: 0.7)

    /// Pomodoro theme accent crossfade. Long enough to feel like a tint
    /// shift, not a structural change.
    static let theme = Animation.easeInOut(duration: 0.5)
}
