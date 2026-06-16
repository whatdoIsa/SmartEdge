import Foundation
import AppKit
import Combine

/// Lightweight OAuth2 PKCE client for Spotify Web API.
///
/// Scope:
/// - Drives the Sign In flow via the system browser + `smartedge://spotify/callback`
/// - Exchanges the auth code for access + refresh tokens (PKCE — no client secret)
/// - Persists tokens in Keychain
/// - Auto-refreshes the access token when it's within 60s of expiring
/// - Surfaces a small Web API helper (currently `/me/player/devices`) so the UI
///   can prove the OAuth roundtrip works end-to-end
///
/// The Spotify Client ID is supplied by the user via `SettingsViewModel`
/// (@AppStorage). When empty, the service stays in the `.disabled` state.
@MainActor
final class SpotifyService: ObservableObject {

    enum AuthState: Equatable {
        case disabled        // No client ID configured
        case signedOut
        case signingIn
        case signedIn
        case error(String)
    }

    struct Device: Equatable, Identifiable, Hashable {
        let id: String
        let name: String
        let type: String
        let isActive: Bool
        let volumePercent: Int?
    }

    /// Snapshot of `/me/player`. Spotify returns 204 No Content when no
    /// playback is active (no recent device) — we surface that as `nil`
    /// `playerState` rather than an error.
    struct PlayerState: Equatable {
        let isPlaying: Bool
        let trackName: String
        let artistName: String
        let albumName: String
        let progressMs: Int
        let durationMs: Int
        let deviceName: String?
        let albumArtURL: URL?
    }

    enum APIError: Error, LocalizedError {
        case notAuthenticated
        case refreshFailed(String)
        case httpStatus(Int, String)
        case transport(String)
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Sign in to Spotify first."
            case .refreshFailed(let m): return "Token refresh failed: \(m)"
            case .httpStatus(let code, let body): return "HTTP \(code): \(body)"
            case .transport(let m): return "Network error: \(m)"
            case .decoding(let m): return "Decode error: \(m)"
            }
        }
    }

    @Published private(set) var state: AuthState = .disabled
    @Published private(set) var devices: [Device] = []
    @Published private(set) var isLoadingDevices: Bool = false
    @Published private(set) var playerState: PlayerState?

    /// True when Spotify returned 403 on a player endpoint — the user is
    /// authenticated but doesn't have Premium. We surface this as a hint
    /// rather than an error because there's nothing to retry: Free accounts
    /// can't access `/me/player/*` regardless of how many times we ask.
    /// Cleared on Sign Out and on first successful 2xx response.
    @Published private(set) var requiresPremium: Bool = false

    private let keychainServiceID = "com.smartedge.app.spotify"
    private let redirectURI = "smartedge://spotify/callback"
    private let authorizeURL = "https://accounts.spotify.com/authorize"
    private let tokenURL = "https://accounts.spotify.com/api/token"
    private let apiBaseURL = "https://api.spotify.com/v1"
    private let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing"
    ]

    private var pendingCodeVerifier: String?
    private var pendingState: String?
    /// In-flight refresh task. Multiple callers that hit `validAccessToken()`
    /// while a refresh is already running should await the same task instead
    /// of triggering parallel POST /api/token calls.
    private var refreshTask: Task<String, Error>?
    /// In-flight code-for-token exchange. Cancelled if the user re-taps Sign
    /// In before the previous callback finishes, so the stale exchange can't
    /// overwrite the new sign-in's state.
    private var exchangeTask: Task<Void, Never>?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        refreshAuthState()
    }

    // MARK: - Public API

    /// Re-reads the configured Client ID + Keychain refresh token and
    /// updates `state`. Call after the user changes the Client ID in
    /// settings, or on app launch to surface the right button label.
    func refreshAuthState() {
        let clientID = UserDefaults.standard.string(forKey: SettingsKeys.spotifyClientID) ?? ""
        guard !clientID.isEmpty else {
            state = .disabled
            return
        }
        if KeychainStorage.getString(service: keychainServiceID, account: "refresh_token") != nil {
            state = .signedIn
        } else {
            state = .signedOut
        }
    }

    /// Opens Safari with the Spotify authorize URL. The user signs in,
    /// approves scopes, and Spotify redirects back to
    /// `smartedge://spotify/callback?code=…&state=…` which the app receives
    /// via `handleCallbackURL(_:)`.
    ///
    /// Re-entrant taps overwrite the pending verifier/state — the *last*
    /// authorize URL the user actually completes in the browser is the one
    /// whose callback will succeed. Earlier callbacks (if any) will fail
    /// the state-match check, which is the safe outcome.
    func beginSignIn() {
        let clientID = UserDefaults.standard.string(forKey: SettingsKeys.spotifyClientID) ?? ""
        guard !clientID.isEmpty else {
            state = .error("Set a Spotify Client ID in Settings → Integrations first.")
            return
        }

        // Cancel any in-flight code exchange — if the user re-taps Sign In
        // while a previous callback is still being exchanged, the new flow
        // takes precedence and the old one should not overwrite the state.
        exchangeTask?.cancel()
        exchangeTask = nil

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.makeCodeChallenge(verifier: verifier)
        let stateToken = Self.makeStateToken()
        pendingCodeVerifier = verifier
        pendingState = stateToken

        var components = URLComponents(string: authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: stateToken),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " "))
        ]

        guard let url = components?.url else {
            state = .error("Could not build Spotify authorize URL.")
            return
        }

        state = .signingIn
        NSWorkspace.shared.open(url)
    }

    /// Called from the URL scheme handler. Validates the state token and
    /// exchanges the code for tokens.
    func handleCallbackURL(_ url: URL) {
        guard url.scheme == "smartedge", url.host == "spotify", url.path == "/callback" else {
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        if let errorParam = items.first(where: { $0.name == "error" })?.value {
            state = .error("Spotify denied authorization: \(errorParam)")
            pendingCodeVerifier = nil
            pendingState = nil
            return
        }

        guard
            let code = items.first(where: { $0.name == "code" })?.value,
            let returnedState = items.first(where: { $0.name == "state" })?.value,
            let expectedState = pendingState,
            let verifier = pendingCodeVerifier
        else {
            state = .error("Missing parameters in Spotify callback.")
            return
        }

        // Constant-time-ish comparison would be ideal, but for a short
        // session-only nonce a regular equality check is fine.
        guard returnedState == expectedState else {
            state = .error("State token mismatch — possible CSRF attempt.")
            return
        }

        pendingCodeVerifier = nil
        pendingState = nil

        exchangeTask?.cancel()
        // SpotifyService is @MainActor, so the Task body inherits the main
        // actor and the trailing `exchangeTask = nil` runs on the main thread
        // — no MainActor.run hop needed.
        exchangeTask = Task { [weak self] in
            await self?.exchangeCodeForTokens(code: code, verifier: verifier)
            self?.exchangeTask = nil
        }
    }

    func signOut() {
        do {
            try KeychainStorage.delete(service: keychainServiceID, account: "refresh_token")
            try KeychainStorage.delete(service: keychainServiceID, account: "access_token")
            try KeychainStorage.delete(service: keychainServiceID, account: "access_token_expires_at")
        } catch {
            AppLogger.general.error(
                "Spotify sign-out keychain cleanup failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        devices = []
        playerState = nil
        requiresPremium = false
        refreshTask?.cancel()
        refreshTask = nil
        exchangeTask?.cancel()
        exchangeTask = nil
        pendingCodeVerifier = nil
        pendingState = nil
        state = .signedOut
    }

    // MARK: - Token lifecycle

    /// Returns a non-expired access token, refreshing if needed.
    /// Throws if no refresh token is stored or if the refresh call fails.
    func validAccessToken() async throws -> String {
        guard let storedToken = KeychainStorage.getString(service: keychainServiceID, account: "access_token") else {
            throw APIError.notAuthenticated
        }
        let expiresAt = expiresAtDate()
        // 60 second cushion — refresh proactively so calls in the next minute
        // don't get a freshly-expired token back.
        if let expiresAt = expiresAt, expiresAt > Date().addingTimeInterval(60) {
            return storedToken
        }
        return try await refreshAccessToken()
    }

    /// POST /api/token with `grant_type=refresh_token`. De-duplicates
    /// concurrent calls via `refreshTask` so a UI tap + a background poll
    /// can't fire two refreshes at once.
    ///
    /// Clear `refreshTask` explicitly after the await completes (success or
    /// failure) — a `defer { refreshTask = nil }` would also work since the
    /// MainActor serializes resumption, but writing it out makes the
    /// lifecycle obvious to a future reader and survives refactoring.
    @discardableResult
    func refreshAccessToken() async throws -> String {
        if let existing = refreshTask {
            return try await existing.value
        }
        let task = Task<String, Error> { [weak self] in
            guard let self = self else { throw APIError.notAuthenticated }
            return try await self.performRefresh()
        }
        refreshTask = task
        do {
            let value = try await task.value
            refreshTask = nil
            return value
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = KeychainStorage.getString(service: keychainServiceID, account: "refresh_token") else {
            throw APIError.notAuthenticated
        }
        let clientID = UserDefaults.standard.string(forKey: SettingsKeys.spotifyClientID) ?? ""
        guard !clientID.isEmpty else {
            throw APIError.refreshFailed("No Client ID configured.")
        }

        guard let url = URL(string: tokenURL) else {
            throw APIError.refreshFailed("Invalid token URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientID)
        ]
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.refreshFailed("Unexpected response type.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
                AppLogger.general.error(
                    "Spotify token refresh failed (\(http.statusCode, privacy: .public)): \(bodyText, privacy: .public)"
                )
                // 400/401 from /api/token with grant_type=refresh_token means
                // the refresh token is invalid (revoked / user changed pw).
                // Force the user to sign in again rather than spamming retries.
                if http.statusCode == 400 || http.statusCode == 401 {
                    signOut()
                }
                throw APIError.refreshFailed("HTTP \(http.statusCode)")
            }
            let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            try persistTokens(decoded)
            return decoded.access_token
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.refreshFailed(error.localizedDescription)
        }
    }

    private func expiresAtDate() -> Date? {
        guard
            let raw = KeychainStorage.getString(service: keychainServiceID, account: "access_token_expires_at"),
            let interval = TimeInterval(raw)
        else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    /// Common handling for non-2xx responses on the /me/player/* endpoints.
    /// Distinguishes between the three error classes the user actually
    /// cares about:
    ///
    /// - **401 Unauthorized**: token was revoked server-side. Sign out
    ///   forces a fresh OAuth flow.
    /// - **403 Forbidden**: account doesn't have Spotify Premium. Stays
    ///   signed in (auth itself is fine) but raises the `requiresPremium`
    ///   flag so the UI can show an upgrade hint instead of a scary error
    ///   toast. Doesn't retry — Free accounts get 403 every time.
    /// - **Other 4xx/5xx**: generic error path; surface the status code.
    private func handleAuthFailure(statusCode: Int, endpoint: String) {
        switch statusCode {
        case 401:
            signOut()
            state = .error("Spotify rejected the access token — please sign in again.")
        case 403:
            requiresPremium = true
            // Don't push into .error — that would block other features and
            // suggest something the user can fix on retry. Premium is a
            // subscription decision, not a transient failure.
            AppLogger.general.notice(
                "Spotify endpoint \(endpoint, privacy: .public) returned 403 — likely Free-tier account."
            )
        default:
            state = .error("Spotify \(endpoint) failed (HTTP \(statusCode)).")
        }
    }

    // MARK: - Web API

    /// PUT /me/player with `{device_ids: [id], play: true}`. Transfers
    /// active playback to the given device. Returns true on 2xx, false
    /// (with error logged) otherwise.
    ///
    /// Spotify documents 204 No Content as the success response — we accept
    /// any 2xx to stay robust against future changes.
    @discardableResult
    func transferPlayback(to deviceID: String, autoPlay: Bool = true) async -> Bool {
        guard state == .signedIn else { return false }
        do {
            let token = try await validAccessToken()
            guard let url = URL(string: "\(apiBaseURL)/me/player") else { return false }
            var request = URLRequest(url: url)
            request.httpMethod = "PUT"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "device_ids": [deviceID],
                "play": autoPlay
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                AppLogger.general.error("Spotify transfer: non-HTTP response.")
                return false
            }
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
                AppLogger.general.error(
                    "Spotify transfer failed (\(http.statusCode, privacy: .public)): \(bodyText, privacy: .public)"
                )
                handleAuthFailure(statusCode: http.statusCode, endpoint: "transfer")
                return false
            }
            requiresPremium = false
            // Refresh the device list so the new active device flag is reflected.
            await fetchAvailableDevices()
            return true
        } catch {
            AppLogger.general.error(
                "Spotify transfer threw: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    /// GET /me/player/devices. Updates `@Published devices` on success.
    /// Surfaces errors via `state = .error(…)` so the panel can show them.
    func fetchAvailableDevices() async {
        guard state == .signedIn else { return }
        isLoadingDevices = true
        defer { isLoadingDevices = false }

        do {
            let token = try await validAccessToken()
            guard let url = URL(string: "\(apiBaseURL)/me/player/devices") else {
                state = .error("Could not build devices URL.")
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .error("Unexpected response from devices endpoint.")
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
                AppLogger.general.error(
                    "Spotify devices fetch failed (\(http.statusCode, privacy: .public)): \(bodyText, privacy: .public)"
                )
                handleAuthFailure(statusCode: http.statusCode, endpoint: "devices")
                return
            }

            // First successful response — user *does* have Premium (or
            // Spotify lifted the restriction). Clear the hint either way.
            requiresPremium = false
            let decoded = try JSONDecoder().decode(SpotifyDevicesResponse.self, from: data)
            devices = decoded.devices.map {
                // Spotify can return `id: null` for restricted devices.
                // Use a stable synthetic ID derived from name+type so SwiftUI
                // ForEach doesn't churn rows on each refresh.
                let stableID = $0.id ?? "unknown:\($0.type):\($0.name)"
                return Device(
                    id: stableID,
                    name: $0.name,
                    type: $0.type,
                    isActive: $0.is_active,
                    volumePercent: $0.volume_percent
                )
            }
        } catch let error as APIError {
            state = .error(error.errorDescription ?? "Unknown API error")
        } catch {
            state = .error("Devices fetch failed: \(error.localizedDescription)")
        }
    }

    /// GET /me/player. Updates `@Published playerState`. A 204 No Content
    /// (no active playback) clears playerState to nil rather than erroring.
    func fetchPlayerState() async {
        guard state == .signedIn else { return }
        do {
            let token = try await validAccessToken()
            guard let url = URL(string: "\(apiBaseURL)/me/player") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            // 204 = no playback session active. Not an error; just nothing
            // to display. Don't surface this as an error toast.
            if http.statusCode == 204 {
                playerState = nil
                return
            }

            guard (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
                AppLogger.general.error(
                    "Spotify player state fetch failed (\(http.statusCode, privacy: .public)): \(bodyText, privacy: .public)"
                )
                handleAuthFailure(statusCode: http.statusCode, endpoint: "playerState")
                return
            }

            requiresPremium = false
            let decoded = try JSONDecoder().decode(SpotifyPlayerStateDTO.self, from: data)
            playerState = decoded.toPlayerState()
        } catch {
            AppLogger.general.error(
                "Spotify player state threw: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Playback controls
    //
    // All four are wrappers over `sendPlayerCommand`. Spotify accepts an
    // optional `device_id` query param — we don't pass it because Spotify
    // applies the command to whatever device is currently active. Users who
    // want to switch device should use `transferPlayback(to:)` first.

    /// Resumes playback on the active device. Returns true on 2xx.
    @discardableResult
    func play() async -> Bool {
        return await sendPlayerCommand(method: "PUT", path: "/me/player/play")
    }

    /// Pauses playback on the active device.
    @discardableResult
    func pause() async -> Bool {
        return await sendPlayerCommand(method: "PUT", path: "/me/player/pause")
    }

    /// Skips to the next track.
    @discardableResult
    func next() async -> Bool {
        return await sendPlayerCommand(method: "POST", path: "/me/player/next")
    }

    /// Skips to the previous track.
    @discardableResult
    func previous() async -> Bool {
        return await sendPlayerCommand(method: "POST", path: "/me/player/previous")
    }

    /// Internal helper. After a successful command, refreshes player state
    /// so observers see the new isPlaying/track immediately.
    private func sendPlayerCommand(method: String, path: String) async -> Bool {
        guard state == .signedIn else { return false }
        do {
            let token = try await validAccessToken()
            guard let url = URL(string: "\(apiBaseURL)\(path)") else { return false }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            // PUT /me/player/play accepts an optional JSON body to start a
            // specific URI; we omit it to just resume the current context.

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
                AppLogger.general.error(
                    "Spotify \(method, privacy: .public) \(path, privacy: .public) failed (\(http.statusCode, privacy: .public)): \(bodyText, privacy: .public)"
                )
                // 404 = no active device. Surface as a hint rather than
                // silently failing — the user probably needs to open
                // Spotify on a device first.
                if http.statusCode == 404 {
                    state = .error("No active Spotify device. Open Spotify on a device first.")
                } else {
                    handleAuthFailure(statusCode: http.statusCode, endpoint: path)
                }
                return false
            }
            requiresPremium = false
            await fetchPlayerState()
            return true
        } catch {
            AppLogger.general.error(
                "Spotify \(method, privacy: .public) \(path, privacy: .public) threw: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    // MARK: - Token exchange

    private func exchangeCodeForTokens(code: String, verifier: String) async {
        let clientID = UserDefaults.standard.string(forKey: SettingsKeys.spotifyClientID) ?? ""
        guard !clientID.isEmpty else {
            state = .error("Spotify Client ID disappeared during sign-in.")
            return
        }

        guard let url = URL(string: tokenURL) else {
            state = .error("Could not build Spotify token URL.")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .error("Unexpected response type from Spotify token endpoint.")
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? "(no body)"
                AppLogger.general.error(
                    "Spotify token exchange failed (\(http.statusCode, privacy: .public)): \(bodyText, privacy: .public)"
                )
                state = .error("Token exchange failed (HTTP \(http.statusCode)).")
                return
            }

            let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            try persistTokens(decoded)
            state = .signedIn
        } catch {
            AppLogger.general.error(
                "Spotify token exchange threw: \(error.localizedDescription, privacy: .public)"
            )
            state = .error("Token exchange failed: \(error.localizedDescription)")
        }
    }

    private func persistTokens(_ tokens: SpotifyTokenResponse) throws {
        try KeychainStorage.setString(
            tokens.access_token,
            service: keychainServiceID,
            account: "access_token"
        )
        if let refresh = tokens.refresh_token {
            try KeychainStorage.setString(
                refresh,
                service: keychainServiceID,
                account: "refresh_token"
            )
        }
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expires_in))
        try KeychainStorage.setString(
            String(expiresAt.timeIntervalSince1970),
            service: keychainServiceID,
            account: "access_token_expires_at"
        )
    }

    // MARK: - PKCE helpers
    //
    // The actual crypto lives in `PKCEGenerator` so it can be unit-tested
    // without touching the URL flow. Keep these thin wrappers for call-site
    // brevity; if you're reading this in a stack trace, look one level down.

    private static func makeCodeVerifier() -> String { PKCEGenerator.makeCodeVerifier() }
    private static func makeCodeChallenge(verifier: String) -> String {
        PKCEGenerator.makeCodeChallenge(verifier: verifier)
    }
    private static func makeStateToken() -> String { PKCEGenerator.makeStateToken() }
}

// MARK: - Wire format

private struct SpotifyTokenResponse: Decodable {
    let access_token: String
    let token_type: String
    let expires_in: Int
    let refresh_token: String?
    let scope: String?
}

private struct SpotifyDevicesResponse: Decodable {
    let devices: [SpotifyDeviceDTO]
}

private struct SpotifyDeviceDTO: Decodable {
    let id: String?
    let name: String
    let type: String
    let is_active: Bool
    let volume_percent: Int?
}

private struct SpotifyPlayerStateDTO: Decodable {
    let is_playing: Bool
    let progress_ms: Int?
    let item: SpotifyTrackDTO?
    let device: SpotifyDeviceDTO?

    func toPlayerState() -> SpotifyService.PlayerState {
        let track = item
        // Spotify ranks album images largest-first; pick the first that
        // fits in a notch row to keep download size sane.
        let artURL = track?.album.images.first(where: { $0.width ?? 0 <= 300 })?.url
            ?? track?.album.images.first?.url
        return SpotifyService.PlayerState(
            isPlaying: is_playing,
            trackName: track?.name ?? "",
            artistName: track?.artists.first?.name ?? "",
            albumName: track?.album.name ?? "",
            progressMs: progress_ms ?? 0,
            durationMs: track?.duration_ms ?? 0,
            deviceName: device?.name,
            albumArtURL: artURL.flatMap { URL(string: $0) }
        )
    }
}

private struct SpotifyTrackDTO: Decodable {
    let name: String
    let duration_ms: Int
    let artists: [SpotifyArtistDTO]
    let album: SpotifyAlbumDTO
}

private struct SpotifyArtistDTO: Decodable {
    let name: String
}

private struct SpotifyAlbumDTO: Decodable {
    let name: String
    let images: [SpotifyImageDTO]
}

private struct SpotifyImageDTO: Decodable {
    let url: String
    let width: Int?
    let height: Int?
}

// Base64URL extension lives in Shared/Utilities/PKCEGenerator.swift
