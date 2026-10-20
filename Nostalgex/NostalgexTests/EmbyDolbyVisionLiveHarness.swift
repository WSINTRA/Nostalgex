import XCTest
@testable import Nostalgex

/// Emby's Dolby Vision profile 5 rule against a real Emby, through the app's own code: the
/// library load (`EmbyAPIService.loadLibrary`) and the channel build
/// (`AppState.rebuildStaticChannelPools`). Read-only. Skipped unless these are set
/// (xcodebuild passes `TEST_RUNNER_`-prefixed variables through to the test process):
///
///   TEST_RUNNER_NOSTALGEX_LIVE_EMBY_URL       server base URL
///   TEST_RUNNER_NOSTALGEX_LIVE_EMBY_TOKEN     access token
///   TEST_RUNNER_NOSTALGEX_LIVE_EMBY_USER      user id
///   TEST_RUNNER_NOSTALGEX_LIVE_EMBY_DV5_IDS   item ids of Dolby Vision profile 5 files, comma separated
///   TEST_RUNNER_NOSTALGEX_LIVE_EMBY_KEEP_IDS  item ids that must reach a channel (DV 8.1, HDR10, SDR)
///
/// The files are named by id so the check does not lean on the code it is checking. Output
/// lines start with `[LiveEmbyDV]` and carry ids and channel numbers, no titles.
@MainActor
final class EmbyDolbyVisionLiveHarness: XCTestCase {

    private struct Lab {
        let api: EmbyAPIService
        let dv5: [String]
        let keep: [String]
    }

    private func lab() throws -> Lab {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["NOSTALGEX_LIVE_EMBY_URL"], let token = env["NOSTALGEX_LIVE_EMBY_TOKEN"],
              let user = env["NOSTALGEX_LIVE_EMBY_USER"], !url.isEmpty, !token.isEmpty, !user.isEmpty else {
            throw XCTSkip("No live Emby server configured")
        }
        func ids(_ key: String) -> [String] {
            (env[key] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return Lab(api: EmbyAPIService(serverURL: url, accessToken: token, userId: user),
                   dv5: ids("NOSTALGEX_LIVE_EMBY_DV5_IDS"), keep: ids("NOSTALGEX_LIVE_EMBY_KEEP_IDS"))
    }

    private func log(_ line: String) { print("[LiveEmbyDV] \(line)") }

    func testDolbyVision5StaysOffChannelsAndTheRestAirs() async throws {
        let lab = try lab()
        XCTAssertFalse(lab.dv5.isEmpty, "name at least one profile 5 file")
        XCTAssertFalse(lab.keep.isEmpty, "name at least one file that must air")

        // The scan, five times; the median is the number to compare.
        var times: [Double] = []
        var items: [PlexMediaItem] = []
        for _ in 0..<5 {
            let started = Date()
            items = try await lab.api.loadLibrary(progress: nil)
            times.append(Date().timeIntervalSince(started))
        }
        let sorted = times.sorted()
        log("scan: \(items.count) items, median \(String(format: "%.3f", sorted[2]))s, runs "
            + times.map { String(format: "%.3f", $0) }.joined(separator: " "))

        let byID = Dictionary(items.map { ($0.ratingKey, $0) }, uniquingKeysWith: { a, _ in a })
        for id in lab.dv5 + lab.keep {
            let item = try XCTUnwrap(byID[id], "item \(id) is not in the library")
            log("item \(id): doviProfile \(item.doviProfile.map(String.init) ?? "nil")")
        }

        let state = AppState()
        state.backendKind = .emby
        state.allItems = items
        let config = ChannelConfigLoader.loadBundled()
        state.exclusiveRules = config.exclusiveRules
        let built = await state.rebuildStaticChannelPools(
            configChannels: config.channels, items: items, onlyChannelIDs: Set(config.channels.map(\.id)))
        func channels(holding id: String) -> [Int] {
            built.filter { ch in ch.itemPool.contains { $0.ratingKey == id } }.map(\.number)
        }
        log("channels built: \(built.count)")
        for id in lab.dv5 {
            let on = channels(holding: id)
            log("DV5 \(id): on \(on.count) channel(s) \(on.prefix(12).map(String.init).joined(separator: ","))")
            XCTAssertEqual(on, [], "profile 5 file \(id) is on a channel")
        }
        for id in lab.keep {
            let on = channels(holding: id)
            log("keep \(id): on \(on.count) channel(s) \(on.prefix(12).map(String.init).joined(separator: ","))")
            XCTAssertFalse(on.isEmpty, "file \(id) reached no channel")
        }

        // Control: the same scanned items, built as if they came from Jellyfin, where the
        // rule does not apply. The profile 5 files must reach channels then, or the check
        // above proves nothing about the rule.
        state.backendKind = .jellyfin
        let control = await state.rebuildStaticChannelPools(
            configChannels: config.channels, items: items, onlyChannelIDs: Set(config.channels.map(\.id)))
        for id in lab.dv5 {
            let on = control.filter { ch in ch.itemPool.contains { $0.ratingKey == id } }.map(\.number)
            log("control (rule off) DV5 \(id): on \(on.count) channel(s) \(on.prefix(12).map(String.init).joined(separator: ","))")
            XCTAssertFalse(on.isEmpty, "control: profile 5 file \(id) reaches no channel even with the rule off")
        }
    }
}
