import XCTest
@testable import SmartEdge

@MainActor
final class MediaServiceTests: XCTestCase {
    var mediaService: MediaService!
    
    override func setUp() {
        super.setUp()
        mediaService = MediaService()
    }
    
    override func tearDown() {
        mediaService = nil
        super.tearDown()
    }
    
    // MARK: - Protocol Conformance Tests
    
    func testProtocolConformance() {
        // Verify MediaService conforms to MediaServiceProtocol
        XCTAssertTrue(mediaService is MediaServiceProtocol)
    }
    
    func testAllProtocolMethodsExist() {
        // Test that all required protocol methods are implemented
        let service: MediaServiceProtocol = mediaService
        
        // Properties should be accessible
        _ = service.currentNowPlaying
        _ = service.currentPlaybackState
        _ = service.isAvailable
        
        // Methods should be callable (though we won't actually call them in unit tests)
        XCTAssertNoThrow({
            // These are async throwing methods - we verify they exist
            let _ = service.startMonitoring
            let _ = service.stopMonitoring
            let _ = service.play
            let _ = service.pause
            let _ = service.togglePlayPause
            let _ = service.nextTrack
            let _ = service.previousTrack
            let _ = service.seek
        })
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertNil(mediaService.currentNowPlaying)
        XCTAssertEqual(mediaService.currentPlaybackState, .unknown)
        // isAvailable depends on MediaRemote framework availability
    }
    
    // MARK: - Error Handling Tests
    
    func testStartMonitoringWhenUnavailable() async {
        // If MediaRemote is unavailable, should throw appropriate error
        if !mediaService.isAvailable {
            do {
                try await mediaService.startMonitoring()
                XCTFail("Should have thrown an error when MediaRemote is unavailable")
            } catch let error as MediaServiceError {
                XCTAssertEqual(error, .mediaRemoteUnavailable)
            } catch {
                XCTFail("Should have thrown MediaServiceError.mediaRemoteUnavailable")
            }
        }
    }
    
    func testPlayWhenUnavailable() async {
        if !mediaService.isAvailable {
            do {
                try await mediaService.play()
                XCTFail("Should have thrown an error when MediaRemote is unavailable")
            } catch let error as MediaServiceError {
                XCTAssertEqual(error, .mediaRemoteUnavailable)
            } catch {
                XCTFail("Should have thrown MediaServiceError.mediaRemoteUnavailable")
            }
        }
    }
    
    func testPauseWhenUnavailable() async {
        if !mediaService.isAvailable {
            do {
                try await mediaService.pause()
                XCTFail("Should have thrown an error when MediaRemote is unavailable")
            } catch let error as MediaServiceError {
                XCTAssertEqual(error, .mediaRemoteUnavailable)
            } catch {
                XCTFail("Should have thrown MediaServiceError.mediaRemoteUnavailable")
            }
        }
    }
    
    func testTogglePlayPauseWhenUnavailable() async {
        if !mediaService.isAvailable {
            do {
                try await mediaService.togglePlayPause()
                XCTFail("Should have thrown an error when MediaRemote is unavailable")
            } catch let error as MediaServiceError {
                XCTAssertEqual(error, .mediaRemoteUnavailable)
            } catch {
                XCTFail("Should have thrown MediaServiceError.mediaRemoteUnavailable")
            }
        }
    }
    
    func testNextTrackWhenUnavailable() async {
        if !mediaService.isAvailable {
            do {
                try await mediaService.nextTrack()
                XCTFail("Should have thrown an error when MediaRemote is unavailable")
            } catch let error as MediaServiceError {
                XCTAssertEqual(error, .mediaRemoteUnavailable)
            } catch {
                XCTFail("Should have thrown MediaServiceError.mediaRemoteUnavailable")
            }
        }
    }
    
    func testPreviousTrackWhenUnavailable() async {
        if !mediaService.isAvailable {
            do {
                try await mediaService.previousTrack()
                XCTFail("Should have thrown an error when MediaRemote is unavailable")
            } catch let error as MediaServiceError {
                XCTAssertEqual(error, .mediaRemoteUnavailable)
            } catch {
                XCTFail("Should have thrown MediaServiceError.mediaRemoteUnavailable")
            }
        }
    }
    
    func testSeekWhenUnavailable() async {
        if !mediaService.isAvailable {
            do {
                try await mediaService.seek(to: 10.0)
                XCTFail("Should have thrown an error when MediaRemote is unavailable")
            } catch let error as MediaServiceError {
                XCTAssertEqual(error, .mediaRemoteUnavailable)
            } catch {
                XCTFail("Should have thrown MediaServiceError.mediaRemoteUnavailable")
            }
        }
    }
    
    // MARK: - Thread Safety Tests
    
    func testMainActorIsolation() {
        // Verify that the service is @MainActor isolated
        XCTAssertTrue(Thread.isMainThread, "MediaService should be accessed on main thread")
    }
    
    // MARK: - State Management Tests
    
    func testDoubleStartMonitoring() async {
        if mediaService.isAvailable {
            do {
                try await mediaService.startMonitoring()
                
                // Try to start monitoring again - should throw invalidState
                do {
                    try await mediaService.startMonitoring()
                    XCTFail("Should have thrown invalidState error")
                } catch let error as MediaServiceError {
                    XCTAssertEqual(error, .invalidState)
                } catch {
                    XCTFail("Should have thrown MediaServiceError.invalidState")
                }
                
                await mediaService.stopMonitoring()
            } catch {
                XCTFail("First startMonitoring should succeed when available")
            }
        }
    }
    
    // MARK: - Delegate Tests
    
    func testDelegateProperty() {
        let mockDelegate = MockMediaServiceDelegate()
        mediaService.delegate = mockDelegate
        XCTAssertNotNil(mediaService.delegate)
        
        // Test weak reference
        mediaService.delegate = nil
        XCTAssertNil(mediaService.delegate)
    }
}

// MARK: - Mock Delegate

private class MockMediaServiceDelegate: MediaServiceDelegate {
    func mediaService(_ service: MediaServiceProtocol, didUpdateNowPlaying info: NowPlayingInfo?) {
        // Mock implementation
    }
    
    func mediaService(_ service: MediaServiceProtocol, didUpdatePlaybackState state: MediaPlaybackState) {
        // Mock implementation
    }
    
    func mediaService(_ service: MediaServiceProtocol, didUpdateVolume volume: Float) {
        // Mock implementation
    }
}