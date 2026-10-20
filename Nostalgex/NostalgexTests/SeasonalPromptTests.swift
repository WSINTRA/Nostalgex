import XCTest
@testable import Nostalgex

final class SeasonalPromptTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "SeasonalPromptTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }
    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func bundle(_ id: String, months: [Int]?) -> ChannelBundle {
        ChannelBundle(id: id, name: id.uppercased(), description: nil, channelIDs: [1], activeMonths: months)
    }
    private var lineup: [ChannelBundle] {
        [bundle("nostalgex", months: nil), bundle("seasonal", months: [10]), bundle("tis-the-season", months: [12])]
    }
    private func offer(_ now: Date, enabled: Set<String> = []) -> ChannelBundle? {
        SeasonalPrompt.bundleToOffer(bundles: lineup, enabledBundleIDs: enabled, now: now) {
            SeasonalPrompt.isSilenced(bundleID: $0, now: now, defaults: defaults)
        }
    }

    func testOffersScreamOnOctoberFirstAndAllMonth() {
        XCTAssertEqual(offer(date(2026, 10, 1))?.id, "seasonal")
        XCTAssertEqual(offer(date(2026, 10, 31))?.id, "seasonal")
    }

    func testOffersNothingOutsideSeason() {
        XCTAssertNil(offer(date(2026, 9, 30)))
        XCTAssertNil(offer(date(2026, 11, 1)))
        XCTAssertEqual(offer(date(2026, 12, 10))?.id, "tis-the-season")
    }

    func testNeverOffersAnAlreadyEnabledBundle() {
        XCTAssertNil(offer(date(2026, 10, 10), enabled: ["seasonal"]))
    }

    func testNeverOffersANonSeasonalBundle() {
        // nostalgex has no activeMonths and must never be prompted for.
        XCTAssertNotEqual(offer(date(2026, 10, 10))?.id, "nostalgex")
    }

    func testYesDoesNotSilenceAndAsksTheBundleBeTurnedOn() {
        let on = SeasonalPrompt.record(.yes, bundleID: "seasonal", now: date(2026, 10, 2), defaults: defaults)
        XCTAssertTrue(on)
        XCTAssertFalse(SeasonalPrompt.isSilenced(bundleID: "seasonal", now: date(2026, 10, 3), defaults: defaults))
    }

    func testNotNowSilencesThisSeasonButComesBackNextYear() {
        let on = SeasonalPrompt.record(.notNow, bundleID: "seasonal", now: date(2026, 10, 2), defaults: defaults)
        XCTAssertFalse(on)
        XCTAssertNil(offer(date(2026, 10, 20)), "a 'no' must hold for the rest of this October")
        XCTAssertEqual(offer(date(2027, 10, 5))?.id, "seasonal", "and must be asked again next October")
    }

    func testNeverIsPermanent() {
        SeasonalPrompt.record(.never, bundleID: "seasonal", now: date(2026, 10, 2), defaults: defaults)
        XCTAssertNil(offer(date(2026, 10, 20)))
        XCTAssertNil(offer(date(2027, 10, 5)))
        XCTAssertNil(offer(date(2030, 10, 5)))
    }

    func testSilencingOneBundleLeavesTheOtherAlone() {
        SeasonalPrompt.record(.never, bundleID: "seasonal", now: date(2026, 10, 2), defaults: defaults)
        XCTAssertEqual(offer(date(2026, 12, 10))?.id, "tis-the-season")
    }

    // MARK: TIS THE SEASON from a week before US Thanksgiving

    private var thanksgivingLineup: [ChannelBundle] {
        [bundle("nostalgex", months: nil), bundle("seasonal", months: [10]),
         ChannelBundle(id: "tis-the-season", name: "TIS THE SEASON", description: nil, channelIDs: [1],
                       activeMonths: [12], seasonStart: SeasonStart(relativeTo: "usThanksgiving", days: -7))]
    }
    private func holidayOffer(_ now: Date) -> String? {
        SeasonalPrompt.bundleToOffer(bundles: thanksgivingLineup, enabledBundleIDs: [], now: now) {
            SeasonalPrompt.isSilenced(bundleID: $0, now: now, defaults: defaults)
        }?.id
    }

    func testHolidayInviteStartsAWeekBeforeThanksgiving() {
        // Thanksgiving 2026 is Nov 26.
        XCTAssertNil(holidayOffer(Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 23, minute: 59))!))
        XCTAssertEqual(holidayOffer(date(2026, 11, 19)), "tis-the-season")
        XCTAssertEqual(holidayOffer(date(2026, 12, 31)), "tis-the-season")
        XCTAssertNil(holidayOffer(date(2027, 1, 1)))
        XCTAssertEqual(holidayOffer(date(2026, 10, 31)), "seasonal", "SCREAM keeps October")
    }

    /// "This year" is the calendar year. The season runs Nov to Dec 31, inside one year,
    /// so a "no" on the first day holds to the end and next November asks again.
    func testNotThisYearOnTheFirstDayHoldsThroughDecember() {
        SeasonalPrompt.record(.notNow, bundleID: "tis-the-season", now: date(2026, 11, 19), defaults: defaults)
        XCTAssertNil(holidayOffer(date(2026, 11, 26)))
        XCTAssertNil(holidayOffer(date(2026, 12, 31)))
        XCTAssertNil(holidayOffer(date(2027, 11, 17)), "2027's start is Nov 18")
        XCTAssertEqual(holidayOffer(date(2027, 11, 18)), "tis-the-season")
    }

    func testNotThisYearLastDecemberDoesNotSilenceThisNovember() {
        SeasonalPrompt.record(.notNow, bundleID: "tis-the-season", now: date(2025, 12, 10), defaults: defaults)
        XCTAssertNil(holidayOffer(date(2025, 12, 31)))
        XCTAssertEqual(holidayOffer(date(2026, 11, 19)), "tis-the-season")
    }

    func testDontAskAgainInNovemberIsForGood() {
        SeasonalPrompt.record(.never, bundleID: "tis-the-season", now: date(2026, 11, 20), defaults: defaults)
        XCTAssertNil(holidayOffer(date(2026, 12, 10)))
        XCTAssertNil(holidayOffer(date(2027, 11, 18)))
        XCTAssertNil(holidayOffer(date(2030, 11, 21)))
    }

    func testHolidayHeadlineOnlySaysDecemberInDecember() {
        let holiday = thanksgivingLineup[2]
        XCTAssertEqual(SeasonalPrompt.headline(for: holiday, now: date(2026, 11, 19)), "THE HOLIDAYS ARE HERE. DECK THE CHANNELS.")
        XCTAssertEqual(SeasonalPrompt.headline(for: holiday, now: date(2026, 12, 1)), "IT'S DECEMBER. DECK THE CHANNELS.")
        XCTAssertEqual(SeasonalPrompt.headline(for: thanksgivingLineup[1], now: date(2026, 10, 1)), "IT'S OCTOBER. ARE YOU READY TO SCREAM?")
    }
}

/// Guards the promise that nothing is added to a lineup without an answer.
@MainActor
final class SeasonalAutoEnableTests: XCTestCase {
    private final class MemStore: Nostalgex.CredentialStoring {
        var values: [String: String] = [:]
        @discardableResult func save(key: String, value: String) -> Bool { values[key] = value; return true }
        func load(key: String) -> String? { values[key] }
        func delete(key: String) { values[key] = nil }
    }

    func testAutoEnableNeverTurnsOnASeasonalBundle() {
        let state = AppState(credentialStore: MemStore())
        state.bundles = [
            ChannelBundleDefinition(id: "nostalgex", name: "NOSTALGEX", description: nil,
                                    channelIDs: [1], activeMonths: nil).toChannelBundle(enabled: false),
            ChannelBundleDefinition(id: "seasonal", name: "SCREAM", description: nil,
                                    channelIDs: [2], activeMonths: [Calendar.current.component(.month, from: Date())])
                .toChannelBundle(enabled: false),
        ]
        state.allChannels = [1, 2].map {
            Channel(id: $0, number: $0, name: "CH\($0)", color: .red, category: nil,
                    rules: nil, timeRestrictions: nil, minItems: 0)
        }
        state.enabledBundleIDs = []

        state.autoEnableBundlesWithContent()

        XCTAssertTrue(state.enabledBundleIDs.contains("nostalgex"),
                      "a normal bundle with content should still auto-enable")
        XCTAssertFalse(state.enabledBundleIDs.contains("seasonal"),
                       "a seasonal bundle must wait to be invited, even in season with content")
    }
}
