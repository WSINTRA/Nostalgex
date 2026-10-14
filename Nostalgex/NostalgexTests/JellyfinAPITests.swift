import XCTest
@testable import Nostalgex

final class JellyfinAPITests: XCTestCase {

    private func makeService(serverID: String = "srv1") -> JellyfinAPIService {
        JellyfinAPIService(serverURL: "http://jelly.local:8096", accessToken: "TKN", userId: "user1", serverID: serverID)
    }

    /// Decodes a representative Jellyfin movie item and maps it to PlexMediaItem.
    private func decodeItem(_ json: String) throws -> JellyfinItem {
        try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))
    }

    func testProviderIdsMapToTmdbAndImdb() throws {
        let item = try decodeItem("""
        { "Id": "abc", "Name": "The Matrix", "ProviderIds": { "Tmdb": "603", "Imdb": "tt0133093" } }
        """)
        XCTAssertEqual(item.tmdbID, "603")
        XCTAssertEqual(item.imdbID, "tt0133093")
    }

    func testProviderIdsAreCaseInsensitive() throws {
        let item = try decodeItem("""
        { "Id": "abc", "Name": "X", "ProviderIds": { "tmdb": "1", "IMDB": "tt1" } }
        """)
        XCTAssertEqual(item.tmdbID, "1")
        XCTAssertEqual(item.imdbID, "tt1")
    }

    func testTicksConvertToMinutes() {
        // 90 minutes == 90 * 600,000,000 ticks
        XCTAssertEqual(JellyfinAPIService.minutes(fromTicks: 90 * 600_000_000), 90)
        XCTAssertEqual(JellyfinAPIService.minutes(fromTicks: nil), 0)
    }

    func testDateOnlyTrimsISO8601() {
        XCTAssertEqual(JellyfinAPIService.dateOnly("1999-03-31T00:00:00.000Z"), "1999-03-31")
        XCTAssertNil(JellyfinAPIService.dateOnly(nil))
    }

    func testSectionTypeMapping() {
        XCTAssertEqual(JellyfinAPIService.sectionType(for: "tvshows"), "show")
        XCTAssertEqual(JellyfinAPIService.sectionType(for: "movies"), "movie")
        XCTAssertEqual(JellyfinAPIService.sectionType(for: "musicvideos"), "musicvideo")
        XCTAssertEqual(JellyfinAPIService.sectionType(for: nil), "movie")
    }

    func testParseMovieItemFullMapping() throws {
        let item = try decodeItem("""
        {
          "Id": "m1", "Name": "Heat", "Overview": "Cops and robbers.",
          "ProductionYear": 1995, "PremiereDate": "1995-12-15T00:00:00Z",
          "OfficialRating": "R", "CommunityRating": 8.3,
          "RunTimeTicks": 100200000000, "Genres": ["Crime", "Drama"],
          "ProviderIds": { "Tmdb": "949", "Imdb": "tt0113277" },
          "Studios": [ { "Name": "Warner Bros." } ],
          "MediaSources": [ { "Id": "src1", "Container": "mp4", "Bitrate": 8000000,
            "MediaStreams": [ { "Type": "Video", "Codec": "h264", "Profile": "High" },
                              { "Type": "Audio", "Codec": "aac" } ] } ]
        }
        """)
        let svc = makeService(serverID: "srv1")
        let mapped = try XCTUnwrap(svc.parseMovieItem(item, isMusicSection: false))

        XCTAssertEqual(mapped.title, "Heat")
        XCTAssertEqual(mapped.year, 1995)
        XCTAssertEqual(mapped.originallyAvailableAt, "1995-12-15")
        XCTAssertEqual(mapped.contentRating, "R")
        XCTAssertEqual(mapped.duration, 167)               // 100.2e9 ticks / 6e8
        XCTAssertEqual(mapped.tmdbID, "949")
        XCTAssertEqual(mapped.imdbID, "tt0113277")
        XCTAssertEqual(mapped.genres, ["Crime", "Drama"])
        XCTAssertEqual(mapped.studio, "Warner Bros.")
        XCTAssertEqual(mapped.container, "mp4")
        XCTAssertEqual(mapped.videoCodec, "h264")
        XCTAssertEqual(mapped.audioCodec, "aac")
        XCTAssertEqual(mapped.bitrate, 8000)               // bps -> kbps
        XCTAssertEqual(mapped.ratingKey, "m1")
        XCTAssertEqual(mapped.serverID, "srv1")
        // Composite id is server-prefixed for cross-server uniqueness.
        XCTAssertEqual(mapped.id, "srv1:m1")
    }

    func testZeroDurationItemsAreDropped() throws {
        let item = try decodeItem(#"{ "Id": "x", "Name": "Trailer", "RunTimeTicks": 0 }"#)
        XCTAssertNil(makeService().parseMovieItem(item, isMusicSection: false))
    }

    func testDirectPlayURLForCompatibleMp4() throws {
        let item = try decodeItem("""
        { "Id": "m1", "Name": "A", "RunTimeTicks": 6000000000,
          "MediaSources": [ { "Id": "src1", "Container": "mp4",
            "MediaStreams": [ { "Type": "Video", "Codec": "h264" }, { "Type": "Audio", "Codec": "aac" } ] } ] }
        """)
        let svc = makeService()
        let mapped = try XCTUnwrap(svc.parseMovieItem(item, isMusicSection: false))
        let url = try XCTUnwrap(svc.buildDirectPlayURL(for: mapped))
        let s = url.absoluteString
        XCTAssertTrue(s.contains("/Videos/m1/stream"))
        XCTAssertTrue(s.contains("Static=true"))
        XCTAssertTrue(s.contains("MediaSourceId=src1"))
        XCTAssertTrue(s.contains("api_key=TKN"))
    }

    /// An MP4 saved as `.mkv` probes as `mov`, passes the direct-play gate, and was served by
    /// `/stream` as `video/x-matroska`, which AVPlayer refuses (-11828). Asking for
    /// `stream.mp4` gets the same bytes labelled `video/mp4`. Every direct-play builder,
    /// Jellyfin, Emby and the PlaybackInfo branch, has to ask the same way.
    func testDirectPlayAsksForTheFileAsMp4OnEveryBuilder() throws {
        let item = try decodeItem("""
        { "Id": "m1", "Name": "A", "RunTimeTicks": 6000000000,
          "MediaSources": [ { "Id": "src1", "Container": "mov",
            "Path": "/media/Chappelle's Show - S01E02.mkv",
            "MediaStreams": [ { "Type": "Video", "Codec": "h264" }, { "Type": "Audio", "Codec": "aac" } ] } ] }
        """)
        let jf = makeService()
        let emby = EmbyAPIService(serverURL: "http://jf.local:8096", accessToken: "TKN", userId: "u1")
        let mapped = try XCTUnwrap(jf.parseMovieItem(item, isMusicSection: false))
        let info = try JSONDecoder().decode(JellyfinPlaybackResolver.PlaybackInfoResponse.self, from: Data("""
        { "MediaSources": [ { "Id": "src1", "SupportsDirectPlay": true } ], "PlaySessionId": "p" }
        """.utf8))
        let resolved = try XCTUnwrap(JellyfinPlaybackResolver.resolve(
            info, serverURL: "http://jf.local:8096", apiKey: "TKN", itemId: "m1", mediaSourceId: "src1"))
        XCTAssertTrue(resolved.isDirectPlay)

        for url in [try XCTUnwrap(jf.buildDirectPlayURL(for: mapped)),
                    try XCTUnwrap(emby.buildDirectPlayURL(for: mapped)),
                    resolved.url] {
            let c = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(c.path, "/Videos/m1/stream.mp4", url.absoluteString)
            let q = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(q["Static"], "true", "the file itself, never a remux")
            XCTAssertEqual(q["MediaSourceId"], "src1")
            XCTAssertEqual(q["api_key"], "TKN")
        }
    }

    /// Jellyfin 12.2 with legacy authorization off (the fresh-install default) answers 401 to
    /// `api_key`, so the hand-built HLS URLs must also carry `ApiKey`. Emby keeps `api_key`.
    func testHandBuiltJellyfinStreamsCarryApiKey() throws {
        let item = try decodeItem("""
        { "Id": "m1", "Name": "A", "RunTimeTicks": 6000000000,
          "MediaSources": [ { "Id": "src1", "Container": "mkv",
            "MediaStreams": [ { "Type": "Video", "Codec": "h264" }, { "Type": "Audio", "Codec": "aac" } ] } ] }
        """)
        let jf = makeService()
        let mapped = try XCTUnwrap(jf.parseMovieItem(item, isMusicSection: false))
        for url in [try XCTUnwrap(jf.buildTranscodeURL(for: mapped)),
                    try XCTUnwrap(jf.cappedTranscodeURL(for: mapped, offsetSeconds: 0, sessionID: "s"))] {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(items.filter { $0.name == "ApiKey" }.map(\.value), ["TKN"], url.absoluteString)
            XCTAssertEqual(items.filter { $0.name == "api_key" }.map(\.value), ["TKN"], "older servers")
        }
        let once = JellyfinAPIService.addingApiKey(URL(string: "http://h/x?ApiKey=A&api_key=A")!, token: "A")
        XCTAssertEqual(once.absoluteString.components(separatedBy: "ApiKey=").count - 1, 1, "never added twice")
    }

    func testDirectPlayLeavesBlackPictureFilesToTheServer() throws {
        func mapped(_ streams: String) throws -> PlexMediaItem {
            let item = try decodeItem("""
            { "Id": "m3", "Name": "C", "RunTimeTicks": 6000000000,
              "MediaSources": [ { "Id": "s", "Container": "mp4", "MediaStreams": [ \(streams), { "Type": "Audio", "Codec": "aac" } ] } ] }
            """)
            return try XCTUnwrap(makeService().parseMovieItem(item, isMusicSection: false))
        }
        let tenBitH264 = try mapped(#"{ "Type": "Video", "Codec": "h264", "BitDepth": 10 }"#)
        XCTAssertEqual(tenBitH264.videoBitDepth, 10, "bit depth is read from the video stream")
        let hevcMp4 = try mapped(#"{ "Type": "Video", "Codec": "hevc", "BitDepth": 10 }"#)
        let eightBitH264 = try mapped(#"{ "Type": "Video", "Codec": "h264", "BitDepth": 8 }"#)
        let emby = EmbyAPIService(serverURL: "http://emby.local:8096", accessToken: "TKN", userId: "u")
        for backend in [makeService() as any MediaBackend, emby] {
            XCTAssertNil(backend.buildDirectPlayURL(for: tenBitH264), "10-bit H.264 plays as sound over black")
            XCTAssertNil(backend.buildDirectPlayURL(for: hevcMp4), "only the server knows whether it is tagged hvc1")
            XCTAssertNotNil(backend.buildDirectPlayURL(for: eightBitH264))
        }
    }

    func testDirectPlayRejectedForMkvContainer() throws {
        let item = try decodeItem("""
        { "Id": "m2", "Name": "B", "RunTimeTicks": 6000000000,
          "MediaSources": [ { "Id": "s", "Container": "mkv",
            "MediaStreams": [ { "Type": "Video", "Codec": "h264" }, { "Type": "Audio", "Codec": "aac" } ] } ] }
        """)
        let svc = makeService()
        let mapped = try XCTUnwrap(svc.parseMovieItem(item, isMusicSection: false))
        XCTAssertNil(svc.buildDirectPlayURL(for: mapped), "mkv must transcode even with supported codecs")
        let transcode = try XCTUnwrap(svc.buildTranscodeURL(for: mapped))
        XCTAssertTrue(transcode.absoluteString.contains("/Videos/m2/master.m3u8"))
    }

    func testAuthorizationHeaderOmitsEmptyToken() {
        let withToken = JellyfinAPIService.authorizationHeader(deviceID: "DEV", token: "T")
        XCTAssertTrue(withToken.contains("Token=\"T\""))
        XCTAssertTrue(withToken.contains("DeviceId=\"DEV\""))

        let noToken = JellyfinAPIService.authorizationHeader(deviceID: "DEV", token: "")
        XCTAssertFalse(noToken.contains("Token="))
        XCTAssertTrue(noToken.hasPrefix("MediaBrowser "))
    }
}

@MainActor
final class BackendKindPersistenceTests: XCTestCase {
    private final class InMemoryStore: Nostalgex.CredentialStoring {
        var values: [String: String] = [:]
        @discardableResult
        func save(key: String, value: String) -> Bool {
            values[key] = value
            return true
        }
        func load(key: String) -> String? { values[key] }
        func delete(key: String) { values[key] = nil }
    }

    func testBackendKindDefaultsToPlex() {
        let store = InMemoryStore()
        let state = AppState(credentialStore: store)
        state.serverURL = "https://plex.example"
        state.token = "t"
        state.saveCredentials()

        let rehydrated = AppState(credentialStore: store)
        rehydrated.loadCredentials()
        XCTAssertEqual(rehydrated.backendKind, .plex)
    }

    func testJellyfinBackendRoundTrips() {
        let store = InMemoryStore()
        let state = AppState(credentialStore: store)
        state.backendKind = .jellyfin
        state.token = "JF_TOKEN"
        state.jellyfinUserId = "user-42"
        state.serverURL = "http://jelly.local:8096"
        state.saveCredentials()

        let rehydrated = AppState(credentialStore: store)
        rehydrated.loadCredentials()
        XCTAssertEqual(rehydrated.backendKind, .jellyfin)
        XCTAssertEqual(rehydrated.jellyfinUserId, "user-42")
        XCTAssertEqual(rehydrated.token, "JF_TOKEN")
    }

    func testClearCredentialsResetsBackendToPlex() {
        let store = InMemoryStore()
        let state = AppState(credentialStore: store)
        state.backendKind = .jellyfin
        state.jellyfinUserId = "u"
        state.token = "t"
        state.serverURL = "http://x"
        state.saveCredentials()

        state.clearCredentials()
        XCTAssertEqual(state.backendKind, .plex)
        XCTAssertEqual(state.jellyfinUserId, "")
    }
}
