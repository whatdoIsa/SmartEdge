import XCTest
@testable import SmartEdge

/// Round-trip tests against the real macOS Keychain. The tests use a unique
/// service name per run so they never collide with each other or with the
/// app's production entries. Each test cleans up its key on tearDown.
final class KeychainStorageTests: XCTestCase {

    private var testService: String!
    private let testAccount = "unit-test-account"

    override func setUp() {
        super.setUp()
        // Unique per-test service id so parallel test runs don't fight over
        // the same keychain item.
        testService = "com.smartedge.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        try? KeychainStorage.delete(service: testService, account: testAccount)
        super.tearDown()
    }

    func testSetAndGetString() throws {
        try KeychainStorage.setString("hello", service: testService, account: testAccount)
        XCTAssertEqual(KeychainStorage.getString(service: testService, account: testAccount), "hello")
    }

    func testOverwriteString() throws {
        try KeychainStorage.setString("first", service: testService, account: testAccount)
        try KeychainStorage.setString("second", service: testService, account: testAccount)
        XCTAssertEqual(KeychainStorage.getString(service: testService, account: testAccount), "second")
    }

    func testEmptyStringDeletes() throws {
        try KeychainStorage.setString("value", service: testService, account: testAccount)
        try KeychainStorage.setString("", service: testService, account: testAccount)
        XCTAssertNil(KeychainStorage.getString(service: testService, account: testAccount))
    }

    func testNilDeletes() throws {
        try KeychainStorage.setString("value", service: testService, account: testAccount)
        try KeychainStorage.setString(nil, service: testService, account: testAccount)
        XCTAssertNil(KeychainStorage.getString(service: testService, account: testAccount))
    }

    func testDeleteIsIdempotent() {
        // Deleting a non-existent item must not throw. This is the
        // property the production sign-out path depends on — we delete
        // refresh + access + expires_at in one pass without checking
        // whether each exists first.
        XCTAssertNoThrow(try KeychainStorage.delete(service: testService, account: testAccount))
        XCTAssertNoThrow(try KeychainStorage.delete(service: testService, account: testAccount))
    }

    func testMissingItemReturnsNil() {
        XCTAssertNil(KeychainStorage.getString(service: testService, account: "never-written"))
    }

    func testUnicodeRoundTrip() throws {
        let value = "토큰-こんにちは-🔐"
        try KeychainStorage.setString(value, service: testService, account: testAccount)
        XCTAssertEqual(KeychainStorage.getString(service: testService, account: testAccount), value)
    }
}
