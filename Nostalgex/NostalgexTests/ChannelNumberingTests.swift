import XCTest
@testable import Nostalgex

/// A package should read as a block in the guide, not as channels scattered through the
/// lineup. SCREAM once ran 19, 77, 131 and 132 — a span of 114 for four channels.
final class ChannelNumberingTests: XCTestCase {

    private func config() throws -> ChannelConfigResult {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "channels", withExtension: "json"))
        return try XCTUnwrap(ChannelConfigLoader.loadConfig(from: Data(contentsOf: url)))
    }

    func testEveryBundleIsOneUnbrokenRunOfNumbers() throws {
        let c = try config()
        let number = Dictionary(uniqueKeysWithValues: c.channels.map { ($0.id, $0.number) })
        for bundle in c.bundles where !bundle.id.hasPrefix("collections-") {
            let ns = bundle.channelIDs.compactMap { number[$0] }.sorted()
            guard let lo = ns.first, let hi = ns.last else { continue }
            XCTAssertEqual(hi - lo + 1, ns.count,
                "\(bundle.name) spans \(lo)-\(hi) for \(ns.count) channels; a package should be one block")
        }
    }

    func testNoTwoChannelsShareANumber() throws {
        let numbers = try config().channels.map(\.number)
        XCTAssertEqual(Set(numbers).count, numbers.count, "two channels claim the same number")
    }

    /// A channel can only sit in one block, so it can only belong to one bundle.
    func testNoChannelIsInTwoBundles() throws {
        let c = try config()
        var owner: [Int: String] = [:]
        for bundle in c.bundles where !bundle.id.hasPrefix("collections-") {
            for id in bundle.channelIDs {
                if let first = owner[id] {
                    XCTFail("channel \(id) is in both \(first) and \(bundle.name); it cannot be numbered into both")
                }
                owner[id] = bundle.name
            }
        }
    }

    func testEveryChannelBelongsToABundle() throws {
        let c = try config()
        let claimed = Set(c.bundles.flatMap(\.channelIDs))
        let orphans = c.channels.filter { !claimed.contains($0.id) }.map(\.name)
        XCTAssertTrue(orphans.isEmpty, "unreachable channels: \(orphans)")
    }

    func testMusicVideosSitAboveTheRestWithRoomToGrow() throws {
        let c = try config()
        let number = Dictionary(uniqueKeysWithValues: c.channels.map { ($0.id, $0.number) })
        let music = try XCTUnwrap(c.bundles.first { $0.id == "high-rotation" })
        let lowest = music.channelIDs.compactMap { number[$0] }.min() ?? 0
        XCTAssertGreaterThanOrEqual(lowest, 200, "music videos start at 200 to leave 150-199 free")
        let others = c.bundles.filter { $0.id != "high-rotation" && !$0.id.hasPrefix("collections-") }
            .flatMap { $0.channelIDs }.compactMap { number[$0] }
        XCTAssertLessThan(others.max() ?? 0, 200, "everything else stays below the music block")
    }
}
