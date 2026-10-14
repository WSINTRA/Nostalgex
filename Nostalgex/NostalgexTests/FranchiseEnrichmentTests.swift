import XCTest
@testable import Nostalgex

/// Phase 0 of the franchise bundle: the enrichment record gains franchise_id /
/// franchise_name, parsed from TMDB's `belongs_to_collection`. These tests lock in
/// (a) back-compat decoding of rows cached before the migration, and
/// (b) that a movie response populates the new fields.
final class FranchiseEnrichmentTests: XCTestCase {

    // Matches SupabaseService.fetchEnrichments date handling.
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: str) { return date }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) { return date }
            return Date()
        }
        return decoder
    }

    // MARK: - Back-compat: a row WITHOUT the new columns still decodes

    func testDecodesRowWithoutFranchiseColumns() throws {
        // A media_enrichments row as it looked before the franchise migration:
        // no franchise_id / franchise_name keys at all.
        let json = """
        {
            "tmdb_id": "603",
            "imdb_id": "tt0133093",
            "media_type": "movie",
            "keywords": ["dystopia", "artificial intelligence"],
            "networks": [],
            "production_companies": ["Warner Bros. Pictures"],
            "tmdb_genres": ["Action", "Science Fiction"],
            "imdb_rating": 8.7,
            "imdb_votes": 2000000,
            "rt_score": 88,
            "metacritic_score": 73,
            "awards": "Won 4 Oscars.",
            "fetched_at": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let enrichment = try makeDecoder().decode(MediaEnrichment.self, from: json)

        // Existing fields still land.
        XCTAssertEqual(enrichment.tmdbID, "603")
        XCTAssertEqual(enrichment.keywords, ["dystopia", "artificial intelligence"])
        XCTAssertEqual(enrichment.imdbRating, 8.7)
        // New fields default to nil when the columns are absent.
        XCTAssertNil(enrichment.franchiseID)
        XCTAssertNil(enrichment.franchiseName)
    }

    // A row WITH the new columns populated decodes them too.
    func testDecodesRowWithFranchiseColumns() throws {
        let json = """
        {
            "tmdb_id": "245891",
            "media_type": "movie",
            "keywords": [],
            "networks": [],
            "production_companies": [],
            "tmdb_genres": [],
            "franchise_id": 404609,
            "franchise_name": "John Wick Collection",
            "fetched_at": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let enrichment = try makeDecoder().decode(MediaEnrichment.self, from: json)
        XCTAssertEqual(enrichment.franchiseID, 404609)
        XCTAssertEqual(enrichment.franchiseName, "John Wick Collection")
    }

    // MARK: - Parse: a movie response with belongs_to_collection populates the fields

    func testParseMoviePopulatesFranchise() throws {
        // Shape of the base /movie/{id} response (belongs_to_collection is an object).
        let movieJSON = """
        {
            "id": 245891,
            "belongs_to_collection": {
                "id": 404609,
                "name": "John Wick Collection",
                "poster_path": "/x.jpg",
                "backdrop_path": "/y.jpg"
            },
            "genres": [{"id": 28, "name": "Action"}, {"id": 53, "name": "Thriller"}],
            "production_companies": [{"id": 1, "name": "Thunder Road"}],
            "keywords": {"keywords": [{"id": 1, "name": "hitman"}]}
        }
        """.data(using: .utf8)!

        let service = TMDBService(apiKey: "test")
        let enrichment = try service.parseResponse(
            data: movieJSON, tmdbID: "245891", imdbID: nil, mediaType: "movie"
        )

        XCTAssertEqual(enrichment.franchiseID, 404609)
        XCTAssertEqual(enrichment.franchiseName, "John Wick Collection")
        // Sanity: existing parse still works alongside the new field.
        XCTAssertEqual(enrichment.tmdbGenres, ["Action", "Thriller"])
        XCTAssertEqual(enrichment.keywords, ["hitman"])
    }

    // A movie with belongs_to_collection == null leaves the fields nil.
    func testParseMovieWithoutCollectionLeavesFranchiseNil() throws {
        let movieJSON = """
        {
            "id": 999,
            "belongs_to_collection": null,
            "genres": [{"id": 18, "name": "Drama"}],
            "keywords": {"keywords": []}
        }
        """.data(using: .utf8)!

        let service = TMDBService(apiKey: "test")
        let enrichment = try service.parseResponse(
            data: movieJSON, tmdbID: "999", imdbID: nil, mediaType: "movie"
        )
        XCTAssertNil(enrichment.franchiseID)
        XCTAssertNil(enrichment.franchiseName)
    }

    // A TV response has no belongs_to_collection field; fields stay nil.
    func testParseTVLeavesFranchiseNil() throws {
        let tvJSON = """
        {
            "id": 1399,
            "genres": [{"id": 18, "name": "Drama"}],
            "networks": [{"id": 49, "name": "HBO"}],
            "keywords": {"results": [{"id": 1, "name": "dragon"}]}
        }
        """.data(using: .utf8)!

        let service = TMDBService(apiKey: "test")
        let enrichment = try service.parseResponse(
            data: tvJSON, tmdbID: "1399", imdbID: nil, mediaType: "tv"
        )
        XCTAssertNil(enrichment.franchiseID)
        XCTAssertNil(enrichment.franchiseName)
        XCTAssertEqual(enrichment.networks, ["HBO"])
    }
}
