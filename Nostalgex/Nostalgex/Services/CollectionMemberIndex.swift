import Foundation

/// Turns a server collection's child keys into the library items its channel airs.
///
/// A collection lists what the viewer put in it: films, whole shows, or both. A film
/// matches a library item by key. A show matches nothing by key, because the library
/// holds its episodes rather than the show; every episode carries its show's key
/// (`PlexMediaItem.showKey`), so a show expands to the episodes the library load already
/// fetched. No request beyond the one the scan already makes per collection.
///
/// The three servers hand back different child shapes, all measured:
/// - Plex: `/library/collections/{key}/children` lists the shows, whose keys equal the
///   episodes' `grandparentRatingKey`. A Plex collection lives in one library, so it is
///   films only or shows only (Plex refuses a film in a TV collection with a 400).
/// - Jellyfin 12: a BoxSet asked for `Movie,Series` with `Recursive=true` lists the
///   series ids, which equal the episodes' `SeriesId`.
/// - Emby 4.10: the same query lists the series' episodes instead, which match by key.
///
/// Pure, so it unit-tests without AppState. Mirrored by `indexLibrary` and
/// `resolveMembers` in scripts/nostalgex-collections.js.
struct CollectionMemberIndex {
    /// A collection needs this many playable items (films plus episodes) to become a
    /// channel. Was "3 movies"; a films-only collection is held to exactly that still.
    static let minimumItems = 3

    private var byKey: [String: PlexMediaItem] = [:]
    private var episodesByShow: [String: [PlexMediaItem]] = [:]

    /// `items`: one server's library items, keyed by their raw (server-local) key.
    init(items: [PlexMediaItem]) {
        for item in items {
            if byKey[item.ratingKey] == nil { byKey[item.ratingKey] = item }
            if item.type == .episode, let show = item.showKey {
                episodesByShow[show, default: []].append(item)
            }
        }
    }

    /// Library items for these child keys, in child order, each item once. A key that
    /// is a film or an episode adds that item; a key that is a show adds all its episodes.
    func resolve(_ childKeys: [String]) -> [PlexMediaItem] {
        var out: [PlexMediaItem] = []
        var seen = Set<String>()
        for key in childKeys {
            if let item = byKey[key] {
                if seen.insert(item.id).inserted { out.append(item) }
            } else if let episodes = episodesByShow[key] {
                for ep in episodes where seen.insert(ep.id).inserted { out.append(ep) }
            }
        }
        return out
    }

    /// Which show an episode belongs to. The key when the library load stamped one; the
    /// show title otherwise (items restored from a snapshot written before `showKey`).
    static func showIdentity(of item: PlexMediaItem) -> String {
        if let key = item.showKey { return "key:\(item.serverID ?? ""):\(key)" }
        return "title:\(item.serverID ?? ""):\(item.title)"
    }
}

extension Array where Element == PlexMediaItem {
    /// Films in a collection's members.
    var collectionMovieCount: Int { reduce(0) { $0 + ($1.type == .movie ? 1 : 0) } }

    /// Distinct shows among a collection's episodes.
    var collectionShowCount: Int {
        Set(lazy.filter { $0.type == .episode }.map(CollectionMemberIndex.showIdentity(of:))).count
    }

    /// Films plus the first episode of each show: the collection as the viewer sees it,
    /// one entry per title. Checks that should weigh a show once rather than once per
    /// episode (the duplicate-channel overlap) run on this.
    var collectionTitleRepresentatives: [PlexMediaItem] {
        var seenShows = Set<String>()
        return filter { item in
            guard item.type == .episode else { return true }
            return seenShows.insert(CollectionMemberIndex.showIdentity(of: item)).inserted
        }
    }
}
