import XCTest
@testable import Nostalgex

final class CollectionClassifierTests: XCTestCase {

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

    // Generated list/overlay collections must land in Custom, never Franchises/Actors.
    func testGeneratedListCollectionsAreCustom() {
        let names = [
            "Anilist Popular", "IMDb Popular", "TMDb Popular", "Plex Popular",
            "MyAnimeList Favorited", "MyAnimeList Top Rated", "Anilist Top Rated",
            "Trakt Trending", "Letterboxd Top 250", "Recently Added"
        ]
        for name in names {
            XCTAssertEqual(CollectionClassifier.classify(title: name, items: []), .custom,
                           "\(name) should be Custom")
        }
    }

    // NOTABLE STARS is gone: actor and director collections are OTHER COLLECTIONS now.
    func testPersonNamesAreCustom() {
        XCTAssertEqual(CollectionClassifier.classify(title: "Tom Hanks", items: []), .custom)
        XCTAssertEqual(CollectionClassifier.classify(title: "Christopher Nolan", items: []), .custom)
    }

    // Known + repeating-name franchises still classify as Franchises (guard didn't over-catch).
    func testFranchisesStillDetected() {
        XCTAssertEqual(CollectionClassifier.classify(title: "James Bond Collection", items: []), .franchises)
        let topGun = [item("Top Gun"), item("Top Gun: Maverick"), item("Top Gun II")]
        XCTAssertEqual(CollectionClassifier.classify(title: "Top Gun Collection", items: topGun), .franchises)
    }

    // A franchise whose name reads like a person ("John Wick", "Hunger Games") and whose
    // films don't all repeat a word used to land in the old NOTABLE STARS category. Seen on
    // a real library, where the third John Wick film is titled just "Parabellum".
    func testFranchiseNamedLikeAPersonIsAFranchise() {
        let wick = [item("John Wick"), item("John Wick: Chapter 2"), item("Parabellum")]
        XCTAssertEqual(CollectionClassifier.classify(title: "John Wick", items: wick), .franchises)
        let hunger = [item("The Hunger Games"), item("Catching Fire"), item("The Hunger Games: Mockingjay - Part 1")]
        XCTAssertEqual(CollectionClassifier.classify(title: "Hunger Games", items: hunger), .franchises)
    }

    // A person's name rarely appears in their films' titles, and once is not enough, so a
    // person collection never reads as a franchise. It lands in OTHER COLLECTIONS.
    func testPersonCollectionsAreNotFranchises() {
        let hanks = [item("Big"), item("Cast Away"), item("Forrest Gump")]
        XCTAssertEqual(CollectionClassifier.classify(title: "Tom Hanks", items: hanks), .custom)
        let jackson = [item("Michael Jackson's This Is It"), item("Thriller"), item("Moonwalker")]
        XCTAssertEqual(CollectionClassifier.classify(title: "Michael Jackson Collection", items: jackson), .custom)
    }

    // MARK: - Enriched franchiseID truth (Phase 1)

    private func enrichment(franchiseID: Int?) -> MediaEnrichment {
        MediaEnrichment(
            tmdbID: UUID().uuidString, imdbID: nil, mediaType: "movie",
            keywords: [], networks: [], productionCompanies: [], tmdbGenres: [],
            imdbRating: nil, imdbVotes: nil, rottenTomatoesScore: nil, metacriticScore: nil,
            awards: nil, franchiseID: franchiseID, franchiseName: nil, fetchedAt: Date()
        )
    }

    // When 2+ items share a TMDB franchiseID, it is a franchise regardless of the name,
    // and regardless of what the string heuristics would have guessed. "Movie Night"
    // would otherwise be Custom.
    func testSharedFranchiseIDForcesFranchise() {
        // Distinct one-word titles so the string heuristics find no repeating name or
        // person name: without enrichment this is Custom, and the franchiseID is the
        // only thing that reveals it is a franchise.
        let films = [item("Alpha"), item("Bravo"), item("Charlie")]
        let fids: [String: Int] = ["Alpha": 777, "Bravo": 777, "Charlie": 777]
        let look: (PlexMediaItem) -> MediaEnrichment? = { [weak self] in self?.enrichment(franchiseID: fids[$0.id]) }
        XCTAssertEqual(CollectionClassifier.classify(title: "Movie Night", items: films, enrichmentFor: look), .franchises)
        // Without the enrichment lookup, the string heuristics run and it stays Custom.
        XCTAssertEqual(CollectionClassifier.classify(title: "Movie Night", items: films), .custom)
    }

    // A generated list ("IMDb Popular") stays Custom even if two of its films happen to
    // share a collection — the generated-list guard runs before the franchiseID signal.
    func testGeneratedListBeatsFranchiseID() {
        let films = [item("Batman Begins"), item("The Dark Knight")]
        let fids: [String: Int] = ["Batman Begins": 263, "The Dark Knight": 263]
        let look: (PlexMediaItem) -> MediaEnrichment? = { [weak self] in self?.enrichment(franchiseID: fids[$0.id]) }
        XCTAssertEqual(CollectionClassifier.classify(title: "IMDb Popular", items: films, enrichmentFor: look), .custom)
    }

    // A single enriched film is not a franchise (a collection of one is not a series).
    func testSingleFranchiseIDItemIsNotEnoughForFranchise() {
        let films = [item("Solo Outing"), item("Different Movie")]
        let fids: [String: Int] = ["Solo Outing": 500] // only one has a franchiseID
        let look: (PlexMediaItem) -> MediaEnrichment? = { [weak self] in self?.enrichment(franchiseID: fids[$0.id]) }
        // Falls through to heuristics -> no franchise signal -> Custom.
        XCTAssertEqual(CollectionClassifier.classify(title: "Random Set", items: films, enrichmentFor: look), .custom)
    }
}
