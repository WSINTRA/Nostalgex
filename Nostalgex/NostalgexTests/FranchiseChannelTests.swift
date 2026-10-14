import XCTest
@testable import Nostalgex

/// Phase 1 of the franchise bundle: pure logic that turns a library + enrichment into
/// the franchise channel list. No Settings wiring, no schedule/playback change — these
/// tests drive `FranchiseChannelBuilder` and `FranchiseDictionary` directly with
/// golden vectors and an injected enrichment lookup (no network).
final class FranchiseChannelTests: XCTestCase {

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

    private func show(_ id: String, _ title: String) -> PlexMediaItem {
        PlexMediaItem(
            id: id, title: title, artist: nil, episodeTitle: "Pilot", seTag: "S01E01",
            summary: "", year: 2020, originallyAvailableAt: nil, contentRating: nil,
            duration: 45, ratingKey: id, partKey: nil, container: nil,
            videoCodec: nil, audioCodec: nil, videoProfile: nil, bitrate: nil,
            genres: [], rating: 0, userRating: 0, type: .episode, thumb: nil, art: nil,
            viewCount: 0, addedAt: 0, studio: nil, tmdbID: id, imdbID: nil, librarySource: .tv
        )
    }

    private func enrichment(franchiseID: Int?, franchiseName: String?) -> MediaEnrichment {
        MediaEnrichment(
            tmdbID: UUID().uuidString, imdbID: nil, mediaType: "movie",
            keywords: [], networks: [], productionCompanies: [], tmdbGenres: [],
            imdbRating: nil, imdbVotes: nil, rottenTomatoesScore: nil, metacriticScore: nil,
            awards: nil, franchiseID: franchiseID, franchiseName: franchiseName, fetchedAt: Date()
        )
    }

    /// Build an enrichment lookup from an [itemID: (fid, name)] table.
    private func lookup(_ table: [String: (Int, String)]) -> (PlexMediaItem) -> MediaEnrichment? {
        var map: [String: MediaEnrichment] = [:]
        for (id, pair) in table {
            map[id] = enrichment(franchiseID: pair.0, franchiseName: pair.1)
        }
        return { map[$0.id] }
    }

    // MARK: - Grouping threshold

    func testThreeFilmsMakeAChannel() {
        let movies = [movie("a", "Spy Kids"), movie("b", "Spy Kids 2"), movie("c", "Spy Kids 3")]
        let look = lookup([
            "a": (99999, "Spy Kids Collection"),
            "b": (99999, "Spy Kids Collection"),
            "c": (99999, "Spy Kids Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(movies: movies, enrichmentFor: look)
        XCTAssertEqual(groupings.count, 1)
        XCTAssertEqual(groupings.first?.name, "SPY KIDS")
        XCTAssertEqual(groupings.first?.placement, .dynamic)
        XCTAssertEqual(groupings.first?.movies.count, 3)
    }

    func testTwoFilmsDoNotMakeAChannel() {
        let movies = [movie("a", "Spy Kids"), movie("b", "Spy Kids 2")]
        let look = lookup([
            "a": (99999, "Spy Kids Collection"),
            "b": (99999, "Spy Kids Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(movies: movies, enrichmentFor: look)
        XCTAssertTrue(groupings.isEmpty)
    }

    // MARK: - Dictionary fold into a stock channel

    func testDictionaryFranchiseFoldsIntoStockChannelWithoutDuplicate() {
        let movies = [movie("a", "Star Wars"), movie("b", "The Empire Strikes Back"), movie("c", "Return of the Jedi")]
        let look = lookup([
            "a": (10, "Star Wars Collection"),
            "b": (10, "Star Wars Collection"),
            "c": (10, "Star Wars Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(
            movies: movies, enrichmentFor: look, availableStockChannelIDs: [100])

        XCTAssertEqual(groupings.count, 1, "no duplicate dynamic channel next to the stock one")
        let sw = groupings.first
        XCTAssertEqual(sw?.name, "STAR WARS")
        XCTAssertEqual(sw?.placement, .stock(channelID: 100))
        XCTAssertEqual(sw?.movies.count, 3)
        XCTAssertFalse(groupings.contains { $0.placement == .dynamic })
    }

    func testStockFoldMergesMultipleCollections() throws {
        // LOTR (119) + The Hobbit (121938, verified against TMDB 2026-10-10) roll up
        // into one franchise on CH104. The ids are read from the dictionary rather than
        // hard-coded so this test tracks the verified values.
        let lotr = try XCTUnwrap(FranchiseDictionary.all.first { $0.canonicalName == "LORD OF THE RINGS" })
        XCTAssertEqual(lotr.tmdbCollectionIDs.count, 2)
        let (ringsID, hobbitID) = (lotr.tmdbCollectionIDs[0], lotr.tmdbCollectionIDs[1])
        let movies = [
            movie("a", "The Fellowship of the Ring"), movie("b", "The Two Towers"),
            movie("c", "An Unexpected Journey"), movie("d", "The Desolation of Smaug")
        ]
        let look = lookup([
            "a": (ringsID, "The Lord of the Rings Collection"),
            "b": (ringsID, "The Lord of the Rings Collection"),
            "c": (hobbitID, "The Hobbit Collection"),
            "d": (hobbitID, "The Hobbit Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(
            movies: movies, enrichmentFor: look, availableStockChannelIDs: [104])
        XCTAssertEqual(groupings.count, 1)
        XCTAssertEqual(groupings.first?.placement, .stock(channelID: 104))
        XCTAssertEqual(groupings.first?.movies.count, 4)
        XCTAssertEqual(groupings.first?.mergedFranchiseIDs, [ringsID, hobbitID].sorted())
    }

    // MARK: - Unmapped found franchise becomes its own channel

    func testUnmappedFranchiseIsItsOwnDynamicChannel() {
        let movies = [movie("a", "Cube"), movie("b", "Cube 2: Hypercube"), movie("c", "Cube Zero")]
        let look = lookup([
            "a": (12345, "Cube Collection"),
            "b": (12345, "Cube Collection"),
            "c": (12345, "Cube Collection")
        ])
        // Even with CH100 present, an unmapped franchise does not fold into it.
        let groupings = FranchiseChannelBuilder.build(
            movies: movies, enrichmentFor: look, availableStockChannelIDs: [100, 101, 102])
        XCTAssertEqual(groupings.count, 1)
        XCTAssertEqual(groupings.first?.name, "CUBE")
        XCTAssertEqual(groupings.first?.placement, .dynamic)
        XCTAssertFalse(groupings.first!.fromDictionary)
    }

    // MARK: - TV joins by name and by dictionary

    func testTVShowJoinsByNameAndByDictionary() {
        let movies = [movie("a", "Star Wars"), movie("b", "The Empire Strikes Back"), movie("c", "Return of the Jedi")]
        let look = lookup([
            "a": (10, "Star Wars Collection"),
            "b": (10, "Star Wars Collection"),
            "c": (10, "Star Wars Collection")
        ])
        let tv = [
            show("t1", "Star Wars: The Clone Wars"), // name-match on "star wars"
            show("t2", "The Mandalorian"),           // dictionary title, no name-match
            show("t3", "Breaking Bad")               // unrelated, must not join
        ]
        let groupings = FranchiseChannelBuilder.build(
            movies: movies, tvItems: tv, enrichmentFor: look, availableStockChannelIDs: [100])

        XCTAssertEqual(groupings.count, 1)
        let joined = Set(groupings.first?.tvItems.map(\.id) ?? [])
        XCTAssertTrue(joined.contains("t1"), "name-match should attach The Clone Wars")
        XCTAssertTrue(joined.contains("t2"), "dictionary title should attach The Mandalorian")
        XCTAssertFalse(joined.contains("t3"), "unrelated show must not attach")
    }

    // MARK: - Films outside any TMDB collection join a dictionary franchise by title

    // Transformers: Rise of the Beasts is belongs_to_collection: null on TMDB, so it
    // has no franchiseID. Its title carries the "transformers" token, so it joins.
    func testFilmOutsideCollectionJoinsDictionaryFranchiseByToken() {
        let movies = [
            movie("a", "Transformers"), movie("b", "Transformers: Revenge of the Fallen"),
            movie("c", "Transformers: Dark of the Moon"),
            movie("d", "Transformers: Rise of the Beasts") // no enrichment entry -> nil franchiseID
        ]
        let look = lookup([
            "a": (8650, "Transformers Collection"),
            "b": (8650, "Transformers Collection"),
            "c": (8650, "Transformers Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(movies: movies, enrichmentFor: look)
        let tf = groupings.first { $0.name == "TRANSFORMERS" }
        XCTAssertEqual(tf?.placement, .dynamic)
        XCTAssertEqual(tf?.movies.count, 4)
        XCTAssertTrue(tf?.movies.contains { $0.id == "d" } ?? false, "Rise of the Beasts should join by token")
        XCTAssertEqual(tf?.mergedFranchiseIDs, [8650], "a title join adds no collection id")
    }

    // Bumblebee is also null on TMDB and its title has no franchise word, so only the
    // explicit filmTitles entry can place it.
    func testFilmOutsideCollectionJoinsDictionaryFranchiseByExplicitTitle() {
        let movies = [
            movie("a", "Transformers"), movie("b", "Transformers: Revenge of the Fallen"),
            movie("c", "Transformers: Dark of the Moon"),
            movie("d", "Bumblebee (2018)") // Plex-style year suffix, no enrichment
        ]
        let look = lookup([
            "a": (8650, "Transformers Collection"),
            "b": (8650, "Transformers Collection"),
            "c": (8650, "Transformers Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(movies: movies, enrichmentFor: look)
        let tf = groupings.first { $0.name == "TRANSFORMERS" }
        XCTAssertEqual(tf?.movies.count, 4)
        XCTAssertTrue(tf?.movies.contains { $0.id == "d" } ?? false, "Bumblebee should join by explicit filmTitles")
    }

    // An auto-found franchise (no dictionary entry) is franchiseID-only. A film whose
    // title merely contains the franchise name must NOT be pulled in, otherwise a
    // common word in an auto-found name would over-match the whole library.
    func testAutoFoundFranchiseDoesNotJoinFilmsByTitle() {
        let movies = [
            movie("a", "Spy Kids"), movie("b", "Spy Kids 2"), movie("c", "Spy Kids 3"),
            movie("d", "Spy Kids: Armageddon") // no enrichment -> nil franchiseID
        ]
        let look = lookup([
            "a": (99999, "Spy Kids Collection"),
            "b": (99999, "Spy Kids Collection"),
            "c": (99999, "Spy Kids Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(movies: movies, enrichmentFor: look)
        let sk = groupings.first { $0.name == "SPY KIDS" }
        XCTAssertEqual(sk?.movies.count, 3, "title-only film must not join an auto-found franchise")
        XCTAssertFalse(sk?.movies.contains { $0.id == "d" } ?? true)
    }

    // A title listed explicitly under one franchise is not stolen by another
    // franchise's token, even when that token would otherwise match.
    func testExplicitFilmTitleBeatsAnotherFranchisesToken() {
        let defs = [
            FranchiseDefinition(canonicalName: "ALPHA", nameMatchTokens: ["shared"]),
            FranchiseDefinition(canonicalName: "BETA", filmTitles: ["Shared Title"])
        ]
        let movies = [movie("x", "Shared Title")]
        let match = FranchiseChannelBuilder.dictionaryMatch(forFilmTitle: movies[0].title, definitions: defs)
        XCTAssertEqual(match?.canonicalName, "BETA")
    }

    // MARK: - Check: the stock CH100 rule covers the anthology films on its own

    // Rogue One and Solo have belongs_to_collection: null on TMDB, so they never fold
    // onto CH100 via franchiseID. CH100 is a static channels.json channel, so the
    // question is whether its own titleContains rule already matches them. Drive the
    // real rule from the real channels.json through the real Swift filter, with an
    // EMPTY membership manifest, so a pass can only come from the rule itself.
    @MainActor
    func testStockStarWarsRuleMatchesTheAnthologyFilms() throws {
        let url = try XCTUnwrap(Bundle(for: AppState.self).url(forResource: "channels", withExtension: "json"))
        let config = try XCTUnwrap(ChannelConfigLoader.loadConfig(from: Data(contentsOf: url)))
        let ch100 = try XCTUnwrap(config.channels.first { $0.id == 100 })
        XCTAssertEqual(ch100.name, "STAR WARS")
        XCTAssertEqual(ch100.rules?.titleContains, ["Star Wars"], "rule changed; re-check this assumption")

        let titles = [
            "Rogue One: A Star Wars Story",
            "Solo: A Star Wars Story",
            "Rogue One: A Star Wars Story (2016)", // Plex TMDB agent appends the year
            "Spaceballs"                            // negative control
        ]
        let cached: [AppState.FilterCache] = titles.enumerated().map { i, title in
            let item = movie("sw\(i)", title)
            return AppState.FilterCache(
                item: item,
                titleLower: AppState.stripTrailingYearSuffix(title.lowercased()),
                episodeTitleLower: "",
                genresLowerSet: [],
                enrichment: nil,
                itemStudioLower: ""
            )
        }
        let pool = AppState.filterItems(
            cached, rules: ch100.rules, forChannelID: ch100.id, category: ch100.category,
            memberships: .empty, exclusiveRules: config.exclusiveRules)
        let passed = Set(pool.map(\.title))

        XCTAssertTrue(passed.contains("Rogue One: A Star Wars Story"))
        XCTAssertTrue(passed.contains("Solo: A Star Wars Story"))
        XCTAssertTrue(passed.contains("Rogue One: A Star Wars Story (2016)"))
        XCTAssertFalse(passed.contains("Spaceballs"), "control: the rule must not match everything")
    }

    // MARK: - Marvel stays studio-based

    func testMarvelStaysStudioBased() {
        // The Avengers Collection (86311) is a real Marvel collection, but Marvel is
        // studio-ruled in the dictionary (no collection ids), so these films must NOT
        // fold into CH101 — they fall through to their own dynamic channel instead.
        let movies = [movie("a", "The Avengers"), movie("b", "Age of Ultron"), movie("c", "Infinity War")]
        let look = lookup([
            "a": (86311, "The Avengers Collection"),
            "b": (86311, "The Avengers Collection"),
            "c": (86311, "The Avengers Collection")
        ])
        let groupings = FranchiseChannelBuilder.build(
            movies: movies, enrichmentFor: look, availableStockChannelIDs: [101])

        XCTAssertFalse(groupings.contains { $0.placement == .stock(channelID: 101) },
                       "franchiseID grouping must never claim the studio-ruled Marvel channel")
        let avengers = groupings.first { $0.name == "THE AVENGERS" }
        XCTAssertEqual(avengers?.placement, .dynamic)

        // And the dictionary entry itself documents the studio rule.
        let marvel = FranchiseDictionary.all.first { $0.canonicalName == "MARVEL" }
        XCTAssertEqual(marvel?.stockChannelID, 101)
        XCTAssertTrue(marvel?.studioRuled ?? false)
        XCTAssertTrue(marvel?.tmdbCollectionIDs.isEmpty ?? false)
    }

    // MARK: - Marvel TV joins CH101 by exact title

    func testMarvelShowsFoldIntoCH101ByExactTitle() {
        let tv = [
            show("l1", "Loki"), show("l2", "Loki (2021)"),
            show("w1", "What If...?"), show("w2", "What If\u{2026}?"), show("w3", "What If"),
            show("s1", "Agents of S.H.I.E.L.D."), show("s2", "Marvel's Agents of S.H.I.E.L.D."),
            show("s3", "Marvel\u{2019}s Agents of S.H.I.E.L.D"),
            show("h1", "She-Hulk: Attorney at Law"), show("h2", "She Hulk Attorney at Law"),
            show("e1", "Echo"),
            // Not Marvel: a token would have taken these, exact match must not.
            show("x1", "Echo Park"), show("x2", "Echoes"), show("x3", "Loki and Friends"),
            show("x4", "What If We Were Kings")
        ]
        let groupings = FranchiseChannelBuilder.build(
            movies: [], tvItems: tv, enrichmentFor: { _ in nil }, availableStockChannelIDs: [101])

        let marvel = groupings.first { $0.placement == .stock(channelID: 101) }
        XCTAssertEqual(marvel?.name, "MARVEL")
        XCTAssertEqual(marvel?.movies.count, 0)
        XCTAssertEqual(Set(marvel?.tvItems.map(\.id) ?? []),
                       ["l1", "l2", "w1", "w2", "w3", "s1", "s2", "s3", "h1", "h2", "e1"])
    }

    func testMarvelFilmsNeverJoinByTitle() {
        // "Echo" and "Loki" are on MARVEL's TV list; a film with that title stays out.
        // CH101's films come only from its studio rule.
        let movies = [movie("f1", "Echo"), movie("f2", "Loki"), movie("f3", "Daredevil")]
        let groupings = FranchiseChannelBuilder.build(
            movies: movies, enrichmentFor: { _ in nil }, availableStockChannelIDs: [101])
        XCTAssertTrue(groupings.isEmpty)
        XCTAssertNil(FranchiseChannelBuilder.dictionaryMatch(forFilmTitle: "Echo"))
    }

    func testMarvelShowsWithoutCH101BuildNothing() {
        // TV alone never makes a dynamic channel, so with CH101 absent nothing is built.
        let groupings = FranchiseChannelBuilder.build(
            movies: [], tvItems: [show("l1", "Loki"), show("l2", "Hawkeye")],
            enrichmentFor: { _ in nil }, availableStockChannelIDs: [])
        XCTAssertTrue(groupings.isEmpty)
    }

    func testExplicitTitleKeyIgnoresCaseAndPunctuationOnly() {
        let key = FranchiseChannelBuilder.explicitTitleKey
        XCTAssertEqual(key("What If...?"), "what if")
        XCTAssertEqual(key("Ms. Marvel"), "ms marvel")
        XCTAssertEqual(key("Agents of S.H.I.E.L.D. (2013)"), "agents of s h i e l d")
        XCTAssertEqual(key("Marvel's Daredevil"), key("Marvel\u{2019}s Daredevil"))
        XCTAssertNotEqual(key("Echo"), key("Echo Park"))
    }

    // MARK: - Server-collection fold helper

    func testServerCollectionMapsToStockChannel() {
        let items = [movie("a", "Harry Potter 1"), movie("b", "Harry Potter 2"), movie("c", "Harry Potter 3")]
        let look = lookup([
            "a": (1241, "Harry Potter Collection"),
            "b": (1241, "Harry Potter Collection"),
            "c": (1241, "Harry Potter Collection")
        ])
        let stock = FranchiseChannelBuilder.stockChannel(
            forCollectionItems: items, enrichmentFor: look, availableStockChannelIDs: [102])
        XCTAssertEqual(stock, 102)

        // Unmapped collection maps to nothing.
        let other = lookup([
            "a": (55555, "Whatever Collection"),
            "b": (55555, "Whatever Collection"),
            "c": (55555, "Whatever Collection")
        ])
        XCTAssertNil(FranchiseChannelBuilder.stockChannel(
            forCollectionItems: items, enrichmentFor: other, availableStockChannelIDs: [102]))
    }

    // MARK: - Dictionary sanity

    func testDictionaryCoversRequiredStockChannels() {
        let byChannel = Dictionary(uniqueKeysWithValues:
            FranchiseDictionary.all.compactMap { d in d.stockChannelID.map { ($0, d.canonicalName) } })
        XCTAssertEqual(byChannel[100], "STAR WARS")
        XCTAssertEqual(byChannel[101], "MARVEL")
        XCTAssertEqual(byChannel[102], "HARRY POTTER")
        XCTAssertEqual(byChannel[103], "JURASSIC PARK")
        XCTAssertEqual(byChannel[104], "LORD OF THE RINGS")
        XCTAssertEqual(byChannel[105], "MISSION IMPOSSIBLE")
        XCTAssertEqual(byChannel[106], "JASON BOURNE")
    }

    func testCleanFranchiseNameStripsCollectionSuffix() {
        XCTAssertEqual(FranchiseDictionary.cleanFranchiseName("John Wick Collection"), "John Wick")
        XCTAssertEqual(FranchiseDictionary.cleanFranchiseName("Star Wars collection"), "Star Wars")
        XCTAssertEqual(FranchiseDictionary.cleanFranchiseName("Alien"), "Alien")
    }
}
