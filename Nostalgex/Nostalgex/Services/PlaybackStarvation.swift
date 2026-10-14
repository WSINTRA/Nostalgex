import Foundation

/// Decides when a stream that *was* playing is being starved by its source.
///
/// Measured 2026-10-06 on a basement Apple TV: a 35 GB 4K 60fps HEVC rip transcoded at
/// 0.72x real time on the Plex server. The player showed picture, drained its buffer,
/// froze, played a little, froze again, and after the third stall sat on one frame for
/// good. The startup watchdog never fires for this, because the stream reached ready and
/// the playhead moved. The same file capped to 1080p transcodes at 1.8x and plays clean,
/// so the answer is to re-request the stream smaller from where we are, not to skip.
///
/// Fed one sample a second. Like the startup watchdog it judges by playhead movement, not
/// AVPlayer's buffer flags: a playhead that stops moving while the player is not paused
/// is a stall whatever the flags say.
struct PlaybackStarvation {
    enum Verdict: Equatable {
        /// Three stalls inside the window, or one stall that never recovered.
        case starving(stalls: Int, longestStallSeconds: Double)
    }

    /// Seconds the playhead must sit still before it counts as a stall. HLS pauses for a
    /// moment between segments on a healthy stream; three seconds is well past that.
    static let stallSeconds: Double = 3
    /// A single stall this long is a frozen picture, whatever came before it.
    static let hardStallSeconds: Double = 20
    /// Repeated short stalls: this many inside `windowSeconds` means the source cannot keep up.
    static let stallsToStarve = 3
    static let windowSeconds: Double = 120
    /// The monitor only arms once playback has genuinely run. Startup is the other
    /// watchdog's job, and a load that never moves must not be mistaken for a stall.
    static let armAfterProgressSeconds: Double = 1
    /// Progress below this between samples is "did not move".
    static let minimumProgressSeconds: Double = 0.25
    /// Inside the tail of an item a stopped playhead is the end of the file, handled by the
    /// end-of-item fallback, not starvation.
    static let tailSeconds: Double = 5

    private(set) var armed = false
    private var firstPlayhead: Double?
    private var lastPlayhead: Double?
    private var stallStartedAt: Double?
    private var stallsEndedAt: [Double] = []
    private(set) var longestStall: Double = 0

    /// - Parameters:
    ///   - playhead: player item time in seconds (whatever clock the stream uses; only deltas matter).
    ///   - wall: wall-clock seconds, monotonic.
    ///   - paused: the player was deliberately paused (not buffering). Paused samples are ignored.
    ///   - remaining: seconds to the end of the item, or nil when unknown.
    mutating func observe(playhead: Double, wall: Double, paused: Bool, remaining: Double?) -> Verdict? {
        guard playhead.isFinite, !paused else { return nil }
        if let remaining, remaining.isFinite, remaining <= Self.tailSeconds { return nil }

        if firstPlayhead == nil { firstPlayhead = playhead }
        defer { lastPlayhead = playhead }

        if !armed {
            if let first = firstPlayhead, playhead - first >= Self.armAfterProgressSeconds { armed = true }
            return nil
        }
        guard let last = lastPlayhead else { return nil }

        let moved = (playhead - last) >= Self.minimumProgressSeconds
        if moved {
            if let start = stallStartedAt, wall - start >= Self.stallSeconds {
                stallsEndedAt.append(wall)
                longestStall = max(longestStall, wall - start)
            }
            stallStartedAt = nil
        } else {
            if stallStartedAt == nil { stallStartedAt = wall }
            let length = wall - stallStartedAt!
            longestStall = max(longestStall, length)
            if length >= Self.hardStallSeconds {
                return .starving(stalls: stallsEndedAt.count + 1, longestStallSeconds: longestStall)
            }
        }

        stallsEndedAt.removeAll { wall - $0 > Self.windowSeconds }
        if stallsEndedAt.count >= Self.stallsToStarve {
            return .starving(stalls: stallsEndedAt.count, longestStallSeconds: longestStall)
        }
        return nil
    }
}
