import Foundation
import CryptoKit
import Security

/// RFC 7636 PKCE helpers — code verifier, S256 challenge, state nonce.
///
/// Extracted from `SpotifyService` so the crypto can be unit-tested in
/// isolation. The service consumes these via the same call sites; the
/// surface is intentionally minimal (3 static functions).
enum PKCEGenerator {

    /// Returns a base64url-encoded random verifier. RFC 7636 requires
    /// 43–128 characters; 64 random bytes encodes to ~86 chars, comfortably
    /// inside that range.
    static func makeCodeVerifier() -> String {
        return Data(secureRandomBytes(count: 64)).base64URLEncodedString()
    }

    /// SHA-256 of the verifier, base64url-encoded. Spotify (and every other
    /// well-behaved PKCE provider) compares this against the SHA-256 it
    /// derives from the verifier the client sends in the token exchange.
    static func makeCodeChallenge(verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    /// Short random nonce for the OAuth `state` parameter — protects
    /// against CSRF by ensuring the callback we receive came from the
    /// authorize request we originated.
    static func makeStateToken() -> String {
        return Data(secureRandomBytes(count: 16)).base64URLEncodedString()
    }

    /// Crashes on RNG failure — an all-zero verifier would silently break
    /// PKCE security, so this is the right place to be loud. In practice
    /// `SecRandomCopyBytes` only fails on misconfigured boot/sandbox
    /// setups where the app couldn't function anyway.
    static func secureRandomBytes(count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            preconditionFailure("SecRandomCopyBytes failed with status \(status)")
        }
        return bytes
    }
}

extension Data {
    /// RFC 7636 PKCE expects base64url *without* padding. Internal so other
    /// crypto-adjacent code (e.g. future Discord OAuth) can reuse it.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
