import XCTest
@testable import Nostalgex

/// Replays the basement Apple TV, 2026-10-06: Armageddon (4K 60fps HEVC) transcoding at
/// 0.72x real time. Picture, buffer drains, freeze, play, freeze, then frozen for good.
final class PlaybackStarvationTests: XCTestCase {
    private func feed(_ m: inout PlaybackStarvation, playheads: [Double], startWall: Double = 0, remaining: Double? = 3000) -> PlaybackStarvation.Verdict? {
        var verdict: PlaybackStarvation.Verdict?
        for (i, p) in playheads.enumerated() {
            if let v = m.observe(playhead: p, wall: startWall + Double(i), paused: false, remaining: remaining) {
                verdict = v
                break
            }
        }
        return verdict
    }

    /// 1 s of playhead per second.
    private func playing(from: Double, seconds: Int) -> [Double] { (0..<seconds).map { from + Double($0) } }
    private func frozen(at: Double, seconds: Int) -> [Double] { Array(repeating: at, count: seconds) }

    func testHealthyStreamNeverStarves() {
        var m = PlaybackStarvation()
        XCTAssertNil(feed(&m, playheads: playing(from: 0, seconds: 600)))
        XCTAssertTrue(m.armed)
    }

    func testThreeStallsInsideTheWindowIsStarving() {
        var m = PlaybackStarvation()
        // The measured shape: ~25 s of play, ~10 s frozen, repeat.
        var trace: [Double] = []
        var head = 0.0
        for _ in 0..<3 {
            trace += playing(from: head, seconds: 25); head += 25
            trace += frozen(at: head, seconds: 10)
        }
        trace += playing(from: head, seconds: 5)
        let v = feed(&m, playheads: trace)
        guard case .starving(let stalls, let longest)? = v else { return XCTFail("expected starving, got \(String(describing: v))") }
        XCTAssertEqual(stalls, 3)
        XCTAssertGreaterThanOrEqual(longest, 9)
    }

    func testOneLongFreezeIsStarvingOnItsOwn() {
        var m = PlaybackStarvation()
        let v = feed(&m, playheads: playing(from: 100, seconds: 30) + frozen(at: 130, seconds: 25))
        guard case .starving(let stalls, let longest)? = v else { return XCTFail("expected starving, got \(String(describing: v))") }
        XCTAssertEqual(stalls, 1)
        XCTAssertGreaterThanOrEqual(longest, PlaybackStarvation.hardStallSeconds)
    }

    func testStartupIsNotAStall() {
        // The playhead sits at zero while the transcoder spins up. That is the startup
        // watchdog's call, never ours: nothing has played yet.
        var m = PlaybackStarvation()
        XCTAssertNil(feed(&m, playheads: frozen(at: 0, seconds: 60)))
        XCTAssertFalse(m.armed)
    }

    func testBriefHLSSegmentPausesAreNotStalls() {
        var m = PlaybackStarvation()
        var trace: [Double] = []
        var head = 0.0
        for _ in 0..<40 {
            trace += playing(from: head, seconds: 8); head += 8
            trace += frozen(at: head, seconds: 2)   // under stallSeconds
        }
        XCTAssertNil(feed(&m, playheads: trace))
    }

    func testStallsSpreadWiderThanTheWindowDoNotAddUp() {
        var m = PlaybackStarvation()
        var trace: [Double] = []
        var head = 0.0
        for _ in 0..<3 {
            trace += playing(from: head, seconds: 90); head += 90
            trace += frozen(at: head, seconds: 5)
        }
        trace += playing(from: head, seconds: 5)
        XCTAssertNil(feed(&m, playheads: trace), "three stalls across 285 s is a rough stream, not a starving one")
    }

    func testPausedSamplesAreIgnored() {
        var m = PlaybackStarvation()
        for i in 0..<10 { _ = m.observe(playhead: Double(i), wall: Double(i), paused: false, remaining: 3000) }
        for i in 10..<60 { XCTAssertNil(m.observe(playhead: 10, wall: Double(i), paused: true, remaining: 3000)) }
    }

    func testTheTailOfAnItemBelongsToTheEndFallback() {
        var m = PlaybackStarvation()
        for i in 0..<10 { _ = m.observe(playhead: Double(i), wall: Double(i), paused: false, remaining: 3000) }
        for i in 10..<60 { XCTAssertNil(m.observe(playhead: 10, wall: Double(i), paused: false, remaining: 2)) }
    }

    func testTwoStallsThenRecoveryStaysQuiet() {
        var m = PlaybackStarvation()
        var trace = playing(from: 0, seconds: 20) + frozen(at: 20, seconds: 5)
        trace += playing(from: 20, seconds: 20) + frozen(at: 40, seconds: 5)
        trace += playing(from: 40, seconds: 200)
        XCTAssertNil(feed(&m, playheads: trace))
    }
}
