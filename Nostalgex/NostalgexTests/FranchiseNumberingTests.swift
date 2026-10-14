import XCTest
@testable import Nostalgex

/// Display numbers for runtime channels, and the franchises that start switched on.
///
/// Found franchises used to number from 220 and custom collections from 260. A library
/// with 86 franchises under ADD ALL ran the franchise numbers through 305, so two rows
/// showed the same number and interleaved in the guide. Franchises now own 300-499 and
/// collections 500-699, each capped at its range end.
@MainActor
final class FranchiseNumberingTests: XCTestCase {

    private let enabledKey = AppState.enabledFranchisesKey
    private let disabledKey = AppState.disabledFranchisesKey
    private let collectionsKey = "nostalgex_enabled_collections"
    private let bundlesKey = "nostalgex_enabled_bundles"
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        for key in [enabledKey, disabledKey, collectionsKey, bundlesKey] {
            if let v = d.object(forKey: key) { saved[key] = v }
            d.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        let d = UserDefaults.standard
        for key in [enabledKey, disabledKey, collectionsKey, bundlesKey] {
            if let v = saved[key] { d.set(v, forKey: key) } else { d.removeObject(forKey: key) }
        }
        super.tearDown()
    }

    // MARK: - Fixtures

    private func movie(_ id: String, _ title: String) -> PlexMediaItem {
        PlexMediaItem(
            id: id, title: title, artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 2000, originallyAvailableAt: nil, contentRating: nil,
            duration: 120, ratingKey: id, partKey: nil, container: nil,
            videoCodec: nil, audioCodec: nil, videoProfile: nil, bitrate: nil,
            genres: [], rating: 0, userRating: 0, type: .movie, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: id, imdbID: nil, librarySource: .movie
        )
    }

    private func films(_ prefix: String, _ count: Int = 3) -> [PlexMediaItem] {
        (1...count).map { movie("\(prefix)-\($0)", "\(prefix) \($0)") }
    }

    private func franchise(_ i: Int, enabled: Bool = true) -> FoundFranchise {
        FoundFranchise(id: "tmdb:\(10_000 + i)", name: String(format: "FRANCHISE %03d", i),
                       movies: films("f\(i)"), tvItems: [], coveredByChannelID: nil,
                       fromDictionary: false, enabled: enabled)
    }

    private func collection(_ id: String, category: CollectionCategory, enabled: Bool = true) -> DiscoveredCollection {
        let items = films(id)
        return DiscoveredCollection(id: id, title: id.uppercased(), movieCount: items.count, items: items,
                                    enabled: enabled, matchedChannel: nil, contentOverlap: nil, category: category)
    }

    private func makeState() -> AppState {
        let state = AppState()
        state.bundles = [
            ChannelBundle(id: AppState.franchisesBundleID, name: "FRANCHISES", description: nil,
                          channelIDs: [100, 101, 102, 103, 104, 105, 106], activeMonths: nil, enabled: true)
        ]
        state.enabledBundleIDs = [AppState.franchisesBundleID]
        state.allChannels = []
        state.discoveredCollections = []
        return state
    }

    private func shippedStaticNumbers() throws -> Set<Int> {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "channels", withExtension: "json"))
        let config = try XCTUnwrap(ChannelConfigLoader.loadConfig(from: Data(contentsOf: url)))
        return Set(config.channels.map(\.number))
    }

    private func numbers(_ state: AppState, _ category: CollectionCategory) -> [Int] {
        state.allChannels.filter { ChannelIDSpace.isDynamic($0.id) && $0.category == category.rawValue }
            .map(\.number).sorted()
    }

    // MARK: - Ranges

    func testRangesSitClearOfEveryShippedNumber() throws {
        let staticNumbers = try shippedStaticNumbers()
        XCTAssertLessThan(staticNumbers.max() ?? 0, CollectionCategory.franchises.displayNumberBase,
                          "channels.json now reaches the franchise range")
        XCTAssertEqual(CollectionCategory.franchises.displayNumberBase, 300)
        XCTAssertEqual(CollectionCategory.franchises.displayNumberEnd, 499)
        XCTAssertEqual(CollectionCategory.custom.displayNumberBase, 500)
        XCTAssertEqual(CollectionCategory.custom.displayNumberEnd, 699)
        let ordered = CollectionCategory.allCases.sorted { $0.displayNumberBase < $1.displayNumberBase }
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(a.displayNumberEnd, b.displayNumberBase, "\(a) and \(b) overlap")
        }
    }

    func testEightySixFranchisesNumber300Through385AndCollectionsStartAt500() throws {
        let state = makeState()
        state.foundFranchises = (0..<86).map { franchise($0) }
        state.discoveredCollections = [
            collection("saga-a", category: .franchises), collection("saga-b", category: .franchises),
            collection("hanks", category: .custom), collection("nolan", category: .custom),
            collection("off", category: .custom, enabled: false)
        ]

        state.materializeDynamicChannels()

        let found = state.allChannels.filter { state.foundFranchiseChannelIDs.contains($0.id) }.map(\.number)
        XCTAssertEqual(found, Array(300...385))
        // The franchise category's own server collections follow the found franchises.
        XCTAssertEqual(numbers(state, .franchises), Array(300...387))
        XCTAssertTrue(numbers(state, .franchises).allSatisfy { $0 < 500 })
        XCTAssertEqual(numbers(state, .custom), [500, 501])

        // No duplicate number anywhere: runtime numbers are unique and none lands on a
        // number channels.json uses.
        let dynamic = state.allChannels.filter { ChannelIDSpace.isDynamic($0.id) }.map(\.number)
        XCTAssertEqual(Set(dynamic).count, dynamic.count)
        XCTAssertTrue(Set(dynamic).isDisjoint(with: try shippedStaticNumbers()))
        XCTAssertEqual(state.dynamicChannelsOverCap, [:])

        // The guide order is by number, so the franchises run as one contiguous block.
        XCTAssertEqual(state.allChannels.map(\.number), state.allChannels.map(\.number).sorted())
    }

    func testFranchiseRangeIsCappedAt499() {
        let state = makeState()
        state.foundFranchises = (0..<205).map { franchise($0) }
        state.discoveredCollections = [
            collection("saga-a", category: .franchises), collection("hanks", category: .custom)
        ]

        state.materializeDynamicChannels()

        let franchiseNumbers = numbers(state, .franchises)
        XCTAssertEqual(franchiseNumbers.count, 200)
        XCTAssertEqual(franchiseNumbers.first, 300)
        XCTAssertEqual(franchiseNumbers.last, 499)
        // Five found franchises and the franchise-category collection did not fit.
        XCTAssertEqual(state.dynamicChannelsOverCap[.franchises], 6)
        XCTAssertNil(state.dynamicChannelsOverCap[.custom])
        XCTAssertEqual(numbers(state, .custom), [500], "collections keep their own numbers")

        // Switching some off frees the range and the counter clears.
        for i in 0..<10 { state.foundFranchises[i].enabled = false }
        state.materializeDynamicChannels()
        XCTAssertEqual(state.dynamicChannelsOverCap, [:])
        XCTAssertEqual(numbers(state, .franchises).last, 495)
    }

    func testCollectionRangeIsCappedAt699() {
        let state = makeState()
        state.enabledBundleIDs.insert(CollectionCategory.custom.bundleID)
        state.discoveredCollections = (0..<203).map { collection(String(format: "set-%03d", $0), category: .custom) }

        state.materializeDynamicChannels()

        let custom = numbers(state, .custom)
        XCTAssertEqual(custom.count, 200)
        XCTAssertEqual(custom.last, 699)
        XCTAssertEqual(state.dynamicChannelsOverCap[.custom], 3)
    }

    // MARK: - Saved choices survive the renumber

    func testSavedChoicesAreKeyedByIDSoTheyComeBackOnTheNewNumbers() {
        // What an older build left behind: ids, never numbers.
        UserDefaults.standard.set(["tmdb:10001", "tmdb:10003"], forKey: enabledKey)
        UserDefaults.standard.set(["hanks"], forKey: collectionsKey)

        let state = makeState()
        XCTAssertEqual(state.enabledFranchiseIDs, ["tmdb:10001", "tmdb:10003"])
        // A runtime row restored from an old snapshot still carries its old number.
        state.allChannels = [Channel(id: CollectionCategory.franchises.idBase, number: 221, name: "FRANCHISE 001",
                                     color: .blue, category: CollectionCategory.franchises.rawValue,
                                     rules: nil, timeRestrictions: nil, minItems: 3)]
        // Rebuilt lists resolve enabled state from the saved ids, the way the scan does.
        state.foundFranchises = (0..<4).map { i in
            franchise(i, enabled: FranchiseDictionary.isOn("tmdb:\(10_000 + i)",
                                                           enabledIDs: state.enabledFranchiseIDs,
                                                           disabledIDs: state.disabledFranchiseIDs))
        }
        state.discoveredCollections = [
            collection("hanks", category: .custom, enabled: state.enabledCollectionKeys.contains("hanks")),
            collection("nolan", category: .custom, enabled: state.enabledCollectionKeys.contains("nolan"))
        ]

        state.materializeDynamicChannels()

        let dynamic = state.allChannels.filter { ChannelIDSpace.isDynamic($0.id) }
        XCTAssertEqual(dynamic.map(\.name), ["FRANCHISE 001", "FRANCHISE 003", "HANKS"])
        XCTAssertEqual(dynamic.map(\.number), [300, 301, 500])
        XCTAssertFalse(state.allChannels.contains { $0.number == 221 }, "the stale row is gone")

        // The snapshot row path agrees.
        let row = StoredFoundFranchise.from(franchise(3))
        XCTAssertTrue(row.resolve(itemLookup: [:], enabledIDs: state.enabledFranchiseIDs).enabled)
    }

    // MARK: - Default-on franchises

    private func enrichment(_ fid: Int, _ name: String) -> MediaEnrichment {
        MediaEnrichment(
            tmdbID: UUID().uuidString, imdbID: nil, mediaType: "movie",
            keywords: [], networks: [], productionCompanies: [], tmdbGenres: [],
            imdbRating: nil, imdbVotes: nil, rottenTomatoesScore: nil, metacriticScore: nil,
            awards: nil, franchiseID: fid, franchiseName: name, fetchedAt: Date()
        )
    }

    private var trek: [PlexMediaItem] {
        [movie("st1", "Star Trek: The Motion Picture"), movie("st2", "Star Trek II: The Wrath of Khan"),
         movie("st3", "Star Trek III: The Search for Spock")]
    }
    private var fast: [PlexMediaItem] {
        [movie("ff1", "The Fast and the Furious"), movie("ff2", "2 Fast 2 Furious"), movie("ff3", "Fast Five")]
    }
    private var wick: [PlexMediaItem] {
        [movie("w1", "John Wick"), movie("w2", "John Wick: Chapter 2"),
         movie("w3", "John Wick: Chapter 3 - Parabellum")]
    }

    private var lookup: (PlexMediaItem) -> MediaEnrichment? {
        var map: [String: MediaEnrichment] = [:]
        for m in trek { map[m.id] = enrichment(151, "Star Trek: The Original Series Collection") }
        for m in fast { map[m.id] = enrichment(9485, "The Fast and the Furious Collection") }
        for m in wick { map[m.id] = enrichment(404609, "John Wick Collection") }
        return { map[$0.id] }
    }

    private func onNames(_ state: AppState) -> [String] {
        state.listedFoundFranchises.filter(\.enabled).map(\.name).sorted()
    }

    func testDictionaryMarksStarTrekAndFastAndFuriousDefaultOn() {
        XCTAssertEqual(FranchiseDictionary.defaultOnIDs, ["dict:STAR TREK", "dict:FAST & FURIOUS"])
    }

    func testStarTrekAndFastAndFuriousStartOnEverythingElseOff() {
        let state = makeState()
        state.allItems = trek + fast + wick
        state.rebuildFoundFranchises(enrichmentFor: lookup)
        state.materializeDynamicChannels()
        state.applyBundleFilter()

        XCTAssertEqual(onNames(state), ["FAST & FURIOUS", "STAR TREK"])
        XCTAssertEqual(state.listedFoundFranchises.first { $0.name == "JOHN WICK" }?.enabled, false)
        XCTAssertTrue(state.channels.contains { $0.name == "STAR TREK" })
        XCTAssertTrue(state.channels.contains { $0.name == "FAST & FURIOUS" })
        XCTAssertFalse(state.channels.contains { $0.name == "JOHN WICK" })
        // A default is not a choice: nothing is written until the viewer acts.
        XCTAssertNil(UserDefaults.standard.stringArray(forKey: enabledKey))
    }

    func testStarTrekSwitchedOffStaysOffAcrossRelaunchAndRescan() {
        let state = makeState()
        state.allItems = trek + fast + wick
        state.rebuildFoundFranchises(enrichmentFor: lookup)
        let star = state.listedFoundFranchises.first { $0.name == "STAR TREK" }!

        state.toggleFranchise(star)

        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: disabledKey), ["dict:STAR TREK"])
        XCTAssertFalse(state.channels.contains { $0.name == "STAR TREK" })

        // Rescan on the same TV.
        state.rebuildFoundFranchises(enrichmentFor: lookup)
        XCTAssertEqual(onNames(state), ["FAST & FURIOUS"])

        // Relaunch.
        let relaunched = makeState()
        relaunched.allItems = trek + fast + wick
        relaunched.rebuildFoundFranchises(enrichmentFor: lookup)
        XCTAssertEqual(onNames(relaunched), ["FAST & FURIOUS"])

        // Snapshot restore path agrees.
        let row = StoredFoundFranchise.from(star)
        XCTAssertFalse(row.resolve(itemLookup: [:], enabledIDs: relaunched.enabledFranchiseIDs,
                                   disabledIDs: relaunched.disabledFranchiseIDs).enabled)
        XCTAssertTrue(row.resolve(itemLookup: [:], enabledIDs: []).enabled, "default on with no choice recorded")

        // Back on: the off record clears.
        relaunched.toggleFranchise(relaunched.listedFoundFranchises.first { $0.name == "STAR TREK" }!)
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: disabledKey), [])
        XCTAssertEqual(onNames(relaunched), ["FAST & FURIOUS", "STAR TREK"])
    }

    func testAddAllAndRemoveAllStillWorkWithDefaults() {
        let state = makeState()
        state.allItems = trek + fast + wick
        state.rebuildFoundFranchises(enrichmentFor: lookup)

        state.setAllFoundFranchises(enabled: false)
        XCTAssertEqual(onNames(state), [])
        XCTAssertTrue(state.channels.filter { $0.rules == nil }.isEmpty)

        let relaunched = makeState()
        relaunched.allItems = trek + fast + wick
        relaunched.rebuildFoundFranchises(enrichmentFor: lookup)
        XCTAssertEqual(onNames(relaunched), [], "REMOVE ALL holds the defaults off too")

        relaunched.setAllFoundFranchises(enabled: true)
        XCTAssertEqual(onNames(relaunched), ["FAST & FURIOUS", "JOHN WICK", "STAR TREK"])
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: disabledKey), [])
        XCTAssertEqual(relaunched.channels.filter { $0.rules == nil }.map(\.number), [300, 301, 302])
    }

    func testNoChannelWhenTheLibraryHasNoneOfThem() {
        let state = makeState()
        state.allItems = wick + [trek[0], fast[0]]   // one film each: under the three-film gate
        state.rebuildFoundFranchises(enrichmentFor: lookup)
        state.materializeDynamicChannels()
        state.applyBundleFilter()

        XCTAssertEqual(state.listedFoundFranchises.map(\.name), ["JOHN WICK"])
        XCTAssertFalse(state.channels.contains { $0.name == "STAR TREK" || $0.name == "FAST & FURIOUS" })
    }
}
