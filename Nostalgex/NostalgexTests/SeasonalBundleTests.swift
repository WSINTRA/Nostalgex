import XCTest
@testable import Nostalgex

/// `activeMonths` shipped long ago but no bundle set it, so the seasonal gate had never
/// run in production. SCREAM (October) and TIS THE SEASON (December) are the first users
/// of it, and a bundle that fails to come back in season is invisible for a year.
final class SeasonalBundleTests: XCTestCase {
    private func date(_ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    private func bundle(_ id: String, months: [Int]?) -> ChannelBundle {
        ChannelBundle(id: id, name: id, description: nil, channelIDs: [1], activeMonths: months)
    }

    func testOctoberOnlyBundleIsVisibleOnlyInOctober() {
        let scream = bundle("scream", months: [10])
        XCTAssertTrue(scream.isInSeason(on: date(10, 1)))
        XCTAssertTrue(scream.isInSeason(on: date(10, 31)))
        XCTAssertFalse(scream.isInSeason(on: date(9, 30)))
        XCTAssertFalse(scream.isInSeason(on: date(11, 1)))
        XCTAssertFalse(scream.isInSeason(on: date(7, 4)))
    }

    func testDecemberOnlyBundleIsVisibleOnlyInDecember() {
        let holiday = bundle("tis-the-season", months: [12])
        XCTAssertTrue(holiday.isInSeason(on: date(12, 1)))
        XCTAssertTrue(holiday.isInSeason(on: date(12, 25)))
        XCTAssertFalse(holiday.isInSeason(on: date(11, 28)))
        XCTAssertFalse(holiday.isInSeason(on: date(1, 2)))
    }

    func testSeptemberIsGatedToTheSecondHalf() {
        let b = bundle("scream", months: [9, 10])
        XCTAssertFalse(b.isInSeason(on: date(9, 14)))
        XCTAssertTrue(b.isInSeason(on: date(9, 15)))
    }

    func testBundleWithoutActiveMonthsIsAlwaysVisible() {
        let b = bundle("nostalgex", months: nil)
        for m in 1...12 { XCTAssertTrue(b.isInSeason(on: date(m, 15)), "month \(m)") }
    }

    /// The shipped config must actually carry the months, or the split is cosmetic.
    func testShippedConfigGatesScreamAndHolidayBundles() throws {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "channels", withExtension: "json"))
        let result = try XCTUnwrap(ChannelConfigLoader.loadConfig(from: Data(contentsOf: url)))
        let scream = try XCTUnwrap(result.bundles.first { $0.name == "SCREAM" })
        let holiday = try XCTUnwrap(result.bundles.first { $0.id == "tis-the-season" })
        XCTAssertEqual(scream.activeMonths, [10])
        XCTAssertEqual(holiday.activeMonths, [12])
        XCTAssertTrue(scream.toChannelBundle().isInSeason(on: date(10, 20)))
        XCTAssertFalse(holiday.toChannelBundle().isInSeason(on: date(10, 20)))
    }
}
