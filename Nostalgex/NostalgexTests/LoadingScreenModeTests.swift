import XCTest
@testable import Nostalgex

final class LoadingScreenModeTests: XCTestCase {
    private func decide(hydrated: Bool = true, first: Bool = false, message: String = "",
                        sections: Int = 0, channels: Int = 0) -> LoadingScreenMode {
        LoadingScreenMode.decide(
            didAttemptCredentialHydration: hydrated, isFirstLibraryLoad: first,
            loadingMessage: message, scanTotalSections: sections, channelBuildTotal: channels)
    }

    func testKeychainReadShowsTheSplashNotAnEmptyProgressBar() {
        XCTAssertEqual(decide(hydrated: false), .splash)
        XCTAssertEqual(decide(hydrated: false, first: true), .splash,
                       "nothing is known yet, so it cannot claim to be a first scan")
    }

    func testAPauseWithNothingToReportShowsTheSplash() {
        XCTAssertEqual(decide(), .splash)
        XCTAssertEqual(decide(message: "   "), .splash, "whitespace is not a headline")
    }

    func testFirstScanGetsTheFullRailAndTheWarning() {
        let m = decide(first: true, message: "SCANNING PLEX LIBRARY", sections: 3)
        XCTAssertEqual(m, .firstScan)
        XCTAssertTrue(m.showsStepRail)
        XCTAssertTrue(m.showsFirstRunWarning)
    }

    func testLaterScanGetsTheRailWithoutTheWarning() {
        let m = decide(first: false, message: "BUILDING CHANNELS", channels: 40)
        XCTAssertEqual(m, .update)
        XCTAssertTrue(m.showsStepRail)
        XCTAssertFalse(m.showsFirstRunWarning, "only the first run should warn about the wait")
    }

    func testWorkWithoutAHeadlineStillCountsAsAScan() {
        XCTAssertEqual(decide(sections: 2), .update)
        XCTAssertEqual(decide(channels: 12), .update)
    }

    func testSplashNeverDrawsAProgressRail() {
        XCTAssertFalse(LoadingScreenMode.splash.showsStepRail)
        XCTAssertFalse(LoadingScreenMode.splash.showsFirstRunWarning)
    }
}
