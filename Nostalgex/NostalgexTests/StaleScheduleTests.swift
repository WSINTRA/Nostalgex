import XCTest
@testable import Nostalgex

/// A tester on build 40: "Media restarts changing channels and plays the video queued to
/// start next." Schedules moved off the main thread, so the guide's copy can lag, and
/// nowPlaying/elapsedSeconds are baked in when the schedule is built rather than read
/// from the clock. Tuning from a lagging copy seeks wrong, or lands on the next programme.
final class StaleScheduleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ title: String, minutes: Int) -> PlexMediaItem {
        PlexMediaItem(id: title, title: title, artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 1990, originallyAvailableAt: nil, contentRating: "PG",
            duration: minutes, ratingKey: title, partKey: nil, container: "mp4",
            videoCodec: "h264", audioCodec: "aac", videoProfile: nil, bitrate: 4000,
            genres: ["Comedy"], rating: 7, userRating: 0, type: .movie, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: .movie, serverID: nil)
    }

    private func entry(_ title: String, start: Date, minutes: Int, now: Bool) -> ScheduleEntry {
        ScheduleEntry(id: title, item: item(title, minutes: minutes), startTime: start,
                      endTime: start.addingTimeInterval(Double(minutes) * 60), isNowPlaying: now)
    }

    /// Two back-to-back programmes, with the schedule built believing the first is on.
    private func schedule() -> ChannelSchedule {
        let first = entry("Top Gun", start: t0, minutes: 60, now: true)
        let second = entry("For Your Eyes Only", start: t0.addingTimeInterval(3600), minutes: 60, now: false)
        return ChannelSchedule(entries: [first, second], nowPlaying: first, upNext: second,
                               progress: 0, elapsedSeconds: 0)
    }

    func testAFreshScheduleIsUsable() {
        XCTAssertTrue(schedule().isCurrent(at: t0.addingTimeInterval(120)))
    }

    func testAScheduleIsRejectedOnceItsProgrammeHasEnded() {
        // 61 minutes in, the baked nowPlaying is the programme that already finished.
        XCTAssertFalse(schedule().isCurrent(at: t0.addingTimeInterval(3660)),
                       "this is the case that played the video queued to start next")
    }

    func testAScheduleBuiltForTheFutureIsAlsoRejected() {
        XCTAssertFalse(schedule().isCurrent(at: t0.addingTimeInterval(-60)))
    }

    func testTheBoundaryIsExact() {
        XCTAssertTrue(schedule().isCurrent(at: t0))
        XCTAssertFalse(schedule().isCurrent(at: t0.addingTimeInterval(3600)),
                       "the moment the next programme starts, the old schedule is done")
    }

    /// The restart half: the baked elapsed is 0, so tuning 20 minutes in used to start
    /// the film from the beginning.
    func testSeekOffsetComesFromTheClockNotTheBakedValue() {
        let s = schedule()
        XCTAssertEqual(s.elapsedSeconds, 0, "baked when built")
        let live = s.livePlayback(at: t0.addingTimeInterval(1200))
        XCTAssertEqual(live?.elapsedSeconds, 1200, "20 minutes in, playback should join there")
    }

    func testAScheduleWithNothingOnIsNeverUsable() {
        let empty = ChannelSchedule(entries: [], nowPlaying: nil, upNext: nil, progress: 0, elapsedSeconds: 0)
        XCTAssertFalse(empty.isCurrent(at: t0))
    }
}
