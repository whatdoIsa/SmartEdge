import XCTest
import CryptoKit
@testable import SmartEdge

/// Cryptographic correctness tests for the PKCE helpers. These would
/// previously have been impossible (the helpers were `private static`
/// inside SpotifyService) — they're extracted now precisely so we can
/// verify the bits that protect the OAuth flow.
final class PKCEGeneratorTests: XCTestCase {

    // MARK: - Code verifier

    func testCodeVerifierLength() {
        // 64 random bytes → base64url encodes to 86 chars (no padding).
        // RFC 7636 allows 43–128, Spotify accepts the same range.
        let verifier = PKCEGenerator.makeCodeVerifier()
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertLessThanOrEqual(verifier.count, 128)
        XCTAssertEqual(verifier.count, 86) // Pin the actual value we produce.
    }

    func testCodeVerifierCharset() {
        // RFC 7636 § 4.1: only `A-Z / a-z / 0-9 / - / . / _ / ~` allowed.
        // base64url uses A-Za-z0-9-_ (no padding), so this is a subset.
        let verifier = PKCEGenerator.makeCodeVerifier()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        XCTAssertTrue(
            verifier.unicodeScalars.allSatisfy { allowed.contains($0) },
            "Verifier contains characters outside PKCE-allowed set: \(verifier)"
        )
    }

    func testCodeVerifierUniqueness() {
        // Statistically: collision odds on 512 bits of entropy are negligible.
        // 100 samples is plenty to catch a "we accidentally hardcoded it" bug.
        var seen = Set<String>()
        for _ in 0..<100 {
            seen.insert(PKCEGenerator.makeCodeVerifier())
        }
        XCTAssertEqual(seen.count, 100, "PKCE verifier appears non-random")
    }

    // MARK: - Code challenge

    func testCodeChallengeIsSHA256OfVerifier() {
        let verifier = "test-verifier-for-deterministic-hash"
        let challenge = PKCEGenerator.makeCodeChallenge(verifier: verifier)

        // Compute expected challenge independently using CryptoKit.
        let expectedHash = SHA256.hash(data: Data(verifier.utf8))
        let expectedChallenge = Data(expectedHash).base64URLEncodedString()

        XCTAssertEqual(challenge, expectedChallenge)
    }

    func testCodeChallengeHasNoPadding() {
        // base64url MUST NOT include `=` padding per RFC 7636. Spotify
        // rejects challenges with padding.
        let verifier = PKCEGenerator.makeCodeVerifier()
        let challenge = PKCEGenerator.makeCodeChallenge(verifier: verifier)
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }

    func testCodeChallengeLength() {
        // SHA-256 → 32 bytes → 43 base64url chars (no padding).
        let challenge = PKCEGenerator.makeCodeChallenge(verifier: "anything")
        XCTAssertEqual(challenge.count, 43)
    }

    // MARK: - State token

    func testStateTokenLength() {
        // 16 random bytes → 22 base64url chars (no padding).
        let token = PKCEGenerator.makeStateToken()
        XCTAssertEqual(token.count, 22)
    }

    func testStateTokenUniqueness() {
        var seen = Set<String>()
        for _ in 0..<100 {
            seen.insert(PKCEGenerator.makeStateToken())
        }
        XCTAssertEqual(seen.count, 100)
    }

    // MARK: - base64URL extension

    func testBase64URLEncodingMatchesRFC() {
        // RFC 4648 § 5 base64url test vectors.
        XCTAssertEqual(Data().base64URLEncodedString(), "")
        XCTAssertEqual(Data([0xfb]).base64URLEncodedString(), "-w") // standard "+w=="
        XCTAssertEqual(Data([0xff]).base64URLEncodedString(), "_w") // standard "/w=="
    }
}
