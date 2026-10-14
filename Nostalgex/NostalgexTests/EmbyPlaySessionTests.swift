import XCTest
@testable import Nostalgex

/// Every HLS URL Nostalgex hands Emby carries a real `PlaySessionId`.
///
/// Emby does not copy the master playlist's query string onto segment URLs the way
/// Jellyfin does. It writes `hls1/main/0.mp4?PlaySessionId=<id>` and nothing else, taking
/// the id from the master request. The hand-built fallback sent none, so every segment
/// asked for `PlaySessionId=` with no value, and Emby answered each one HTTP 400 "Value
/// cannot be null. (Parameter 'key')" while the master and variant playlists still answered
/// 200. A direct play that failed, on an Emby server, therefore never recovered.
///
/// Measured against Emby 4.10.1.0 on 2026-10-13, 8-bit H.264 MKV and MP4 sources:
///
///     no PlaySessionId on master   master 200, variant 200, init 400, segments 0-2 400
///     PlaySessionId = UUID()       master 200, variant 200, init 200, segments 0-2 200
final class EmbyPlaySessionTests: XCTestCase {

    private let emby = EmbyAPIService(serverURL: "http://emby.local:8096", accessToken: "TKN", userId: "u1")

    private func item() -> PlexMediaItem {
        PlexMediaItem(
            id: "1666", title: "Test", artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 2001, originallyAvailableAt: nil, contentRating: nil,
            duration: 100, ratingKey: "1666", partKey: "mediasource_1666", container: "mkv",
            videoCodec: "h264", audioCodec: "aac", videoProfile: nil, bitrate: 3_200,
            genres: [], rating: 0, userRating: 0, type: .movie, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: .movie
        )
    }

    private func sessions(in url: URL) -> [String?] {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .filter { $0.name == "PlaySessionId" }.map(\.value)
    }

    func testTheHandBuiltStreamCarriesTheSessionItWasGiven() throws {
        let url = try XCTUnwrap(emby.buildTranscodeURL(for: item(), sessionID: "sess-1"))
        let c = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(c.path, "/Videos/1666/master.m3u8")
        XCTAssertEqual(sessions(in: url), ["sess-1"], "exactly one, with the value the caller will stop")
        let q = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(q["MediaSourceId"], "mediasource_1666")
        XCTAssertEqual(q["api_key"], "TKN")
        XCTAssertEqual(q["SegmentContainer"], "mp4")
        XCTAssertNil(q["StartTimeTicks"], "Emby rejects a start time on segment requests too; the player seeks")
    }

    /// The protocol entry point is what any caller without its own id reaches.
    func testTheProtocolEntryPointNeverSendsAnEmptySession() throws {
        let backend: any MediaBackend = emby
        let a = try XCTUnwrap(backend.buildTranscodeURL(for: item()))
        let b = try XCTUnwrap(backend.buildTranscodeURL(for: item()))
        let first = try XCTUnwrap(sessions(in: a).first ?? nil, "no PlaySessionId means every segment 400s")
        XCTAssertFalse(first.isEmpty, "an empty PlaySessionId is the bug itself")
        XCTAssertNotEqual(sessions(in: a), sessions(in: b), "each stream is its own session, so stopping one stops no other")
    }

    /// Loopback port 9 refuses the PlaybackInfo POST at once, which sends the resolver down
    /// the hand-built fallback. The id it reports must be the one on the URL, or the
    /// channel change that follows stops nothing and the encode runs on unwatched.
    func testThePlaybackInfoFallbackReportsTheSessionOnItsURL() async throws {
        let offline = EmbyAPIService(serverURL: "http://127.0.0.1:9", accessToken: "k", userId: "u")
        let resolved = await offline.resolveTranscodePlayback(for: item())
        let resolution = try XCTUnwrap(resolved)
        XCTAssertFalse(resolution.isDirectPlay)
        let reported = try XCTUnwrap(resolution.playSessionId, "the fallback session has to be stoppable")
        XCTAssertFalse(reported.isEmpty)
        XCTAssertEqual(sessions(in: resolution.url), [reported])
    }

    /// Both rungs below a direct play on Emby: the runtime fallback and the 1080p retry.
    func testEveryEmbyHLSURLCarriesANonEmptySession() throws {
        let urls = [
            try XCTUnwrap(emby.buildTranscodeURL(for: item())),
            try XCTUnwrap(emby.buildTranscodeURL(for: item(), sessionID: "s")),
            try XCTUnwrap(emby.cappedTranscodeURL(for: item(), offsetSeconds: 0, sessionID: "s")),
        ]
        for url in urls {
            let ids = sessions(in: url)
            XCTAssertEqual(ids.count, 1, url.absoluteString)
            XCTAssertFalse((ids.first ?? nil)?.isEmpty ?? true, url.absoluteString)
        }
    }
}
