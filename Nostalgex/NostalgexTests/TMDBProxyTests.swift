import XCTest
@testable import Nostalgex

/// The App Store build ships without a TMDB key. TMDBService then routes through the
/// site proxy (api/tmdb.js) with a client header and no key in the URL; a build with a
/// key keeps talking to TMDB directly. EnrichmentService runs when either route is
/// available but still insists on Supabase, and its skip log names what is missing.
final class TMDBProxyTests: XCTestCase {

    // MARK: - Request routing

    func testProxyRequestWhenKeyIsEmpty() throws {
        let service = TMDBService(apiKey: "")
        XCTAssertTrue(service.usesProxy)

        let request = try XCTUnwrap(service.enrichmentRequest(tmdbID: "603", mediaType: "movie"))
        XCTAssertEqual(request.url?.absoluteString, "https://www.nostalgex.app/api/tmdb?path=movie/603")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Nostalgex-Client"), "tvos")
        XCTAssertFalse(try XCTUnwrap(request.url?.absoluteString).contains("api_key"))
        XCTAssertFalse(try XCTUnwrap(request.url?.absoluteString).contains("themoviedb.org"))
    }

    func testProxyRequestForTV() throws {
        let service = TMDBService(apiKey: "")
        let request = try XCTUnwrap(service.enrichmentRequest(tmdbID: "1399", mediaType: "tv"))
        XCTAssertEqual(request.url?.absoluteString, "https://www.nostalgex.app/api/tmdb?path=tv/1399")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Nostalgex-Client"), "tvos")
    }

    func testDirectRequestWhenKeyIsPresent() throws {
        let service = TMDBService(apiKey: "abc123")
        XCTAssertFalse(service.usesProxy)

        let request = try XCTUnwrap(service.enrichmentRequest(tmdbID: "1399", mediaType: "tv"))
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.themoviedb.org/3/tv/1399?api_key=abc123&append_to_response=keywords"
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Nostalgex-Client"))
    }

    func testDirectRequestForMovie() throws {
        let service = TMDBService(apiKey: "abc123")
        let request = try XCTUnwrap(service.enrichmentRequest(tmdbID: "603", mediaType: "movie"))
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.themoviedb.org/3/movie/603?api_key=abc123&append_to_response=keywords"
        )
    }

    // A key wins over the proxy even when both are configured, so a dev build with
    // TMDB_API_KEY in the scheme never leans on the production function.
    func testKeyWinsOverProxy() throws {
        let service = TMDBService(apiKey: "abc123", proxyURL: "https://example.test/api/tmdb")
        XCTAssertFalse(service.usesProxy)
        let request = try XCTUnwrap(service.enrichmentRequest(tmdbID: "603", mediaType: "movie"))
        XCTAssertTrue(try XCTUnwrap(request.url?.absoluteString).hasPrefix("https://api.themoviedb.org/3/"))
    }

    func testNoKeyAndNoProxyFallsBackToDirect() {
        // Nothing to route through. EnrichmentService refuses this combination before
        // a request is built; the service itself just reports no proxy.
        let service = TMDBService(apiKey: "", proxyURL: "")
        XCTAssertFalse(service.usesProxy)
    }

    func testProxyURLConstant() {
        XCTAssertEqual(TMDBConfig.tmdbProxyURL, "https://www.nostalgex.app/api/tmdb")
    }

    // The proxy returns TMDB's document unchanged, so the parse that the direct path
    // uses applies as is. Franchise fields included.
    func testProxyDocumentParsesLikeDirect() throws {
        let movieJSON = """
        {
            "id": 603,
            "belongs_to_collection": {"id": 2344, "name": "The Matrix Collection"},
            "genres": [{"id": 28, "name": "Action"}],
            "production_companies": [{"id": 79, "name": "Village Roadshow Pictures"}],
            "keywords": {"keywords": [{"id": 310, "name": "artificial intelligence"}]}
        }
        """.data(using: .utf8)!

        let viaProxy = try TMDBService(apiKey: "")
            .parseResponse(data: movieJSON, tmdbID: "603", imdbID: nil, mediaType: "movie")
        let viaKey = try TMDBService(apiKey: "abc123")
            .parseResponse(data: movieJSON, tmdbID: "603", imdbID: nil, mediaType: "movie")

        XCTAssertEqual(viaProxy.franchiseID, 2344)
        XCTAssertEqual(viaProxy.franchiseName, "The Matrix Collection")
        XCTAssertEqual(viaProxy.keywords, ["artificial intelligence"])
        XCTAssertEqual(viaProxy.franchiseID, viaKey.franchiseID)
        XCTAssertEqual(viaProxy.keywords, viaKey.keywords)
        XCTAssertEqual(viaProxy.productionCompanies, viaKey.productionCompanies)
    }

    // MARK: - Enrichment gate

    func testProxyAloneSatisfiesTMDB() {
        let missing = EnrichmentService.missingConfiguration(
            tmdbAPIKey: "", tmdbProxyURL: TMDBConfig.tmdbProxyURL,
            supabaseURL: "https://x.supabase.co", supabaseAnonKey: "anon"
        )
        XCTAssertEqual(missing, [])
    }

    func testKeyAloneSatisfiesTMDB() {
        let missing = EnrichmentService.missingConfiguration(
            tmdbAPIKey: "abc123", tmdbProxyURL: "",
            supabaseURL: "https://x.supabase.co", supabaseAnonKey: "anon"
        )
        XCTAssertEqual(missing, [])
    }

    func testSupabaseStillRequiredWithProxy() {
        let missing = EnrichmentService.missingConfiguration(
            tmdbAPIKey: "", tmdbProxyURL: TMDBConfig.tmdbProxyURL,
            supabaseURL: "", supabaseAnonKey: ""
        )
        XCTAssertEqual(missing, ["supabase url", "anon key"])
    }

    func testAnonKeyAloneMissing() {
        let missing = EnrichmentService.missingConfiguration(
            tmdbAPIKey: "", tmdbProxyURL: TMDBConfig.tmdbProxyURL,
            supabaseURL: "https://x.supabase.co", supabaseAnonKey: ""
        )
        XCTAssertEqual(missing, ["anon key"])
    }

    func testNothingConfiguredNamesEveryPiece() {
        let missing = EnrichmentService.missingConfiguration(
            tmdbAPIKey: "", tmdbProxyURL: "", supabaseURL: "", supabaseAnonKey: ""
        )
        XCTAssertEqual(missing, ["tmdb proxy/key", "supabase url", "anon key"])
    }
}
