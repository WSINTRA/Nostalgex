import Foundation

/// One line a tester can read off the screen and send back.
///
/// A Jellyfin user reported 349 movies and 2,252 episodes on his server producing a
/// single channel. Ruling that out took days, because nothing in the app ever said how
/// much of his library it actually held — and no rules failure explains it. Stripping
/// every metadata field from a library that size still builds eleven channels, so a
/// lineup of one means the items never arrived. That is a different bug in a different
/// place, and the count is what tells the two apart in one screenshot.
enum LibraryDiagnostics {

    static func summary(_ items: [PlexMediaItem]) -> String {
        guard !items.isEmpty else { return "No titles loaded — the scan came back empty." }
        let movies = items.filter { $0.type == .movie }.count
        let episodes = items.filter { $0.type == .episode }.count
        let shows = Set(items.filter { $0.type == .episode }.map(\.title)).count
        let tmdb = items.filter { $0.tmdbID != nil }.count
        let genres = items.filter { !$0.genres.isEmpty }.count

        var parts = ["\(fmt(items.count)) titles"]
        if movies > 0 { parts.append("\(fmt(movies)) movies") }
        if episodes > 0 { parts.append("\(fmt(episodes)) episodes from \(fmt(shows)) shows") }
        parts.append("\(pct(genres, items.count))% with genres")
        parts.append("\(pct(tmdb, items.count))% matched to TMDB")
        return parts.joined(separator: " · ")
    }

    /// Percentages read better than raw counts for the metadata coverage, and 0% is the
    /// signal worth spotting — it means the server has the files but never scraped them.
    static func pct(_ n: Int, _ total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(n) / Double(total) * 100).rounded())
    }

    static func fmt(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
