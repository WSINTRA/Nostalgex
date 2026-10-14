import XCTest
@testable import Nostalgex

/// Runs the real collection path against a real server: the backend's own library load,
/// `AppState.scanCollections`, `materializeDynamicChannels` and the daily scheduler, then
/// prints every collection that holds shows, the channel it became and a day of its
/// schedule. Read-only. Skipped unless these are set (xcodebuild passes `TEST_RUNNER_`-
/// prefixed variables through to the test process):
///
///   TEST_RUNNER_NOSTALGEX_LIVE_COLLECTIONS_BACKEND  plex | jellyfin | emby
///   TEST_RUNNER_NOSTALGEX_LIVE_COLLECTIONS_URL      server base URL
///   TEST_RUNNER_NOSTALGEX_LIVE_COLLECTIONS_TOKEN    token
///   TEST_RUNNER_NOSTALGEX_LIVE_COLLECTIONS_USER     user id (Jellyfin and Emby)
///
/// Output lines start with `[LiveCollections]`. They carry library titles, so keep the
/// log out of the repo.
@MainActor
final class LiveCollectionShowsHarness: XCTestCase {

    private func backend() throws -> any MediaBackend {
        let env = ProcessInfo.processInfo.environment
        guard let kind = env["NOSTALGEX_LIVE_COLLECTIONS_BACKEND"], let url = env["NOSTALGEX_LIVE_COLLECTIONS_URL"],
              let token = env["NOSTALGEX_LIVE_COLLECTIONS_TOKEN"], !url.isEmpty, !token.isEmpty else {
            throw XCTSkip("No live collections server configured")
        }
        let user = env["NOSTALGEX_LIVE_COLLECTIONS_USER"] ?? ""
        switch kind {
        case "jellyfin": return JellyfinAPIService(serverURL: url, accessToken: token, userId: user)
        case "emby": return EmbyAPIService(serverURL: url, accessToken: token, userId: user)
        default: return PlexAPIService(serverURL: url, token: token)
        }
    }

    private func log(_ line: String) { print("[LiveCollections] \(line)") }

    func testShowCollectionsBecomeChannelsWithASchedule() async throws {
        let api = try backend()
        let started = Date()
        let items = try await api.loadLibrary(progress: nil)
        let episodes = items.filter { $0.type == .episode }
        log("library: \(items.count) items, \(items.count - episodes.count) films, \(episodes.count) episodes, "
            + "\(episodes.filter { $0.showKey != nil }.count) episodes with a show key "
            + "(\(String(format: "%.1f", Date().timeIntervalSince(started)))s)")

        let state = AppState()
        state.backendOverride = { _ in api }
        state.allItems = items
        state.enabledCollectionKeys = []
        let scanStart = Date()
        await state.scanCollections()
        log("scan: \(state.discoveredCollections.count) collections become candidates "
            + "(\(String(format: "%.1f", Date().timeIntervalSince(scanStart)))s)")

        // Films-only collections must come out exactly as the films-only scan made them:
        // movie libraries' collections, children matched against films, 3 or more kept.
        let sections = try await api.loadSections()
        var oldRows: [(id: String, items: [String])] = []
        var seen = Set<String>()
        let filmByKey = Dictionary(items.filter { $0.type == .movie }.map { ($0.ratingKey, $0) }, uniquingKeysWith: { a, _ in a })
        for section in sections where section.type == "movie" {
            for c in try await api.loadCollections(sectionKey: section.key) where seen.insert(c.ratingKey).inserted {
                let matched = try await api.loadCollectionItems(collectionKey: c.ratingKey).compactMap { filmByKey[$0] }
                if matched.count >= 3 { oldRows.append((c.ratingKey, matched.map(\.id))) }
            }
        }
        let newFilmRows = state.discoveredCollections.filter { $0.showCount == 0 }
        let newByID = Dictionary(newFilmRows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let sameItems = oldRows.filter { newByID[$0.id]?.items.map(\.id) == $0.items }.count
        log("films-only collections: old matcher \(oldRows.count), new scan \(newFilmRows.count), "
            + "same members \(sameItems)/\(oldRows.count)")
        XCTAssertEqual(Set(oldRows.map(\.id)), Set(newFilmRows.map(\.id)))
        XCTAssertEqual(sameItems, oldRows.count)
        XCTAssertTrue(newFilmRows.allSatisfy { $0.movieCount == $0.items.count && $0.memberSummary == "\($0.items.count) movies" })

        let withShows = state.discoveredCollections.filter { $0.showCount > 0 }
        log("holding shows: \(withShows.count)")
        guard !withShows.isEmpty else {
            log("no collection holds shows on this server; the films-only check above is the whole run")
            return
        }

        // What the films-only matcher this replaces made of the same collections.
        let films = Dictionary(items.filter { $0.type == .movie }.map { ($0.ratingKey, $0) }, uniquingKeysWith: { a, _ in a })
        for dc in withShows {
            let rawKey = dc.id.split(separator: ":").last.map(String.init) ?? dc.id
            let children = try await api.loadCollectionItems(collectionKey: rawKey)
            let oldMatches = children.filter { films[$0] != nil }.count
            log("  '\(dc.title)' [\(dc.category.rawValue)] \(dc.memberSummary); children returned \(children.count); "
                + "films-only matcher: \(oldMatches) film(s), \(oldMatches >= 3 ? "kept" : "skipped"); "
                + "folded: \(dc.foldedIntoFranchise ?? "no")")
        }

        // Switch the show collections on, as the viewer would, and build the channels.
        state.enabledCollectionKeys = Set(withShows.map(\.id))
        for i in state.discoveredCollections.indices {
            state.discoveredCollections[i].enabled = state.enabledCollectionKeys.contains(state.discoveredCollections[i].id)
        }
        state.materializeDynamicChannels()
        let channels = state.allChannels.filter { ChannelIDSpace.isDynamic($0.id) }.sorted { $0.number < $1.number }
        XCTAssertEqual(channels.count, withShows.filter { !$0.isFoldedIntoFranchise }.count)

        let fp = "live-collections-\(UUID().uuidString)"
        defer { DailyManifestStore.clearAll(credentialFingerprint: fp) }
        DailyManifestScheduler.invalidateMemo()
        let calendar = Calendar.current
        let now = Date()
        for channel in channels {
            let pool = channel.itemPool
            let poolEpisodes = pool.filter { $0.type == .episode }
            log("CH \(channel.number) \(channel.name) id=\(channel.id) category=\(channel.category ?? "-") "
                + "pool=\(pool.count) (\(pool.count - poolEpisodes.count) films, \(poolEpisodes.count) episodes)")
            let blocks = DailyManifestScheduler.blocks(for: channel, at: now, credentialFingerprint: fp, calendar: calendar)
            let dayStart = calendar.startOfDay(for: now)
            let covered = blocks.last.map { $0.endTime.timeIntervalSince(dayStart) / 3600 } ?? 0
            let firstPass = Array(blocks.prefix(pool.count)).map(\.item)
            var maxRun = 1, run = 1
            for (a, b) in zip(firstPass, firstPass.dropFirst()) {
                run = (a.type == .episode && a.title == b.title) ? run + 1 : 1
                maxRun = max(maxRun, run)
            }
            var inOrderShows = 0, shows = 0
            for title in Set(firstPass.filter { $0.type == .episode }.map(\.title)) {
                let tags = firstPass.filter { $0.title == title }.compactMap(\.seTag)
                guard tags.count > 2 else { continue }
                shows += 1
                if tags == tags.sorted() { inOrderShows += 1 }
            }
            log("  day: \(blocks.count) blocks, \(String(format: "%.1f", covered))h covered; first pass: "
                + "\(Set(firstPass.map(\.id)).count)/\(pool.count) distinct, longest same-show run \(maxRun), "
                + "\(inOrderShows)/\(shows) shows aired in S/E order")
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            fmt.timeZone = calendar.timeZone
            for block in blocks.prefix(12) {
                let what = block.item.type == .episode
                    ? "\(block.item.title) \(block.item.seTag ?? "") \"\(block.item.episodeTitle ?? "")\""
                    : "\(block.item.title) (\(block.item.year.map(String.init) ?? "-")) [film]"
                log("    \(fmt.string(from: block.startTime))-\(fmt.string(from: block.endTime)) \(what)")
            }
            XCTAssertFalse(blocks.isEmpty)
            XCTAssertEqual(Set(blocks.map(\.item.id)).subtracting(Set(pool.map(\.id))), [], "schedule draws only from the pool")
        }
    }
}
