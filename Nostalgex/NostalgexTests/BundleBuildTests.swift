import XCTest
@testable import Nostalgex

/// Switching a package on in Settings builds its channels in the background. These tests
/// drive the real `toggleBundle` path and wait for the build to finish.
@MainActor
final class BundleBuildTests: XCTestCase {
    private var savedBundles: Any?
    private var state: AppState!

    override func setUp() {
        savedBundles = UserDefaults.standard.object(forKey: PreferenceSync.enabledBundlesKey)
        let suite = UserDefaults(suiteName: "BundleBuildTests.\(UUID().uuidString)")!
        let sync = PreferenceSync(cloud: InMemoryKeyValueStore(), defaults: suite,
                                  observeNotifications: false, keys: PreferenceSync.syncedKeys)
        state = AppState(preferenceSync: sync)
    }

    override func tearDown() {
        if let savedBundles {
            UserDefaults.standard.set(savedBundles, forKey: PreferenceSync.enabledBundlesKey)
        } else {
            UserDefaults.standard.removeObject(forKey: PreferenceSync.enabledBundlesKey)
        }
    }

    private func item(_ title: String) -> PlexMediaItem {
        PlexMediaItem(
            id: title, title: title, artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 2000, originallyAvailableAt: nil, contentRating: nil,
            duration: 90, ratingKey: title, partKey: nil, container: nil,
            videoCodec: nil, audioCodec: nil, videoProfile: nil, bitrate: nil,
            genres: [], rating: 0, userRating: 0, type: .movie, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil, librarySource: .movie
        )
    }

    private func template(_ id: Int, _ word: String) -> Channel {
        var rules = ChannelRules()
        rules.titleContains = [word]
        return Channel(id: id, number: id, name: "CH\(id)", color: .blue, category: nil,
                       rules: rules, timeRestrictions: nil, minItems: 1, itemPool: [])
    }

    /// Two packages of six channels each, every channel matching its own word.
    private func setUpTwoPackages() -> (ChannelBundle, ChannelBundle) {
        let words = (1...12).map { "word\($0)x" }
        state.allItems = words.flatMap { w in (1...20).map { item("\(w) \($0)") } }
        state.channelConfigChannels = (1...12).map { template($0, words[$0 - 1]) }
        let a = ChannelBundle(id: "a", name: "A", description: "", channelIDs: Array(1...6), activeMonths: nil, enabled: false)
        let b = ChannelBundle(id: "b", name: "B", description: "", channelIDs: Array(7...12), activeMonths: nil, enabled: false)
        let base = ChannelBundle(id: "base", name: "BASE", description: "", channelIDs: [], activeMonths: nil, enabled: true)
        state.bundles = [base, a, b]
        state.enabledBundleIDs = ["base"]
        state.allChannels = []
        return (a, b)
    }

    func testTwoQuickTogglesBothKeepTheirChannels() async {
        let (a, b) = setUpTwoPackages()
        state.toggleBundle(a)
        state.toggleBundle(b)
        XCTAssertEqual(state.buildingBundleIDs, ["a", "b"], "both rows show they are building")
        await state.collectionScanTask?.value
        // Let any build that was not the last-stored task finish too.
        for _ in 0..<50 { await Task.yield() }

        let built = Set(state.allChannels.map(\.id))
        XCTAssertEqual(built, Set(1...12), "missing \(Set(1...12).subtracting(built).sorted())")
        XCTAssertEqual(Set(state.channels.map(\.id)), Set(1...12))
        XCTAssertTrue(state.buildingBundleIDs.isEmpty, "spinners clear once the channels are in")
    }

    func testSwitchingAPackageOffNeedsNoBuild() {
        let (a, _) = setUpTwoPackages()
        state.enabledBundleIDs.insert("a")
        state.toggleBundle(a)
        XCTAssertTrue(state.buildingBundleIDs.isEmpty)
    }
}
