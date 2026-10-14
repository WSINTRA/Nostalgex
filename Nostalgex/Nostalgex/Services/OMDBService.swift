import Foundation

/// Raw OMDb fetch result — transient, gets merged into MediaEnrichment by the orchestrator.
struct OMDBResult {
    let imdbID: String
    let imdbRating: Double?
    let imdbVotes: Int?
    let rottenTomatoesScore: Int?
    let metacriticScore: Int?
    let awards: String?
}

/// OMDb API wrapper. Mirrors TMDBService: direct OMDb when a key is present (dev
/// builds), otherwise the site relay (`api/tmdb.js`, `path=omdb/{imdbID}`), which holds
/// the key server-side and caches answers at the edge for a week.
struct OMDBService {
    let apiKey: String
    let proxyURL: String

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

    private static let baseURL = "https://www.omdbapi.com/"

    var usesProxy: Bool { apiKey.isEmpty && !proxyURL.isEmpty }
    var isConfigured: Bool { !apiKey.isEmpty || !proxyURL.isEmpty }

    /// The relay accepts `tt` plus 7 to 9 digits and nothing else; the direct path uses
    /// the same check so an odd guid never becomes a wasted request.
    static func isValidIMDbID(_ id: String) -> Bool {
        id.range(of: #"^tt\d{7,9}$"#, options: .regularExpression) != nil
    }

    // MARK: - Public API

    func fetch(imdbID: String) async throws -> OMDBResult {
        guard isConfigured else { throw OMDBError.notConfigured }
        guard let request = request(imdbID: imdbID) else { throw OMDBError.invalidURL }

        let (data, response) = try await Self.session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OMDBError.invalidResponse
        }

        // The relay maps OMDb's "Request limit reached!" (a 401) to 429. Direct OMDb
        // still sends the 401, which parseResponse recognises by its message.
        if http.statusCode == 429 {
            throw OMDBError.rateLimited
        }

        guard http.statusCode == 200 else {
            if Self.isLimitMessage(data) { throw OMDBError.rateLimited }
            throw OMDBError.httpError(http.statusCode)
        }

        return try parseResponse(data: data, imdbID: imdbID)
    }

    // MARK: - Request building

    /// Proxy: `{proxyURL}?path=omdb/{imdbID}` with the client header and no key in the
    /// URL. Direct: OMDb's own URL with the key.
    func request(imdbID: String) -> URLRequest? {
        guard Self.isValidIMDbID(imdbID) else { return nil }
        let urlString: String
        if usesProxy {
            urlString = "\(proxyURL)?path=omdb/\(imdbID)"
        } else {
            urlString = "\(Self.baseURL)?i=\(imdbID)&apikey=\(apiKey)&tomatoes=true"
        }
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if usesProxy {
            request.setValue(TMDBService.clientHeaderValue, forHTTPHeaderField: TMDBService.clientHeaderField)
        }
        return request
    }

    private static func isLimitMessage(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = json["Error"] as? String else { return false }
        return err.lowercased().contains("limit reached")
    }

    // MARK: - Response parsing

    func parseResponse(data: Data, imdbID: String) throws -> OMDBResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OMDBError.invalidResponse
        }

        // OMDb signals errors via { "Response": "False", "Error": "..." }
        if let response = json["Response"] as? String, response == "False" {
            let err = (json["Error"] as? String) ?? ""
            if err.lowercased().contains("limit") || err.lowercased().contains("reached") {
                throw OMDBError.rateLimited
            }
            if err.lowercased().contains("not found") || err.lowercased().contains("incorrect imdb") {
                throw OMDBError.notFound
            }
            throw OMDBError.apiError(err)
        }

        let imdbRating = parseDouble(json["imdbRating"])
        let imdbVotes = parseVotes(json["imdbVotes"])
        let rt = extractRottenTomatoesScore(from: json)
        let metacritic = parseInt(json["Metascore"])
        let awards = (json["Awards"] as? String).flatMap { $0 == "N/A" ? nil : $0 }

        return OMDBResult(
            imdbID: imdbID,
            imdbRating: imdbRating,
            imdbVotes: imdbVotes,
            rottenTomatoesScore: rt,
            metacriticScore: metacritic,
            awards: awards
        )
    }

    private func parseDouble(_ any: Any?) -> Double? {
        guard let s = any as? String, s != "N/A" else { return nil }
        return Double(s)
    }

    private func parseInt(_ any: Any?) -> Int? {
        guard let s = any as? String, s != "N/A" else { return nil }
        return Int(s)
    }

    /// Parses strings like "1,234,567" → 1234567, or "N/A" → nil.
    private func parseVotes(_ any: Any?) -> Int? {
        guard let s = any as? String, s != "N/A" else { return nil }
        return Int(s.replacingOccurrences(of: ",", with: ""))
    }

    /// Finds the Rotten Tomatoes entry in the `Ratings` array and strips the `%`.
    private func extractRottenTomatoesScore(from json: [String: Any]) -> Int? {
        guard let ratings = json["Ratings"] as? [[String: Any]] else { return nil }
        for rating in ratings {
            if let source = rating["Source"] as? String, source == "Rotten Tomatoes",
               let value = rating["Value"] as? String {
                let trimmed = value.replacingOccurrences(of: "%", with: "")
                return Int(trimmed)
            }
        }
        return nil
    }

    // MARK: - Errors

    enum OMDBError: Error {
        case notConfigured
        case invalidURL
        case invalidResponse
        case rateLimited       // daily quota exhausted
        case notFound          // IMDb ID not in OMDb
        case httpError(Int)
        case apiError(String)
    }
}
