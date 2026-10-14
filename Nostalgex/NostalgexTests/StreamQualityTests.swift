import XCTest
@testable import Nostalgex

final class StreamQualityTests: XCTestCase {

    private func service(_ url: String) -> PlexAPIService {
        PlexAPIService(serverURL: url, token: "t")
    }

    // MARK: - LAN detection

    func testLocalServer_privateRanges() {
        XCTAssertTrue(service("http://192.168.1.50:32400").isLikelyLocalServer)
        XCTAssertTrue(service("http://10.0.0.5:32400").isLikelyLocalServer)
        XCTAssertTrue(service("http://172.16.0.1:32400").isLikelyLocalServer)
        XCTAssertTrue(service("http://172.31.255.1:32400").isLikelyLocalServer)
        XCTAssertTrue(service("http://127.0.0.1:32400").isLikelyLocalServer)
        XCTAssertTrue(service("http://169.254.1.1:32400").isLikelyLocalServer)
        XCTAssertTrue(service("http://localhost:32400").isLikelyLocalServer)
        XCTAssertTrue(service("http://tower.local:32400").isLikelyLocalServer)
    }

    /// Plex hands out plex.direct hostnames with the address dash-encoded. A LAN
    /// connection still resolves to a private address, so it must read as local.
    func testLocalServer_plexDirectEncodedPrivateAddress() {
        XCTAssertTrue(service("https://192-168-1-50.abc123.plex.direct:32400").isLikelyLocalServer)
        XCTAssertTrue(service("https://10-1-2-3.abc123.plex.direct:32400").isLikelyLocalServer)
    }

    func testRemoteServer_publicAddresses() {
        XCTAssertFalse(service("https://1-2-3-4.abc123.plex.direct:32400").isLikelyLocalServer)
        XCTAssertFalse(service("https://plex.example.com:32400").isLikelyLocalServer)
        XCTAssertFalse(service("https://8.8.8.8:32400").isLikelyLocalServer)
    }

    /// 172.x is only private within 16-31. 172.15 and 172.32 are public.
    func testRemoteServer_172BoundariesAreNotAllPrivate() {
        XCTAssertFalse(service("http://172.15.0.1:32400").isLikelyLocalServer)
        XCTAssertFalse(service("http://172.32.0.1:32400").isLikelyLocalServer)
    }

    /// A hostname carrying digits must not be mistaken for an address.
    func testRemoteServer_numericLookingHostname() {
        XCTAssertFalse(service("https://172.20.example.com:32400").isLikelyLocalServer)
    }

    // MARK: - Quality tiers

    /// Auto must reach 4K so users on fast connections aren't capped; slow ones are
    /// protected by the app's own starvation ladder, not by a low ceiling.
    func testAutoReaches4K() {
        XCTAssertEqual(StreamQuality.auto.width, 3840)
        XCTAssertEqual(StreamQuality.auto.height, 2160)
        XCTAssertEqual(StreamQuality.auto.maxBitrateKbps, 40_000)
    }

    /// Plex's adaptive mode (`autoAdjustQuality=1`) is never requested: measured 2026-10-06,
    /// it turned every both-streams-re-encoded film into 3-second segments that slowed to
    /// one per 6 seconds after the eighth, and tvOS 26 gave up at 24 seconds (-15628).
    func testNoQualityEverAsksPlexToAdaptMidStream() {
        for q in StreamQuality.allCases {
            XCTAssertFalse(q.allowsAutoAdjust, "\(q) must not request autoAdjustQuality=1")
        }
        XCTAssertEqual(StreamQuality.maximum.width, StreamQuality.auto.width)
    }

    /// Direct play has no adaptive fallback, so auto's ceiling there stays well below
    /// its transcode ceiling.
    func testAutoDirectPlayCeilingIsConservative() {
        XCTAssertLessThan(
            StreamQuality.auto.remoteDirectPlayCeilingKbps,
            StreamQuality.auto.maxBitrateKbps
        )
    }

    func testMaximumDoesNotCapDirectPlay() {
        XCTAssertEqual(StreamQuality.maximum.remoteDirectPlayCeilingKbps, .max)
    }

    func testTiersDescendMonotonically() {
        let ordered: [StreamQuality] = [.maximum, .high, .medium, .low]
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            XCTAssertGreaterThan(a.maxBitrateKbps, b.maxBitrateKbps, "\(a) should exceed \(b)")
            XCTAssertGreaterThanOrEqual(a.width, b.width, "\(a) should be at least \(b)")
        }
    }

    // MARK: - Retryable HTTP statuses

    /// A proxy in front of Plex returns these while the upstream is still working.
    /// Reported in the field as an HTTP 504 that aborted a whole library scan.
    func testGatewayErrorsAreRetryable() {
        XCTAssertTrue(PlexAPIService.isRetryableHTTPStatus(502))
        XCTAssertTrue(PlexAPIService.isRetryableHTTPStatus(503))
        XCTAssertTrue(PlexAPIService.isRetryableHTTPStatus(504))
        XCTAssertTrue(PlexAPIService.isRetryableHTTPStatus(408))
        XCTAssertTrue(PlexAPIService.isRetryableHTTPStatus(429))
    }

    /// Auth and client errors must fail fast — retrying a bad token just delays the
    /// "sign in again" prompt three times over.
    func testClientAndAuthErrorsAreNotRetryable() {
        XCTAssertFalse(PlexAPIService.isRetryableHTTPStatus(200))
        XCTAssertFalse(PlexAPIService.isRetryableHTTPStatus(401))
        XCTAssertFalse(PlexAPIService.isRetryableHTTPStatus(403))
        XCTAssertFalse(PlexAPIService.isRetryableHTTPStatus(404))
        XCTAssertFalse(PlexAPIService.isRetryableHTTPStatus(500))
    }

    func testPersistenceRoundTrip() {
        let original = StreamQuality.current
        defer { StreamQuality.current = original }

        StreamQuality.current = .low
        XCTAssertEqual(StreamQuality.current, .low)
        StreamQuality.current = .high
        XCTAssertEqual(StreamQuality.current, .high)
    }
}
