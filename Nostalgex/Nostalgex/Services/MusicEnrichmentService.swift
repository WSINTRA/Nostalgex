import Foundation
import Observation

/// Enriches music-video items via MusicBrainz when Plex metadata is thin.
@Observable
@MainActor
final class MusicEnrichmentService {

    private(set) var cache: [String: MusicVideoEnrichment] = [:]
    var isEnriching = false
    var progress: Double = 0
    var enrichedCount = 0
    var totalToEnrich = 0

    private let musicBrainz = MusicBrainzService()
    private let deezer = DeezerService()
    private let cacheFileName = "music_video_enrichments_v2.json"

    private let cacheDirectory: URL?

    init(cacheDirectory: URL? = nil) { self.cacheDirectory = cacheDirectory }

    // MARK: - Public API

    func enrichment(for item: PlexMediaItem) -> MusicVideoEnrichment? {
        cache[item.id]
    }

    /// Plex-only genres are often just "Music Video" — treat as thin metadata.
    static func plexGenresAreThin(_ genres: [String]) -> Bool {
        let useful = genres.filter { g in
            let l = g.lowercased()
            return !l.contains("music video") && l != "music" && l != "musical"
        }
        return useful.isEmpty
    }

    func loadDiskCache() {
        guard let url = cacheFileURL(),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: MusicVideoEnrichment].self, from: data) else { return }
        cache = decoded
        print("[MusicEnrichment] Loaded \(decoded.count) cached music-video rows")
    }

    func enrichMusicVideos(_ items: [PlexMediaItem]) async {
        loadDiskCache()

        let candidates = items.filter { ($0.librarySource ?? .movie) == .musicVideo }
        guard !candidates.isEmpty else { return }

        var work: [PlexMediaItem] = []
        var genrePass: [PlexMediaItem] = []
        for item in candidates {
            if let cached = cache[item.id], Self.isSettled(cached) { continue }
            if let cached = cache[item.id], Self.needsOnlyGenres(cached) { genrePass.append(item); continue }
            work.append(item)
        }

        // Rows MusicBrainz already named but never got a genre for: Deezer only, no
        // second MusicBrainz round trip (1/sec) for a thousand videos.
        if !genrePass.isEmpty {
            totalToEnrich = genrePass.count
            enrichedCount = 0
            progress = 0
            isEnriching = true
            print("[MusicEnrichment] Genre pass for \(genrePass.count) cached music videos via Deezer")
            var touched = false
            for (index, item) in genrePass.enumerated() {
                if let cached = cache[item.id] {
                    cache[item.id] = await withDeezerGenres(cached, item: item)
                    touched = true
                }
                enrichedCount = index + 1
                progress = Double(enrichedCount) / Double(totalToEnrich)
                if index % 5 == 4 { await Task.yield() }
            }
            if touched { saveDiskCache() }
        }

        guard !work.isEmpty else {
            print("[MusicEnrichment] All \(candidates.count) music videos already cached")
            totalToEnrich = 0
            enrichedCount = 0
            isEnriching = false
            progress = 1
            return
        }

        totalToEnrich = work.count
        enrichedCount = 0
        progress = 0
        isEnriching = true
        print("[MusicEnrichment] Resolving \(totalToEnrich) music videos via MusicBrainz (~1/sec), Deezer for genres")

        var updated = false
        for (index, item) in work.enumerated() {
            if let row = await resolve(item) {
                cache[item.id] = row
                updated = true
            }
            enrichedCount = index + 1
            progress = Double(enrichedCount) / Double(totalToEnrich)
            if index % 5 == 4 { await Task.yield() }
        }

        if updated { saveDiskCache() }

        let withArtist = cache.values.filter { ($0.artist ?? "").isEmpty == false }.count
        let withGenres = cache.values.filter(\.hasUsefulGenres).count
        print("[MusicEnrichment] Done — \(withArtist) with artist, \(withGenres)/\(cache.count) with mapped genres")
        isEnriching = false
        progress = 1
    }

    /// Re-apply disk cache to library + channels (e.g. after same-day snapshot restore).
    func applyCachedDisplayMetadata(allItems: inout [PlexMediaItem], allChannels: inout [Channel]) {
        loadDiskCache()
        allItems = itemsWithDisplayMetadata(allItems)
        allChannels = refreshChannelPools(allChannels, from: allItems)
    }

    // MARK: - Resolution

    /// Nothing left to ask anyone: it has genres, or Deezer was already consulted.
    static func isSettled(_ row: MusicVideoEnrichment, now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(row.fetchedAt) < 60 * 60 * 24 * 90 else { return false }
        if row.hasUsefulGenres { return true }
        return row.deezerCheckedAt != nil
    }

    /// Named (by MusicBrainz or the parser) but genreless and never shown to Deezer.
    static func needsOnlyGenres(_ row: MusicVideoEnrichment) -> Bool {
        !row.hasUsefulGenres && row.deezerCheckedAt == nil && (row.artist != nil || row.musicBrainzID != nil)
    }

    private func resolve(_ item: PlexMediaItem) async -> MusicVideoEnrichment? {
        let parsed = MusicTitleParser.parse(item.title)
        let songTitle = parsed.song
        let artistHint = item.artist ?? parsed.artist
        let year = item.year

        var row: MusicVideoEnrichment?
        do {
            if let match = try await musicBrainz.resolveRecording(title: songTitle, artist: artistHint, year: year) {
                row = MusicVideoEnrichment(
                    ratingKey: item.ratingKey,
                    recordingTitle: match.recordingTitle,
                    artist: match.artist ?? artistHint,
                    musicBrainzID: match.mbid,
                    genres: mergeGenres(plex: item.genres, resolved: match.genres),
                    releaseYear: match.releaseYear,
                    fetchedAt: Date()
                )
            }
        } catch {
            print("[MusicEnrichment] MusicBrainz failed \(item.title): \(error)")
        }

        if row == nil {
            row = MusicVideoEnrichment(
                ratingKey: item.ratingKey,
                recordingTitle: songTitle,
                artist: artistHint,
                musicBrainzID: nil,
                genres: item.genres,
                releaseYear: nil,
                fetchedAt: Date()
            )
        }
        guard var current = row else { return nil }
        if !current.hasUsefulGenres {
            current = await withDeezerGenres(current, item: item)
        }
        // A row with no name, no genre and no Deezer match is still worth keeping now:
        // its deezerCheckedAt stops the same dead lookup repeating every launch.
        return current
    }

    /// One Deezer round trip for a row that has a name but no genre. Fills genres, and
    /// the artist and year when the row had none. Always stamps `deezerCheckedAt`.
    private func withDeezerGenres(_ row: MusicVideoEnrichment, item: PlexMediaItem) async -> MusicVideoEnrichment {
        let parsed = MusicTitleParser.parse(item.title)
        let song = row.recordingTitle.isEmpty ? parsed.song : row.recordingTitle
        let artist = row.artist ?? parsed.artist
        var genres = row.genres
        var deezerID: Int? = row.deezerID
        var resolvedArtist = row.artist
        // Deezer's year is the album's (remasters, compilations): measured wrong by
        // years on 15 of 15. It never becomes releaseYear; MusicYear decides.
        let year = row.releaseYear
        do {
            if let match = try await deezer.resolve(song: song, artist: artist) {
                genres = mergeGenres(plex: genres, resolved: match.genres)
                deezerID = match.trackID
                if resolvedArtist == nil { resolvedArtist = match.artist }
            }
        } catch {
            print("[MusicEnrichment] Deezer failed \(item.title): \(error)")
        }
        var out = MusicVideoEnrichment(
            ratingKey: row.ratingKey,
            recordingTitle: row.recordingTitle,
            artist: resolvedArtist,
            musicBrainzID: row.musicBrainzID,
            genres: genres,
            releaseYear: year,
            fetchedAt: row.fetchedAt
        )
        out.deezerID = deezerID
        out.deezerCheckedAt = Date()
        return out
    }

    /// Apply cached MusicBrainz rows onto Plex items for UI and schedules.
    func itemsWithDisplayMetadata(_ items: [PlexMediaItem]) -> [PlexMediaItem] {
        items.map { item in
            guard item.isMusicVideo, let music = cache[item.id] else { return item.applyingTrustedMusicYear() }
            return item.applyingMusicEnrichment(music)
        }
    }

    /// Refresh channel pools so schedule entries show enriched titles/artists.
    func refreshChannelPools(_ channels: [Channel], from items: [PlexMediaItem]) -> [Channel] {
        let byKey = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return channels.map { ch in
            var copy = ch
            copy.itemPool = ch.itemPool.map { byKey[$0.id] ?? $0 }
            return copy
        }
    }

    private func mergeGenres(plex: [String], resolved: [String]) -> [String] {
        var out = plex
        for g in resolved {
            if !out.contains(where: { $0.caseInsensitiveCompare(g) == .orderedSame }) {
                out.append(g)
            }
        }
        return out
    }

    // MARK: - Persistence

    private func cacheFileURL() -> URL? {
        (cacheDirectory ?? LocalStore.rootDirectory)?.appendingPathComponent(cacheFileName)
    }

    private func saveDiskCache() {
        guard let url = cacheFileURL(),
              let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
