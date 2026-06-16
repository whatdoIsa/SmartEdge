import Foundation

/// Compile-time feature toggles. Flipping these affects UI surface area
/// but never deletes the underlying implementation — that way "boldly
/// turning a feature off" stays a one-line change, not an archeology dig.
///
/// Each flag has a single source of truth here. Other files import the
/// flag rather than recomputing the condition, so a future re-enable is
/// safe and obvious.
enum FeatureFlags {
    /// Spotify Web API integration. Disabled while we wait on:
    /// - A polished sign-in flow for users without Spotify Premium
    /// - Clearer UX for "what you get vs what needs Premium"
    /// All Spotify code (SpotifyService, polling coordinator, UI overlays)
    /// remains in the codebase; this flag just hides the user-facing surfaces.
    static let isSpotifyEnabled = false
}
