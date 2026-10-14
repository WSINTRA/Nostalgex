import XCTest
import AVFoundation
@testable import Nostalgex

/// Live harness, not a unit test: tunes real channels against a local Jellyfin server
/// through the production AppState/AVPlayer path and prints what happened, so a
/// channel-change bug can be measured instead of reasoned about.
///
/// Skipped unless the server is supplied:
///   TEST_RUNNER_NOSTALGEX_JF_URL=http://127.0.0.1:8096
///   TEST_RUNNER_NOSTALGEX_JF_TOKEN=<access token>
///   TEST_RUNNER_NOSTALGEX_JF_USER=<user id>
@MainActor
final class JellyfinLiveOffsetHarness: XCTestCase {
    private final class MemStore: Nostalgex.CredentialStoring, @unchecked Sendable {
        var values: [String: String] = [:]
        @discardableResult
        func save(key: String, value: String) -> Bool { values[key] = value; return true }
        func load(key: String) -> String? { values[key] }
        func delete(key: String) { values[key] = nil }
    }

    func testTuneAtScheduleOffsetAgainstLocalJellyfin() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["NOSTALGEX_JF_URL"], let token = env["NOSTALGEX_JF_TOKEN"],
              let user = env["NOSTALGEX_JF_USER"] else {
            throw XCTSkip("No local Jellyfin configured (NOSTALGEX_JF_URL/TOKEN/USER)")
        }
        let tunes = Int(env["NOSTALGEX_JF_TUNES"] ?? "") ?? 4
        let observeSeconds = Double(env["NOSTALGEX_JF_OBSERVE"] ?? "") ?? 14
        // xcodebuild does not relay the test host's stdout, so mirror every line to a file.
        let outPath = env["NOSTALGEX_JF_OUT"]
        var out: [String] = []
        func emit(_ s: String) { print(s); out.append(s) }
        defer {
            if let outPath { try? out.joined(separator: "\n").write(toFile: outPath, atomically: true, encoding: .utf8) }
        }

        let app = AppState(credentialStore: MemStore())
        app.backendKind = .jellyfin
        app.serverURL = url
        app.token = token
        app.jellyfinUserId = user
        app.setSelectedServers([AppState.ServerRef(
            machineIdentifier: "harness-server", name: "Harness Jellyfin",
            baseURL: url, owned: true, token: token, userId: user)])

        await app.loadLibrary()
        let channels = app.channels.filter { !$0.filteredPool().isEmpty }
        emit("[HARNESS] channels with items: \(channels.map { "\($0.number) \($0.name) (\($0.filteredPool().count))" })")
        XCTAssertFalse(channels.isEmpty, "library loaded no channels")

        var summary: [String] = []
        for i in 0..<tunes {
            let ch = channels[i % channels.count]
            let t0 = Date()
            app.selectChannel(ch)
            let scheduledTitle = app.currentItem?.title ?? "nil"
            let scheduledOffset = app.seekOffset
            var transcript: [String] = []
            var firstPlayingAt: Double? = nil
            var playheadAtFirstPlaying: Double? = nil
            let steps = Int(observeSeconds * 2)
            for _ in 0..<steps {
                try await Task.sleep(nanoseconds: 500_000_000)
                let elapsed = Date().timeIntervalSince(t0)
                let head = app.player?.currentTime().seconds ?? -1
                let itemDuration = app.player?.currentItem?.duration.seconds ?? -1
                let rate = app.player?.rate ?? 0
                transcript.append(String(format: "+%4.1fs state=%@ item=\"%@\" playhead=%.1f rate=%.1f itemDuration=%.0f",
                                         elapsed, "\(app.playbackState)", app.currentItem?.title ?? "nil", head, rate, itemDuration))
                if firstPlayingAt == nil, case .playing = app.playbackState {
                    firstPlayingAt = elapsed
                    playheadAtFirstPlaying = head
                }
            }
            let finalTitle = app.currentItem?.title ?? "nil"
            let finalHead = app.player?.currentTime().seconds ?? -1
            let line = String(format: "[HARNESS] TUNE %d CH %d %@: scheduled=\"%@\" offset=%ds | first .playing at %@ with playhead %@ | after %.0fs item=\"%@\" seekOffset=%d playhead=%.1f | %@",
                              i + 1, ch.number, ch.name, scheduledTitle, scheduledOffset,
                              firstPlayingAt.map { String(format: "%.1fs", $0) } ?? "never",
                              playheadAtFirstPlaying.map { String(format: "%.1fs", $0) } ?? "-",
                              observeSeconds, finalTitle, app.seekOffset, finalHead,
                              finalTitle == scheduledTitle ? "SAME ITEM" : "ITEM CHANGED")
            emit(line)
            transcript.forEach { emit("[HARNESS]    \($0)") }
            summary.append(line)
        }
        // Forced phase: every item in the pool, through the same production load path,
        // at a fixed offset, so the mkv (remux/transcode) items are measured whatever the
        // schedule happens to be airing.
        let forcedOffset = Int(env["NOSTALGEX_JF_FORCED_OFFSET"] ?? "") ?? 120
        if let ch = channels.first {
            for item in ch.filteredPool().sorted(by: { $0.title < $1.title }) {
                let t0 = Date()
                app.currentChannel = ch
                app.currentItem = item
                app.seekOffset = forcedOffset
                app.loadCurrentItem()
                var transcript: [String] = []
                var firstPlayingAt: Double? = nil
                var playheadAtFirstPlaying: Double? = nil
                for _ in 0..<Int(observeSeconds * 2) {
                    try await Task.sleep(nanoseconds: 500_000_000)
                    let elapsed = Date().timeIntervalSince(t0)
                    let head = app.player?.currentTime().seconds ?? -1
                    let itemDuration = app.player?.currentItem?.duration.seconds ?? -1
                    transcript.append(String(format: "+%4.1fs state=%@ item=\"%@\" playhead=%.1f rate=%.1f itemDuration=%.0f hlsBase=%.0f",
                                             elapsed, "\(app.playbackState)", app.currentItem?.title ?? "nil", head,
                                             app.player?.rate ?? 0, itemDuration, app.hlsBaseOffset))
                    if firstPlayingAt == nil, case .playing = app.playbackState {
                        firstPlayingAt = elapsed
                        playheadAtFirstPlaying = head
                    }
                }
                let finalTitle = app.currentItem?.title ?? "nil"
                let line = String(format: "[HARNESS] FORCED \"%@\" (%@:%@ %@) offset=%ds | first .playing at %@ with playhead %@ | after %.0fs item=\"%@\" seekOffset=%d playhead=%.1f hlsBase=%.0f | %@",
                                  item.title, item.videoCodec ?? "?", item.audioCodec ?? "?", item.container ?? "?", forcedOffset,
                                  firstPlayingAt.map { String(format: "%.1fs", $0) } ?? "never",
                                  playheadAtFirstPlaying.map { String(format: "%.1fs", $0) } ?? "-",
                                  observeSeconds, finalTitle, app.seekOffset,
                                  app.player?.currentTime().seconds ?? -1, app.hlsBaseOffset,
                                  finalTitle == item.title ? "SAME ITEM" : "ITEM CHANGED")
                emit(line)
                transcript.forEach { emit("[HARNESS]    \($0)") }
                summary.append(line)
            }
        }
        emit("[HARNESS] ==== SUMMARY ====")
        summary.forEach { emit($0) }
    }
}
