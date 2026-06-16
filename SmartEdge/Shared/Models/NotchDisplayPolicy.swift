import Foundation

/// Which displays SmartEdge places the notch overlay on.
///
/// The previous boolean (`showOnNonNotchDisplays`) was a binary "all or
/// nothing" toggle. This 3-way enum surfaces the realistic middle option —
/// "primary monitor only" — which is what most users with one external
/// 4K + one MacBook actually want: notch on whichever screen has their
/// menu bar, not duplicated across every attached display.
///
/// Raw values are stable strings (not Int) so saved settings survive
/// case reordering. Add new cases at the end of the enum, never insert.
enum NotchDisplayPolicy: String, CaseIterable, Identifiable {
    /// Only on the display with a hardware notch (MacBook Pro / Air with
    /// notch). External monitors and non-notch Macs see nothing.
    case notchOnly = "notch_only"

    /// On the display that currently owns `NSScreen.main` (the menu bar
    /// display). For most users this is the laptop notch when open or the
    /// external display when clamshelled.
    case primaryOnly = "primary_only"

    /// On any attached display — the most permissive option. Default for
    /// historical reasons (matches the original boolean toggle's true).
    case allDisplays = "all_displays"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notchOnly: return "Notch displays only"
        case .primaryOnly: return "Primary display only"
        case .allDisplays: return "All displays"
        }
    }

    var subtitle: String {
        switch self {
        case .notchOnly:
            return "Hide on external monitors and older MacBooks."
        case .primaryOnly:
            return "Follow the active menu bar. Best for clamshell users."
        case .allDisplays:
            return "Show wherever you focus. Default."
        }
    }
}
