import Foundation

// Report Playback keeps Now Playing and real watches flowing to the user's server, but a
// program Nostalgex tuned past must never be left in Continue Watching (Plex), Resume
// (Jellyfin, Emby) or On Deck.
//
// Plex: reports carry no position (PR #18), so a surf writes nothing and needs no
// cleanup. The one thing left to undo is the next episode Plex adds to Continue Watching
// after a counted episode, when the show was not there before tune-in.
//
// Jellyfin and Emby count a play on the start report and mark an item played on a stop
// without a position (measured on Emby 4.10.1, 2026-10-13), so position-free does not
// work there. The tracker captures UserData before the first report and writes it back
// when the session ends. Numbers in docs/plex-session-reporting.md.
//
// The decision table (`WatchCleanupPlan`) is shared with the web tuner through
// scripts/watch-cleanup-golden.json, which both test suites read.

// MARK: - Transport

/// One HTTP round trip for playback reporting. Production goes through URLSession;
/// tests swap in a recorder so they can assert the exact calls without a server.
protocol ReportTransport: Sendable {
    /// Status code and body, or nil when the request never got an answer.
    func send(_ request: URLRequest) async -> (status: Int, body: Data)?
}

struct URLSessionReportTransport: ReportTransport {
    static let shared = URLSessionReportTransport()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    func send(_ request: URLRequest) async -> (status: Int, body: Data)? {
        guard let (data, response) = try? await Self.session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return (http.statusCode, data)
    }
}

// MARK: - Ordering

/// Runs reporting calls one at a time, in the order they were queued, off the main actor.
///
/// Order is the whole point. Plex writes a resume point on every timeline report, so a
/// cleanup that lands before the last report is undone by it. Serialising also means
/// the next program's "what did the server hold before" read happens after the previous
/// program's cleanup, so back-to-back episodes of one show see the real row.
final class ReportQueue: @unchecked Sendable {
    static let shared = ReportQueue()

    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        lock.lock()
        defer { lock.unlock() }
        let previous = tail
        tail = Task.detached {
            await previous?.value
            await operation()
        }
    }

    /// Waits for everything queued so far. Tests use it, and the app's background task
    /// waits on it so the final stop goes out before the app is suspended.
    func drain() async {
        lock.lock()
        let last = tail
        lock.unlock()
        await last?.value
    }
}

// MARK: - Backoff

/// A server that stops answering gets fewer pulses, never a changed setting. Each
/// failure skips more of the 10 second pulses (1, 2, 4 ... up to 30, about five
/// minutes); any answered report resets it. Starts, stops, scrobbles and cleanup are
/// always sent. Results arrive from the report queue, so it locks.
final class PulseBackoff: @unchecked Sendable {
    static let maxSkip = 30

    private let lock = NSLock()
    private var failures = 0
    private var skipRemaining = 0

    /// True when the next pulse should go out. Consumes one skip when it says no.
    func allowPulse() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard skipRemaining == 0 else { skipRemaining -= 1; return false }
        return true
    }

    func record(success: Bool) {
        lock.lock(); defer { lock.unlock() }
        if success {
            failures = 0
            skipRemaining = 0
        } else {
            failures += 1
            skipRemaining = min(Self.maxSkip, 1 << min(failures - 1, 5))
        }
    }
}

// MARK: - Prior state and the cleanup decision

/// What the server held for an item before Nostalgex sent its first report.
struct PriorWatchState: Equatable, Sendable {
    /// Resume point in the server's own unit: Plex milliseconds, Jellyfin/Emby 100ns ticks.
    var resumePosition: Int
    var playCount: Int
    var played: Bool
    /// Jellyfin/Emby `LastPlayedDate`, sent back verbatim on restore. Nil on Plex.
    var lastPlayedDate: String? = nil
    /// Plex episodes: the show's rating key (`grandparentRatingKey`). The only Plex field
    /// the cleanup reads, with `showInContinueWatching`.
    var showKey: String? = nil
    /// Plex episodes: the show already had an entry in Continue Watching.
    var showInContinueWatching: Bool = false
}

enum WatchCleanupStep: Equatable, Sendable {
    /// Plex: remove whatever Continue Watching entry the scrobble created for this show.
    case removeShowFromContinueWatching(String)
    /// Jellyfin/Emby `DELETE /Users/{id}/PlayedItems/{item}`: back to never-played.
    case markUnplayed
    /// Jellyfin/Emby `POST /Users/{id}/Items/{item}/UserData`.
    case setUserData(position: Int, playCount: Int?, played: Bool?, lastPlayedDate: String?)

    /// Compact form used by scripts/watch-cleanup-golden.json.
    var goldenDescription: String {
        switch self {
        case .removeShowFromContinueWatching(let show): return "removeShowFromContinueWatching \(show)"
        case .markUnplayed: return "markUnplayed"
        case let .setUserData(position, playCount, played, lastPlayedDate):
            var parts = ["userData position=\(position)"]
            if let playCount { parts.append("playCount=\(playCount)") }
            if let played { parts.append("played=\(played)") }
            if let lastPlayedDate { parts.append("lastPlayedDate=\(lastPlayedDate)") }
            return parts.joined(separator: " ")
        }
    }
}

enum WatchCleanupPlan {
    /// Plex. `countedWatch` means this session scrobbled (the 15% / 75% gate passed).
    /// Reports carry no position, so a surf leaves nothing to undo and the item's own
    /// resume point, play count and Continue Watching entry are never touched. An episode
    /// scrobble puts the NEXT episode in Continue Watching; take that out unless the show
    /// was already there. Unknown prior: leave it, rather than remove a row the user had.
    static func plex(prior: PriorWatchState?, countedWatch: Bool) -> [WatchCleanupStep] {
        guard countedWatch, let prior, let show = prior.showKey, !prior.showInContinueWatching else { return [] }
        return [.removeShowFromContinueWatching(show)]
    }

    /// Jellyfin and Emby. Both bump PlayCount on the start report and store the stop
    /// position, so the restore writes the exact prior values back.
    static func mediaServer(prior: PriorWatchState?, countedWatch: Bool) -> [WatchCleanupStep] {
        guard let prior else {
            return [.setUserData(position: 0, playCount: nil, played: nil, lastPlayedDate: nil)]
        }
        if countedWatch {
            return [.setUserData(position: 0, playCount: prior.playCount + 1, played: true, lastPlayedDate: nil)]
        }
        if prior.resumePosition == 0 && prior.playCount == 0 && !prior.played {
            return [.markUnplayed]
        }
        return [.setUserData(position: prior.resumePosition, playCount: prior.playCount,
                             played: prior.played, lastPlayedDate: prior.lastPlayedDate)]
    }
}

// MARK: - Guards

protocol WatchStateGuarding: Sendable {
    /// Reads what the server holds for the item. Nil when the read failed.
    func captureWatchState(for item: PlexMediaItem) async -> PriorWatchState?
    /// Puts the item back the way the plan says. Best effort: one attempt per call.
    func restoreWatchState(for item: PlexMediaItem, prior: PriorWatchState?, countedWatch: Bool) async
}

struct PlexWatchStateGuard: WatchStateGuarding {
    static let libraryIdentifier = "com.plexapp.plugins.library"

    let serverURL: String
    let headers: [String: String]
    let transport: any ReportTransport

    func request(method: String, path: String, query: [URLQueryItem] = []) -> URLRequest? {
        guard var components = URLComponents(string: "\(serverURL)\(path)") else { return nil }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return req
    }

    /// `key` is the bare rating key. `/library/metadata/{rk}` is answered with 404.
    func scrobbleRequest(ratingKey: String) -> URLRequest? {
        request(method: "GET", path: "/:/scrobble", query: [
            .init(name: "key", value: ratingKey),
            .init(name: "identifier", value: Self.libraryIdentifier),
        ])
    }

    func removeFromContinueWatchingRequest(ratingKey: String) -> URLRequest? {
        request(method: "PUT", path: "/actions/removeFromContinueWatching", query: [
            .init(name: "ratingKey", value: ratingKey),
        ])
    }

    private struct Container: Decodable {
        struct Inner: Decodable { let Metadata: [Entry]? }
        struct Entry: Decodable {
            let ratingKey: String?
            let type: String?
            let grandparentRatingKey: String?
        }
        let MediaContainer: Inner
    }

    private func entries(_ req: URLRequest?) async -> [Container.Entry]? {
        guard let req, let (status, body) = await transport.send(req), (200...299).contains(status),
              let decoded = try? JSONDecoder().decode(Container.self, from: body) else { return nil }
        return decoded.MediaContainer.Metadata ?? []
    }

    private func continueWatching() async -> [Container.Entry]? {
        await entries(request(method: "GET", path: "/hubs/continueWatching/items", query: [
            .init(name: "count", value: "200"),
        ]))
    }

    /// Episodes only: is the show already in Continue Watching before tune-in? Films
    /// need nothing, so they cost no request.
    func captureWatchState(for item: PlexMediaItem) async -> PriorWatchState? {
        guard item.type == .episode,
              let meta = await entries(request(method: "GET", path: "/library/metadata/\(item.ratingKey)"))?.first,
              meta.type == "episode", let show = meta.grandparentRatingKey else { return nil }
        // Unreadable row: assume the show was there, so we never remove a real entry.
        let inRow = await continueWatching().map { row in
            row.contains { $0.grandparentRatingKey == show || $0.ratingKey == show }
        } ?? true
        return PriorWatchState(resumePosition: 0, playCount: 0, played: false,
                               showKey: show, showInContinueWatching: inRow)
    }

    func restoreWatchState(for item: PlexMediaItem, prior: PriorWatchState?, countedWatch: Bool) async {
        for case .removeShowFromContinueWatching(let show) in WatchCleanupPlan.plex(prior: prior, countedWatch: countedWatch) {
            // Plex adds the next episode about a second after the scrobble, which can be
            // the moment before this runs. Look up to three times.
            for attempt in 0..<3 {
                let added = (await continueWatching() ?? [])
                    .filter { $0.grandparentRatingKey == show }
                    .compactMap(\.ratingKey)
                for key in added {
                    guard let req = removeFromContinueWatchingRequest(ratingKey: key) else { continue }
                    let status = await transport.send(req)?.status
                    print("[Tracker] cleanup rk=\(item.ratingKey) removeFromContinueWatching next-up rk=\(key) HTTP \(status.map(String.init) ?? "failed")")
                }
                if !added.isEmpty || attempt == 2 { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

/// Jellyfin and Emby. Both answer the `/Users/{id}/...` routes (Jellyfin keeps them
/// for compatibility next to `/UserItems`), measured on Emby 4.10.1 and Jellyfin 12.2.
struct MediaServerWatchStateGuard: WatchStateGuarding {
    let serverURL: String
    let authorization: String
    let userId: String
    let transport: any ReportTransport

    private func path(_ suffix: String) -> String? {
        guard let user = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return "\(serverURL)/Users/\(user)\(suffix)"
    }

    private func itemPath(_ itemId: String) -> String? {
        itemId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    private func request(method: String, url: String?, body: Data? = nil) -> URLRequest? {
        guard let url, let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    func request(for step: WatchCleanupStep, itemId: String) -> URLRequest? {
        guard let item = itemPath(itemId) else { return nil }
        switch step {
        case .markUnplayed:
            return request(method: "DELETE", url: path("/PlayedItems/\(item)"))
        case let .setUserData(position, playCount, played, lastPlayedDate):
            var body: [String: Any] = ["PlaybackPositionTicks": position]
            if let playCount { body["PlayCount"] = playCount }
            if let played { body["Played"] = played }
            if let lastPlayedDate { body["LastPlayedDate"] = lastPlayedDate }
            let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            return request(method: "POST", url: path("/Items/\(item)/UserData"), body: data)
        case .removeShowFromContinueWatching:
            return nil
        }
    }

    private struct ItemResponse: Decodable {
        struct UserData: Decodable {
            let PlaybackPositionTicks: Int?
            let PlayCount: Int?
            let Played: Bool?
            let LastPlayedDate: String?
        }
        let UserData: UserData?
    }

    func captureWatchState(for item: PlexMediaItem) async -> PriorWatchState? {
        guard let id = itemPath(item.ratingKey),
              let req = request(method: "GET", url: path("/Items/\(id)")),
              let (status, body) = await transport.send(req), (200...299).contains(status),
              let decoded = try? JSONDecoder().decode(ItemResponse.self, from: body),
              let data = decoded.UserData else { return nil }
        return PriorWatchState(
            resumePosition: data.PlaybackPositionTicks ?? 0,
            playCount: data.PlayCount ?? 0,
            played: data.Played ?? false,
            lastPlayedDate: data.LastPlayedDate
        )
    }

    func restoreWatchState(for item: PlexMediaItem, prior: PriorWatchState?, countedWatch: Bool) async {
        for step in WatchCleanupPlan.mediaServer(prior: prior, countedWatch: countedWatch) {
            guard let req = request(for: step, itemId: item.ratingKey) else { continue }
            let status = await transport.send(req)?.status
            print("[Tracker] cleanup item=\(item.ratingKey) \(step.goldenDescription) HTTP \(status.map(String.init) ?? "failed")")
        }
    }
}

/// Holds the captured prior state. Only read and written from operations on one
/// `ReportQueue`, which runs them one at a time, so it needs no lock of its own.
final class PriorWatchStateBox: @unchecked Sendable {
    var prior: PriorWatchState?
}
