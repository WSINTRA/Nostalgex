import Foundation
import AVFoundation

/// Unattended, on-device playback proof. Launch the app with `-playbackSoak [count]` and it
/// plays a stratified sample of the library (every container / codec / bit depth / HDR /
/// resolution combination present), tuning into each a third of the way through like a
/// channel change does, and prints one line per file plus a pass rate. Run from a Mac with
/// `xcrun devicectl device process launch --console ... com.muellhaus.nostalgex -playbackSoak 60`.
/// A file passes when the player reports playing AND the playhead advances at least 3s.
@MainActor
enum PlaybackSoak {
    /// `devicectl` refuses app arguments that begin with a dash, so the flag is also accepted
    /// as `playbackSoak=N` and as the environment variable NOSTALGEX_PLAYBACK_SOAK=N.
    static var requestedCount: Int? {
        let p = ProcessInfo.processInfo
        if let i = p.arguments.firstIndex(of: "-playbackSoak") { return i + 1 < p.arguments.count ? Int(p.arguments[i + 1]) ?? 40 : 40 }
        if let a = p.arguments.first(where: { $0.hasPrefix("playbackSoak=") }) { return Int(a.dropFirst("playbackSoak=".count)) ?? 40 }
        if let e = p.environment["NOSTALGEX_PLAYBACK_SOAK"] { return Int(e) ?? 40 }
        // devicectl also rejects environment passthrough on tvOS, so a file dropped into the
        // container with `devicectl device copy to` is the trigger that actually works.
        if let url = triggerURL, let text = try? String(contentsOf: url, encoding: .utf8) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("rk:") { return 0 }
            return Int(t) ?? 40
        }
        return nil
    }

    /// `rk:1853,4040` in the trigger file plays exactly those ratingKeys, for reproducing.
    static var requestedRatingKeys: [String]? {
        guard let url = triggerURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let t = String(text.split(separator: "\n").first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("rk:") else { return nil }
        return t.dropFirst(3).split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    /// Trigger line `hold:N` keeps each passing file playing N more seconds and reports how
    /// far the playhead got, so sustained playback is measured, not just first picture.
    static var holdSeconds: Int {
        guard let url = triggerURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        for line in text.split(separator: "\n") where line.hasPrefix("hold:") { return Int(line.dropFirst(5).trimmingCharacters(in: .whitespaces)) ?? 0 }
        return 0
    }

    /// Second trigger line `q:name=value;name=value` overrides transcode query items for the
    /// run (value `UNSET` removes one), so server-side parameters can be trialled on a real
    /// Apple TV without a rebuild per trial.
    nonisolated(unsafe) static var queryOverrides: [String: String] = [:]
    static func loadQueryOverrides() {
        guard let url = triggerURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") where line.hasPrefix("q:") {
            for pair in line.dropFirst(2).split(separator: ";") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 { queryOverrides[kv[0]] = kv[1] }
            }
        }
        if !queryOverrides.isEmpty { emit("[SOAK] query overrides: \(queryOverrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))") }
    }
    static var triggerURL: URL? { LocalStore.rootDirectory?.appendingPathComponent("soak.trigger") }
    static var resultsURL: URL? { LocalStore.rootDirectory?.appendingPathComponent("soak-results.log") }

    /// stdout for an attached console, plus a file in the container that
    /// `devicectl device copy from` can retrieve when no console is attached.
    static var stdoutCaptured = false
    static func emit(_ line: String) {
        print(line)
        if stdoutCaptured { return }  // print already lands in the results file
        guard let url = resultsURL, let data = (line + "\n").data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(data); try? h.close() }
        else { try? data.write(to: url) }
    }
    static var isRequested: Bool { requestedCount != nil }

    static func category(of item: PlexMediaItem) -> String {
        var v = (item.videoCodec ?? "?").lowercased()
        if let d = item.videoBitDepth, d > 8 { v += "\(d)" }
        if let dovi = item.doviProfile { v += "-dv\(dovi)" }
        if (item.videoHeight ?? 0) >= 2000 || (item.videoWidth ?? 0) >= 3000 { v += "-4k" }
        return "\(item.container?.lowercased() ?? "?")/\(v)/\(item.audioCodec?.lowercased() ?? "?")"
    }

    /// Round-robin across categories so rare combinations are always represented. Sorted
    /// input so two runs on the same library test the same files.
    static func stratifiedSample(_ items: [PlexMediaItem], count: Int) -> [PlexMediaItem] {
        var groups: [String: [PlexMediaItem]] = [:]
        for it in items where it.partKey != nil { groups[category(of: it), default: []].append(it) }
        let keys = groups.keys.sorted()
        var queues = keys.map { groups[$0]!.sorted { $0.ratingKey < $1.ratingKey } }
        var out: [PlexMediaItem] = []
        while out.count < count, queues.contains(where: { !$0.isEmpty }) {
            for i in queues.indices where !queues[i].isEmpty && out.count < count {
                out.append(queues[i].removeFirst())
            }
        }
        return out
    }

    struct Outcome { let item: PlexMediaItem; let category: String; let result: String; let firstPlayingSeconds: Double? }

    /// Round trip to the item's server for a tiny request, so a failure can be read against
    /// the state of the link at that moment rather than blamed on the file.
    static func linkLatencyMs(appState: AppState, item: PlexMediaItem) async -> Int? {
        let backend = appState.api(for: item.serverID)
        let t = Date()
        do { _ = try await backend.testConnection() } catch { return nil }
        return Int(Date().timeIntervalSince(t) * 1000)
    }

    static func run(appState: AppState) async {
        let count = requestedCount ?? 40
        let keys = requestedRatingKeys
        let hold = holdSeconds
        loadQueryOverrides()
        if let t = triggerURL { try? FileManager.default.removeItem(at: t) }  // one run per trigger
        if let r = resultsURL {
            try? FileManager.default.removeItem(at: r)
            // Every print() from the player lands in the results file too, so a soak pulled
            // off the device explains its own failures without a console attach.
            if freopen(r.path, "a", stdout) != nil { setvbuf(stdout, nil, _IOLBF, 0); stdoutCaptured = true }
        }
        let sample: [PlexMediaItem] = keys.map { ks in ks.compactMap { k in appState.allItems.first { $0.ratingKey == k } } }
            ?? stratifiedSample(appState.allItems, count: count)
        let categories = Set(sample.map(category(of:))).count
        emit("[SOAK] start: \(sample.count) files across \(categories) categories, from \(appState.allItems.count) items")
        appState.currentChannel = appState.channels.first ?? appState.allChannels.first
        appState.isFullScreen = true

        var outcomes: [Outcome] = []
        for (index, item) in sample.enumerated() {
            let cat = category(of: item)
            let started = Date()
            let linkMs = await linkLatencyMs(appState: appState, item: item)
            appState.currentPartIndex = 0
            appState.seekOffset = max(0, item.duration * 60 / 3)
            appState.currentItem = item
            appState.loadCurrentItem()

            // Room for the whole ladder: direct play, server stream, capped retry.
            let limit = 15 + PlaybackWatchdog.deadlineSeconds(isDirectPlay: false, videoWidth: item.videoWidth, videoHeight: item.videoHeight) * 2 + 10
            var result = "TIMEOUT"
            var firstPlaying: Double? = nil
            var playheadAtFirst: Double? = nil
            var size = CGSize.zero
            var sawFrame = false
            // The capped retry can add a full second deadline; allow for it.
            let generous = limit * 2 + 10
            while Date().timeIntervalSince(started) < Double(generous) {
                try? await Task.sleep(for: .milliseconds(500))
                if appState.currentItem?.ratingKey != item.ratingKey { result = "SKIPPED"; break }
                if appState.playbackState == .playing, let t = appState.player?.currentTime().seconds, t.isFinite {
                    if firstPlaying == nil { firstPlaying = Date().timeIntervalSince(started); playheadAtFirst = t }
                    size = appState.player?.currentItem?.presentationSize ?? .zero
                    let frame = appState.videoFrameProbe?.hasNewPixelBuffer(forItemTime: CMTime(seconds: t, preferredTimescale: 600)) ?? false
                    if frame { sawFrame = true }
                    if let p0 = playheadAtFirst, t - p0 >= 3, sawFrame { result = "PASS"; break }
                }
            }
            if result == "TIMEOUT", firstPlaying != nil, !sawFrame { result = "AUDIO_ONLY" }
            if result == "PASS", hold > 0 {
                // Sustained playback: sample the playhead once a second for `hold` seconds.
                let startHead = appState.player?.currentTime().seconds ?? 0
                var stalls = 0, lastHead = startHead
                for _ in 0..<hold {
                    try? await Task.sleep(for: .seconds(1))
                    if appState.currentItem?.ratingKey != item.ratingKey { result = "SKIPPED_DURING_HOLD"; break }
                    let head = appState.player?.currentTime().seconds ?? lastHead
                    if head - lastHead < 0.25 { stalls += 1 }
                    lastHead = head
                }
                let advanced = lastHead - startHead
                let access = appState.player?.currentItem?.accessLog()?.events.last
                emit("[SOAK] hold \(hold)s: playhead advanced \(String(format: "%.1f", advanced))s, still-seconds=\(stalls), segments=\(access?.numberOfMediaRequests ?? -1) stalls=\(access?.numberOfStalls ?? -1) observedKbps=\(Int((access?.observedBitrate ?? 0) / 1000)) dropped=\(access?.numberOfDroppedVideoFrames ?? -1)  \"\(item.title)\"")
                if result == "PASS", advanced < Double(hold) * 0.8 { result = "STALLED_IN_HOLD" }
            }
            let ttp = firstPlaying.map { String(format: "%.1fs", $0) } ?? "-"
            emit("[SOAK] \(index + 1)/\(sample.count) \(result.padding(toLength: 12, withPad: " ", startingAt: 0)) \(cat.padding(toLength: 28, withPad: " ", startingAt: 0)) playing@\(ttp.padding(toLength: 6, withPad: " ", startingAt: 0)) video=\(Int(size.width))x\(Int(size.height)) frames=\(sawFrame) link=\(linkMs.map { "\($0)ms" } ?? "down")  \"\(item.title)\" rk=\(item.ratingKey)")
            outcomes.append(Outcome(item: item, category: cat, result: result, firstPlayingSeconds: firstPlaying))
        }

        let passed = outcomes.filter { $0.result == "PASS" }.count
        emit("[SOAK] ---- summary ----")
        for cat in Set(outcomes.map(\.category)).sorted() {
            let rows = outcomes.filter { $0.category == cat }
            let p = rows.filter { $0.result == "PASS" }.count
            let fails = rows.filter { $0.result != "PASS" }.map { "\($0.item.title) [\($0.result)]" }
            emit("[SOAK]   \(cat.padding(toLength: 28, withPad: " ", startingAt: 0)) \(p)/\(rows.count)\(fails.isEmpty ? "" : "  FAILED: " + fails.joined(separator: "; "))")
        }
        let rate = outcomes.isEmpty ? 0 : Double(passed) * 100 / Double(outcomes.count)
        emit("[SOAK] PASS RATE \(String(format: "%.1f", rate))% (\(passed)/\(outcomes.count))")
        emit("[SOAK] DONE")
        appState.player?.pause()
        appState.stopActiveTranscodeIfNeeded()
    }
}
