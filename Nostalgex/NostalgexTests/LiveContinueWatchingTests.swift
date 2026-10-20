import XCTest
@testable import Nostalgex

/// Runs the real `PlaybackTracker` and `PlexAPIService` against a real Plex server and
/// checks Continue Watching is left exactly as it was. Skipped unless these are set
/// (xcodebuild passes `TEST_RUNNER_`-prefixed variables through to the test process):
///
///   TEST_RUNNER_NOSTALGEX_LIVE_PLEX_URL    server base URL
///   TEST_RUNNER_NOSTALGEX_LIVE_PLEX_TOKEN  token
///   TEST_RUNNER_NOSTALGEX_LIVE_FILM        rating key of an unwatched film with no resume point
///   TEST_RUNNER_NOSTALGEX_LIVE_EPISODE     rating key of an unwatched episode whose show is not in Continue Watching
///
/// It writes to that server. The film is surfed for two real minutes: reports carry no
/// position, so Plex lists it in Now Playing and stores nothing. The episode is watched
/// through the gate on a fake clock, so the test unscrobbles it afterwards to put the
/// server back the way it found it.
@MainActor
final class LiveContinueWatchingTests: XCTestCase {

    private struct Live {
        let api: PlexAPIService
        let film: String?
        let episode: String?
    }

    private func live() throws -> Live {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["NOSTALGEX_LIVE_PLEX_URL"], let token = env["NOSTALGEX_LIVE_PLEX_TOKEN"],
              !url.isEmpty, !token.isEmpty else {
            throw XCTSkip("No live Plex server configured")
        }
        return Live(api: PlexAPIService(serverURL: url, token: token),
                    film: env["NOSTALGEX_LIVE_FILM"], episode: env["NOSTALGEX_LIVE_EPISODE"])
    }

    private struct Snapshot: Equatable {
        let viewOffset: Int?
        let viewCount: Int?
        let lastViewedAt: Int?
    }

    private struct Container: Decodable {
        struct Inner: Decodable { let Metadata: [Entry]? }
        struct Entry: Decodable {
            let ratingKey: String
            let title: String?
            let duration: Int?
            let viewOffset: Int?
            let viewCount: Int?
            let lastViewedAt: Int?
        }
        let MediaContainer: Inner
    }

    private func get(_ api: PlexAPIService, _ path: String, _ query: [URLQueryItem] = []) async throws -> [Container.Entry] {
        let req = try XCTUnwrap(api.watchStateGuard.request(method: "GET", path: path, query: query))
        let response = await api.reportTransport.send(req)
        let (status, body) = try XCTUnwrap(response)
        XCTAssertEqual(status, 200, path)
        return try JSONDecoder().decode(Container.self, from: body).MediaContainer.Metadata ?? []
    }

    /// Rating key -> viewOffset for every session in Now Playing.
    private func nowPlaying(_ api: PlexAPIService) async throws -> [String: Int] {
        let sessions = try await get(api, "/status/sessions")
        return Dictionary(sessions.map { ($0.ratingKey, $0.viewOffset ?? 0) }, uniquingKeysWith: { a, _ in a })
    }

    private func continueWatching(_ api: PlexAPIService) async throws -> [String] {
        try await get(api, "/hubs/continueWatching/items", [.init(name: "count", value: "200")]).map(\.ratingKey)
    }

    private func snapshot(_ api: PlexAPIService, _ rk: String) async throws -> (Snapshot, Container.Entry) {
        let entries = try await get(api, "/library/metadata/\(rk)")
        let e = try XCTUnwrap(entries.first)
        return (Snapshot(viewOffset: e.viewOffset, viewCount: e.viewCount, lastViewedAt: e.lastViewedAt), e)
    }

    private func item(_ e: Container.Entry, type: MediaType) -> PlexMediaItem {
        PlexMediaItem(
            id: e.ratingKey, title: e.title ?? e.ratingKey, artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: nil, originallyAvailableAt: nil, contentRating: nil,
            duration: max(1, (e.duration ?? 60_000) / 60_000), ratingKey: e.ratingKey, partKey: nil,
            container: nil, videoCodec: nil, audioCodec: nil, videoProfile: nil, bitrate: nil,
            genres: [], rating: 0, userRating: 0, type: type, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: type == .episode ? .tv : .movie
        )
    }

    /// Drives the tracker on a fake clock: `seconds` of watching in 10 second pulses,
    /// each pulse a real request.
    private func watch(
        _ api: PlexAPIService, _ item: PlexMediaItem, seconds: Int, seekOffset: Int = 0,
        realTime: Bool = false, beforeStop: () async throws -> Void = {}
    ) async rethrows -> Bool {
        var clock = Date()
        let queue = ReportQueue()
        let tracker = PlaybackTracker(item: item, seekOffset: seekOffset, plexAPI: api, showNowPlaying: true, markWatched: true, queue: queue, now: { clock })
        tracker.onPlaybackReady()
        for _ in 0..<(seconds / 10) {
            if realTime { try? await Task.sleep(nanoseconds: 10_000_000_000) }
            clock += 10
            tracker.timelineTickForTesting()
        }
        await queue.drain()
        try await beforeStop()
        tracker.stop()
        await queue.drain()
        return tracker.scrobbled
    }

    func testSurfingAnUnwatchedFilmLeavesNoTrace() async throws {
        let live = try live()
        let rk = try XCTUnwrap(live.film, "NOSTALGEX_LIVE_FILM not set")
        let rowBefore = try await continueWatching(live.api)
        let (before, entry) = try await snapshot(live.api, rk)
        XCTAssertNil(before.viewOffset, "pick a film with no resume point")
        XCTAssertNil(before.viewCount, "pick an unwatched film")

        // Tune in 25 minutes in and surf for two real minutes.
        let counted = try await watch(live.api, item(entry, type: .movie), seconds: 120, seekOffset: 1500, realTime: true) {
            // The reports land: Plex lists the film in Now Playing, and stores nothing.
            let (during, _) = try await snapshot(live.api, rk)
            let rowDuring = try await continueWatching(live.api)
            let playing = try await nowPlaying(live.api)
            print("[Live] film \(rk) during=\(during) nowPlaying=\(playing[rk].map { "offset \($0)" } ?? "absent") inCW=\(rowDuring.contains(rk))")
            XCTAssertNotNil(playing[rk], "Now Playing shows the film")
            XCTAssertEqual(during, before, "no resume point mid-surf")
            XCTAssertFalse(rowDuring.contains(rk))
        }
        XCTAssertFalse(counted)

        let (after, _) = try await snapshot(live.api, rk)
        let rowAfter = try await continueWatching(live.api)
        let playingAfter = try await nowPlaying(live.api)
        print("[Live] film \(rk) before=\(before) after=\(after) CW \(rowBefore.count) -> \(rowAfter.count) nowPlayingAfterStop=\(playingAfter[rk] != nil)")
        XCTAssertEqual(after, before)
        XCTAssertEqual(rowAfter, rowBefore)
        XCTAssertNil(playingAfter[rk], "stopped clears Now Playing")
    }

    func testWatchingAnEpisodeCountsItButLeavesContinueWatchingAlone() async throws {
        let live = try live()
        let rk = try XCTUnwrap(live.episode, "NOSTALGEX_LIVE_EPISODE not set")
        let rowBefore = try await continueWatching(live.api)
        let (before, entry) = try await snapshot(live.api, rk)
        XCTAssertNil(before.viewCount, "pick an unwatched episode")

        let episode = item(entry, type: .episode)
        let counted = try await watch(live.api, episode, seconds: episode.duration * 60 * 8 / 10)
        XCTAssertTrue(counted, "80% from the start passes the gate")

        let (watched, _) = try await snapshot(live.api, rk)
        let rowAfter = try await continueWatching(live.api)
        print("[Live] episode \(rk) before=\(before) watched=\(watched) CW \(rowBefore.count) -> \(rowAfter.count)")
        XCTAssertEqual(watched.viewCount, 1, "the watch counted")
        XCTAssertNil(watched.viewOffset, "no resume point on a watched episode")
        XCTAssertEqual(rowAfter, rowBefore, "neither the episode nor the next one is in Continue Watching")
        // Plex adds the next episode about a second after the scrobble. Look again later so a
        // next-up that lands after the cleanup cannot pass unseen.
        try await Task.sleep(nanoseconds: 5_000_000_000)
        let rowLater = try await continueWatching(live.api)
        XCTAssertEqual(rowLater, rowBefore, "no next-up entry five seconds on")

        // Put the server back: this episode was unwatched before the test.
        let unscrobble = try XCTUnwrap(live.api.watchStateGuard.request(method: "GET", path: "/:/unscrobble", query: [
            .init(name: "key", value: rk), .init(name: "identifier", value: PlexWatchStateGuard.libraryIdentifier),
        ]))
        _ = await live.api.reportTransport.send(unscrobble)
        let (restored, _) = try await snapshot(live.api, rk)
        let rowRestored = try await continueWatching(live.api)
        print("[Live] episode \(rk) restored=\(restored) CW \(rowRestored.count)")
        XCTAssertEqual(restored, before)
        XCTAssertEqual(rowRestored, rowBefore)
    }

    // MARK: - Jellyfin / Emby
    //
    //   TEST_RUNNER_NOSTALGEX_LIVE_MS_KIND   emby | jellyfin
    //   TEST_RUNNER_NOSTALGEX_LIVE_MS_URL, _MS_TOKEN, _MS_USER
    //   TEST_RUNNER_NOSTALGEX_LIVE_MS_ITEM   an unplayed film with no resume point

    private struct MediaServerLive {
        let reporter: any WatchActivityReporting
        let url: String
        let token: String
        let user: String
        let itemId: String
    }

    private func mediaServerLive() throws -> MediaServerLive {
        let env = ProcessInfo.processInfo.environment
        guard let kind = env["NOSTALGEX_LIVE_MS_KIND"], let url = env["NOSTALGEX_LIVE_MS_URL"],
              let token = env["NOSTALGEX_LIVE_MS_TOKEN"], let user = env["NOSTALGEX_LIVE_MS_USER"],
              let itemId = env["NOSTALGEX_LIVE_MS_ITEM"] else {
            throw XCTSkip("No live Jellyfin/Emby server configured")
        }
        let reporter: any WatchActivityReporting = kind == "emby"
            ? EmbyAPIService(serverURL: url, accessToken: token, userId: user)
            : JellyfinAPIService(serverURL: url, accessToken: token, userId: user)
        return MediaServerLive(reporter: reporter, url: url, token: token, user: user, itemId: itemId)
    }

    private struct UserDataSnapshot: Decodable, Equatable {
        let PlaybackPositionTicks: Int?
        let PlayCount: Int?
        let Played: Bool?
        let LastPlayedDate: String?
    }

    private func msGet(_ live: MediaServerLive, _ path: String) async throws -> Data {
        var c = try XCTUnwrap(URLComponents(string: "\(live.url)\(path)"))
        c.queryItems = [.init(name: "Recursive", value: "true"),
                        .init(name: "MediaTypes", value: "Video"), .init(name: "Limit", value: "200")]
        var req = URLRequest(url: try XCTUnwrap(c.url))
        // Jellyfin 10.11+ refuses api_key in the query; the header works on both servers.
        req.setValue(JellyfinAPIService.authorizationHeader(deviceID: "nostalgex-live-test", token: live.token),
                     forHTTPHeaderField: "Authorization")
        let response = await URLSessionReportTransport.shared.send(req)
        let (status, body) = try XCTUnwrap(response)
        XCTAssertEqual(status, 200, path)
        return body
    }

    private func msUserData(_ live: MediaServerLive) async throws -> UserDataSnapshot {
        struct Item: Decodable { let UserData: UserDataSnapshot }
        return try JSONDecoder().decode(Item.self, from: try await msGet(live, "/Users/\(live.user)/Items/\(live.itemId)")).UserData
    }

    private func msMinutes(_ live: MediaServerLive) async throws -> Int {
        struct Item: Decodable { let RunTimeTicks: Int? }
        let ticks = try JSONDecoder().decode(Item.self, from: try await msGet(live, "/Users/\(live.user)/Items/\(live.itemId)")).RunTimeTicks
        return max(1, (ticks ?? 0) / 600_000_000)
    }

    private func msResume(_ live: MediaServerLive) async throws -> [String] {
        struct Page: Decodable { struct I: Decodable { let Id: String }; let Items: [I] }
        return try JSONDecoder().decode(Page.self, from: try await msGet(live, "/Users/\(live.user)/Items/Resume")).Items.map(\.Id)
    }

    private func msWatch(_ live: MediaServerLive, minutes: Int, seconds: Int, seekOffset: Int,
                         beforeStop: () async throws -> Void) async rethrows -> Bool {
        var clock = Date()
        let queue = ReportQueue()
        let item = PlexMediaItem(
            id: live.itemId, title: "live", artist: nil, episodeTitle: nil, seTag: nil, summary: "",
            year: nil, originallyAvailableAt: nil, contentRating: nil, duration: minutes,
            ratingKey: live.itemId, partKey: nil, container: nil, videoCodec: nil, audioCodec: nil,
            videoProfile: nil, bitrate: nil, genres: [], rating: 0, userRating: 0, type: .movie,
            thumb: nil, art: nil, viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: .movie
        )
        let tracker = PlaybackTracker(item: item, seekOffset: seekOffset, plexAPI: nil,
                                      watchReporter: live.reporter, showNowPlaying: true, markWatched: true, queue: queue, now: { clock })
        tracker.onPlaybackReady()
        for _ in 0..<(seconds / 10) {
            clock += 10
            tracker.timelineTickForTesting()
        }
        await queue.drain()
        try await beforeStop()
        tracker.stop()
        await queue.drain()
        return tracker.scrobbled
    }

    func testMediaServerSurfAndWatchLeaveResumeAlone() async throws {
        let live = try mediaServerLive()
        let resumeBefore = try await msResume(live)
        let before = try await msUserData(live)
        XCTAssertEqual(before.PlayCount ?? 0, 0, "pick an unplayed item")
        let minutes = try await msMinutes(live)

        // Surf: tune in 10 minutes in, two minutes of pulses.
        let surfCounted = try await msWatch(live, minutes: minutes, seconds: 120, seekOffset: 600) {
            let during = try await msUserData(live)
            print("[Live] ms surf during=\(during)")
            XCTAssertGreaterThan(during.PlaybackPositionTicks ?? 0, 0, "the reports really land")
        }
        XCTAssertFalse(surfCounted)
        let afterSurf = try await msUserData(live)
        let resumeAfterSurf = try await msResume(live)
        print("[Live] ms surf before=\(before) after=\(afterSurf) resume \(resumeBefore.count) -> \(resumeAfterSurf.count)")
        XCTAssertEqual(afterSurf, before)
        XCTAssertEqual(resumeAfterSurf, resumeBefore)

        // A real watch: 80% from the start counts once and leaves no resume point.
        let counted = try await msWatch(live, minutes: minutes, seconds: minutes * 60 * 8 / 10, seekOffset: 0) {}
        XCTAssertTrue(counted)
        let watched = try await msUserData(live)
        let resumeAfterWatch = try await msResume(live)
        print("[Live] ms watch after=\(watched) resume \(resumeAfterWatch.count)")
        XCTAssertEqual(watched.Played, true)
        XCTAssertEqual(watched.PlayCount, (before.PlayCount ?? 0) + 1)
        XCTAssertEqual(watched.PlaybackPositionTicks ?? 0, 0)
        XCTAssertEqual(resumeAfterWatch, resumeBefore)

        // Put the server back: the item was unplayed before the test.
        let guardian = MediaServerWatchStateGuard(
            serverURL: live.url,
            authorization: JellyfinAPIService.authorizationHeader(deviceID: "nostalgex-live-test", token: live.token),
            userId: live.user,
            transport: URLSessionReportTransport.shared)
        let reset = try XCTUnwrap(guardian.request(for: .markUnplayed, itemId: live.itemId))
        _ = await URLSessionReportTransport.shared.send(reset)
        let restored = try await msUserData(live)
        print("[Live] ms restored=\(restored)")
        XCTAssertEqual(restored, before)
    }
}
