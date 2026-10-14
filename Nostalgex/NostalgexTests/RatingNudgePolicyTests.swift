import XCTest
@testable import Nostalgex

final class RatingNudgePolicyTests: XCTestCase {
    private typealias Policy = RatingNudgePolicy

    private func persisted(sessions: Int, shown: String? = nil) -> Policy.Persisted {
        Policy.Persisted(qualifyingSessions: sessions, lastShownVersion: shown)
    }

    private func launch(_ version: String = "1.0.26", configure: (inout Policy.Launch) -> Void = { _ in }) -> Policy.Launch {
        var l = Policy.Launch(appVersion: version)
        configure(&l)
        return l
    }

    // MARK: - After RATE

    func testRatePressStopsTheBannerForGoodAcrossVersions() {
        var rated = Policy.Persisted(qualifyingSessions: 9, lastShownVersion: "1.0.25")
        rated.rated = true
        XCTAssertFalse(Policy.shouldShow(persisted: rated, launch: launch("1.0.26")))
        XCTAssertFalse(Policy.shouldShow(persisted: rated, launch: launch("2.0")))
        // The test switch still forces it, for checking the banner on hardware.
        XCTAssertTrue(Policy.shouldShow(persisted: rated, launch: launch { $0.forced = true }))
    }

    func testStoreRemembersTheRatePress() {
        let defaults = UserDefaults(suiteName: "rating-nudge-rated-\(UUID().uuidString)")!
        let store = RatingNudgeStore(defaults: defaults)
        XCTAssertFalse(store.persisted.rated)
        store.recordRated()
        XCTAssertTrue(RatingNudgeStore(defaults: defaults).persisted.rated)
    }

    // MARK: - Session counting

    func testUnderThreeSessionsDoesNotShow() {
        XCTAssertFalse(Policy.shouldShow(persisted: persisted(sessions: 0), launch: launch()))
        XCTAssertFalse(Policy.shouldShow(persisted: persisted(sessions: 2), launch: launch()))
    }

    func testThreeQualifyingSessionsShows() {
        XCTAssertTrue(Policy.shouldShow(persisted: persisted(sessions: 3), launch: launch()))
        XCTAssertTrue(Policy.shouldShow(persisted: persisted(sessions: 7), launch: launch()))
    }

    func testSessionsUnderTenMinutesDoNotCount() {
        XCTAssertFalse(Policy.countsAsViewingSession(watchedSeconds: 0))
        XCTAssertFalse(Policy.countsAsViewingSession(watchedSeconds: 114))
        XCTAssertFalse(Policy.countsAsViewingSession(watchedSeconds: 599.9))
        XCTAssertTrue(Policy.countsAsViewingSession(watchedSeconds: 600))
        XCTAssertTrue(Policy.countsAsViewingSession(watchedSeconds: 3600))
    }

    func testShortSessionsNeverReachTheThreshold() {
        let store = RatingNudgeStore(defaults: defaults)
        for seconds in [114.0, 300, 599, 45, 590] where Policy.countsAsViewingSession(watchedSeconds: seconds) {
            store.recordViewingSession()
        }
        XCTAssertEqual(store.persisted.qualifyingSessions, 0)
        XCTAssertFalse(Policy.shouldShow(persisted: store.persisted, launch: launch()))
    }

    // MARK: - Gates for this launch

    func testPlaybackFailureThisLaunchBlocks() {
        XCTAssertFalse(Policy.shouldShow(persisted: persisted(sessions: 5), launch: launch { $0.hadPlaybackFailure = true }))
    }

    func testConnectErrorThisLaunchBlocks() {
        XCTAssertFalse(Policy.shouldShow(persisted: persisted(sessions: 5), launch: launch { $0.hadConnectError = true }))
    }

    func testFirstLaunchBlocks() {
        XCTAssertFalse(Policy.shouldShow(persisted: persisted(sessions: 5), launch: launch { $0.isFirstLaunch = true }))
    }

    func testNeverTwiceInOneLaunch() {
        XCTAssertFalse(Policy.shouldShow(persisted: persisted(sessions: 5), launch: launch { $0.shownThisLaunch = true }))
    }

    // MARK: - Once per version

    func testAlreadyShownThisVersionBlocks() {
        XCTAssertFalse(Policy.shouldShow(persisted: persisted(sessions: 5, shown: "1.0.26"), launch: launch("1.0.26")))
    }

    func testNewVersionAllowsAgain() {
        XCTAssertTrue(Policy.shouldShow(persisted: persisted(sessions: 5, shown: "1.0.26"), launch: launch("1.0.27")))
    }

    // MARK: - Debug override

    func testForceBypassesCountersAndGatesButStillOncePerLaunch() {
        let forced = launch {
            $0.forced = true
            $0.isFirstLaunch = true
            $0.hadPlaybackFailure = true
        }
        XCTAssertTrue(Policy.shouldShow(persisted: persisted(sessions: 0, shown: "1.0.26"), launch: forced))
        var again = forced
        again.shownThisLaunch = true
        XCTAssertFalse(Policy.shouldShow(persisted: persisted(sessions: 0), launch: again))
    }

    // MARK: - Store

    private var defaults: UserDefaults!
    private let suiteName = "RatingNudgePolicyTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testStoreCountsAcrossInstancesAndRecordsVersion() {
        let first = RatingNudgeStore(defaults: defaults)
        first.recordViewingSession()
        first.recordViewingSession()
        let second = RatingNudgeStore(defaults: defaults)
        second.recordViewingSession()
        XCTAssertEqual(second.persisted.qualifyingSessions, 3)
        second.recordShown(version: "1.0.26")
        XCTAssertEqual(RatingNudgeStore(defaults: defaults).persisted.lastShownVersion, "1.0.26")
        XCTAssertTrue(RatingNudgeStore.qualifyingSessionsKey.hasPrefix("nostalgex_"))
        XCTAssertTrue(RatingNudgeStore.lastShownVersionKey.hasPrefix("nostalgex_"))
    }

    func testFirstLaunchIsConsumedOnce() {
        let store = RatingNudgeStore(defaults: defaults)
        XCTAssertTrue(store.consumeFirstLaunch())
        XCTAssertFalse(store.consumeFirstLaunch())
    }

    func testUpgraderWithLaunchMarkerIsNotFirstLaunch() {
        defaults.set(true, forKey: RatingNudgeStore.legacyLaunchMarkerKey)
        XCTAssertFalse(RatingNudgeStore(defaults: defaults).consumeFirstLaunch())
    }

    // MARK: - Analytics

    func testAnalyticsEventsHaveStableNamesAndNoParameters() {
        XCTAssertEqual(AnalyticsEvent.ratingNudgeShown.name, "rating_nudge.shown")
        XCTAssertEqual(AnalyticsEvent.ratingNudgeTapped.name, "rating_nudge.tapped")
        XCTAssertTrue(AnalyticsEvent.ratingNudgeShown.parameters.isEmpty)
        XCTAssertNil(AnalyticsEvent.ratingNudgeTapped.floatValue)
    }
}
