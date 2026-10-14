import XCTest
@testable import Nostalgex

final class PlaybackDiagnosticsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "PlaybackDiagnosticsTests"

    override func setUp() { super.setUp(); UserDefaults().removePersistentDomain(forName: suite); defaults = UserDefaults(suiteName: suite) }
    override func tearDown() { UserDefaults().removePersistentDomain(forName: suite); super.tearDown() }

    func testNothingRecordedMeansNothingShown() {
        XCTAssertNil(PlaybackDiagnostics.latestForSettings(defaults: defaults))
        XCTAssertTrue(PlaybackDiagnostics.recent(defaults: defaults).isEmpty)
    }

    func testTheLatestVerdictCarriesWhatSettlesDeviceVersusServer() {
        PlaybackDiagnostics.record(outcome: "skipped to next after 40s", title: "Armageddon",
                                   detail: "ready=true, playhead moved 2.0s, frames=false, segments=14 stalls=0", defaults: defaults)
        let line = try! XCTUnwrap(PlaybackDiagnostics.latestForSettings(defaults: defaults))
        XCTAssertTrue(line.contains("Armageddon"), line)
        XCTAssertTrue(line.contains("frames=false"), "the one field that discriminates must survive: \(line)")
        XCTAssertTrue(line.contains("playhead moved 2.0s"), line)
        XCTAssertTrue(line.contains("skipped to next after 40s"), line)
    }

    func testNewestFirstAndOnlyAFewKept() {
        for i in 1...8 { PlaybackDiagnostics.record(outcome: "v\(i)", title: "T\(i)", detail: "d", defaults: defaults) }
        let rows = PlaybackDiagnostics.recent(defaults: defaults)
        XCTAssertEqual(rows.count, 5, "keep the last five, not a growing log")
        XCTAssertTrue(rows[0].contains("\"T8\""), "newest first: \(rows[0])")
        XCTAssertTrue(rows[4].contains("\"T4\""))
    }

    func testCredentialsAreRemovedBeforePersistenceAndLegacyRowsArePurged() {
        let samples = [
            "https://user:pass@example.invalid/file?X-Plex-Token=fixture-one#fragment",
            "/segment.ts?x-plex-token=fixture-two&other=ok",
            "X-Plex-Token: \"fixture-three\"",
            "Authorization: Bearer fixture-four",
            "https%3A%2F%2Fexample.invalid%2Ffile%3FX-Plex-Token%3Dfixture-five",
            "api_key=fixture-six; Token='fixture-seven'",
            #"{"X-Plex-Token": "fixture-eight", "Authorization": "Bearer fixture-nine"}"#,
            "X%252DPlex%252DToken%253Dfixture-ten",

        ]
        for sample in samples {
            PlaybackDiagnostics.record(outcome: "HTTP 403", title: "Synthetic", detail: sample, defaults: defaults)
            let persisted = defaults.dictionaryRepresentation().description
            XCTAssertFalse(persisted.contains("fixture-"), sample)
            XCTAssertFalse(persisted.contains("user:pass"), sample)
        }
        let rows = PlaybackDiagnostics.recent(defaults: defaults).joined()
        XCTAssertFalse(rows.contains("fixture-"))
        XCTAssertTrue(rows.contains("HTTP 403"))
        defaults.set(["legacy token tail"], forKey: "nostalgex_playback_verdicts")
        _ = PlaybackDiagnostics.recent(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "nostalgex_playback_verdicts"))
    }

    func testClearEmptiesIt() {
        PlaybackDiagnostics.record(outcome: "x", title: "y", detail: "z", defaults: defaults)
        PlaybackDiagnostics.clear(defaults: defaults)
        XCTAssertNil(PlaybackDiagnostics.latestForSettings(defaults: defaults))
    }
}
