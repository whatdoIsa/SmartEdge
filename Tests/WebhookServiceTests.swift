import XCTest
@testable import SmartEdge

/// Tests the URL/scheme validation paths and result mapping of WebhookService.
/// The actual network call is exercised by injecting a URLSession backed by
/// URLProtocol stubs so we don't hit real hooks.slack.com endpoints.
@MainActor
final class WebhookServiceTests: XCTestCase {

    func testRejectsNonHTTPSURL() async {
        let service = WebhookService(session: .shared)
        let result = await service.postSlackMessage("hi", to: "http://example.com")
        XCTAssertEqual(result, .invalidURL)
    }

    func testRejectsInvalidURLString() async {
        let service = WebhookService(session: .shared)
        let result = await service.postSlackMessage("hi", to: "not a url at all")
        XCTAssertEqual(result, .invalidURL)
    }

    func testAcceptsHTTPSURL() async {
        // Stubbed session that returns 200 OK regardless of request.
        let session = stubbedSession(statusCode: 200, body: Data())
        let service = WebhookService(session: session)
        let result = await service.postSlackMessage("hi", to: "https://hooks.slack.com/services/x/y/z")
        XCTAssertEqual(result, .success)
    }

    func testMapsNon2xxToHTTPStatus() async {
        let session = stubbedSession(statusCode: 404, body: Data())
        let service = WebhookService(session: session)
        let result = await service.postSlackMessage("hi", to: "https://hooks.slack.com/services/x/y/z")
        XCTAssertEqual(result, .httpStatus(404))
    }

    func testMapsTransportErrorToTransportResult() async {
        let session = stubbedSession(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        let service = WebhookService(session: session)
        let result = await service.postSlackMessage("hi", to: "https://hooks.slack.com/services/x/y/z")
        if case .transportError = result {
            // pass
        } else {
            XCTFail("Expected .transportError, got \(result)")
        }
    }

    // MARK: - URLProtocol stubbing

    private func stubbedSession(statusCode: Int? = nil, body: Data = Data(), error: Error? = nil) -> URLSession {
        StubURLProtocol.stubbedStatusCode = statusCode
        StubURLProtocol.stubbedBody = body
        StubURLProtocol.stubbedError = error

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

/// Minimal URLProtocol that returns a canned response. Static state is fine
/// since tests run serially per XCTestCase and each test sets its own stub.
private final class StubURLProtocol: URLProtocol {
    static var stubbedStatusCode: Int?
    static var stubbedBody: Data = Data()
    static var stubbedError: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = StubURLProtocol.stubbedError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: StubURLProtocol.stubbedStatusCode ?? 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubURLProtocol.stubbedBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
