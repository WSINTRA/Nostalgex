import Foundation

/// Tracks a single playback session for one item on one channel.
/// Reports to Plex (timeline + scrobble) or to Jellyfin/Emby (session + play count).
/// With neither reporter, it only accumulates watch time for analytics.
///
/// Scrobble rule (hybrid gate), same on every server:
///   1. Entry gate — tuned in during the first 15% of the program
///   2. Active time — accumulated ≥ 75% of total runtime while this tracker is active
/// Both gates must pass. The count increments as soon as the threshold is crossed or on stop.
///
/// Continue Watching: reporting must never leave a program in the user's Continue
/// Watching, Resume or On Deck rows.
/// - Plex: every timeline report is position-free (PR #18), so Now Playing sees the title
///   and whether it is playing, paused or buffering, and Plex stores nothing. A counted
///   episode's next-up entry is removed unless its show was already in Continue Watching.
/// - Jellyfin/Emby: reports carry the position (a stop without one marks the item played),
///   so the tracker reads UserData before the first report and writes it back when the
///   session ends, the app backgrounds or the user turns reporting off.
/// See `WatchCleanupPlan`. Every server call goes through one `ReportQueue`, so cleanup
/// always lands after the last report. A server that stops answering gets fewer pulses
/// (`PulseBackoff`); nothing here ever changes the user's setting.
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

    // MARK: - Rating nudge

    /// Set once this watch has been counted toward the rating nudge, so the same
    /// continuous watch is never counted twice (once at exit-to-guide, again on stop).
    var countedAsViewingSession = false
    /// Called from `stop()` with the session's total active watch seconds.
    var onStop: ((PlaybackTracker, Double) -> Void)?

    /// Total active watch time so far, including the running stretch. Read-only: it
    /// does not drain either accumulator.
    var watchedSecondsSoFar: Double {
        activeWatchSeconds + (watchStart.map { now().timeIntervalSince($0) } ?? 0)
    }

    // MARK: - 10-second timeline pulse

    private var timelineTimer: Timer?

    // MARK: - Server reporting (nil = reporting off, or demo)

    private let plexAPI: PlexAPIService?
    private let watchReporter: (any WatchActivityReporting)?

    /// AVPlayer's last state ("playing", "paused", "buffering"), so Now Playing on Plex
    /// shows a pause as a pause. From PR #18.
    private var playerState: String?
    /// Backgrounding already sent the stop; foregrounding clears it. From PR #18.
    private var backgrounded = false
    private let backoff = PulseBackoff()

    // MARK: - Continue Watching guard

    private let watchGuard: (any WatchStateGuarding)?
    private let queue: ReportQueue
    private let now: () -> Date
    /// Written by the capture operation on `queue`, read by the cleanup operation on it.
    private let priorBox = PriorWatchStateBox()
    private var captureQueued = false
    /// Something reached the server, so there is something to clean up.
    private var reportedToServer = false

    // MARK: - Init

    init(
        item: PlexMediaItem,
        seekOffset: Int,
        plexAPI: PlexAPIService?,
        watchReporter: (any WatchActivityReporting)? = nil,
        queue: ReportQueue = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.item = item
        self.seekOffset = seekOffset
        self.plexAPI = plexAPI
        self.watchReporter = watchReporter
        if let plexAPI {
            self.watchGuard = plexAPI.watchStateGuard
        } else {
            self.watchGuard = watchReporter?.watchStateGuard
        }
        self.queue = queue
        self.now = now

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
        guard !stopped, !backgrounded else { return }
        if watchStart == nil {
            watchStart = now()
        }
        if timelineTimer == nil {
            scheduleTimeline()
        }
        sendTimeline(state: "playing")
    }

    /// Keep one logical viewing session across parts without counting loading time.
    func onPlaybackPreparing() {
        guard !stopped else { return }
        accumulateTime()
        timelineTimer?.invalidate()
        timelineTimer = nil
    }

    /// AVPlayer's state, from `timeControlStatus`. On Plex a change shows in Now Playing
    /// at once instead of on the next pulse. Never touches the watch clock.
    func onHeartbeatPlaybackState(_ state: String) {
        guard !stopped, !backgrounded, state != playerState else { return }
        playerState = state
        if plexAPI != nil, reportedToServer { sendTimeline(state: state) }
    }

    /// Call when the app enters the background. The app may never come back, so the
    /// item is put back the way it was now; returning to the foreground reports again
    /// and the next stop cleans up again.
    func onBackground() {
        guard !stopped, !backgrounded else { return }
        backgrounded = true
        playerState = nil
        accumulateTime()
        sendTimeline(state: "stopped")
        didStartSession = false
        timelineTimer?.invalidate()
        timelineTimer = nil
        enqueueCleanup()
    }

    /// Call when the app returns to the foreground.
    func onForeground() {
        guard !stopped else { return }
        backgrounded = false
        watchStart = now()
        scheduleTimeline()
        sendTimeline(state: "playing")
    }

    /// Finalize the session: flush accumulated time, send stopped, evaluate scrobble,
    /// then restore Continue Watching. Called before advancing, channel change, or disconnect.
    func stop() {
        guard !stopped else { return }
        stopped = true
        timelineTimer?.invalidate()
        timelineTimer = nil
        accumulateTime()
        if !backgrounded { sendTimeline(state: "stopped") }
        evaluateAndScrobble()
        enqueueCleanup()
        print("[Tracker] \(sessionID.prefix(8)) STOP \"\(item.title)\" watched=\(Int(activeWatchSeconds))s scrobbled=\(scrobbled)")
        onStop?(self, activeWatchSeconds)
        onStop = nil
    }

    /// Tear down without further progress. Used when the user turns off playback
    /// reporting mid-program: no more pulses or scrobble. Plex gets one position-free stop
    /// so Now Playing clears now (it writes nothing). Jellyfin/Emby get no stop, which would
    /// store a position or mark the item played; the cleanup writes UserData back.
    func abandon() {
        guard !stopped else { return }
        stopped = true
        timelineTimer?.invalidate()
        timelineTimer = nil
        if plexAPI != nil, !backgrounded { sendTimeline(state: "stopped") }
        enqueueCleanup()
    }

    /// Runs one pulse now. Tests drive the tracker with this instead of the 10s timer.
    func timelineTickForTesting() {
        onTimelineTick()
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
            let delta = now().timeIntervalSince(start)
            activeWatchSeconds += delta
            analyticsWatchSeconds += delta
            // Keep accumulating from now if the session is still live; otherwise leave
            // it nil so nothing is added after a stop.
            watchStart = stopped ? nil : now()
        }
        let out = analyticsWatchSeconds
        analyticsWatchSeconds = 0
        return out
    }

    // MARK: - Private

    private func accumulateTime() {
        guard let start = watchStart else { return }
        let delta = now().timeIntervalSince(start)
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
        guard !stopped, !backgrounded else {
            timelineTimer?.invalidate()
            return
        }
        // accumulateTime folds elapsed since watchStart into BOTH counters (scrobble
        // and analytics). Resetting watchStart keeps the next tick's delta clean.
        accumulateTime()
        watchStart = now()
        sendTimeline(state: "playing", pulse: true)
        evaluateAndScrobble()
    }

    private func currentTimeMs() -> Int {
        (seekOffset * 1000) + Int(activeWatchSeconds * 1000)
    }

    /// Before the first report, read what the server holds for the item. Queued ahead of
    /// that report, so it sees the state from before Nostalgex touched anything.
    private func captureWatchStateIfNeeded() {
        guard !captureQueued, let guardian = watchGuard else { return }
        captureQueued = true
        let item = self.item
        let box = priorBox
        let tag = sessionID.prefix(8)
        queue.enqueue {
            box.prior = await guardian.captureWatchState(for: item)
            if let prior = box.prior {
                print("[Tracker] \(tag) PRIOR rk=\(item.ratingKey) resume=\(prior.resumePosition) count=\(prior.playCount) showInCW=\(prior.showInContinueWatching)")
            } else {
                print("[Tracker] \(tag) PRIOR rk=\(item.ratingKey) none (Plex film, or unreadable)")
            }
        }
    }

    /// Puts Continue Watching / Resume back the way it was (or, after a counted watch,
    /// the way a finished watch should leave it). Queued behind every report already sent.
    private func enqueueCleanup() {
        guard reportedToServer, let guardian = watchGuard else { return }
        let item = self.item
        let box = priorBox
        let counted = scrobbled
        queue.enqueue {
            await guardian.restoreWatchState(for: item, prior: box.prior, countedWatch: counted)
        }
    }

    /// `pulse`: the 10 second keep-alive. Pulses wait out `PulseBackoff`; every other
    /// report always goes out.
    private func sendTimeline(state: String, pulse: Bool = false) {
        // A "stopped" for a session that never reported "playing" (tuned past before the
        // picture came up) has nothing to close.
        if let api = plexAPI, state != "stopped" || reportedToServer {
            captureWatchStateIfNeeded()
            reportedToServer = true
            // No position, ever: Plex shows the session in Now Playing and stores nothing.
            let reported = state == "playing" ? (playerState ?? "playing") : state
            let rk = item.ratingKey
            let sid = sessionID
            send(pulse: pulse) { await api.reportHeartbeat(ratingKey: rk, state: reported, sessionID: sid) }
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
        captureWatchStateIfNeeded()
        reportedToServer = true
        let ticks = reportedTicks(actual: currentTimeMs() * 10_000, event: event)
        let itemId = item.ratingKey
        let mediaSourceId = item.partKey ?? item.ratingKey
        let sid = sessionID
        send(pulse: pulse && event == .progress) {
            await reporter.reportWatchActivity(
                itemId: itemId,
                mediaSourceId: mediaSourceId,
                playSessionId: sid,
                positionTicks: ticks,
                event: event
            )
        }
    }

    private func send(pulse: Bool, _ report: @escaping @Sendable () async -> Bool) {
        if pulse, !backoff.allowPulse() { return }
        let backoff = self.backoff
        queue.enqueue { backoff.record(success: await report()) }
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
            queue.enqueue { await api.scrobble(ratingKey: rk) }
        }
        if let reporter = watchReporter {
            let fraction = Double(currentTimeMs()) / (totalSec * 1000)
            // At or past the server's own completion line, the stop report counts it.
            guard fraction < 0.9 else { return }
            let itemId = item.ratingKey
            queue.enqueue { await reporter.markWatched(itemId: itemId) }
        }
    }
}
