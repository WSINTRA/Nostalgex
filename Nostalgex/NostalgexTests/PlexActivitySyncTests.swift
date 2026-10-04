import XCTest
@testable import Nostalgex

@MainActor
final class PlexActivitySyncTests: XCTestCase {

    // Never-touched installs must land on OFF: channel surfing otherwise floods the
    // household's Plex "Continue Watching" row with programs nobody chose to start.
    func testResolveSyncPlexActivity_defaultsOffWhenNothingStored() {
        XCTAssertFalse(AppState.resolveSyncPlexActivity(stored: nil))
    }

    // An explicit choice always wins, in both directions, so flipping the default never
    // overrides a user who already decided.
    func testResolveSyncPlexActivity_honorsExplicitChoice() {
        XCTAssertTrue(AppState.resolveSyncPlexActivity(stored: true))
        XCTAssertFalse(AppState.resolveSyncPlexActivity(stored: false))
    }

    // UserDefaults hands back NSNumber; a non-Bool value must not read as ON.
    func testResolveSyncPlexActivity_ignoresNonBooleanStoredValue() {
        XCTAssertFalse(AppState.resolveSyncPlexActivity(stored: "yes"))
    }

    func testSyncPlexActivityToggle_persistsToUserDefaults() {
        let defaults = UserDefaults.standard
        let key = AppState.syncPlexActivityDefaultsKey
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        let state = AppState()
        state.syncPlexActivity = true
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, true)

        state.syncPlexActivity = false
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, false)
    }

    // With no Plex API the tracker must be completely inert: no timeline, no scrobble.
    // This is what makes the OFF default actually stop Continue Watching entries, since
    // AppState passes a nil API whenever sync is off.
    func testPlaybackTrackerWithoutAPI_neverScrobbles() {
        let item = PlexMediaItem(
            id: "1",
            title: "Test",
            artist: nil,
            episodeTitle: nil,
            seTag: nil,
            summary: "",
            year: 1988,
            originallyAvailableAt: nil,
            contentRating: nil,
            duration: 90,
            ratingKey: "1",
            partKey: "/library/parts/1/file.mkv",
            container: "mkv",
            videoCodec: nil,
            audioCodec: nil,
            videoProfile: nil,
            bitrate: nil,
            genres: [],
            rating: 0,
            userRating: 0,
            type: .movie,
            thumb: nil,
            art: nil,
            viewCount: 0,
            addedAt: 0,
            studio: nil,
            tmdbID: nil,
            imdbID: nil,
            librarySource: .movie
        )
        let tracker = PlaybackTracker(item: item, seekOffset: 0, plexAPI: nil)
        tracker.onPlaybackReady()
        tracker.stop()
        XCTAssertFalse(tracker.scrobbled)
    }

    func testServerWatchCount_usesPlayCountWhenTheServerHasOne() {
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: 4, played: true), 4)
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: 3, played: false), 3)
    }

    func testServerWatchCount_playedWithNoCountStillCountsAsOneWatch() {
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: 0, played: true), 1)
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: nil, played: true), 1)
    }

    func testServerWatchCount_unplayedIsZero() {
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: nil, played: false), 0)
        XCTAssertEqual(ServerWatchCount.viewCount(playCount: nil, played: nil), 0)
    }
}
