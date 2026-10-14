import XCTest
@testable import Nostalgex

/// The retry after a direct play that gave no picture or starved must be a server stream.
///
/// The watchdog and the starvation ladder both asked Jellyfin and Emby the first-attempt
/// PlaybackInfo question again. For a file the server can direct play, that question has
/// one answer: the file. Measured 2026-10-13 on an 8-bit H.264 MP4, Jellyfin 12.2.0 and
/// Emby 4.10.1.0 alike:
///
///     first-attempt body               SupportsDirectPlay=true, no TranscodingUrl
///                                      -> resolver returned stream.mp4?Static=true, the
///                                         same file, played a second time
///     + EnableDirectPlay=false         Jellyfin: TranscodingUrl. Emby: SupportsDirectStream
///                                      =true and still no TranscodingUrl
///     + EnableDirectStream=false too   both: master.m3u8 TranscodingUrl; variant, init and
///                                      segments 0-2 all HTTP 200
///
/// So the retry sends both flags false, and the resolver never hands back the static file
/// on a retry. The first attempt is untouched: neither key is sent.
final class StallRetryServerStreamTests: XCTestCase {

    private func mp4() -> PlexMediaItem {
        PlexMediaItem(
            id: "4242", title: "Test", artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 2001, originallyAvailableAt: nil, contentRating: nil,
            duration: 100, ratingKey: "4242", partKey: "mediasource_4242", container: "mp4",
            videoCodec: "h264", audioCodec: "aac", videoProfile: nil, bitrate: 8_000,
            genres: [], rating: 0, userRating: 0, type: .movie, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: .movie
        )
    }

    private func json(_ body: PlaybackInfoBody) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func json(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decodeInfo(_ s: String) throws -> JellyfinPlaybackResolver.PlaybackInfoResponse {
        try JSONDecoder().decode(JellyfinPlaybackResolver.PlaybackInfoResponse.self, from: Data(s.utf8))
    }

    // MARK: - Request body

    func testTheFirstAttemptSendsExactlyTheThreeKeysItAlwaysSent() throws {
        let body = try json(JellyfinPlaybackResolver.playbackInfoBody(
            mediaSourceId: "src1", supportsHEVC: true, serverStreamOnly: false))
        XCTAssertEqual(Set(body.keys), ["DeviceProfile", "MediaSourceId", "MaxStreamingBitrate"],
                       "the first attempt must let the server direct play exactly as before")
    }

    func testTheRetryTurnsOffDirectPlayAndDirectStream() throws {
        let body = try json(JellyfinPlaybackResolver.playbackInfoBody(
            mediaSourceId: "src1", supportsHEVC: true, serverStreamOnly: true))
        XCTAssertEqual(body["EnableDirectPlay"] as? Bool, false)
        XCTAssertEqual(body["EnableDirectStream"] as? Bool, false,
                       "Emby 4.10.1.0 with only EnableDirectPlay=false still returns no TranscodingUrl")
    }

    func testTheRetryAsksTheSameQuestionOtherwise() throws {
        let first = try json(JellyfinPlaybackResolver.playbackInfoBody(
            mediaSourceId: "src1", supportsHEVC: true, serverStreamOnly: false))
        var retry = try json(JellyfinPlaybackResolver.playbackInfoBody(
            mediaSourceId: "src1", supportsHEVC: true, serverStreamOnly: true))
        retry.removeValue(forKey: "EnableDirectPlay")
        retry.removeValue(forKey: "EnableDirectStream")
        XCTAssertEqual(NSDictionary(dictionary: retry), NSDictionary(dictionary: first),
                       "same profile, source and bitrate: only the two flags differ")
    }

    func testBothServicesPutTheFlagsOnTheRetryRequestOnly() throws {
        let backends: [(String, (PlexMediaItem, Bool) -> URLRequest?)] = [
            ("Jellyfin", JellyfinAPIService(serverURL: "http://jelly.local:8096", accessToken: "TKN", userId: "u1")
                .playbackInfoRequest),
            ("Emby", EmbyAPIService(serverURL: "http://emby.local:8096", accessToken: "TKN", userId: "u1")
                .playbackInfoRequest),
        ]
        for (name, build) in backends {
            let first = try XCTUnwrap(build(mp4(), false), name)
            let retry = try XCTUnwrap(build(mp4(), true), name)
            for req in [first, retry] {
                XCTAssertEqual(req.httpMethod, "POST", name)
                XCTAssertEqual(req.url?.path, "/Items/4242/PlaybackInfo", name)
                XCTAssertEqual(URLComponents(url: try XCTUnwrap(req.url), resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "userId" }?.value, "u1", name)
                XCTAssertEqual(try json(req)["MediaSourceId"] as? String, "mediasource_4242", name)
            }
            XCTAssertNil(try json(first)["EnableDirectPlay"], "\(name): first attempt unchanged")
            XCTAssertNil(try json(first)["EnableDirectStream"], "\(name): first attempt unchanged")
            XCTAssertEqual(try json(retry)["EnableDirectPlay"] as? Bool, false, name)
            XCTAssertEqual(try json(retry)["EnableDirectStream"] as? Bool, false, name)
        }
    }

    // MARK: - Resolver

    /// The exact answer both servers give the first-attempt question about an MP4.
    private let directPlayAnswer = """
    { "PlaySessionId": "PS1",
      "MediaSources": [ { "Id": "src1", "SupportsDirectPlay": true, "SupportsDirectStream": true,
                          "SupportsTranscoding": true } ] }
    """

    func testTheFirstAttemptStillDirectPlaysWhatTheServerOffers() throws {
        let res = try XCTUnwrap(JellyfinPlaybackResolver.resolve(
            try decodeInfo(directPlayAnswer), serverURL: "http://jelly.local:8096", apiKey: "TKN",
            itemId: "m1", mediaSourceId: "src1"))
        XCTAssertTrue(res.isDirectPlay)
        XCTAssertTrue(res.url.path.hasSuffix("/stream.mp4"))
    }

    func testTheRetryNeverHandsBackTheStaticFile() throws {
        XCTAssertNil(JellyfinPlaybackResolver.resolve(
            try decodeInfo(directPlayAnswer), serverURL: "http://jelly.local:8096", apiKey: "TKN",
            itemId: "m1", mediaSourceId: "src1", serverStreamOnly: true),
            "nil sends the service to its hand-built HLS stream; the static file is what just failed")
    }

    /// Emby's answer when only EnableDirectPlay is off.
    func testTheRetryTreatsDirectStreamWithoutAURLAsNothing() throws {
        let info = try decodeInfo("""
        { "PlaySessionId": "PS2",
          "MediaSources": [ { "Id": "src1", "SupportsDirectPlay": false, "SupportsDirectStream": true,
                              "SupportsTranscoding": true } ] }
        """)
        XCTAssertNil(JellyfinPlaybackResolver.resolve(
            info, serverURL: "http://emby.local:8096", apiKey: "TKN", itemId: "m1", mediaSourceId: "src1",
            serverStreamOnly: true))
    }

    func testTheRetryTakesTheServersTranscodingUrl() throws {
        let info = try decodeInfo("""
        { "PlaySessionId": "PS3",
          "MediaSources": [ { "Id": "src1", "SupportsDirectPlay": false, "SupportsTranscoding": true,
                              "TranscodingUrl": "/videos/m1/master.m3u8?MediaSourceId=src1&PlaySessionId=PS3" } ] }
        """)
        let res = try XCTUnwrap(JellyfinPlaybackResolver.resolve(
            info, serverURL: "http://emby.local:8096", apiKey: "TKN", itemId: "m1", mediaSourceId: "src1",
            serverStreamOnly: true))
        XCTAssertFalse(res.isDirectPlay)
        XCTAssertTrue(res.url.path.hasSuffix("/master.m3u8"))
        XCTAssertEqual(res.playSessionId, "PS3")
    }

    // MARK: - End to end, without a server

    /// Loopback port 9 refuses the PlaybackInfo POST at once, so this runs the hand-built
    /// fallback: an HLS master with its own stoppable session, and a client seek.
    func testJellyfinAndEmbyRetryWithAnHLSStreamWhenPlaybackInfoFails() async throws {
        let backends: [(String, any MediaBackend)] = [
            ("Jellyfin", JellyfinAPIService(serverURL: "http://127.0.0.1:9", accessToken: "k", userId: "u")),
            ("Emby", EmbyAPIService(serverURL: "http://127.0.0.1:9", accessToken: "k", userId: "u")),
        ]
        for (name, backend) in backends {
            let result = await backend.resolveServerStream(for: mp4(), offsetSeconds: 1234)
            let resolved = try XCTUnwrap(result, name)
            XCTAssertFalse(resolved.resolution.isDirectPlay, name)
            XCTAssertTrue(resolved.resolution.url.path.hasSuffix("/master.m3u8"), "\(name): \(resolved.resolution.url.path)")
            XCTAssertFalse(resolved.startsAtOffset, "\(name): the playlist starts at zero, so the player seeks")
        }
    }

    /// Plex was never affected: its transcode request is always a server stream, and it
    /// keeps building the offset into the request.
    func testPlexRetryIsTheTranscodeItAlwaysWas() async throws {
        let plex = PlexAPIService(serverURL: "http://127.0.0.1:9", token: "t", serverID: "m")
        let result = await plex.resolveServerStream(for: mp4(), offsetSeconds: 1234)
        let resolved = try XCTUnwrap(result)
        XCTAssertFalse(resolved.resolution.isDirectPlay)
        XCTAssertTrue(resolved.resolution.url.path.hasSuffix("/start.m3u8"), resolved.resolution.url.path)
        XCTAssertTrue(resolved.startsAtOffset)
    }
}
