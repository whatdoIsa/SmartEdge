import SwiftUI

/// Tiny enhancement layer for `MusicPlayerView`. When the user has signed
/// into Spotify and at least one playback device is available, this overlay
/// surfaces a speaker icon that opens a device picker — selecting a device
/// transfers playback there via the Spotify Web API.
///
/// Design intent:
/// - **MediaService (system-level MRMediaRemote) stays the source of truth**
///   for the "Now Playing" display. SpotifyService is layered on top as
///   an *enhancement* — no replacement, no fall-through routing of
///   play/pause/next/previous (system media keys already work fine for the
///   currently-active app).
/// - The overlay no-ops when Spotify isn't signed in, so MacBook users who
///   haven't connected Spotify see exactly the original UI.
/// - We don't continuously poll `fetchAvailableDevices` — the list only
///   changes when the user opens/closes Spotify on another device, so a
///   one-shot fetch on appear plus a manual "Refresh" menu item is enough.
@MainActor
struct SpotifyDeviceOverlay: View {
    @ObservedObject var spotify: SpotifyService

    var body: some View {
        Group {
            // Feature-flagged off while the Spotify integration is on hold.
            // The whole view collapses to EmptyView so the music player
            // looks like a stock MediaService-driven UI.
            if FeatureFlags.isSpotifyEnabled && spotify.state == .signedIn && !spotify.devices.isEmpty {
                Menu {
                    ForEach(spotify.devices) { device in
                        Button {
                            Task { await spotify.transferPlayback(to: device.id) }
                        } label: {
                            if device.isActive {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                        .disabled(device.isActive)
                    }
                    Divider()
                    Button {
                        Task { await spotify.fetchAvailableDevices() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "hifispeaker.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(activeDeviceHelp)
                .accessibilityLabel("Spotify device picker")
            } else {
                EmptyView()
            }
        }
        .task {
            // One-shot fetch on appear so the menu has something the first
            // time the user opens the music view. Cheap if devices were
            // already loaded; SpotifyService just updates the @Published list.
            guard FeatureFlags.isSpotifyEnabled else { return }
            if spotify.state == .signedIn && spotify.devices.isEmpty {
                await spotify.fetchAvailableDevices()
            }
        }
    }

    /// Tooltip showing the currently-active device, useful as a quick
    /// glance for "where is the music actually playing?".
    private var activeDeviceHelp: String {
        if let active = spotify.devices.first(where: { $0.isActive }) {
            return "Playing on \(active.name)"
        }
        return "Choose Spotify playback device"
    }
}

#Preview {
    SpotifyDeviceOverlay(spotify: SpotifyService())
        .padding()
        .background(.ultraThinMaterial)
}
