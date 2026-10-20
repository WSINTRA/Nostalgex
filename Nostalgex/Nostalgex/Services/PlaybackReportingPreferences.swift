import Foundation

/// Independent, opt-in choices. The old Report Playback switch meant both.
struct PlaybackReportingPreferences: Equatable, Sendable {
    static let legacyKey = "nostalgex_sync_plex_activity"
    static let nowPlayingKey = "nostalgex_show_now_playing_v2"
    static let markWatchedKey = "nostalgex_mark_watched_v2"

    var showNowPlaying: Bool
    var markWatched: Bool

    static func resolve(nowPlaying: Any?, markWatched: Any?, legacy: Any?) -> Self {
        let old = (legacy as? Bool) ?? false
        return Self(showNowPlaying: (nowPlaying as? Bool) ?? old,
                    markWatched: (markWatched as? Bool) ?? old)
    }

    /// Materialize a legacy choice once. An absent choice stays absent, so a new TV
    /// does not publish default false values over a household's delayed iCloud sync.
    static func loadAndMigrate(from defaults: UserDefaults) -> Self {
        let legacy = defaults.object(forKey: legacyKey)
        let now = defaults.object(forKey: nowPlayingKey)
        let watched = defaults.object(forKey: markWatchedKey)
        let result = resolve(nowPlaying: now, markWatched: watched, legacy: legacy)
        if legacy is Bool {
            if now == nil { defaults.set(result.showNowPlaying, forKey: nowPlayingKey) }
            if watched == nil { defaults.set(result.markWatched, forKey: markWatchedKey) }
        }
        return result
    }
}

/// AppState shares this permission scope across outgoing and current trackers, so
/// changing a choice also revokes work retained by an earlier channel's queue.
final class PlaybackReportingControlScope: @unchecked Sendable {
    private let lock = NSLock()
    private var activity: Bool
    private var watched: Bool
    private var activityVersion = 0
    private var markVersion = 0
    private var attemptedReporting = false

    init(showNowPlaying: Bool, markWatched: Bool) { activity = showNowPlaying; watched = markWatched }
    var activityEpoch: Int { lock.withLock { activityVersion } }
    var markEpoch: Int { lock.withLock { markVersion } }
    var markEnabled: Bool { lock.withLock { watched } }
    /// Sticky across channels so backgrounding can drain an outgoing stop even
    /// when the current tracker has both choices off. Merely queueing does not set it.
    var hasAttemptedReporting: Bool { lock.withLock { attemptedReporting } }
    func update(showNowPlaying: Bool, markWatched: Bool) {
        lock.withLock {
            if activity != showNowPlaying { activityVersion += 1; activity = showNowPlaying }
            if watched != markWatched { markVersion += 1; watched = markWatched }
        }
    }
    func allowsActivity(epoch: Int) -> Bool { lock.withLock { activity && activityVersion == epoch } }
    func allowsMark(epoch: Int) -> Bool { lock.withLock { watched && markVersion == epoch } }
    func beginActivity(epoch: Int) -> Bool {
        lock.withLock {
            guard activity, activityVersion == epoch else { return false }
            attemptedReporting = true
            return true
        }
    }
    func beginMark(epoch: Int, _ body: () -> Bool) -> Bool {
        lock.withLock {
            guard watched, markVersion == epoch else { return false }
            let began = body()
            if began { attemptedReporting = true }
            return began
        }
    }
}
