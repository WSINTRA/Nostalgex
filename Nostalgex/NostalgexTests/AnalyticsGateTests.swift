import XCTest
@testable import Nostalgex

/// The signal budget. Each test feeds the gate the event stream a real session produces
/// and checks what would reach TelemetryDeck, with the clock passed in.
final class AnalyticsGateTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func channel(_ id: Int) -> AnalyticsChannelDescriptor {
        AnalyticsChannelDescriptor(kind: .static, channelID: id, channelName: "CH \(id)", bundle: "nostalgex")
    }

    private func tuned(_ id: Int, _ method: AnalyticsTuneMethod = .next, _ backend: AnalyticsBackend = .plex) -> AnalyticsEvent {
        .channelTuned(channelNumber: id, backend: backend, method: method, channel: channel(id))
    }

    private func ready(_ id: Int, _ delivery: AnalyticsPlaybackDelivery = .directPlay) -> AnalyticsEvent {
        .playbackReady(channelNumber: id, backend: .plex, delivery: delivery, channel: channel(id))
    }

    private func stopped(_ id: Int, _ seconds: Double, _ delivery: AnalyticsPlaybackDelivery = .directPlay) -> AnalyticsEvent {
        .playbackStopped(channelNumber: id, backend: .plex, delivery: delivery, channel: channel(id), activeWatchSeconds: seconds)
    }

    private func error(_ code: AnalyticsPlaybackErrorCode, _ backend: AnalyticsBackend = .emby) -> AnalyticsEvent {
        .playbackError(channelNumber: 3, backend: backend, code: code)
    }

    /// Runs `events` (offset in seconds from t0) through one gate, returns what was sent.
    private func run(_ gate: inout AnalyticsGate, _ events: [(TimeInterval, AnalyticsEvent)]) -> [AnalyticsEvent] {
        events.flatMap { gate.admit($0.1, at: t0.addingTimeInterval($0.0)) }
    }

    private func names(_ events: [AnalyticsEvent]) -> [String: Int] {
        events.reduce(into: [:]) { $0[$1.name, default: 0] += 1 }
    }

    // MARK: - The surfing session

    /// 200 channel changes in one session. Each change used to send channel.tuned, a
    /// playback.stopped for the channel left and a playback.ready for the one arriving:
    /// about 600 signals. A few long stays in between are the watching worth keeping.
    func testTwoHundredChannelChangesSendAtMostEightSignals() {
        var gate = AnalyticsGate()
        var events: [(TimeInterval, AnalyticsEvent)] = [(0, .launch(kind: .returning))]
        var clock: TimeInterval = 1
        for flip in 1...200 {
            let id = flip % 40 + 1
            let method: AnalyticsTuneMethod = flip.isMultiple(of: 10) ? .guide : .next
            // Three real stays (10 minutes); everything else is a two-second flip.
            let stay: Double = [50, 120, 180].contains(flip) ? 600 : 2
            events.append((clock, tuned(id, method)))
            events.append((clock + 0.5, ready(id)))
            clock += stay
            events.append((clock, stopped(id, stay)))
        }
        events.append((clock + 1, .sessionEnded(activeSeconds: clock)))

        let sent = run(&gate, events)
        let raw = events.count
        XCTAssertEqual(raw, 602)
        XCTAssertLessThanOrEqual(sent.count, 8, "\(names(sent))")
        XCTAssertEqual(names(sent), [
            "app.launch": 1,
            "channel.tuned": 2,        // one per method: next, guide
            "playback.ready": 1,       // one per delivery
            "playback.stopped": 3,     // the three 10-minute stays
            "app.session.ended": 1,
        ])
        let stops = sent.filter { $0.name == "playback.stopped" }
        XCTAssertEqual(stops.compactMap(\.floatValue), [600, 600, 600])
        guard case .sessionEnded(_, let summary?) = sent.last else { return XCTFail("no summary") }
        XCTAssertEqual(summary.tunes, 200)
        XCTAssertEqual(summary.playbackStarts, 200)
        XCTAssertEqual(summary.backend, "plex")
        XCTAssertEqual(summary.wireParameters["tunes"], "51-200")
        XCTAssertEqual(summary.wireParameters["playbackStarts"], "51-200")
        XCTAssertEqual(summary.suppressed, 198 + 199 + 197) // held back: tunes, readies, short stays
    }

    /// 80 flips in three minutes, the burst in the brief. Same shape, smaller.
    func testEightyFlipsInThreeMinutesSendTwoPlaybackSignals() {
        var gate = AnalyticsGate()
        var events: [(TimeInterval, AnalyticsEvent)] = []
        for flip in 0..<80 {
            let at = Double(flip) * 2.25
            events.append((at, tuned(flip + 1)))
            events.append((at + 1, ready(flip + 1)))
            events.append((at + 2.2, stopped(flip + 1, 1.2)))
        }
        let sent = run(&gate, events)
        XCTAssertEqual(names(sent), ["channel.tuned": 1, "playback.ready": 1])
    }

    // MARK: - Error loops

    /// A channel whose every item fails skips every five seconds for as long as the TV
    /// is on: 720 playback.error an hour before the gate. One per backend and code after.
    func testHourLongErrorLoopSendsOneErrorPerCode() {
        var gate = AnalyticsGate()
        var events: [(TimeInterval, AnalyticsEvent)] = []
        for i in 0..<720 {
            events.append((Double(i) * 5, error(.playerFailed)))
            events.append((Double(i) * 5, error(.playerFailed)))   // retry path sends it twice
            events.append((Double(i) * 5 + 1, .playbackTranscodeFallback(channelNumber: 3, backend: .emby)))
        }
        events.append((3599, error(.noPlayableSource)))
        let sent = run(&gate, events)
        XCTAssertEqual(names(sent), ["playback.error": 2, "playback.transcode_fallback": 1])
        let codes = sent.compactMap { $0.name == "playback.error" ? $0.parameters["code"] : nil }
        XCTAssertEqual(codes, ["player_failed", "no_playable_source"])

        let end = gate.admit(.sessionEnded(activeSeconds: 3600), at: t0.addingTimeInterval(3600))
        guard case .sessionEnded(_, let summary?) = end.last else { return XCTFail("no summary") }
        XCTAssertEqual(summary.playbackErrors, 1441)
        XCTAssertEqual(summary.wireParameters["playbackErrors"], "201+")
        XCTAssertEqual(summary.backend, "emby")
    }

    func testSameErrorOnAnotherBackendIsItsOwnKind() {
        var gate = AnalyticsGate()
        let sent = run(&gate, [(0, error(.stalled, .plex)), (1, error(.stalled, .jellyfin)), (2, error(.stalled, .plex))])
        XCTAssertEqual(sent.compactMap { $0.parameters["backend"] }, ["plex", "jellyfin"])
    }

    // MARK: - Channel stays

    /// A channel left on all evening crosses many programme boundaries, each of which
    /// used to send its own stopped/ready pair. The stops merge into one stay.
    func testProgrammeBoundariesOnOneChannelMergeIntoOneStay() {
        var gate = AnalyticsGate()
        var events: [(TimeInterval, AnalyticsEvent)] = [(0, tuned(150, .guide))]
        for boundary in 0..<50 {       // 50 four-minute music videos, inside one window
            events.append((Double(boundary) * 240, ready(150)))
            events.append((Double(boundary + 1) * 240, stopped(150, 240)))
        }
        events.append((12_001, .sessionEnded(activeSeconds: 12_001)))
        let sent = run(&gate, events)
        XCTAssertEqual(names(sent), ["channel.tuned": 1, "playback.ready": 1, "playback.stopped": 1, "app.session.ended": 1])
        XCTAssertEqual(sent.first { $0.name == "playback.stopped" }?.floatValue, 12_000)
    }

    func testStayEndsWhenDeliveryOrChannelChanges() {
        var gate = AnalyticsGate()
        let sent = run(&gate, [
            (0, stopped(5, 300)), (300, stopped(5, 300, .transcode)),   // same channel, new delivery
            (600, stopped(6, 90)), (690, .sessionEnded(activeSeconds: 690)),
        ])
        XCTAssertEqual(sent.filter { $0.name == "playback.stopped" }.compactMap(\.floatValue), [300, 300, 90])
    }

    func testShortStaysAreCountedNotSent() {
        var gate = AnalyticsGate()
        let sent = run(&gate, [(0, stopped(1, 20)), (20, stopped(2, 59)), (80, .sessionEnded(activeSeconds: 80))])
        XCTAssertEqual(names(sent), ["app.session.ended": 1])
        guard case .sessionEnded(_, let summary?) = sent.last else { return XCTFail("no summary") }
        XCTAssertEqual(summary.suppressed, 2)
    }

    func testStaysAreCappedPerWindow() {
        var gate = AnalyticsGate()
        var events: [(TimeInterval, AnalyticsEvent)] = []
        for i in 0..<30 { events.append((Double(i) * 120, stopped(i + 1, 120))) }
        events.append((3600, .sessionEnded(activeSeconds: 3600)))
        let sent = run(&gate, events)
        XCTAssertEqual(names(sent)["playback.stopped"], AnalyticsGate.Limits.standard.stopsPerWindow)
    }

    // MARK: - Ceilings and windows

    func testPerNameLimits() {
        var gate = AnalyticsGate()
        var events: [(TimeInterval, AnalyticsEvent)] = []
        for i in 0..<30 { events.append((Double(i), .settingChanged(key: "bundle:b\(i)", value: "true"))) }
        for i in 0..<9 { events.append((40 + Double(i), .connectFailed(backend: .plex, reason: "r\(i)"))) }
        for _ in 0..<3 { events.append((60, .rateTapped)) }
        events.append((61, .settingChanged(key: "bundle:b0", value: "true")))   // duplicate kind
        let sent = run(&gate, events)
        XCTAssertEqual(names(sent), ["setting.changed": 20, "connect.failed": 5, "rate.tapped": 1])
    }

    /// Whatever the per-name rules allow, one window never sends more than `perWindow`.
    /// Guards against a loop through many distinct kinds that nobody has found yet.
    func testWindowCeilingHoldsAcrossNames() {
        var gate = AnalyticsGate()
        var events: [(TimeInterval, AnalyticsEvent)] = []
        for i in 0..<20 {
            events.append((Double(i), .settingChanged(key: "k\(i)", value: "v")))
            events.append((Double(i), .connectStarted(backend: .plex, method: .pin)))
            events.append((Double(i), .libraryLoadCompleted(channelCount: i, itemCount: i, background: true, durationMs: i, partial: false)))
            events.append((Double(i), .libraryLoadFailed(reason: "r\(i)", background: false)))
            events.append((Double(i), .connectFailed(backend: .emby, reason: "r\(i)")))
            events.append((Double(i), .credentialsSignInLost(code: "\(i)")))
            for code in [AnalyticsPlaybackErrorCode.noPlayableSource, .stalled, .playerFailed, .watchdogSkip, .transcodingUnavailable] {
                events.append((Double(i), error(code, [.plex, .jellyfin, .emby][i % 3])))
            }
            events.append((Double(i), .settingChanged(key: "x\(i)", value: "v")))
            events.append((Double(i), .libraryLoadStarted(background: i % 2 == 0, firstLoad: i % 4 == 0)))
            events.append((Double(i), .connectCompleted(backend: .jellyfin, serverCount: i)))
            events.append((Double(i), tuned(i + 1, [.guide, .next, .previous, .miniStrip][i % 4], [.plex, .jellyfin, .emby][i % 3])))
            events.append((Double(i), ready(i + 1, i % 2 == 0 ? .directPlay : .transcode)))
            events.append((Double(i), .connectCancelled(backend: [.plex, .jellyfin, .emby][i % 3], method: [.pin, .password, .quickConnect][i % 3])))
            events.append((Double(i), .libraryLoadAbandoned(background: false, itemsFound: i, userInitiated: true)))
            events.append((Double(i), .libraryRefreshBackgroundFailed(reason: "r\(i)")))
        }
        events.append((100, .launch(kind: .returning)))
        events.append((101, .sessionEnded(activeSeconds: 101)))
        let sent = run(&gate, events)
        let gated = sent.filter { AnalyticsGate.rule(for: $0.name) != nil }
        XCTAssertEqual(gated.count, AnalyticsGate.Limits.standard.perWindow)
        XCTAssertEqual(names(sent)["app.launch"], 1, "launch always goes out")
        XCTAssertEqual(names(sent)["app.session.ended"], 1, "the session summary always goes out")
    }

    /// An Apple TV left playing never backgrounds, so its session never ends. Each
    /// window gets a fresh allowance and releases the stay it was holding.
    func testLongSessionGetsAFreshAllowanceEachWindow() {
        var gate = AnalyticsGate()
        let window = AnalyticsGate.Limits.standard.windowSeconds
        let sent = run(&gate, [
            (0, error(.stalled)), (60, stopped(9, 3600)),
            (3600, error(.stalled)),                       // same window, same kind: held back
            (window + 1, error(.stalled)),                 // new window: sent, and the stay is released
        ])
        XCTAssertEqual(sent.map(\.name), ["playback.error", "playback.stopped", "playback.error"])
    }

    func testSessionEndResetsTheAllowance() {
        var gate = AnalyticsGate()
        let sent = run(&gate, [
            (0, error(.stalled)), (1, error(.stalled)), (2, .sessionEnded(activeSeconds: 2)),
            (900, error(.stalled)),
        ])
        XCTAssertEqual(sent.map(\.name), ["playback.error", "app.session.ended", "playback.error"])
        guard case .sessionEnded(_, let summary?) = sent[1] else { return XCTFail("no summary") }
        XCTAssertEqual(summary.playbackErrors, 2)
        XCTAssertEqual(summary.suppressed, 1)
    }

    // MARK: - Wire shape and privacy

    func testSummaryWireParameters() {
        var summary = AnalyticsSessionSummary()
        XCTAssertEqual(summary.wireParameters, ["tunes": "0", "playbackStarts": "0", "playbackErrors": "0", "suppressed": "0"])
        summary.tunes = 7; summary.playbackStarts = 1; summary.playbackErrors = 300; summary.suppressed = 3
        summary.backend = "jellyfin"
        XCTAssertEqual(summary.wireParameters, [
            "tunes": "6-20", "playbackStarts": "1", "playbackErrors": "201+", "suppressed": "2-5", "backend": "jellyfin",
        ])
        let event = AnalyticsEvent.sessionEnded(activeSeconds: 42, summary: summary)
        XCTAssertEqual(event.name, "app.session.ended")
        XCTAssertEqual(event.floatValue, 42)
        XCTAssertEqual(event.parameters, summary.wireParameters)
    }

    func testBuckets() {
        let cases: [(Int, String)] = [(0, "0"), (1, "1"), (2, "2-5"), (5, "2-5"), (6, "6-20"), (20, "6-20"),
                                      (21, "21-50"), (50, "21-50"), (51, "51-200"), (200, "51-200"), (201, "201+")]
        for (n, bucket) in cases { XCTAssertEqual(AnalyticsSessionSummary.bucket(n), bucket, "\(n)") }
    }

    /// The gate only drops, merges and counts. It never invents a parameter, so nothing
    /// leaves the device that the event catalog did not already allow, and the summary
    /// is a fixed vocabulary of counts and a backend name.
    func testGateNeverAddsParameters() {
        var gate = AnalyticsGate()
        let input: [(TimeInterval, AnalyticsEvent)] = [
            (0, tuned(1)), (1, ready(1)), (300, stopped(1, 299)), (301, tuned(2, .guide)),
            (302, error(.playerFailed)), (900, stopped(2, 598)), (901, .sessionEnded(activeSeconds: 901)),
        ]
        let allowedByName = Dictionary(input.map { ($0.1.name, Set($0.1.parameters.keys)) }, uniquingKeysWith: { $0.union($1) })
        for event in run(&gate, input) where event.name != "app.session.ended" {
            XCTAssertTrue(Set(event.parameters.keys).isSubset(of: allowedByName[event.name] ?? []), event.name)
        }
        XCTAssertEqual(Set(AnalyticsSessionSummary(tunes: 1, backend: "plex").wireParameters.keys),
                       ["tunes", "playbackStarts", "playbackErrors", "suppressed", "backend"])
    }
}

// MARK: - The facade uses the gate

private final class RecordingAnalytics: AnalyticsService, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [AnalyticsEvent] = []
    var events: [AnalyticsEvent] { lock.lock(); defer { lock.unlock() }; return _events }
    func configure() {}
    func track(_ event: AnalyticsEvent, contextParameters: [String: String]) {
        lock.lock(); _events.append(event); lock.unlock()
    }
}

final class AnalyticsFacadeGateTests: XCTestCase {
    override func tearDown() {
        Analytics.configure(with: NoOpAnalytics())
    }

    func testTrackGoesThroughTheGate() {
        let spy = RecordingAnalytics()
        Analytics.configure(with: spy)
        for i in 1...200 {
            Analytics.track(.channelTuned(channelNumber: i, backend: .plex, method: .next,
                                          channel: AnalyticsChannelDescriptor(kind: .static, channelID: i, channelName: nil, bundle: "nostalgex")))
        }
        XCTAssertEqual(spy.events.count, 1)
    }

    func testConfigureStartsAFreshGate() {
        let first = RecordingAnalytics()
        Analytics.configure(with: first)
        Analytics.track(.rateTapped)
        Analytics.track(.rateTapped)
        let second = RecordingAnalytics()
        Analytics.configure(with: second)
        Analytics.track(.rateTapped)
        XCTAssertEqual(first.events.count, 1)
        XCTAssertEqual(second.events.count, 1)
    }

    func testNilGatePassesEverything() {
        let spy = RecordingAnalytics()
        Analytics.configure(with: spy, gate: nil)
        for _ in 0..<5 { Analytics.track(.rateTapped) }
        XCTAssertEqual(spy.events.count, 5)
    }
}
