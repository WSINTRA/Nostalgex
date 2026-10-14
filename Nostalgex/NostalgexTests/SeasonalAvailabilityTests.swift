import XCTest
@testable import Nostalgex

/// `activeMonths` controls three different things and they must not be conflated again.
/// A seasonal package is available ALL YEAR. Its months decide only when it is OFFERED in
/// the guide, and when it LEADS the lineup. It first shipped hiding the package outside
/// its month, so horror was unreachable for eleven months.
@MainActor
final class SeasonalAvailabilityTests: XCTestCase {
    private final class MemStore: Nostalgex.CredentialStoring {
        var values: [String: String] = [:]
        @discardableResult func save(key: String, value: String) -> Bool { values[key] = value; return true }
        func load(key: String) -> String? { values[key] }
        func delete(key: String) { values[key] = nil }
    }

    private func date(_ m: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: m, day: 12))!
    }
    private var scream: ChannelBundle {
        ChannelBundleDefinition(id: "seasonal", name: "SCREAM", description: nil,
                                channelIDs: [131, 141], activeMonths: [10]).toChannelBundle(enabled: true)
    }

    /// The point of the change: switched on in July, the channels are in the lineup.
    func testAnEnabledSeasonalPackageAirsOutOfSeason() {
        let state = AppState(credentialStore: MemStore())
        state.bundles = [scream]
        state.enabledBundleIDs = ["seasonal"]
        state.allChannels = [131, 141].map {
            Channel(id: $0, number: $0, name: "CH\($0)", color: .red, category: nil,
                    rules: nil, timeRestrictions: nil, minItems: 0)
        }
        state.applyBundleFilter()
        XCTAssertEqual(Set(state.channels.map(\.id)), [131, 141],
                       "a package the viewer turned on must air whatever the month")
    }

    func testItIsOnlyOfferedInItsOwnMonth() {
        let offer: (Date) -> String? = { now in
            SeasonalPrompt.bundleToOffer(bundles: [self.scream], enabledBundleIDs: [], now: now) { _ in false }?.id
        }
        XCTAssertEqual(offer(date(10)), "seasonal")
        XCTAssertNil(offer(date(7)), "no invitation outside October")
    }

    func testItOnlyLeadsTheGuideInItsOwnMonth() {
        let lead: (Date) -> [Int] = {
            GuideChannelOrder.seasonalLeadIDs(bundles: [self.scream], enabledBundleIDs: ["seasonal"], now: $0)
        }
        XCTAssertEqual(lead(date(10)), [131, 141], "October: straight to the top")
        XCTAssertEqual(lead(date(7)), [], "July: sits in normal channel order")
    }

    func testAutoEnableStillNeverTurnsASeasonalPackageOn() {
        let state = AppState(credentialStore: MemStore())
        state.bundles = [scream.id == "seasonal" ? ChannelBundleDefinition(
            id: "seasonal", name: "SCREAM", description: nil,
            channelIDs: [131], activeMonths: [10]).toChannelBundle(enabled: false) : scream]
        state.allChannels = [Channel(id: 131, number: 131, name: "x", color: .red, category: nil,
                                     rules: nil, timeRestrictions: nil, minItems: 0)]
        state.enabledBundleIDs = []
        state.autoEnableBundlesWithContent()
        XCTAssertFalse(state.enabledBundleIDs.contains("seasonal"),
                       "still invitation-only, in season or out")
    }
}
