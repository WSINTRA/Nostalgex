import XCTest
@testable import Nostalgex

/// Pure unit tests for the Jellyfin PlaybackInfo flow — DeviceProfile construction and the
/// response→URL selection. The live PlaybackInfo POST itself isn't tested (no network mock
/// infra, matching the existing JellyfinAPITests), but every pure piece around it is.
final class JellyfinPlaybackInfoTests: XCTestCase {

    private func decodeInfo(_ json: String) throws -> JellyfinPlaybackResolver.PlaybackInfoResponse {
        try JSONDecoder().decode(JellyfinPlaybackResolver.PlaybackInfoResponse.self, from: Data(json.utf8))
    }

    private func profileJSON(supportsHEVC: Bool) throws -> String {
        let data = try JSONEncoder().encode(JellyfinPlaybackResolver.deviceProfile(supportsHEVC: supportsHEVC))
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - DeviceProfile

    func testDeviceProfileExcludesHEVCWhenUnsupported() throws {
        let json = try profileJSON(supportsHEVC: false)
        XCTAssertFalse(json.contains("hevc"), "HEVC must not be offered when the device can't decode it")
        XCTAssertTrue(json.contains("\"Protocol\":\"hls\""))
        // Transcode container is always fMP4, never MPEG-TS.
        XCTAssertTrue(json.contains("\"Container\":\"mp4\""))
        XCTAssertFalse(json.contains("\"Container\":\"ts\""))
    }

    func testDeviceProfileIncludesHEVCWhenSupported() throws {
        let json = try profileJSON(supportsHEVC: true)
        XCTAssertTrue(json.contains("hevc"))
        XCTAssertTrue(json.contains("h264"))
        XCTAssertTrue(json.contains("\"Container\":\"mp4\""))
    }

    func testDeviceProfileEncodesExpectedShape() throws {
        let json = try profileJSON(supportsHEVC: true)
        XCTAssertTrue(json.contains("DirectPlayProfiles"))
        XCTAssertTrue(json.contains("TranscodingProfiles"))
        XCTAssertTrue(json.contains("Streaming"))
    }

    func testDeviceProfileNamesTheBlackPictureCases() throws {
        let json = try profileJSON(supportsHEVC: true)
        XCTAssertTrue(json.contains("CodecProfiles"))
        XCTAssertTrue(json.contains("\"Property\":\"VideoCodecTag\""), "hev1 HEVC must be remuxed, not direct played")
        XCTAssertTrue(json.contains("hvc1|dvh1"))
        XCTAssertTrue(json.contains("\"Property\":\"VideoBitDepth\""), "10-bit H.264 has no decoder on Apple TV")
        XCTAssertFalse(try profileJSON(supportsHEVC: false).contains("VideoCodecTag"), "no HEVC rule when HEVC is not offered")
    }

    // MARK: - Subtitles never go into the picture

    private func bodyJSON(serverStreamOnly: Bool) throws -> [String: Any] {
        let data = try JSONEncoder().encode(JellyfinPlaybackResolver.playbackInfoBody(
            mediaSourceId: "src1", supportsHEVC: true, serverStreamOnly: serverStreamOnly))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Without it Jellyfin 12.2.0 burned every default or forced subtitle track into a full
    /// libx264 re-encode, and Emby 4.10.1.0 every forced one (measured 2026-10-19).
    func testPlaybackInfoAsksForNoSubtitleStreamOnEveryAttempt() throws {
        for serverStreamOnly in [false, true] {
            let body = try bodyJSON(serverStreamOnly: serverStreamOnly)
            XCTAssertEqual(body["SubtitleStreamIndex"] as? Int, -1, "serverStreamOnly=\(serverStreamOnly)")
            XCTAssertEqual(body["MediaSourceId"] as? String, "src1",
                           "the server honours -1 only with a matching MediaSourceId; without one Jellyfin burned in")
        }
    }

    func testBothServicesSendTheSubtitleFields() throws {
        let item = PlexMediaItem(
            id: "4242", title: "Film", artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 2001, originallyAvailableAt: nil, contentRating: nil,
            duration: 100, ratingKey: "4242", partKey: "mediasource_4242", container: "mkv",
            videoCodec: "h264", audioCodec: "aac", videoProfile: nil, bitrate: 8_000,
            genres: [], rating: 0, userRating: 0, type: .movie, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: .movie
        )
        let requests: [(String, URLRequest?)] = [
            ("Jellyfin", JellyfinAPIService(serverURL: "http://jelly.local:8096", accessToken: "TKN", userId: "u1")
                .playbackInfoRequest(for: item, serverStreamOnly: false)),
            ("Emby", EmbyAPIService(serverURL: "http://emby.local:8096", accessToken: "TKN", userId: "u1")
                .playbackInfoRequest(for: item, serverStreamOnly: false)),
        ]
        for (name, request) in requests {
            let data = try XCTUnwrap(try XCTUnwrap(request, name).httpBody, name)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], name)
            XCTAssertEqual(body["SubtitleStreamIndex"] as? Int, -1, name)
            let profile = try XCTUnwrap(body["DeviceProfile"] as? [String: Any], name)
            let subs = try XCTUnwrap(profile["SubtitleProfiles"] as? [[String: String]], name)
            XCTAssertFalse(subs.isEmpty, name)
        }
    }

    /// Image formats matter as much as text: with only text formats listed, Jellyfin still
    /// burned PGS and VobSub tracks.
    func testDeviceProfileListsEverySubtitleFormatAsExternal() throws {
        for hevc in [true, false] {
            let subs = JellyfinPlaybackResolver.deviceProfile(supportsHEVC: hevc).SubtitleProfiles
            let formats = Set(subs.map { $0.Format.lowercased() })
            for format in ["srt", "subrip", "ass", "ssa", "mov_text", "webvtt", "pgssub", "dvdsub", "dvbsub"] {
                XCTAssertTrue(formats.contains(format), "\(format) missing (hevc=\(hevc))")
            }
            XCTAssertEqual(Set(subs.map(\.Method)), ["External"], "nothing may be Encode (burn in) or Hls (cues 10 s late on fMP4)")
        }
        XCTAssertEqual(Set(JellyfinPlaybackResolver.deviceProfile(supportsHEVC: true, burningSubtitle: true).SubtitleProfiles.map(\.Method)),
                       ["Encode"], "only when burning the forced track")
        let json = try profileJSON(supportsHEVC: true)
        XCTAssertTrue(json.contains("\"SubtitleProfiles\":[{"), "encoded under the server's key")
        XCTAssertTrue(json.contains("\"Method\":\"External\""))
    }

    // MARK: - A forced track in the viewer's language is the one exception: burned in

    private func streams(_ json: String) throws -> [JellyfinPlaybackResolver.PlaybackInfoResponse.MediaStream] {
        try JSONDecoder().decode([JellyfinPlaybackResolver.PlaybackInfoResponse.MediaStream].self, from: Data(json.utf8))
    }

    func testAForcedTrackInTheViewersLanguageIsBurned() throws {
        let s = try streams("""
        [ { "Index": 0, "Type": "Video" }, { "Index": 1, "Type": "Audio", "Language": "eng" },
          { "Index": 2, "Type": "Subtitle", "Language": "eng", "IsForced": true, "IsDefault": false } ]
        """)
        XCTAssertEqual(JellyfinPlaybackResolver.forcedSubtitleToBurn(in: s, preferredLanguage: "en"), 2)
    }

    func testADefaultOnlyTrackIsNeverBurned() throws {
        let s = try streams("""
        [ { "Index": 2, "Type": "Subtitle", "Language": "eng", "IsDefault": true, "IsForced": false } ]
        """)
        XCTAssertNil(JellyfinPlaybackResolver.forcedSubtitleToBurn(in: s, preferredLanguage: "en"),
                     "full subtitles are the viewer's choice and full screen only")
    }

    func testNoSubtitlesNothingBurned() throws {
        XCTAssertNil(JellyfinPlaybackResolver.forcedSubtitleToBurn(in: try streams("[ { \"Index\": 0, \"Type\": \"Video\" } ]"), preferredLanguage: "en"))
        XCTAssertNil(JellyfinPlaybackResolver.forcedSubtitleToBurn(in: nil, preferredLanguage: "en"))
    }

    func testAForcedTrackInAnotherLanguageIsNotBurned() throws {
        let s = try streams("""
        [ { "Index": 2, "Type": "Subtitle", "Language": "ger", "IsForced": true } ]
        """)
        XCTAssertNil(JellyfinPlaybackResolver.forcedSubtitleToBurn(in: s, preferredLanguage: "en"))
        XCTAssertNil(JellyfinPlaybackResolver.forcedSubtitleToBurn(in: s, preferredLanguage: "es"))
    }

    /// Emby kept "ger" from the file, Jellyfin 12.2.0 reported the same track as "deu".
    func testBothISOCodesForTheViewersLanguageCount() throws {
        for code in ["ger", "deu"] {
            let s = try streams("[ { \"Index\": 2, \"Type\": \"Subtitle\", \"Language\": \"\(code)\", \"IsForced\": true } ]")
            XCTAssertEqual(JellyfinPlaybackResolver.forcedSubtitleToBurn(in: s, preferredLanguage: "de"), 2, code)
        }
    }

    /// The lab's Blu-ray layout: English PGS default, SRT, ASS, then an English forced PGS.
    func testOnABluRayLayoutTheForcedImageTrackIsTheOneBurned() throws {
        let s = try streams("""
        [ { "Index": 0, "Type": "Video" }, { "Index": 1, "Type": "Audio", "Language": "eng" },
          { "Index": 2, "Type": "Subtitle", "Language": "eng", "IsDefault": true, "IsForced": false },
          { "Index": 3, "Type": "Subtitle", "Language": "eng" },
          { "Index": 4, "Type": "Subtitle", "Language": "eng" },
          { "Index": 5, "Type": "Subtitle", "Language": "eng", "IsForced": true } ]
        """)
        XCTAssertEqual(JellyfinPlaybackResolver.forcedSubtitleToBurn(in: s, preferredLanguage: "en"), 5)
    }

    func testOnlySubtitleTracksCount() throws {
        let s = try streams("[ { \"Index\": 1, \"Type\": \"Audio\", \"Language\": \"eng\", \"IsForced\": true } ]")
        XCTAssertNil(JellyfinPlaybackResolver.forcedSubtitleToBurn(in: s, preferredLanguage: "en"))
    }

    /// Asked for a track by index with External profiles, both servers answered External and
    /// copied the video; with Encode both burned it in.
    func testTheBurnBodyNamesTheTrackAndAsksForEncode() throws {
        let data = try JSONEncoder().encode(JellyfinPlaybackResolver.playbackInfoBody(
            mediaSourceId: "src1", supportsHEVC: true, serverStreamOnly: false, burningSubtitle: 5))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["SubtitleStreamIndex"] as? Int, 5)
        let profile = try XCTUnwrap(body["DeviceProfile"] as? [String: Any])
        let subs = try XCTUnwrap(profile["SubtitleProfiles"] as? [[String: String]])
        XCTAssertFalse(subs.isEmpty)
        XCTAssertEqual(Set(subs.map { $0["Method"] ?? "" }), ["Encode"])
    }

    // MARK: - The two PlaybackInfo requests, through both services

    /// Answers PlaybackInfo like a server: the first request (no subtitle) gets `first`,
    /// a request naming a track gets `burned`, or an error when `burned` is nil.
    private final class FakeServer: @unchecked Sendable {
        let first: String
        let burned: String?
        private let lock = NSLock()
        private(set) var bodies: [[String: Any]] = []
        init(first: String, burned: String?) { self.first = first; self.burned = burned }
        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
            lock.withLock { bodies.append(body) }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            if (body["SubtitleStreamIndex"] as? Int) == -1 { return (Data(first.utf8), response) }
            guard let burned else { throw URLError(.timedOut) }
            return (Data(burned.utf8), response)
        }
        var sentIndexes: [Int] { lock.withLock { bodies.compactMap { $0["SubtitleStreamIndex"] as? Int } } }
    }

    private func answer(session: String, forced: Bool) -> String {
        """
        { "PlaySessionId": "\(session)",
          "MediaSources": [ { "Id": "mediasource_4242", "SupportsDirectPlay": false, "SupportsTranscoding": true,
            "TranscodingUrl": "/videos/4242/master.m3u8?MediaSourceId=mediasource_4242&PlaySessionId=\(session)&ApiKey=TKN",
            "MediaStreams": [ { "Index": 0, "Type": "Video" }, { "Index": 1, "Type": "Audio", "Language": "eng" },
              { "Index": 2, "Type": "Subtitle", "Language": "eng", "IsDefault": true },
              { "Index": 5, "Type": "Subtitle", "Language": "eng", "IsForced": \(forced) } ] } ] }
        """
    }

    private func mkv() -> PlexMediaItem {
        PlexMediaItem(
            id: "4242", title: "Film", artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 2001, originallyAvailableAt: nil, contentRating: nil,
            duration: 100, ratingKey: "4242", partKey: "mediasource_4242", container: "mkv",
            videoCodec: "h264", audioCodec: "aac", videoProfile: nil, bitrate: 8_000,
            genres: [], rating: 0, userRating: 0, type: .movie, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: .movie
        )
    }

    private func negotiate(_ server: FakeServer) async -> [(String, PlaybackResolution?)] {
        let send: JellyfinPlaybackResolver.PlaybackInfoSend = { try await server.send($0) }
        let jellyfin = await JellyfinAPIService(serverURL: "http://jelly.local:8096", accessToken: "TKN", userId: "u1")
            .negotiatePlayback(for: mkv(), serverStreamOnly: false, preferredSubtitleLanguage: "en", send: send)
        let emby = await EmbyAPIService(serverURL: "http://emby.local:8096", accessToken: "TKN", userId: "u1")
            .negotiatePlayback(for: mkv(), serverStreamOnly: false, preferredSubtitleLanguage: "en", send: send)
        return [("Jellyfin", jellyfin), ("Emby", emby)]
    }

    func testAFileWithAForcedTrackAsksASecondTimeAndPlaysTheBurnedStream() async throws {
        let server = FakeServer(first: answer(session: "plain", forced: true), burned: answer(session: "burned", forced: true))
        for (name, resolution) in await negotiate(server) {
            let r = try XCTUnwrap(resolution, name)
            XCTAssertEqual(r.playSessionId, "burned", name)
            XCTAssertTrue(r.url.absoluteString.contains("PlaySessionId=burned"), name)
        }
        XCTAssertEqual(server.sentIndexes, [-1, 5, -1, 5], "no subtitle first, then the forced track, on each service")
        let methods = server.bodies.map { body -> Set<String> in
            let profiles = (body["DeviceProfile"] as? [String: Any])?["SubtitleProfiles"] as? [[String: String]] ?? []
            return Set(profiles.map { $0["Method"] ?? "" })
        }
        XCTAssertEqual(methods, [["External"], ["Encode"], ["External"], ["Encode"]])
    }

    func testAFileWithOnlyADefaultTrackAsksOnce() async throws {
        let server = FakeServer(first: answer(session: "plain", forced: false), burned: nil)
        for (name, resolution) in await negotiate(server) {
            XCTAssertEqual(try XCTUnwrap(resolution, name).playSessionId, "plain", name)
        }
        XCTAssertEqual(server.sentIndexes, [-1, -1], "one request per service, no subtitle")
    }

    func testWhenTheBurnRequestFailsTheFilmStillPlaysWithoutIt() async throws {
        let server = FakeServer(first: answer(session: "plain", forced: true), burned: nil)
        for (name, resolution) in await negotiate(server) {
            XCTAssertEqual(try XCTUnwrap(resolution, name).playSessionId, "plain", name)
        }
        XCTAssertEqual(server.sentIndexes, [-1, 5, -1, 5])
    }

    // MARK: - Dolby Vision arrives signalled as Dolby Vision

    private func rangeCondition(_ codec: String, supportsHEVC: Bool) -> JellyfinDeviceProfile.ProfileCondition? {
        JellyfinPlaybackResolver.deviceProfile(supportsHEVC: supportsHEVC).CodecProfiles
            .first { $0.Codec == codec }?.Conditions.first { $0.Property == "VideoRangeType" }
    }

    /// Without the list Jellyfin 12.2.0 sent a DV profile 5 file as plain hvc1 with no dvcC,
    /// which a player shows green and purple. With it: dvh1, dvcC, CODECS="dvh1.05.06".
    func testHEVCDeclaresTheDynamicRangesAppleTVRenders() throws {
        let condition = try XCTUnwrap(rangeCondition("hevc", supportsHEVC: true))
        XCTAssertEqual(condition.Condition, "EqualsAny")
        XCTAssertFalse(condition.IsRequired, "optional, like the H.264 bit-depth cap")
        let ranges = Set(condition.Value.split(separator: "|").map(String.init))
        for range in ["SDR", "HDR10", "HLG", "DOVI", "DOVIWithHDR10", "DOVIWithHLG", "DOVIWithSDR"] {
            XCTAssertTrue(ranges.contains(range), "\(range) missing")
        }
        XCTAssertFalse(ranges.contains("DOVIWithEL"),
                       "profile 7 must not be sent as Dolby Vision; Jellyfin strips its RPU to HDR10 instead")
    }

    func testOnlyHEVCCarriesTheRangeList() {
        XCTAssertNil(rangeCondition("h264", supportsHEVC: true), "H.264 is SDR only; nothing to declare")
        XCTAssertNil(rangeCondition("hevc", supportsHEVC: false), "no HEVC profile at all on an Apple TV HD")
    }

    // MARK: - resolve()

    func testResolveSelectsTranscodingUrlAndSession() throws {
        let info = try decodeInfo("""
        { "PlaySessionId": "PS123",
          "MediaSources": [ { "Id": "src1", "TranscodingUrl": "/Videos/m1/master.m3u8?MediaSourceId=src1&api_key=TKN" } ] }
        """)
        let res = try XCTUnwrap(JellyfinPlaybackResolver.resolve(
            info, serverURL: "http://jelly.local:8096", apiKey: "TKN", itemId: "m1", mediaSourceId: "src1"))
        XCTAssertFalse(res.isDirectPlay)
        XCTAssertEqual(res.playSessionId, "PS123")
        XCTAssertTrue(res.url.absoluteString.hasPrefix("http://jelly.local:8096"))
        XCTAssertTrue(res.url.absoluteString.contains("/Videos/m1/master.m3u8"))
        XCTAssertTrue(res.url.absoluteString.contains("api_key=TKN"))
    }

    func testResolveAppendsApiKeyWhenMissing() throws {
        let info = try decodeInfo("""
        { "PlaySessionId": "PS1",
          "MediaSources": [ { "Id": "src1", "TranscodingUrl": "/Videos/m1/master.m3u8?MediaSourceId=src1" } ] }
        """)
        let res = try XCTUnwrap(JellyfinPlaybackResolver.resolve(
            info, serverURL: "http://jelly.local:8096", apiKey: "TKN", itemId: "m1", mediaSourceId: "src1"))
        let occurrences = res.url.absoluteString.components(separatedBy: "api_key=").count - 1
        XCTAssertEqual(occurrences, 1, "api_key must be appended exactly once")
    }

    func testResolveDoesNotDuplicateApiKey() throws {
        let info = try decodeInfo("""
        { "MediaSources": [ { "Id": "src1", "TranscodingUrl": "/Videos/m1/master.m3u8?api_key=TKN" } ] }
        """)
        let res = try XCTUnwrap(JellyfinPlaybackResolver.resolve(
            info, serverURL: "http://jelly.local:8096", apiKey: "TKN", itemId: "m1", mediaSourceId: "src1"))
        let occurrences = res.url.absoluteString.components(separatedBy: "api_key=").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func testResolveFallsBackToDirectStream() throws {
        let info = try decodeInfo("""
        { "PlaySessionId": "PS9",
          "MediaSources": [ { "Id": "src1", "SupportsDirectPlay": true } ] }
        """)
        let res = try XCTUnwrap(JellyfinPlaybackResolver.resolve(
            info, serverURL: "http://jelly.local:8096", apiKey: "TKN", itemId: "m1", mediaSourceId: "src1"))
        XCTAssertTrue(res.isDirectPlay)
        XCTAssertTrue(res.url.absoluteString.contains("/Videos/m1/stream"))
        XCTAssertTrue(res.url.absoluteString.contains("Static=true"))
        XCTAssertEqual(res.playSessionId, "PS9")
    }

    func testResolveReturnsNilWhenNoPlayableSource() throws {
        let info = try decodeInfo("""
        { "MediaSources": [ { "Id": "src1", "SupportsDirectPlay": false, "SupportsTranscoding": false } ] }
        """)
        XCTAssertNil(JellyfinPlaybackResolver.resolve(
            info, serverURL: "http://jelly.local:8096", apiKey: "TKN", itemId: "m1", mediaSourceId: "src1"))
    }

    func testResolvePicksMatchingMediaSourceId() throws {
        let info = try decodeInfo("""
        { "MediaSources": [
            { "Id": "other", "TranscodingUrl": "/Videos/m1/master.m3u8?MediaSourceId=other&api_key=TKN" },
            { "Id": "src1",  "TranscodingUrl": "/Videos/m1/master.m3u8?MediaSourceId=src1&api_key=TKN" } ] }
        """)
        let res = try XCTUnwrap(JellyfinPlaybackResolver.resolve(
            info, serverURL: "http://jelly.local:8096", apiKey: "TKN", itemId: "m1", mediaSourceId: "src1"))
        XCTAssertTrue(res.url.absoluteString.contains("MediaSourceId=src1"))
    }

    // MARK: - Tuning in at a schedule offset

    /// Tuning into a channel mid-programme on Jellyfin: the HLS URL must be the server's
    /// TranscodingUrl untouched and the client must do the seeking. Jellyfin's segment
    /// handler answers 400 "StartTimeTicks is not allowed." to any segment URL carrying
    /// StartTimeTicks, and its playlist copies the master's query string onto every
    /// segment, so an offset smuggled into the URL made every tuned-in transcode fail and
    /// auto-skip to the next title (measured against Jellyfin 12.2.0, 2026-10-06; same
    /// check in 10.10.7 and 10.11.0). Recorded PlaybackInfo response, trimmed.
    func testOffsetTuneLeavesTranscodingUrlVerbatimAndSeeksClientSide() throws {
        let info = try decodeInfo("""
        { "PlaySessionId": "040049f188504bd2a104ce71f6987ef7",
          "MediaSources": [ { "Id": "c7851b0aa9ae4ac34456de4d4392a853",
            "SupportsDirectPlay": false, "SupportsDirectStream": false, "SupportsTranscoding": true,
            "TranscodingUrl": "/videos/c7851b0a-a9ae-4ac3-4456-de4d4392a853/master.m3u8?DeviceId=atv&MediaSourceId=c7851b0aa9ae4ac34456de4d4392a853&VideoCodec=h264,hevc&AudioCodec=aac,ac3,eac3,mp3&SegmentContainer=mp4&PlaySessionId=040049f188504bd2a104ce71f6987ef7&ApiKey=TKN&TranscodeReasons=ContainerNotSupported,AudioCodecNotSupported" } ] }
        """)
        let base = try XCTUnwrap(JellyfinPlaybackResolver.resolve(
            info, serverURL: "http://127.0.0.1:8096", apiKey: "TKN",
            itemId: "c7851b0aa9ae4ac34456de4d4392a853", mediaSourceId: "c7851b0aa9ae4ac34456de4d4392a853"))

        let tuned = JellyfinPlaybackResolver.offsetPlayback(base, offsetSeconds: 1483)

        XCTAssertFalse(tuned.startsAtOffset, "the client seeks; Jellyfin's HLS timeline always starts at zero")
        XCTAssertEqual(tuned.resolution.url, base.url, "the TranscodingUrl must go to AVPlayer exactly as the server built it")
        XCTAssertFalse(tuned.resolution.url.absoluteString.contains("StartTimeTicks"),
                       "StartTimeTicks on a Jellyfin HLS URL is inherited by every segment request and rejected with 400")
        XCTAssertEqual(tuned.resolution.playSessionId, "040049f188504bd2a104ce71f6987ef7")
        XCTAssertFalse(tuned.resolution.isDirectPlay)
    }

    /// Zero offset (tuning in exactly at a programme start) has nothing to seek either way.
    func testZeroOffsetTuneIsUnchanged() throws {
        let base = PlaybackResolution(url: URL(string: "http://127.0.0.1:8096/videos/x/master.m3u8?ApiKey=TKN")!,
                                      playSessionId: "PS1", isDirectPlay: false)
        let tuned = JellyfinPlaybackResolver.offsetPlayback(base, offsetSeconds: 0)
        XCTAssertFalse(tuned.startsAtOffset)
        XCTAssertEqual(tuned.resolution.url, base.url)
    }
}
