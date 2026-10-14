import XCTest
@testable import Nostalgex

/// Shared golden vectors for franchise grouping.
///
/// `scripts/franchise-golden.json` is read by this test AND by the web tuner's node
/// test (`npm run test:franchises`, scripts/nostalgex-franchise-smoke.mjs). Both
/// engines must produce the expected groupings exactly, so the Apple TV app and the
/// browser build the same franchise channels from the same library. The dictionary
/// comes from the bundled `franchises.json`, which also proves the build phase copied
/// it into the app.
final class FranchiseGoldenTests: XCTestCase {

    // MARK: - Golden file shape

    private struct Golden: Decodable {
        let cases: [Case]
        let titleKeys: [TitleKey]
        let filmMatches: [FilmMatch]
        let mergeKeys: [MergeKey]
        let collectionFolds: [Fold]
    }

    private struct MergeKey: Decodable {
        let name: String
        let key: String
    }

    private struct Enrichment: Decodable {
        let franchiseID: Int?
        let franchiseName: String?
    }

    private struct Item: Decodable {
        let id: String
        let title: String
        let episodeTitle: String?
        let enrichment: Enrichment?
    }

    private struct Placement: Decodable, Equatable {
        let type: String
        let channelID: Int?
    }

    private struct Expected: Decodable, Equatable {
        let name: String
        let stableID: String
        let placement: Placement
        let movies: [String]
        let tvItems: [String]
        let mergedFranchiseIDs: [Int]
        let fromDictionary: Bool
    }

    private struct Case: Decodable {
        let name: String
        let definitions: [FranchiseDefinition]?
        let minimumFilms: Int?
        let availableStockChannelIDs: [Int]
        let movies: [Item]
        let tvItems: [Item]
        let expected: [Expected]
    }

    private struct TitleKey: Decodable {
        let title: String
        let key: String
    }

    private struct FilmMatch: Decodable {
        let title: String
        let franchise: String?
    }

    private struct Fold: Decodable {
        let about: String
        let availableStockChannelIDs: [Int]
        let items: [Item]
        let stockChannelID: Int?
    }

    // MARK: - Fixtures

    /// Repo root, found from this source file: NostalgexTests -> Nostalgex -> root.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func loadGolden() throws -> Golden {
        let url = Self.repoRoot.appendingPathComponent("scripts/franchise-golden.json")
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    private func movie(_ item: Item) -> PlexMediaItem {
        PlexMediaItem(
            id: item.id, title: item.title, artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 2000, originallyAvailableAt: nil, contentRating: nil,
            duration: 120, ratingKey: item.id, partKey: nil, container: nil,
            videoCodec: nil, audioCodec: nil, videoProfile: nil, bitrate: nil,
            genres: [], rating: 0, userRating: 0, type: .movie, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: item.id, imdbID: nil, librarySource: .movie
        )
    }

    private func episode(_ item: Item) -> PlexMediaItem {
        PlexMediaItem(
            id: item.id, title: item.title, artist: nil, episodeTitle: item.episodeTitle ?? "Pilot",
            seTag: "S01E01", summary: "", year: 2020, originallyAvailableAt: nil, contentRating: nil,
            duration: 45, ratingKey: item.id, partKey: nil, container: nil,
            videoCodec: nil, audioCodec: nil, videoProfile: nil, bitrate: nil,
            genres: [], rating: 0, userRating: 0, type: .episode, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: item.id, imdbID: nil, librarySource: .tv
        )
    }

    /// id -> enrichment, only for items the golden file marks as enriched.
    private func lookup(_ items: [Item]) -> (PlexMediaItem) -> MediaEnrichment? {
        var map: [String: MediaEnrichment] = [:]
        for item in items {
            guard let e = item.enrichment else { continue }
            map[item.id] = MediaEnrichment(
                tmdbID: item.id, imdbID: nil, mediaType: "movie",
                keywords: [], networks: [], productionCompanies: [], tmdbGenres: [],
                imdbRating: nil, imdbVotes: nil, rottenTomatoesScore: nil, metacriticScore: nil,
                awards: nil, franchiseID: e.franchiseID, franchiseName: e.franchiseName, fetchedAt: Date()
            )
        }
        return { map[$0.id] }
    }

    private func project(_ g: FranchiseChannelBuilder.FranchiseGrouping) -> Expected {
        let placement: Placement
        switch g.placement {
        case let .stock(channelID): placement = Placement(type: "stock", channelID: channelID)
        case .dynamic: placement = Placement(type: "dynamic", channelID: nil)
        }
        return Expected(
            name: g.name, stableID: g.stableID, placement: placement,
            movies: g.movies.map(\.id), tvItems: g.tvItems.map(\.id),
            mergedFranchiseIDs: g.mergedFranchiseIDs, fromDictionary: g.fromDictionary
        )
    }

    private func signature(_ d: FranchiseDefinition) -> String {
        "\(d.canonicalName)|\(String(describing: d.stockChannelID))|\(d.tmdbCollectionIDs)|\(d.nameMatchTokens)"
            + "|\(d.tvShowTitles)|\(d.filmTitles)|\(d.studioRuled)|\(d.defaultOn)"
    }

    // MARK: - The dictionary comes from franchises.json

    func testBundledDictionaryIsTheRepoFile() throws {
        let repoFile = try FranchiseDictionary.decode(
            Data(contentsOf: Self.repoRoot.appendingPathComponent("franchises.json")))
        XCTAssertEqual(FranchiseDictionary.all.count, 19)
        XCTAssertEqual(FranchiseDictionary.all.map(signature), repoFile.map(signature),
                       "the app bundle carries a stale franchises.json; check the Sync channel config build phase")
    }

    func testMissingFileFallsBackToEmptyDictionary() {
        // The test bundle has no franchises.json: the loader logs and returns nothing.
        XCTAssertTrue(FranchiseDictionary.loadBundled(bundle: Bundle(for: FranchiseGoldenTests.self)).isEmpty)
    }

    func testDecoderFillsDefaults() throws {
        let defs = try FranchiseDictionary.decode(Data(#"{"version":1,"franchises":[{"canonicalName":"X","note":"ignored"}]}"#.utf8))
        XCTAssertEqual(defs.count, 1)
        XCTAssertEqual(signature(defs[0]), "X|nil|[]|[]|[]|[]|false|false")
    }

    // MARK: - Golden vectors (same file the node test reads)

    func testGoldenCases() throws {
        let golden = try loadGolden()
        XCTAssertGreaterThanOrEqual(golden.cases.count, 15)
        for c in golden.cases {
            let groupings = FranchiseChannelBuilder.build(
                movies: c.movies.map(movie),
                tvItems: c.tvItems.map(episode),
                enrichmentFor: lookup(c.movies),
                availableStockChannelIDs: Set(c.availableStockChannelIDs),
                definitions: c.definitions ?? FranchiseDictionary.all,
                minimumFilms: c.minimumFilms ?? 3
            )
            XCTAssertEqual(groupings.map(project), c.expected, "golden case \(c.name)")
        }
    }

    func testGoldenTitleKeys() throws {
        for v in try loadGolden().titleKeys {
            XCTAssertEqual(FranchiseChannelBuilder.explicitTitleKey(v.title), v.key, "title key \(v.title)")
        }
    }

    func testGoldenFilmMatches() throws {
        for v in try loadGolden().filmMatches {
            XCTAssertEqual(FranchiseChannelBuilder.dictionaryMatch(forFilmTitle: v.title)?.canonicalName,
                           v.franchise, "film match \(v.title)")
        }
    }

    func testGoldenMergeKeys() throws {
        let keys = try loadGolden().mergeKeys
        XCTAssertFalse(keys.isEmpty)
        for v in keys {
            XCTAssertEqual(FranchiseChannelBuilder.franchiseMergeKey(v.name), v.key, "merge key \(v.name)")
        }
    }

    func testGoldenCollectionFolds() throws {
        for v in try loadGolden().collectionFolds {
            let got = FranchiseChannelBuilder.stockChannel(
                forCollectionItems: v.items.map(movie),
                enrichmentFor: lookup(v.items),
                availableStockChannelIDs: Set(v.availableStockChannelIDs))
            XCTAssertEqual(got, v.stockChannelID, "collection fold: \(v.about)")
        }
    }
}
