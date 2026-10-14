import XCTest
import AVFoundation
@testable import Nostalgex

/// Live harness, not a unit test: plays files whose name and contents disagree (an MP4
/// saved as `.mkv`) through the URLs the Jellyfin backend really builds, in AVPlayer on
/// the tvOS simulator, and prints what AVPlayer did with each one.
///
/// Skipped unless a server is supplied:
///   TEST_RUNNER_NOSTALGEX_JF_URL=http://127.0.0.1:8096
///   TEST_RUNNER_NOSTALGEX_JF_TOKEN=<access token>
///   TEST_RUNNER_NOSTALGEX_JF_USER=<user id>
///   TEST_RUNNER_NOSTALGEX_JF_TITLES=<comma-separated title fragments to play>
///   TEST_RUNNER_NOSTALGEX_JF_OUT=<file to mirror the transcript to>
@MainActor
final class JellyfinContainerMismatchHarness: XCTestCase {
    func testPlayEveryURLTheBackendBuilds() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["NOSTALGEX_JF_URL"], let token = env["NOSTALGEX_JF_TOKEN"],
              let user = env["NOSTALGEX_JF_USER"] else {
            throw XCTSkip("No local Jellyfin configured (NOSTALGEX_JF_URL/TOKEN/USER)")
        }
        let fragments = (env["NOSTALGEX_JF_TITLES"] ?? "").split(separator: ",").map(String.init)
        let observe = Double(env["NOSTALGEX_JF_OBSERVE"] ?? "") ?? 12
        var out: [String] = []
        func emit(_ s: String) { print(s); out.append(s) }
        defer {
            if let p = env["NOSTALGEX_JF_OUT"] { try? out.joined(separator: "\n").write(toFile: p, atomically: true, encoding: .utf8) }
        }

        // NOSTALGEX_JF_BACKEND=emby points the same run at an Emby server.
        let api: any MediaBackend = env["NOSTALGEX_JF_BACKEND"] == "emby"
            ? EmbyAPIService(serverURL: url, accessToken: token, userId: user)
            : JellyfinAPIService(serverURL: url, accessToken: token, userId: user)
        let items = try await api.loadLibrary()
        let picked = items.filter { item in fragments.isEmpty || fragments.contains { item.title.contains($0) } }
        XCTAssertFalse(picked.isEmpty, "no library item matched \(fragments)")

        for item in picked {
            emit("[MISMATCH] ===== \"\(item.title)\" container=\(item.container ?? "nil") video=\(item.videoCodec ?? "nil") audio=\(item.audioCodec ?? "nil")")
            var candidates: [(label: String, url: URL, direct: Bool)] = []
            if let d = api.buildDirectPlayURL(for: item) { candidates.append(("buildDirectPlayURL", d, true)) }
            if let t = api.buildTranscodeURL(for: item) { candidates.append(("buildTranscodeURL (runtime fallback)", t, false)) }
            let resolved = await api.resolveTranscodePlayback(for: item)
            if let r = resolved {
                candidates.append(("resolveTranscodePlayback (PlaybackInfo) isDirectPlay=\(r.isDirectPlay)", r.url, r.isDirectPlay))
            }
            // The direct-play URL as it was before 2026-10-12: no extension, so the server
            // labels the response by the file's name.
            if var c = URLComponents(string: "\(url)/Videos/\(item.ratingKey)/stream") {
                c.queryItems = [.init(name: "Static", value: "true"),
                                .init(name: "MediaSourceId", value: item.partKey ?? item.ratingKey),
                                .init(name: "api_key", value: token)]
                if let u = c.url { candidates.append(("static stream, no extension (old URL)", u, true)) }
            }

            for cand in candidates {
                let result = await play(cand.url, direct: cand.direct, headers: api.authHeaders, observe: observe)
                emit("[MISMATCH]   \(cand.label): \(result)")
                emit("[MISMATCH]     url=\(redact(cand.url, token: token))")
            }
            await api.stopTranscode(playSessionId: resolved?.playSessionId)
        }
    }

    private final class MemStore: Nostalgex.CredentialStoring, @unchecked Sendable {
        var values: [String: String] = [:]
        @discardableResult
        func save(key: String, value: String) -> Bool { values[key] = value; return true }
        func load(key: String) -> String? { values[key] }
        func delete(key: String) { values[key] = nil }
    }

    /// The production load path: AppState.loadCurrentItem on each item, then whatever the
    /// player, the fallback and the failure classifier do with it. Prints the state the
    /// viewer would see.
    func testAppLoadPathOnEachItem() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["NOSTALGEX_JF_URL"], let token = env["NOSTALGEX_JF_TOKEN"],
              let user = env["NOSTALGEX_JF_USER"] else {
            throw XCTSkip("No local Jellyfin configured (NOSTALGEX_JF_URL/TOKEN/USER)")
        }
        let fragments = (env["NOSTALGEX_JF_TITLES"] ?? "").split(separator: ",").map(String.init)
        let observe = Double(env["NOSTALGEX_JF_OBSERVE"] ?? "") ?? 12
        var out: [String] = []
        func emit(_ s: String) { print(s); out.append(s) }
        defer {
            if let p = env["NOSTALGEX_JF_OUT"] {
                try? out.joined(separator: "\n").write(toFile: p + ".app", atomically: true, encoding: .utf8)
            }
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
        let picked = app.allItems.filter { item in fragments.isEmpty || fragments.contains { item.title.contains($0) } }
        XCTAssertFalse(picked.isEmpty, "no library item matched \(fragments)")

        for item in picked {
            app.currentItem = item
            app.seekOffset = 0
            app.loadCurrentItem()
            let t0 = Date()
            var states: [String] = []
            var urls: [String] = []
            var outcome = "no terminal state"
            while Date().timeIntervalSince(t0) < observe {
                try await Task.sleep(nanoseconds: 250_000_000)
                let s = "\(app.playbackState)"
                if states.last != s { states.append(String(format: "+%.1fs %@", Date().timeIntervalSince(t0), s)) }
                if let u = app.lastStreamURL.map({ redact($0, token: token) }), urls.last != u { urls.append(u) }
                if case .error(let f) = app.playbackState { outcome = "CARD \"\(f.headline)\" | \(f.diagnosticSummary)"; break }
                if case .playing = app.playbackState, (app.player?.currentTime().seconds ?? 0) > 3 {
                    outcome = String(format: "PLAYING, playhead %.1fs", app.player?.currentTime().seconds ?? -1); break
                }
            }
            emit("[APPPATH] \"\(item.title)\" container=\(item.container ?? "nil"): \(outcome)")
            emit("[APPPATH]   states: \(states.joined(separator: " -> "))")
            for u in urls { emit("[APPPATH]   url: \(u)") }
            app.currentItem = nil
            app.loadCurrentItem()
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func redact(_ url: URL, token: String) -> String {
        url.absoluteString.replacingOccurrences(of: token, with: "TOKEN")
    }

    /// Mirrors AppState's player construction: direct play goes through an AVURLAsset with
    /// the auth headers, everything else through `AVPlayerItem(url:)`.
    private func play(_ url: URL, direct: Bool, headers: [String: String], observe: Double) async -> String {
        let playerItem: AVPlayerItem
        if direct {
            playerItem = AVPlayerItem(asset: AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers]))
        } else {
            playerItem = AVPlayerItem(url: url)
        }
        playerItem.preferredForwardBufferDuration = 5
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true
        defer { player.pause(); player.replaceCurrentItem(with: nil) }

        let t0 = Date()
        var readyAt: Double?
        var startedHead: Double?
        var lastHead = -1.0
        while Date().timeIntervalSince(t0) < observe {
            try? await Task.sleep(nanoseconds: 250_000_000)
            switch playerItem.status {
            case .readyToPlay:
                if readyAt == nil {
                    readyAt = Date().timeIntervalSince(t0)
                    player.play()
                }
                lastHead = player.currentTime().seconds
                if startedHead == nil { startedHead = lastHead }
            case .failed:
                return "FAILED after \(String(format: "%.1f", Date().timeIntervalSince(t0)))s | " + describe(playerItem)
            default:
                break
            }
        }
        guard let readyAt else {
            return "NEVER READY in \(observe)s (status=\(playerItem.status.rawValue)) | " + describe(playerItem)
        }
        let advanced = lastHead - (startedHead ?? 0)
        let tracks = playerItem.tracks.compactMap { $0.assetTrack?.mediaType.rawValue }
        return String(format: "READY at %.1fs, playhead advanced %.1fs, rate=%.1f, tracks=%@, presentationSize=%.0fx%.0f | ",
                      readyAt, advanced, player.rate, tracks.description,
                      playerItem.presentationSize.width, playerItem.presentationSize.height) + describe(playerItem)
    }

    private func describe(_ item: AVPlayerItem) -> String {
        var parts: [String] = []
        if let e = item.error as NSError? {
            parts.append("error=\(e.domain) \(e.code) \"\(e.localizedDescription)\"")
            if let u = e.userInfo[NSUnderlyingErrorKey] as? NSError {
                parts.append("underlying=\(u.domain) \(u.code) \"\(u.localizedDescription)\"")
            }
            if let reason = e.localizedFailureReason { parts.append("reason=\(reason)") }
        }
        if let log = item.errorLog() {
            for ev in log.events.prefix(4) {
                parts.append("errorLog[\(ev.errorDomain) \(ev.errorStatusCode) \(ev.errorComment ?? "")]")
            }
        }
        return parts.isEmpty ? "no error" : parts.joined(separator: " ")
    }
}
