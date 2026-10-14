import Foundation

/// Deezer track search + album lookup (free, no key, ~50 requests per 5 s per IP).
/// https://developers.deezer.com/api
///
/// Why a second source after MusicBrainz: measured 2026-10-07 on Chad's 1,131 music
/// videos, MusicBrainz left 87% without a genre (its tags are sparse). Deezer resolved
/// 47 of a random 60 and every match carried album genres; with the filename cleaner
/// in `MusicTitleParser` it recovered 10 of the 13 misses. Genres come from the
/// album, which is what Deezer tags; tracks and artists carry none.
actor DeezerService {

    struct TrackMatch: Sendable {
        let trackID: Int
        let albumID: Int
        let title: String
        let artist: String
        /// Deezer's own genre names, e.g. "Rap/Hip Hop", "Soul & Funk".
        let rawGenres: [String]
        /// Mapped into the vocabulary channels.json rules use.
        let genres: [String]
        let releaseYear: Int?
    }

    enum DeezerError: Error {
        case invalidURL
        case httpError(Int)
        case decodeFailed
    }

    private static let baseURL = "https://api.deezer.com"
    private static let userAgent = "Nostalgex/1.0.23 (https://www.nostalgex.app)"
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        return URLSession(configuration: config)
    }()

    private var lastRequestAt: Date = .distantPast

    /// Search with the artist first, then the bare song when that finds nothing (a wrong or
    /// mangled artist hint should not cost the whole lookup). One album fetch for genres.
    func resolve(song: String, artist: String?) async throws -> TrackMatch? {
        let song = song.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !song.isEmpty else { return nil }

        var queries: [String] = []
        if let artist, !artist.isEmpty { queries.append("\(artist) \(song)") }
        queries.append(song)

        for query in queries {
            let hits = try await search(query)
            guard let pick = Self.bestHit(hits, artistHint: artist) else { continue }
            let album = try await album(id: pick.albumID)
            return TrackMatch(
                trackID: pick.trackID,
                albumID: pick.albumID,
                title: pick.title,
                artist: pick.artist,
                rawGenres: album.genres,
                genres: Self.mapGenres(album.genres),
                releaseYear: album.releaseYear
            )
        }
        return nil
    }

    // MARK: - Search

    struct SearchHit: Sendable, Equatable {
        let trackID: Int
        let albumID: Int
        let title: String
        let artist: String
    }

    private func search(_ query: String) async throws -> [SearchHit] {
        guard var components = URLComponents(string: "\(Self.baseURL)/search") else { throw DeezerError.invalidURL }
        components.queryItems = [.init(name: "q", value: query), .init(name: "limit", value: "5")]
        guard let url = components.url else { throw DeezerError.invalidURL }
        let data = try await fetch(url: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["data"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let id = row["id"] as? Int,
                  let title = row["title"] as? String,
                  let artist = (row["artist"] as? [String: Any])?["name"] as? String,
                  let albumID = (row["album"] as? [String: Any])?["id"] as? Int else { return nil }
            return SearchHit(trackID: id, albumID: albumID, title: title, artist: artist)
        }
    }

    /// Deezer ranks by popularity, which is right most of the time. When we know the
    /// artist, prefer the first hit whose artist shares a word with the hint, so
    /// "Nelly ft. Akon - Body On Me" does not come back as whoever covered it most.
    static func bestHit(_ hits: [SearchHit], artistHint: String?) -> SearchHit? {
        guard let first = hits.first else { return nil }
        guard let hint = artistHint?.lowercased(), !hint.isEmpty else { return first }
        let hintWords = Set(hint.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 })
        guard !hintWords.isEmpty else { return first }
        return hits.first { hit in
            let words = Set(hit.artist.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            return !words.isDisjoint(with: hintWords)
        } ?? first
    }

    // MARK: - Album

    private struct AlbumInfo {
        let genres: [String]
        let releaseYear: Int?
    }

    private func album(id: Int) async throws -> AlbumInfo {
        guard let url = URL(string: "\(Self.baseURL)/album/\(id)") else { throw DeezerError.invalidURL }
        let data = try await fetch(url: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw DeezerError.decodeFailed }
        let genres = ((json["genres"] as? [String: Any])?["data"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        let year = (json["release_date"] as? String).flatMap { Int($0.prefix(4)) }
        return AlbumInfo(genres: genres, releaseYear: year)
    }

    // MARK: - HTTP

    private func fetch(url: URL) async throws -> Data {
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        if elapsed < 0.25 {
            try await Task.sleep(nanoseconds: UInt64((0.25 - elapsed) * 1_000_000_000))
        }
        lastRequestAt = Date()

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeezerError.decodeFailed }
        guard http.statusCode == 200 else { throw DeezerError.httpError(http.statusCode) }
        return data
    }

    // MARK: - Genre vocabulary

    /// Deezer's album genres → the names channels.json rules match on. Measured on the
    /// sample: Pop, Rock, Rap/Hip Hop, Alternative, Country, R&B, Dance, Metal covered
    /// 44 of 47 matches; "Films/Games" and "Kids" are deliberately unmapped.
    static func mapGenres(_ raw: [String]) -> [String] {
        var out: [String] = []
        func add(_ names: String...) {
            for g in names where !out.contains(where: { $0.caseInsensitiveCompare(g) == .orderedSame }) {
                out.append(g)
            }
        }
        for name in raw {
            let g = name.lowercased()
            switch g {
            case "pop", "international pop", "indie pop", "k-pop", "j-pop", "latin pop":
                add("Pop")
                if g == "indie pop" { add("Alternative") }
                if g == "latin pop" { add("Latin") }
            case "rock":                          add("Rock")
            case "hard rock":                     add("Hard Rock", "Rock")
            case "classic rock":                  add("Classic Rock", "Rock")
            case "indie rock", "indie rock/rock pop": add("Indie Rock", "Alternative", "Rock")
            case "alternative":                   add("Alternative")
            case "punk":                          add("Punk", "Rock", "Alternative")
            case "metal":                         add("Metal", "Hard Rock", "Rock")
            case "rap/hip hop":                   add("Hip-Hop", "Hip Hop", "Rap")
            case "r&b":                           add("R&B")
            case "soul & funk":                   add("Soul", "Funk")
            case "disco":                         add("Disco", "Funk")
            case "dance", "dancefloor":           add("Dance", "Electronic")
            case "electro", "dubstep", "chill out/trip-hop/lounge", "electro pop/electro rock":
                add("Electronic", "Dance")
                if g == "electro pop/electro rock" { add("Pop") }
            case "techno/house":                  add("House", "Techno", "Electronic", "Dance")
            case "country":                       add("Country")
            case "latin music", "brazilian music": add("Latin")
            case "reggaeton":                     add("Reggaeton", "Latin")
            case "reggae":                        add("Reggae")
            case "folk":                          add("Acoustic", "Folk")
            case "jazz":                          add("Jazz")
            case "blues":                         add("Blues")
            default:                              break
            }
        }
        return out
    }
}
