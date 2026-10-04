import XCTest
@testable import Nostalgex

/// The guide swallowed every Menu press: the handler guarded inside the closure, and an
/// attached closure consumes the press whether or not it does anything. Back-to-live
/// worked once and then the app could not be exited at all.
final class GuideExitActionTests: XCTestCase {

    func testMenuJumpsToTheLiveChannelWhenFocusIsElsewhere() {
        XCTAssertEqual(
            GuideExitAction.decide(liveChannelID: 7, focusedChannelID: 42),
            .jumpToLiveChannel(7)
        )
    }

    func testMenuIsDeclinedOnceFocusIsAlreadyOnTheLiveChannel() {
        XCTAssertEqual(
            GuideExitAction.decide(liveChannelID: 7, focusedChannelID: 7),
            .letSystemHandle,
            "a second Menu press must leave the app, not be swallowed"
        )
    }

    func testMenuIsDeclinedWhenNothingIsPlaying() {
        XCTAssertEqual(GuideExitAction.decide(liveChannelID: nil, focusedChannelID: 3), .letSystemHandle)
        XCTAssertEqual(GuideExitAction.decide(liveChannelID: nil, focusedChannelID: nil), .letSystemHandle)
    }

    func testMenuIsDeclinedWhenNothingHasFocus() {
        XCTAssertEqual(GuideExitAction.decide(liveChannelID: 7, focusedChannelID: nil), .jumpToLiveChannel(7))
    }

    /// The seasonal invite row uses a sentinel id, and Menu from there behaves like any
    /// other non-live row.
    func testMenuFromTheSeasonalInviteRowJumpsToLive() {
        XCTAssertEqual(GuideExitAction.decide(liveChannelID: 7, focusedChannelID: -900), .jumpToLiveChannel(7))
    }
}
