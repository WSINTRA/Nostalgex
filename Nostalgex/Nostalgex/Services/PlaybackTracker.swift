import Foundation

/// Tracks a single playback session for one item on one channel.
/// Reports to Plex (timeline + scrobble) or to Jellyfin/Emby (session + play count).
/// With neither reporter, it only accumulates watch time for analytics.
///
/// Scrobble rule (hybrid gate), same on every server:
///   1. Entry gate — tuned in during the first 15% of the program
///   2. Active time — accumulated ≥ 75% of total runtime while this tracker is active
/// Both gates must pass. The count increments as soon as the threshold is crossed or on stop.
@MainActor
final class PlaybackTracker {

    // MARK: - Identity

    let sessionID = UUID().uuidString
    let item: PlexMediaItem
    /// Seconds into the program when the user tuned in.
    let seekOffset: Int

    // MARK: - Entry gate

    /// True if the user tuned in during the first 15% of the program.
    let eligibleEntry: Bool

    // MARK: - Watch clock

    private var activeWatchSeconds: Double = 0
    /// Independent accumulator drained by `flushWatchSecondsForAnalytics`. Kept
    /// separate from `activeWatchSeconds` so draining it for a `playback.stopped`
    /// analytics signal doesn't reset the scrobble threshold ( ≥ 75% of runtime ).
    private var analyticsWatchSeconds: Double = 0
    private var watchStart: Date? = nil

    // MARK: - State

    private(set) var scrobbled = false
    private var stopped = false
    /// Jellyfin/Emby need a Playing call before Progress. Reset when a stop closes the session.
    private var didStartSession = false

    // MARK: - 10-second timeline pulse

    private var timelineTimer: Timer?

    // MARK: - Server reporting (nil = reporting off, or demo)

    private let plexAPI: PlexAPIService?
    private let watchReporter: (any WatchActivityReporting)?

    // MARK: - Init

    init(
        item: PlexMediaItem,
        seekOffset: Int,
        plexAPI: PlexAPIService?,
        watchReporter: (any WatchActivityReporting)? = nil
    ) {
        self.item = item
        self.seekOffset = seekOffset
        self.plexAPI = plexAPI
        self.watchReporter = watchReporter

        let totalSec = Double(item.duration * 60)
        let entryFrac = totalSec > 0 ? Double(seekOffset) / totalSec : 1.0
        self.eligibleEntry = entryFrac <= 0.15

        print("[Tracker] \(sessionID.prefix(8)) START \"\(item.title)\" offset=\(seekOffset)s eligible=\(eligibleEntry)")
    }

    deinit {
        timelineTimer?.invalidate()
    }

    // MARK: - Lifecycle hooks

    /// Call when AVPlayer becomes .readyToPlay and begins playing.
    /// Idempotent — safe to call from retry / transcode-fallback paths for the same item.
    func onPlaybackReady() {
        guard !stopped else { return }
        if watchStart == nil {
            watchStart = Date()
        }
        if timelineTimer == nil {
            scheduleTimeline()
        }
        sendTimeline(state: "playing")
    }

    /// Call when the app enters the background.
    func onBackground() {
        guard !stopped else { return }
        accumulateTime()
        sendTimeline(state: "stopped")
        didStartSession = false
        timelineTimer?.invalidate()
        timelineTimer = nil
    }

    /// Call when the app returns to the foreground.
    func onForeground() {
        guard !stopped else { return }
        watchStart = Date()
        scheduleTimeline()
        sendTimeline(state: "playing")
    }

    /// Finalize the session: flush accumulated time, send stopped, evaluate scrobble.
    /// Called before advancing, channel change, or disconnect.
    func stop() {
        guard !stopped else { return }
        stopped = true
        timelineTimer?.invalidate()
        timelineTimer = nil
        accumulateTime()
        sendTimeline(state: "stopped")
        evaluateAndScrobble()
        print("[Tracker] \(sessionID.prefix(8)) STOP \"\(item.title)\" watched=\(Int(activeWatchSeconds))s scrobbled=\(scrobbled)")
    }

    /// Tear down without reporting anything. Used when the user turns off Plex activity
    /// sync mid-program: clears the pulse timer so no further timeline/scrobble fires and,
    /// unlike `stop()`, sends no final "stopped" report — so no view-offset is written and
    /// the item never lands in Continue Watching.
    func abandon() {
        guard !stopped else { return }
        stopped = true
        timelineTimer?.invalidate()
        timelineTimer = nil
    }

    /// Return the accumulated active watch time and reset the counter so the next
    /// `playback.stopped` analytics signal doesn't double-count. Independent of the
    /// Plex scrobble path (which needs the running total until `stop()`), so this is
    /// called by AppState in every backend, including Jellyfin/Emby/demo.
    ///
    /// Safe to call while the session is still running: the split second between the
    /// last accumulation and now is folded in, and a fresh accumulation window opens
    /// for whatever comes next.
    func flushWatchSecondsForAnalytics() -> Double {
        if let start = watchStart {
            let delta = Date().timeIntervalSince(start)
            activeWatchSeconds += delta
            analyticsWatchSeconds += delta
            // Keep accumulating from now if the session is still live; otherwise leave
            // it nil so nothing is added after a stop.
            watchStart = stopped ? nil : Date()
        }
        let out = analyticsWatchSeconds
        analyticsWatchSeconds = 0
        return out
    }

    // MARK: - Private

    private func accumulateTime() {
        guard let start = watchStart else { return }
        let delta = Date().timeIntervalSince(start)
        activeWatchSeconds += delta
        analyticsWatchSeconds += delta
        watchStart = nil
    }

    private func scheduleTimeline() {
        timelineTimer?.invalidate()
        timelineTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onTimelineTick() }
        }
    }

    private func onTimelineTick() {
        guard !stopped else {
            timelineTimer?.invalidate()
            return
        }
        // accumulateTime folds elapsed since watchStart into BOTH counters (scrobble
        // and analytics). Resetting watchStart keeps the next tick's delta clean.
        accumulateTime()
        watchStart = Date()
        let timeMs = (seekOffset * 1000) + Int(activeWatchSeconds * 1000)
        let durationMs = item.duration * 60 * 1000
        sendTimeline(state: "playing", timeMs: timeMs, durationMs: durationMs)
        evaluateAndScrobble()
    }

    private func currentTimeMs() -> Int {
        (seekOffset * 1000) + Int(activeWatchSeconds * 1000)
    }

    private func sendTimeline(state: String, timeMs: Int? = nil, durationMs: Int? = nil) {
        let t = timeMs ?? currentTimeMs()
        let d = durationMs ?? (item.duration * 60 * 1000)
        if let api = plexAPI {
            let rk = item.ratingKey
            let key = "/library/metadata/\(rk)"
            let sid = sessionID
            Task.detached {
                await api.reportTimeline(ratingKey: rk, key: key, state: state, timeMs: t, durationMs: d, sessionID: sid)
            }
        }
        guard let reporter = watchReporter else { return }
        if state == "stopped", !didStartSession { return }
        let event: MediaServerPlaybackReport.Event
        if state == "stopped" {
            event = .stopped
        } else if didStartSession {
            event = .progress
        } else {
            event = .started
            didStartSession = true
        }
        let ticks = reportedTicks(actual: t * 10_000, event: event)
        let itemId = item.ratingKey
        let mediaSourceId = item.partKey ?? item.ratingKey
        let sid = sessionID
        Task.detached {
            await reporter.reportWatchActivity(
                itemId: itemId,
                mediaSourceId: mediaSourceId,
                playSessionId: sid,
                positionTicks: ticks,
                event: event
            )
        }
    }

    /// Jellyfin and Emby count a play when a stop lands at about 90% of the runtime.
    /// Once this session already counted the watch, later stops stay under that line
    /// so the same viewing is not counted twice.
    private func reportedTicks(actual: Int, event: MediaServerPlaybackReport.Event) -> Int {
        guard event == .stopped, scrobbled, watchReporter != nil else { return actual }
        let durationTicks = item.duration * 60 * 10_000_000
        guard durationTicks > 0 else { return actual }
        return min(actual, Int(Double(durationTicks) * 0.89))
    }

    private func evaluateAndScrobble() {
        guard eligibleEntry, !scrobbled else { return }
        let totalSec = Double(item.duration * 60)
        guard totalSec > 0, activeWatchSeconds / totalSec >= 0.75 else { return }
        scrobbled = true
        print("[Tracker] \(sessionID.prefix(8)) SCROBBLE \"\(item.title)\" rk=\(item.ratingKey)")
        if let api = plexAPI {
            let rk = item.ratingKey
            Task.detached { await api.scrobble(ratingKey: rk) }
        }
        if let reporter = watchReporter {
            let fraction = Double(currentTimeMs()) / (totalSec * 1000)
            // At or past the server's own completion line, the stop report counts it.
            guard fraction < 0.9 else { return }
            let itemId = item.ratingKey
            Task.detached { await reporter.markWatched(itemId: itemId) }
        }
    }
}
