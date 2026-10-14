import XCTest
@testable import Nostalgex

/// #21 added version and part fields to PlexMediaItem without bumping the snapshot
/// format. A bump clears every user's snapshot and forces a full rescan, so these prove
/// a snapshot written before those fields existed still loads and plays as it did: the
/// chunked v3 directory 1.0.26 writes, and the legacy v2 single file it migrates from.
final class LibrarySnapshotCompatibilityTests: XCTestCase {
    private let identity = "snapshot-compat-test"
    private let addedKeys = ["mediaIndex", "partIndex", "playbackParts", "exactDurationSeconds"]

    override func setUp() {
        super.setUp()
        LibrarySnapshotStore.clear()
    }

    override func tearDown() {
        LibrarySnapshotStore.clear()
        super.tearDown()
    }

    private func snapshotDirectory() throws -> URL {
        try XCTUnwrap(LibrarySnapshotStore.snapshotDirectoryURL)
    }

    private func legacyURL() throws -> URL {
        try XCTUnwrap(LibrarySnapshotStore.legacySnapshotURL)
    }

    /// The live generation directory named by current.json.
    private func liveGeneration() throws -> URL {
        let root = try snapshotDirectory()
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: root.appendingPathComponent("current.json"))) as? [String: Any])
        return root.appendingPathComponent(try XCTUnwrap(manifest["generation"] as? String), isDirectory: true)
    }

    private func stripAddedKeys(_ rows: [[String: Any]]) -> [[String: Any]] {
        rows.map { row in
            var legacy = row
            addedKeys.forEach { legacy.removeValue(forKey: $0) }
            return legacy
        }
    }

    private func item(id: String) -> PlexMediaItem {
        PlexMediaItem(id: id, title: "T\(id)", artist: nil, episodeTitle: nil, seTag: nil, summary: "", year: 2020,
                      originallyAvailableAt: nil, contentRating: nil, duration: 180, ratingKey: id,
                      partKey: "/library/parts/\(id)/part1.mkv",
                      container: "mkv", videoCodec: "h264", audioCodec: "aac", videoProfile: nil, bitrate: 6000,
                      genres: [], rating: 0, userRating: 0, type: .movie, thumb: nil, art: nil, viewCount: 0, addedAt: 0,
                      studio: nil, tmdbID: nil, imdbID: nil, librarySource: .movie, serverID: "server-a",
                      additionalPartKeys: nil, videoBitDepth: 8, doviProfile: nil, videoWidth: 1920, videoHeight: 1080)
    }

    /// A three-part film on its third version, with every #21 field set.
    private func threePartFilm() -> PlexMediaItem {
        var film = item(id: "1")
        film.additionalPartKeys = ["/library/parts/1/part2.mkv", "/library/parts/1/part3.mkv"]
        film.mediaIndex = 2
        film.partIndex = 0
        film.playbackParts = ["/library/parts/1/part1.mkv", "/library/parts/1/part2.mkv", "/library/parts/1/part3.mkv"].map {
            PlexPartPlaybackInfo(key: $0, container: "mkv", videoCodec: "h264", audioCodec: "aac",
                                 bitDepth: 8, doviProfile: nil, durationSeconds: 60)
        }
        film.exactDurationSeconds = 180.5
        return film
    }

    private func save(_ items: [PlexMediaItem]) throws {
        try LibrarySnapshotStore.save(
            identity: identity, serverName: "Test", librarySignature: "sig",
            lastLoadAtUnix: Int(Date().timeIntervalSince1970), allItems: items,
            channelConfigChannels: [], allChannels: [], bundles: [], enabledBundleIDs: [],
            exclusiveRules: [], discoveredCollections: []
        )
    }

    /// A 1.0.26 chunked snapshot: same format version, item chunks without the #21 keys.
    func testChunkedSnapshotFromBeforeVersionAndPartFieldsStillLoads() throws {
        try save([threePartFilm(), item(id: "2")])

        // Strip the keys #21 added from every item chunk. The pre-#21 encoder never wrote
        // them, so what is left is the shape of a snapshot already on a user's device.
        let gen = try liveGeneration()
        let meta = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(contentsOf: gen.appendingPathComponent("meta.json"))) as? [String: Any])
        XCTAssertEqual(meta["schemaVersion"] as? Int, 3, "the format must match what pre-#21 builds (1.0.26) wrote")
        XCTAssertEqual(LibrarySnapshotStore.formatVersion, 3)
        let chunkURL = gen.appendingPathComponent("items-0000.json")
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: chunkURL)) as? [[String: Any]])
        XCTAssertTrue(rows[0].keys.contains("mediaIndex"), "fixture sanity: the new keys were written and are being removed")
        try JSONSerialization.data(withJSONObject: stripAddedKeys(rows)).write(to: chunkURL)

        let loaded = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: identity),
                                   "an old snapshot must load, not force a rescan")
        XCTAssertFalse(loaded.fromLegacyFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: chunkURL.path), "an old snapshot must not be cleared")
        assertPreVersionBehaviour(loaded.snapshot)
    }

    /// The legacy v2 single file (pre-1.0.26) without the #21 keys still migrates.
    func testLegacyFileFromBeforeVersionAndPartFieldsStillLoads() throws {
        let items = [threePartFilm(), item(id: "2")]
        let snap = LibrarySnapshotV1(
            schemaVersion: 2, credentialFingerprint: LibrarySnapshotStore.fingerprint(identity: identity),
            lastLoadAtUnix: Int(Date().timeIntervalSince1970), serverName: "Test", allItems: items,
            channelConfigRows: [], allChannelRows: [], bundleDefinitions: [], enabledBundleIDList: [],
            exclusiveRuleJSON: [], discoveredCollectionRows: [], librarySignature: "sig")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snap)) as? [String: Any])
        json["allItems"] = stripAddedKeys(try XCTUnwrap(json["allItems"] as? [[String: Any]]))
        let url = try legacyURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let loaded = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: identity),
                                   "an old legacy snapshot must load, not force a rescan")
        XCTAssertTrue(loaded.fromLegacyFile)
        assertPreVersionBehaviour(loaded.snapshot)
    }

    private func assertPreVersionBehaviour(_ snap: LibrarySnapshotV1, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(snap.allItems.map(\.id), ["1", "2"], file: file, line: line)
        guard let film = snap.allItems.first else { return }
        XCTAssertEqual(film.mediaIndex, 0, file: file, line: line)
        XCTAssertEqual(film.partIndex, 0, file: file, line: line)
        XCTAssertNil(film.playbackParts, file: file, line: line)
        XCTAssertNil(film.exactDurationSeconds, file: file, line: line)
        XCTAssertEqual(film.partKey, "/library/parts/1/part1.mkv", file: file, line: line)
        XCTAssertEqual(film.additionalPartKeys, ["/library/parts/1/part2.mkv", "/library/parts/1/part3.mkv"], file: file, line: line)
        XCTAssertEqual(film.serverID, "server-a", file: file, line: line)

        // Defaults reproduce pre-#21 behaviour: no part mapping without part lengths...
        let position = film.playbackPosition(at: 135)
        XCTAssertEqual(position.item.partKey, film.partKey, file: file, line: line)
        XCTAssertEqual(position.baseSeconds, 0, file: file, line: line)
        XCTAssertEqual(position.offsetSeconds, 135, file: file, line: line)
        // ...and the same first-version, first-part transcode request as before.
        let query = PlexAPIService.transcodeQueryItems(for: film, sessionID: "test", offsetSeconds: 12,
            isLocal: true, quality: .low, token: "synthetic", clientID: "synthetic", hevcCapable: true)
        XCTAssertEqual(query.first { $0.name == "mediaIndex" }?.value, "0", file: file, line: line)
        XCTAssertEqual(query.first { $0.name == "partIndex" }?.value, "0", file: file, line: line)
    }

    func testVersionAndPartFieldsSurviveTheSnapshot() throws {
        let original = threePartFilm()
        try save([original])

        let loaded = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: identity))
        let film = try XCTUnwrap(loaded.snapshot.allItems.first)
        XCTAssertEqual(film.mediaIndex, 2)
        XCTAssertEqual(film.partIndex, 0)
        XCTAssertEqual(film.playbackParts, original.playbackParts)
        XCTAssertEqual(film.exactDurationSeconds, 180.5)
        XCTAssertEqual(film.playbackPosition(at: 135).item.partKey, "/library/parts/1/part3.mkv")
    }
}
