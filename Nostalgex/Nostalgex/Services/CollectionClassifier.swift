import Foundation

enum CollectionClassifier {

    /// - Parameter enrichmentFor: optional TMDB enrichment lookup. When provided and the
    ///   library is enriched, a shared `franchiseID` across the collection's films is the
    ///   authoritative franchise signal; the string heuristics below are the fallback for
    ///   un-enriched items. Defaulted to nil so existing callers and tests are unchanged.
    static func classify(title: String, items: [PlexMediaItem],
                         enrichmentFor: ((PlexMediaItem) -> MediaEnrichment?)? = nil) -> CollectionCategory {
        // Shows. Every episode carries its show's title, so the repeated-word and
        // name-in-titles rules below would call any collection of shows a franchise
        // (one show with 30 episodes is "30 titles sharing a word"). FRANCHISES is movie
        // series, so the films alone decide, exactly as they did when the scan kept only
        // films; a collection with no films is the viewer's own set.
        let films = items.filter { $0.type == .movie }
        if films.count < items.count {
            guard !films.isEmpty else { return .custom }
            return classify(title: title, items: films, enrichmentFor: enrichmentFor)
        }

        let cleaned = title
            .replacingOccurrences(of: " Collection", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "Collection", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "'s", with: "")
            .replacingOccurrences(of: "\u{2019}s", with: "")
            .trimmingCharacters(in: .whitespaces)
        let lower = cleaned.lowercased()

        // 0. Auto-generated list/overlay collections (e.g. "IMDb Popular", "Anilist Top
        //    Rated", "MyAnimeList Favorited"). These are not franchises, so they go
        //    straight to Custom. Checked before the franchiseID signal so a "Popular"
        //    list that happens to hold two films of one series still lands in Custom.
        if isGeneratedListCollection(lower) { return .custom }

        // 0.5 Enriched truth: if 2+ of the collection's items share a non-nil TMDB
        //    franchiseID (belongs_to_collection), it is a real franchise collection no
        //    matter how the name reads. This replaces the string guesswork below whenever
        //    the library is enriched; the heuristics remain the fallback for items that
        //    have no enrichment yet.
        if let enrichmentFor, sharesFranchiseID(items, enrichmentFor: enrichmentFor) {
            return .franchises
        }

        // 1. Known franchise names (catches tricky ones like James Bond)
        if isKnownFranchise(lower) { return .franchises }

        // 2. Franchise keywords in title (saga, trilogy, etc.)
        if hasFranchiseKeyword(lower) { return .franchises }

        // 3. Repeating name detection -- if 3+ items share a common title word/phrase, it's a franchise
        if items.count >= 3 && hasRepeatingNames(items) { return .franchises }

        // 4. The collection's own name in 2+ of its titles. Catches franchises that read
        //    like a person ("John Wick", "Hunger Games") when a sequel drops the name
        //    ("Parabellum", "Catching Fire") and step 3 misses. A person's name almost
        //    never appears in their films' titles more than once.
        if nameAppearsInTitles(lower, items: items) { return .franchises }

        // 5. Everything else, actor and director sets included. NOTABLE STARS used to
        //    sit here as its own category; those collections now belong with the rest
        //    of the user's own sets under OTHER COLLECTIONS.
        return .custom
    }

    /// True when 2+ items share the same non-nil TMDB franchiseID. Two films from one
    /// TMDB collection is a strong franchise signal; actor/director sets (Tom Hanks,
    /// Christopher Nolan) hold films from many different collections, so they never trip
    /// this. One film alone is not enough — a collection of one is not a franchise.
    private static func sharesFranchiseID(_ items: [PlexMediaItem],
                                          enrichmentFor: (PlexMediaItem) -> MediaEnrichment?) -> Bool {
        var counts: [Int: Int] = [:]
        for item in items {
            guard let fid = enrichmentFor(item)?.franchiseID else { continue }
            counts[fid, default: 0] += 1
            if counts[fid]! >= 2 { return true }
        }
        return false
    }

    private static func nameAppearsInTitles(_ lowerName: String, items: [PlexMediaItem]) -> Bool {
        guard lowerName.count >= 3 else { return false }
        return items.filter { $0.title.lowercased().contains(lowerName) }.count >= 2
    }

    // MARK: - Generated / list collections

    /// Source names (safe as substrings) for service-generated collections.
    private static let listSources: [String] = [
        "anilist", "myanimelist", "mal ", "imdb", "tmdb", "themoviedb",
        "letterboxd", "trakt", "tvdb", "rotten tomatoes", "metacritic"
    ]

    /// List/quality phrases that mark a generated collection rather than a franchise or
    /// actor set. Phrases (not bare ambiguous words like "top") so real titles such as
    /// "Top Gun" aren't caught.
    private static let listPhrases: [String] = [
        "popular", "trending", "top rated", "highest rated", "best rated",
        "most watched", "most popular", "recently added", "recently released",
        "newly added", "new releases", "favorited", "recommended", "watchlist",
        "top 250", "top 100", "top 50", "top 10"
    ]

    private static func isGeneratedListCollection(_ lower: String) -> Bool {
        if listSources.contains(where: { lower.contains($0) }) { return true }
        if listPhrases.contains(where: { lower.contains($0) }) { return true }
        return false
    }

    // MARK: - Known Franchises (for ones that are hard to detect by name repetition)

    private static let knownFranchises: [String] = [
        // Superheroes (titles vary a lot: Batman Begins, The Dark Knight, The Batman)
        "batman", "superman", "spider-man", "spiderman",
        "wolverine", "x-men", "deadpool", "venom",
        "wonder woman", "aquaman", "the flash",
        "iron man", "captain america", "thor", "ant-man",
        "black panther", "hulk", "avengers",
        "guardians of the galaxy",
        "fantastic four", "blade",
        "hellboy", "spawn", "the crow",
        "teenage mutant ninja turtles", "tmnt",

        // Spy / Action (different titles per film)
        "james bond", "007",
        "jack ryan", "jack reacher",
        "the equalizer",

        // Horror (different titles per film)
        "the conjuring", "conjuring", "annabelle",
        "final destination",
        "a nightmare on elm street", "elm street",
        "friday the 13th",
        "child's play", "chucky",
        "the exorcist", "the omen",
        "evil dead",

        // Comedy (different titles per film)
        "national lampoon",
        "monty python",
        "ocean", // Ocean's Eleven, Twelve, Thirteen
        "naked gun",
        "scary movie",
        "hot shots",

        // Misc (titles don't repeat cleanly)
        "planet of the apes",
        "the karate kid", "karate kid",
        "the chronicles of narnia", "narnia"
    ]

    private static func isKnownFranchise(_ title: String) -> Bool {
        knownFranchises.contains { title.contains($0) }
    }

    // MARK: - Franchise Keywords

    private static func hasFranchiseKeyword(_ title: String) -> Bool {
        let keywords = ["saga", "trilogy", "universe", "chronicles", "franchise", "cinematic"]
        return keywords.contains { title.contains($0) }
    }

    // MARK: - Repeating Name Detection

    /// Check if 3+ items in the collection share a significant common word or phrase
    /// e.g. "Fast and Furious", "2 Fast 2 Furious", "Fast Five" all contain "fast"
    /// e.g. "High School Musical", "High School Musical 2" share "high school musical"
    private static func hasRepeatingNames(_ items: [PlexMediaItem]) -> Bool {
        let titles = items.map { $0.title.lowercased() }

        // Strategy 1: Find longest common substring shared by 3+ titles
        // Start by checking if the collection name words appear across items
        // Build word frequency across all titles
        let stopWords: Set<String> = [
            "the", "a", "an", "of", "and", "in", "on", "to", "for", "is", "it",
            "at", "by", "or", "as", "no", "not", "but", "be", "was", "with", "from"
        ]

        // Extract meaningful words from each title
        let titleWords: [[String]] = titles.map { title in
            title.split(separator: " ")
                .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
                .filter { $0.count >= 3 && !stopWords.contains($0) }
        }

        // Count how many titles contain each word
        var wordHits: [String: Int] = [:]
        for words in titleWords {
            let unique = Set(words)
            for word in unique {
                wordHits[word, default: 0] += 1
            }
        }

        // If any meaningful word appears in 3+ titles (or 60%+ of titles), it's a franchise
        let threshold = max(3, items.count * 6 / 10)
        if wordHits.values.contains(where: { $0 >= threshold }) {
            return true
        }

        // Strategy 2: Check for shared multi-word prefix
        // "High School Musical" and "High School Musical 2" share "high school musical"
        if let prefix = longestCommonPrefix(titles), prefix.count >= 4 {
            let matchCount = titles.filter { $0.hasPrefix(prefix) }.count
            if matchCount >= threshold { return true }
        }

        return false
    }

    // MARK: - Helpers

    private static func longestCommonPrefix(_ strings: [String]) -> String? {
        guard let first = strings.first else { return nil }
        var prefix = first
        for s in strings.dropFirst() {
            while !s.hasPrefix(prefix) && !prefix.isEmpty {
                prefix = String(prefix.dropLast())
            }
        }
        let trimmed = prefix.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        return trimmed.isEmpty ? nil : trimmed
    }
}
