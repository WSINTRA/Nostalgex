import Foundation

struct TMDBService {
    let apiKey: String
    let proxyURL: String

    /// Direct TMDB when a key is present (dev builds); otherwise the site proxy, which
    /// holds the key server-side. Pass an empty `proxyURL` to turn the proxy off.
    init(apiKey: String, proxyURL: String = TMDBConfig.tmdbProxyURL) {
        self.apiKey = apiKey
        self.proxyURL = proxyURL
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    private static let baseURL = "https://api.themoviedb.org/3"

    /// The proxy drops requests without this header. A cheap filter, not security.
    static let clientHeaderField = "X-Nostalgex-Client"
    static let clientHeaderValue = "tvos"

    var usesProxy: Bool { apiKey.isEmpty && !proxyURL.isEmpty }

    // MARK: - Public API

    func fetchEnrichment(tmdbID: String, imdbID: String?, mediaType: String) async throws -> MediaEnrichment {
        guard let request = enrichmentRequest(tmdbID: tmdbID, mediaType: mediaType) else {
            throw TMDBError.invalidURL
        }

        let (data, response) = try await Self.session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TMDBError.invalidResponse
        }

        if http.statusCode == 429 {
            throw TMDBError.rateLimited
        }

        guard http.statusCode == 200 else {
            throw TMDBError.httpError(http.statusCode)
        }

        return try parseResponse(data: data, tmdbID: tmdbID, imdbID: imdbID, mediaType: mediaType)
    }

    // MARK: - Request building

    /// Proxy: `{proxyURL}?path=movie/{id}` with the client header and no key in the URL.
    /// The proxy adds `append_to_response=keywords` itself, so both routes return the
    /// same TMDB document and `parseResponse` does not care which one answered.
    /// Direct: TMDB's own URL with the key, as before.
    func enrichmentRequest(tmdbID: String, mediaType: String) -> URLRequest? {
        let kind = mediaType == "tv" ? "tv" : "movie"
        let urlString: String
        if usesProxy {
            urlString = "\(proxyURL)?path=\(kind)/\(tmdbID)"
        } else {
            urlString = "\(Self.baseURL)/\(kind)/\(tmdbID)?api_key=\(apiKey)&append_to_response=keywords"
        }

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if usesProxy {
            request.setValue(Self.clientHeaderValue, forHTTPHeaderField: Self.clientHeaderField)
        }
        return request
    }

    // MARK: - Response parsing

    func parseResponse(data: Data, tmdbID: String, imdbID: String?, mediaType: String) throws -> MediaEnrichment {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let keywords = extractKeywords(from: json, mediaType: mediaType)
        let networks = extractNetworks(from: json)
        let productionCompanies = extractProductionCompanies(from: json)
        let genres = extractGenres(from: json)
        let (franchiseID, franchiseName) = extractFranchise(from: json)

        // A movie document carries `imdb_id`. It stands in when the server had no IMDb
        // guid, so OMDb can still be asked about the title.
        let docIMDbID = (json["imdb_id"] as? String).flatMap { OMDBService.isValidIMDbID($0) ? $0 : nil }

        return MediaEnrichment(
            tmdbID: tmdbID,
            imdbID: imdbID ?? docIMDbID,
            mediaType: mediaType,
            keywords: keywords,
            networks: networks,
            productionCompanies: productionCompanies,
            tmdbGenres: genres,
            imdbRating: nil,
            imdbVotes: nil,
            rottenTomatoesScore: nil,
            metacriticScore: nil,
            awards: nil,
            franchiseID: franchiseID,
            franchiseName: franchiseName,
            fetchedAt: Date()
        )
    }

    /// TMDB movie responses carry `belongs_to_collection` as an object {id, name, ...}
    /// or null. TV responses have no such field, so this returns (nil, nil) for them.
    private func extractFranchise(from json: [String: Any]) -> (Int?, String?) {
        guard let collection = json["belongs_to_collection"] as? [String: Any] else {
            return (nil, nil)
        }
        let id = collection["id"] as? Int
        let name = collection["name"] as? String
        return (id, name)
    }

    private func extractKeywords(from json: [String: Any], mediaType: String) -> [String] {
        guard let keywordsObj = json["keywords"] as? [String: Any] else { return [] }
        // Movies: keywords.keywords[].name
        // TV: keywords.results[].name
        let key = mediaType == "tv" ? "results" : "keywords"
        guard let list = keywordsObj[key] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["name"] as? String }
    }

    private func extractNetworks(from json: [String: Any]) -> [String] {
        guard let list = json["networks"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["name"] as? String }
    }

    private func extractProductionCompanies(from json: [String: Any]) -> [String] {
        guard let list = json["production_companies"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["name"] as? String }
    }

    private func extractGenres(from json: [String: Any]) -> [String] {
        guard let list = json["genres"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["name"] as? String }
    }

    // MARK: - Errors

    enum TMDBError: Error {
        case invalidURL
        case invalidResponse
        case rateLimited
        case httpError(Int)
    }
}
