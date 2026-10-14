import XCTest
@testable import Nostalgex

final class GuideChannelOrderTests: XCTestCase {
    private func ch(_ id: Int, _ number: Int) -> Channel {
        Channel(id: id, number: number, name: "CH\(number)", color: .blue, category: nil,
                rules: nil, timeRestrictions: nil, minItems: 0)
    }
    /// Mirrors the real SCREAM bundle: four channels scattered across the lineup.
    private var lineup: [Channel] {
        [ch(1, 1), ch(2, 2), ch(19, 19), ch(50, 40), ch(141, 77), ch(131, 131), ch(132, 132)]
    }
    private let screamIDs = [141, 132, 131, 19]   // bundle order, not number order

    func testWithoutASeasonalPackageEverythingIsByNumber() {
        XCTAssertEqual(GuideChannelOrder.sorted(lineup, seasonalFirst: []).map(\.number),
                       [1, 2, 19, 40, 77, 131, 132])
    }

    func testSeasonalChannelsLeadTheGuideAsABlock() {
        let out = GuideChannelOrder.sorted(lineup, seasonalFirst: screamIDs)
        XCTAssertEqual(out.map(\.id), [141, 132, 131, 19, 1, 2, 50],
                       "the package leads in its own order, then the rest by number")
    }

    func testSeasonalBlockSitsAboveChannelOne() {
        let out = GuideChannelOrder.sorted(lineup, seasonalFirst: screamIDs)
        let firstOrdinary = out.firstIndex { !screamIDs.contains($0.id) }!
        XCTAssertEqual(out[firstOrdinary].number, 1, "channel one comes straight after the block")
        XCTAssertTrue(out.prefix(4).allSatisfy { screamIDs.contains($0.id) })
    }

    func testTheRestStayInNumberOrder() {
        let rest = GuideChannelOrder.sorted(lineup, seasonalFirst: screamIDs)
            .filter { !screamIDs.contains($0.id) }.map(\.number)
        XCTAssertEqual(rest, [1, 2, 40])
    }

    func testAnIDThatIsNotOnAirIsSkippedWithoutGaps() {
        // NOSTALGEX HORROR can fail to build on a small library; the block just shortens.
        let thin = lineup.filter { $0.id != 19 }
        XCTAssertEqual(GuideChannelOrder.sorted(thin, seasonalFirst: screamIDs).map(\.id),
                       [141, 132, 131, 1, 2, 50])
    }

    func testOnlySeasonalBundlesLead() {
        let b = [
            ChannelBundleDefinition(id: "nostalgex", name: "NOSTALGEX", description: nil,
                                    channelIDs: [1, 2], activeMonths: nil).toChannelBundle(),
            ChannelBundleDefinition(id: "seasonal", name: "SCREAM", description: nil,
                                    channelIDs: screamIDs, activeMonths: [10]).toChannelBundle(),
        ]
        let oct = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let jul = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 12))!
        XCTAssertEqual(GuideChannelOrder.seasonalLeadIDs(bundles: b, enabledBundleIDs: ["nostalgex", "seasonal"], now: oct),
                       screamIDs, "only the seasonal bundle leads, never NOSTALGEX")
        XCTAssertEqual(GuideChannelOrder.seasonalLeadIDs(bundles: b, enabledBundleIDs: ["nostalgex", "seasonal"], now: jul),
                       [], "out of season it goes back to plain number order")
        XCTAssertEqual(GuideChannelOrder.seasonalLeadIDs(bundles: b, enabledBundleIDs: ["nostalgex"], now: oct),
                       [], "a package that was declined does not lead")
    }
}
