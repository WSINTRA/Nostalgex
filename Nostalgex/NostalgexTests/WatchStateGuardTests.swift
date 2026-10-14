import XCTest
@testable import Nostalgex

/// Report Playback must never leave a program in Continue Watching. These drive the real
/// `PlaybackTracker` and `PlexAPIService` request builders through a recording transport
/// and a fake clock, so the exact calls a two-minute surf makes are checked in
/// milliseconds. The live-server version is `LiveContinueWatchingTests`; numbers in
/// docs/plex-session-reporting.md. Request-shape, background and pulse tests are ported
/// from PR #18 (w6trp).
@MainActor
final class WatchStateGuardTests: XCTestCase {

    // MARK: - Fakes

    final class RecordingTransport: ReportTransport, @unchecked Sendable {
        struct Call {
            let method: String
            let path: String
            let query: [String: String]
            let body: [String: Any]?
            let sessionHeader: String?
        }

        private let lock = NSLock()
        private var recorded: [Call] = []
        /// "METHOD /path" -> responses served in order; the last one repeats.
        private var scripted: [String: [(Int, String)]] = [:]

        func respond(_ route: String, _ status: Int, _ body: String) {
            lock.lock(); defer { lock.unlock() }
            scripted[route, default: []].append((status, body))
        }

        var calls: [Call] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        func send(_ request: URLRequest) async -> (status: Int, body: Data)? {
            guard let url = request.url,
                  let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            var query: [String: String] = [:]
            comps.queryItems?.forEach { query[$0.name] = $0.value ?? "" }
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let method = request.httpMethod ?? "GET"
            lock.lock(); defer { lock.unlock() }
            recorded.append(Call(method: method, path: comps.path, query: query, body: body,
                                 sessionHeader: request.value(forHTTPHeaderField: "X-Plex-Session-Identifier")))
            let route = "\(method) \(comps.path)"
            guard var queue = scripted[route], !queue.isEmpty else { return (200, Data()) }
            let next = queue.count > 1 ? queue.removeFirst() : queue[0]
            scripted[route] = queue
            return (next.0, Data(next.1.utf8))
        }
    }

    private var clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(rk: String, minutes: Int, type: MediaType) -> PlexMediaItem {
        PlexMediaItem(
            id: rk, title: "Item \(rk)", artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 1999, originallyAvailableAt: nil, contentRating: nil,
            duration: minutes, ratingKey: rk, partKey: "/library/parts/\(rk)/file.mkv",
            container: "mkv", videoCodec: nil, audioCodec: nil, videoProfile: nil, bitrate: nil,
            genres: [], rating: 0, userRating: 0, type: type, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: type == .episode ? .tv : .movie
        )
    }

    private func tracker(_ item: PlexMediaItem, _ transport: RecordingTransport, _ queue: ReportQueue) -> PlaybackTracker {
        let api = PlexAPIService(serverURL: "http://plex.test", token: "tok", serverID: "srv", reportTransport: transport)
        return PlaybackTracker(item: item, seekOffset: 0, plexAPI: api, queue: queue, now: { [unowned self] in self.clock })
    }

    private func metadata(rk: String, type: String, viewOffset: Int? = nil, viewCount: Int? = nil, show: String? = nil) -> String {
        var fields = ["\"ratingKey\":\"\(rk)\"", "\"type\":\"\(type)\""]
        if let viewOffset { fields.append("\"viewOffset\":\(viewOffset)") }
        if let viewCount { fields.append("\"viewCount\":\(viewCount)") }
        if let show { fields.append("\"grandparentRatingKey\":\"\(show)\"") }
        return "{\"MediaContainer\":{\"Metadata\":[{\(fields.joined(separator: ","))}]}}"
    }

    private func continueWatching(_ entries: [(rk: String, show: String?)]) -> String {
        let items = entries.map { e -> String in
            e.show.map { "{\"ratingKey\":\"\(e.rk)\",\"type\":\"episode\",\"grandparentRatingKey\":\"\($0)\"}" }
                ?? "{\"ratingKey\":\"\(e.rk)\",\"type\":\"movie\"}"
        }
        return "{\"MediaContainer\":{\"Metadata\":[\(items.joined(separator: ","))]}}"
    }

    /// Plays `seconds` of the program in 10 second pulses, like the timer does.
    private func play(_ tracker: PlaybackTracker, seconds: Int) {
        tracker.onPlaybackReady()
        for _ in 0..<(seconds / 10) {
            clock += 10
            tracker.timelineTickForTesting()
        }
    }

    private func timelines(_ calls: [RecordingTransport.Call]) -> [RecordingTransport.Call] {
        calls.filter { $0.path == "/:/timeline" }
    }

    private func removals(_ calls: [RecordingTransport.Call]) -> [RecordingTransport.Call] {
        calls.filter { $0.path == "/actions/removeFromContinueWatching" }
    }

    /// Every Plex timeline report: PUT, no position, this tracker's session.
    private func assertPositionFree(_ calls: [RecordingTransport.Call], session: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        for c in timelines(calls) {
            XCTAssertEqual(c.method, "PUT", file: file, line: line)
            XCTAssertEqual(Set(c.query.keys), ["ratingKey", "key", "state"], "no time or duration", file: file, line: line)
            XCTAssertEqual(c.sessionHeader, session, file: file, line: line)
        }
    }

    // MARK: - Plex, through the tracker

    func testSurfTwoMinutesOnUnwatchedFilm_isPositionFreeAndNeedsNoCleanup() async {
        let transport = RecordingTransport()
        let queue = ReportQueue()
        let t = tracker(item(rk: "41418", minutes: 99, type: .movie), transport, queue)

        play(t, seconds: 120)
        t.stop()
        await queue.drain()

        let calls = transport.calls
        XCTAssertEqual(Set(calls.map(\.path)), ["/:/timeline"], "a film is never read, scrobbled or cleaned up")
        XCTAssertEqual(calls.count, 14, "ready + 12 pulses + stopped")
        XCTAssertEqual(calls.first?.query["state"], "playing")
        XCTAssertEqual(calls.last?.query["state"], "stopped")
        XCTAssertEqual(calls.first?.query["key"], "/library/metadata/41418")
        assertPositionFree(calls, session: t.sessionID)
    }

    func testQualifyingEpisodeWatch_scrobblesAndRemovesNextUpWhenShowWasNotInContinueWatching() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/48281", 200, metadata(rk: "48281", type: "episode", show: "48279"))
        // Before tune-in: someone else's show in the row. After the scrobble: Plex added the next episode.
        transport.respond("GET /hubs/continueWatching/items", 200, continueWatching([("900", "777")]))
        transport.respond("GET /hubs/continueWatching/items", 200, continueWatching([("900", "777"), ("48283", "48279")]))
        let queue = ReportQueue()
        let t = tracker(item(rk: "48281", minutes: 11, type: .episode), transport, queue)

        play(t, seconds: 600)
        XCTAssertTrue(t.scrobbled)
        t.stop()
        await queue.drain()

        let calls = transport.calls
        XCTAssertEqual(calls.first?.path, "/library/metadata/48281", "the show is looked up before the first report")
        let scrobbles = calls.filter { $0.path == "/:/scrobble" }
        XCTAssertEqual(scrobbles.count, 1)
        XCTAssertEqual(scrobbles.first?.query["key"], "48281", "bare rating key; /library/metadata/{rk} is a 404")
        assertPositionFree(calls, session: t.sessionID)
        XCTAssertEqual(removals(calls).map { $0.query["ratingKey"] }, ["48283"], "only the next-up entry the scrobble created")
        XCTAssertEqual(calls.last?.path, "/actions/removeFromContinueWatching", "cleanup lands after the last report")
        XCTAssertFalse(calls.contains { $0.path == "/:/unscrobble" || $0.path == "/:/progress" })
    }

    func testQualifyingEpisodeWatch_leavesNextUpWhenShowWasAlreadyInContinueWatching() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/48281", 200, metadata(rk: "48281", type: "episode", show: "48279"))
        transport.respond("GET /hubs/continueWatching/items", 200, continueWatching([("48280", "48279")]))
        let queue = ReportQueue()
        let t = tracker(item(rk: "48281", minutes: 11, type: .episode), transport, queue)

        play(t, seconds: 600)
        t.stop()
        await queue.drain()

        XCTAssertTrue(t.scrobbled)
        XCTAssertTrue(removals(transport.calls).isEmpty)
    }

    func testNextUpThatLandsJustAfterTheScrobble_isStillRemoved() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/48281", 200, metadata(rk: "48281", type: "episode", show: "48279"))
        transport.respond("GET /hubs/continueWatching/items", 200, continueWatching([]))   // before tune-in
        transport.respond("GET /hubs/continueWatching/items", 200, continueWatching([]))   // cleanup, too early
        transport.respond("GET /hubs/continueWatching/items", 200, continueWatching([("48283", "48279")]))
        let queue = ReportQueue()
        let t = tracker(item(rk: "48281", minutes: 11, type: .episode), transport, queue)

        play(t, seconds: 600)
        t.stop()
        await queue.drain()

        XCTAssertEqual(removals(transport.calls).map { $0.query["ratingKey"] }, ["48283"])
    }

    func testEpisodeUnreadableBeforeTuneIn_countsButRemovesNothing() async {
        let transport = RecordingTransport()
        transport.respond("GET /library/metadata/700", 500, "")
        let queue = ReportQueue()
        let t = tracker(item(rk: "700", minutes: 11, type: .episode), transport, queue)

        play(t, seconds: 600)
        t.stop()
        await queue.drain()

        XCTAssertEqual(transport.calls.filter { $0.path == "/:/scrobble" }.count, 1)
        XCTAssertTrue(removals(transport.calls).isEmpty, "never remove a row on a guess")
    }

    func testTunedPastBeforePlaybackStarted_sendsNothing() async {
        let transport = RecordingTransport()
        let queue = ReportQueue()
        let t = tracker(item(rk: "800", minutes: 100, type: .movie), transport, queue)

        t.stop()
        await queue.drain()

        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testTurningReportingOffMidProgram_clearsNowPlayingAndWritesNothing() async {
        let transport = RecordingTransport()
        let queue = ReportQueue()
        let t = tracker(item(rk: "41418", minutes: 99, type: .movie), transport, queue)

        play(t, seconds: 30)
        t.abandon()
        t.timelineTickForTesting()
        await queue.drain()

        XCTAssertEqual(timelines(transport.calls).map { $0.query["state"] }, ["playing", "playing", "playing", "playing", "stopped"])
        XCTAssertEqual(Set(transport.calls.map(\.path)), ["/:/timeline"])
    }

    func testBackgroundSendsOneStopAndForegroundResumesTheSameSession() async {
        let transport = RecordingTransport()
        let queue = ReportQueue()
        let t = tracker(item(rk: "41418", minutes: 99, type: .movie), transport, queue)

        play(t, seconds: 30)
        t.onBackground()
        t.onBackground()
        t.timelineTickForTesting()
        t.onPlaybackReady()
        t.onForeground()
        t.stop()
        await queue.drain()

        XCTAssertEqual(timelines(transport.calls).map { $0.query["state"] },
                       ["playing", "playing", "playing", "playing", "stopped", "playing", "stopped"])
        assertPositionFree(transport.calls, session: t.sessionID)
    }

    func testBackgroundThenStop_doesNotRepeatTheStop() async {
        let transport = RecordingTransport()
        let queue = ReportQueue()
        let t = tracker(item(rk: "41418", minutes: 99, type: .movie), transport, queue)

        play(t, seconds: 10)
        t.onBackground()
        t.stop()
        await queue.drain()

        XCTAssertEqual(timelines(transport.calls).map { $0.query["state"] }, ["playing", "playing", "stopped"])
    }

    func testPlayerStateShowsInNowPlaying() async {
        let transport = RecordingTransport()
        let queue = ReportQueue()
        let t = tracker(item(rk: "41418", minutes: 99, type: .movie), transport, queue)

        t.onHeartbeatPlaybackState("buffering")   // before the picture: nothing to report yet
        t.onPlaybackReady()
        t.onHeartbeatPlaybackState("paused")
        t.onHeartbeatPlaybackState("paused")      // no change, no report
        clock += 10
        t.timelineTickForTesting()                // the pulse keeps saying paused
        t.onHeartbeatPlaybackState("playing")
        t.stop()
        await queue.drain()

        XCTAssertEqual(timelines(transport.calls).map { $0.query["state"] },
                       ["buffering", "paused", "paused", "playing", "stopped"])
    }

    func testOneHundredPulsesHaveNoCutoff() async {
        let transport = RecordingTransport()
        let queue = ReportQueue()
        let t = tracker(item(rk: "41418", minutes: 200, type: .movie), transport, queue)

        play(t, seconds: 1000)
        await queue.drain()

        XCTAssertEqual(timelines(transport.calls).count, 101)
        t.stop()
        await queue.drain()
        XCTAssertEqual(timelines(transport.calls).last?.query["state"], "stopped")
    }

    func testFailingServerGetsFewerPulsesThenRecovers() async {
        let transport = RecordingTransport()
        for status in [500, 500, 500, 200] { transport.respond("PUT /:/timeline", status, "") }
        let queue = ReportQueue()
        let t = tracker(item(rk: "41418", minutes: 99, type: .movie), transport, queue)

        t.onPlaybackReady()                       // fails: skip 1 pulse
        await queue.drain()
        for _ in 0..<11 {
            clock += 10
            t.timelineTickForTesting()
            await queue.drain()
        }
        // Sent: ready, pulse 2 (fails: skip 2), pulse 5 (fails: skip 4), pulse 10 (answers), pulse 11.
        XCTAssertEqual(timelines(transport.calls).count, 5)
        t.stop()
        await queue.drain()
        XCTAssertEqual(timelines(transport.calls).last?.query["state"], "stopped", "a stop is never skipped")
    }

    func testPulseBackoffGrowsAndCaps() {
        let backoff = PulseBackoff()
        var skipped: [Int] = []
        for _ in 0..<8 {
            backoff.record(success: false)
            var n = 0
            while !backoff.allowPulse() { n += 1 }
            skipped.append(n)
        }
        XCTAssertEqual(skipped, [1, 2, 4, 8, 16, 30, 30, 30])
        backoff.record(success: true)
        XCTAssertTrue(backoff.allowPulse())
    }

    func testHeartbeatRequestCarriesNoPosition() throws {
        let api = PlexAPIService(serverURL: "https://synthetic.invalid", token: "synthetic-token")
        for state in ["playing", "paused", "buffering", "stopped"] {
            let request = try XCTUnwrap(api.heartbeatRequest(ratingKey: "42", state: state, sessionID: "exact-session"))
            let parts = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(parts.path, "/:/timeline")
            XCTAssertEqual(Set(parts.queryItems!.map(\.name)), ["ratingKey", "key", "state"])
            XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "key" })?.value, "/library/metadata/42")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Plex-Session-Identifier"), "exact-session")
            XCTAssertFalse(request.url!.absoluteString.contains("synthetic-token"))
        }
        XCTAssertNil(api.heartbeatRequest(ratingKey: "../other", state: "playing", sessionID: "x"))
        XCTAssertNil(api.heartbeatRequest(ratingKey: "42", state: "watched", sessionID: "x"))
    }

    // MARK: - Jellyfin / Emby guard

    private func mediaServerGuard(_ transport: RecordingTransport) -> MediaServerWatchStateGuard {
        MediaServerWatchStateGuard(serverURL: "http://jf.test", authorization: "MediaBrowser Token=\"t\"",
                                   userId: "u1", transport: transport)
    }

    func testMediaServerCapture_readsUserData() async {
        let transport = RecordingTransport()
        transport.respond("GET /Users/u1/Items/i1", 200,
                          "{\"UserData\":{\"PlaybackPositionTicks\":6000000000,\"PlayCount\":2,\"Played\":true,\"LastPlayedDate\":\"2026-10-11T18:03:04.0000000Z\"}}")
        let prior = await mediaServerGuard(transport).captureWatchState(for: item(rk: "i1", minutes: 90, type: .movie))
        XCTAssertEqual(prior, PriorWatchState(resumePosition: 6_000_000_000, playCount: 2, played: true,
                                              lastPlayedDate: "2026-10-11T18:03:04.0000000Z"))
    }

    func testMediaServerRestore_untouchedItemIsMarkedUnplayed() async {
        let transport = RecordingTransport()
        await mediaServerGuard(transport).restoreWatchState(
            for: item(rk: "i1", minutes: 90, type: .movie),
            prior: PriorWatchState(resumePosition: 0, playCount: 0, played: false), countedWatch: false)
        XCTAssertEqual(transport.calls.map { "\($0.method) \($0.path)" }, ["DELETE /Users/u1/PlayedItems/i1"])
    }

    func testMediaServerRestore_writesPriorUserDataBack() async {
        let transport = RecordingTransport()
        await mediaServerGuard(transport).restoreWatchState(
            for: item(rk: "i1", minutes: 90, type: .movie),
            prior: PriorWatchState(resumePosition: 6_000_000_000, playCount: 1, played: false, lastPlayedDate: "2026-10-01T00:00:00Z"),
            countedWatch: false)
        let call = transport.calls.first
        XCTAssertEqual(transport.calls.count, 1)
        XCTAssertEqual(call?.method, "POST")
        XCTAssertEqual(call?.path, "/Users/u1/Items/i1/UserData")
        XCTAssertEqual(call?.body?["PlaybackPositionTicks"] as? Int, 6_000_000_000)
        XCTAssertEqual(call?.body?["PlayCount"] as? Int, 1)
        XCTAssertEqual(call?.body?["Played"] as? Bool, false)
        XCTAssertEqual(call?.body?["LastPlayedDate"] as? String, "2026-10-01T00:00:00Z")
    }

    func testMediaServerRestore_countedWatchIsPlayedOnceWithNoResumePoint() async {
        let transport = RecordingTransport()
        await mediaServerGuard(transport).restoreWatchState(
            for: item(rk: "i1", minutes: 90, type: .movie),
            prior: PriorWatchState(resumePosition: 0, playCount: 0, played: false), countedWatch: true)
        let body = transport.calls.first?.body
        XCTAssertEqual(body?["PlaybackPositionTicks"] as? Int, 0)
        XCTAssertEqual(body?["PlayCount"] as? Int, 1)
        XCTAssertEqual(body?["Played"] as? Bool, true)
    }

    // MARK: - Shared decision table (web tuner reads the same file)

    private struct Golden: Decodable {
        struct Prior: Decodable {
            let resumePosition: Int
            let playCount: Int
            let played: Bool
            let lastPlayedDate: String?
            let showKey: String?
            let showInContinueWatching: Bool
        }
        struct Case: Decodable {
            let name: String
            let backend: String
            let counted: Bool
            let prior: Prior?
            let steps: [String]
        }
        let cases: [Case]
    }

    func testCleanupPlanMatchesSharedGoldenVectors() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("scripts/watch-cleanup-golden.json"))
        let golden = try JSONDecoder().decode(Golden.self, from: data)
        XCTAssertGreaterThan(golden.cases.count, 10)
        for c in golden.cases {
            let prior = c.prior.map {
                PriorWatchState(resumePosition: $0.resumePosition, playCount: $0.playCount, played: $0.played,
                                lastPlayedDate: $0.lastPlayedDate, showKey: $0.showKey,
                                showInContinueWatching: $0.showInContinueWatching)
            }
            let steps = c.backend == "plex"
                ? WatchCleanupPlan.plex(prior: prior, countedWatch: c.counted)
                : WatchCleanupPlan.mediaServer(prior: prior, countedWatch: c.counted)
            XCTAssertEqual(steps.map(\.goldenDescription), c.steps, c.name)
        }
    }
}
