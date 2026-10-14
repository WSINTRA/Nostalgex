import XCTest
@testable import Nostalgex

/// The lineup keeps growing. These stop it from growing into the range the app hands to
/// discovered collections at runtime, which is what turned HISTORY & BIO into Toy Story.
final class ChannelIDSpaceTests: XCTestCase {

    private func shippedConfig() throws -> ChannelConfigResult {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "channels", withExtension: "json"))
        return try XCTUnwrap(ChannelConfigLoader.loadConfig(from: Data(contentsOf: url)))
    }

    /// The one that matters: add a channel above the line and this fails before it ships.
    func testNoChannelInTheConfigUsesARuntimeID() throws {
        let offenders = try shippedConfig().channels
            .filter { ChannelIDSpace.isDynamic($0.id) }
            .map { "\($0.name) (id \($0.id))" }
        XCTAssertTrue(offenders.isEmpty,
            "channels.json must stay below \(ChannelIDSpace.dynamicBase); discovered collections own everything above it. Offending: \(offenders)")
    }

    func testBundlesOnlyReferenceStaticChannels() throws {
        let config = try shippedConfig()
        for bundle in config.bundles {
            let bad = bundle.channelIDs.filter { ChannelIDSpace.isDynamic($0) }
            XCTAssertTrue(bad.isEmpty, "\(bundle.name) references runtime ids \(bad)")
        }
    }

    func testCategoryRangesDoNotOverlapEachOther() {
        // franchises and custom used to collide at 240-269.
        let bases = CollectionCategory.allCases.map(\.idBase).sorted()
        for (a, b) in zip(bases, bases.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, ChannelIDSpace.categoryStride,
                "categories must not share ids")
        }
        XCTAssertEqual(Set(bases).count, CollectionCategory.allCases.count)
    }

    func testEveryCategoryStartsInsideTheRuntimeSpace() {
        for category in CollectionCategory.allCases {
            XCTAssertTrue(ChannelIDSpace.isDynamic(category.idBase), "\(category) base must be runtime")
            // A library would need 10,000 collections in one category to run out.
            XCTAssertTrue(ChannelIDSpace.isDynamic(category.idBase + ChannelIDSpace.categoryStride - 1))
        }
    }

    func testDisplayNumbersStayReadable() {
        // Ids are large so they cannot collide; the row still shows a short number.
        for category in CollectionCategory.allCases {
            XCTAssertLessThan(category.displayNumberBase, 1000, "\(category) would show a six-digit channel number")
        }
    }

    func testTheBoundaryItself() {
        XCTAssertTrue(ChannelIDSpace.isStatic(ChannelIDSpace.dynamicBase - 1))
        XCTAssertTrue(ChannelIDSpace.isDynamic(ChannelIDSpace.dynamicBase))
    }
}
