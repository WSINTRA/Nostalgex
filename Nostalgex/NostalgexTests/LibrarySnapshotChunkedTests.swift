import XCTest
@testable import Nostalgex

/// The chunked (v3) library snapshot: round trip, a save killed part way, ordering against
/// clear(), and the one-time migration from the legacy single-file snapshot.
@MainActor
final class LibrarySnapshotChunkedTests: XCTestCase {

    private final class InMemoryStore: Nostalgex.CredentialStoring, @unchecked Sendable {
        var values: [String: String] = [:]
        @discardableResult
        func save(key: String, value: String) -> Bool { values[key] = value; return true }
        func load(key: String) -> String? { values[key] }
        func delete(key: String) { values[key] = nil }
    }

    private static let serverID = "plex-machine-chunks"
    private static let identity = "plex|\(serverID)"
    private var savedLegacyCap: UInt64 = 0

    override func setUp() {
        super.setUp()
        savedLegacyCap = LibrarySnapshotStore.legacyMaxBytes
        LibrarySnapshotStore.afterChunkWritten = nil
        LibrarySnapshotStore.clear()
    }

    override func tearDown() {
        LibrarySnapshotStore.afterChunkWritten = nil
        LibrarySnapshotStore.legacyMaxBytes = savedLegacyCap
        LibrarySnapshotStore.waitForPendingSaves()
        LibrarySnapshotStore.clear()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func items(_ n: Int, tag: String = "A") -> [PlexMediaItem] {
        (0..<n).map { i in
            PlexMediaItem(
                id: "\(Self.serverID):\(100_000 + i)", title: "\(tag) Title \(i)", artist: i % 7 == 0 ? "Artist \(i % 50)" : nil,
                episodeTitle: i % 3 == 0 ? "Episode \(i)" : nil, seTag: i % 3 == 0 ? "S01E\(i % 22 + 1)" : nil,
                summary: "Summary for \(i) with \"quotes\" and unicode é ✓", year: 1950 + i % 70,
                originallyAvailableAt: i % 2 == 0 ? "1999-01-0\(i % 9 + 1)" : nil, contentRating: i % 4 == 0 ? "R" : "PG",
                duration: 20 + i % 120, ratingKey: "\(100_000 + i)", partKey: "/library/parts/\(i)/file.mkv",
                container: "mkv", videoCodec: i % 2 == 0 ? "hevc" : "h264", audioCodec: "eac3", videoProfile: "main 10",
                bitrate: 1_000 + i, genres: ["Drama", "Comedy \(i % 5)"], rating: Double(i % 100) / 10, userRating: 0,
                type: i % 3 == 0 ? .episode : .movie, thumb: "/t/\(i)", art: nil, viewCount: i % 4, addedAt: 1_600_000_000 + i,
                studio: i % 2 == 0 ? "Studio \(i % 13)" : nil, tmdbID: i % 5 == 0 ? "\(i)" : nil, imdbID: nil,
                librarySource: i % 3 == 0 ? .tv : .movie, serverID: Self.serverID,
                videoBitDepth: 10, doviProfile: nil, videoWidth: 1920, videoHeight: 1080)
        }
    }

    private struct Fixture {
        let items: [PlexMediaItem]
        let channels: [Channel]
        let collections: [DiscoveredCollection]
        let bundles: [ChannelBundle]
    }

    private func fixture(_ n: Int, tag: String = "A") -> Fixture {
        let all = items(n, tag: tag)
        let channels = (0..<5).map { c in
            Channel(id: 10 + c, number: 100 + c, name: "CH \(c)", color: .blue, category: "Test",
                    rules: nil, timeRestrictions: nil, minItems: 0,
                    itemPool: all.enumerated().filter { $0.offset % (c + 2) == 0 }.map(\.element))
        }
        let collections = [DiscoveredCollection(id: "col-1", title: "TRILOGY", movieCount: 3,
                                                 items: Array(all.suffix(3)), enabled: true, matchedChannel: "CH 1")]
        let bundles = [ChannelBundle(id: "nostalgex", name: "Nostalgex", description: nil, channelIDs: [10, 11], activeMonths: nil)]
        return Fixture(items: all, channels: channels, collections: collections, bundles: bundles)
    }

    private func save(_ f: Fixture, signature: String? = "sig-1", lastLoad: Int = Int(Date().timeIntervalSince1970)) throws {
        try LibrarySnapshotStore.save(
            identity: Self.identity, serverName: "Vault", librarySignature: signature, lastLoadAtUnix: lastLoad,
            allItems: f.items, channelConfigChannels: f.channels, allChannels: f.channels, bundles: f.bundles,
            enabledBundleIDs: ["nostalgex"], exclusiveRules: [], discoveredCollections: f.collections)
    }

    private func payload(_ f: Fixture) -> LibrarySnapshotStore.Payload {
        LibrarySnapshotStore.makePayload(
            identity: Self.identity, serverName: "Vault", librarySignature: "sig", lastLoadAtUnix: Int(Date().timeIntervalSince1970),
            allItems: f.items, channelConfigChannels: f.channels, allChannels: f.channels, bundles: f.bundles,
            enabledBundleIDs: ["nostalgex"], exclusiveRules: [], discoveredCollections: f.collections)
    }

    private func generationDirectories() -> [String] {
        guard let dir = LibrarySnapshotStore.snapshotDirectoryURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasPrefix("g-") }.sorted()
    }

    /// The old writer, verbatim: one JSON document, schemaVersion 2, one atomic file.
    private func writeLegacyFile(_ f: Fixture) throws -> Int {
        let snap = LibrarySnapshotV1(
            schemaVersion: 2, credentialFingerprint: LibrarySnapshotStore.fingerprint(identity: Self.identity),
            lastLoadAtUnix: Int(Date().timeIntervalSince1970), serverName: "Vault", allItems: f.items,
            channelConfigRows: f.channels.map { $0.toStoredChannel(includeItemKeys: false) },
            allChannelRows: f.channels.map { $0.toStoredChannel(includeItemKeys: true) },
            bundleDefinitions: [], enabledBundleIDList: ["nostalgex"], exclusiveRuleJSON: [],
            discoveredCollectionRows: f.collections.map { StoredDiscoveredCollection.from($0) },
            librarySignature: "legacy-sig")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snap)
        try data.write(to: LibrarySnapshotStore.legacySnapshotURL!, options: .atomic)
        return data.count
    }

    private func assertMatches(_ snap: LibrarySnapshotV1, _ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(snap.allItems, f.items, "items round-trip in order, field for field", file: file, line: line)
        XCTAssertEqual(snap.allChannelRows.map(\.id), f.channels.map(\.id), file: file, line: line)
        for (row, channel) in zip(snap.allChannelRows, f.channels) {
            XCTAssertEqual(row.itemRatingKeys, channel.itemPool.map(\.id), "CH \(channel.number) pool", file: file, line: line)
        }
        XCTAssertEqual(snap.channelConfigRows.map(\.name), f.channels.map(\.name), file: file, line: line)
        XCTAssertTrue(snap.channelConfigRows.allSatisfy { $0.itemRatingKeys.isEmpty }, file: file, line: line)
        XCTAssertEqual(snap.discoveredCollectionRows.map(\.itemRatingKeys), f.collections.map { $0.items.map(\.id) }, file: file, line: line)
    }

    // MARK: - Round trip

    /// 25,001 items: two full chunks and a ragged third.
    func testChunkedRoundTripEqualsOriginal() throws {
        let f = fixture(2 * LibrarySnapshotStore.chunkSize + 5_001)
        try save(f)

        XCTAssertEqual(generationDirectories().count, 1)
        let gen = generationDirectories()[0]
        let files = try FileManager.default.contentsOfDirectory(
            atPath: LibrarySnapshotStore.snapshotDirectoryURL!.appendingPathComponent(gen).path).sorted()
        XCTAssertEqual(files, ["items-0000.json", "items-0001.json", "items-0002.json", "meta.json"])

        let loaded = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: Self.identity))
        XCTAssertFalse(loaded.isStale)
        XCTAssertFalse(loaded.fromLegacyFile)
        XCTAssertEqual(loaded.snapshot.serverName, "Vault")
        XCTAssertEqual(loaded.snapshot.librarySignature, "sig-1")
        XCTAssertEqual(loaded.snapshot.enabledBundleIDList, ["nostalgex"])
        XCTAssertEqual(loaded.snapshot.bundleDefinitions.map(\.id), ["nostalgex"])
        assertMatches(loaded.snapshot, f)
    }

    /// Found franchises and the collection fold label ride in meta.json as item indexes,
    /// and come back as the same rating keys.
    func testFoundFranchisesAndFoldRoundTripThroughChunks() throws {
        let all = items(LibrarySnapshotStore.chunkSize + 40)
        let movies = Array(all.prefix(3))
        let tv = Array(all.suffix(4))
        let franchises = [
            FoundFranchise(id: "dict:JOHN WICK", name: "JOHN WICK", movies: movies, tvItems: tv,
                           coveredByChannelID: nil, fromDictionary: true, enabled: true),
            FoundFranchise(id: "tmdb:10", name: "STAR WARS", movies: [all[5]], tvItems: [],
                           coveredByChannelID: 100, fromDictionary: true, enabled: false),
        ]
        var collection = DiscoveredCollection(id: "col-wick", title: "JOHN WICK", movieCount: 3,
                                              items: movies, enabled: false, matchedChannel: nil)
        collection.foldedIntoFranchise = "JOHN WICK"
        try LibrarySnapshotStore.save(
            identity: Self.identity, serverName: "Vault", librarySignature: "sig", lastLoadAtUnix: Int(Date().timeIntervalSince1970),
            allItems: all, channelConfigChannels: [], allChannels: [], bundles: [],
            enabledBundleIDs: [], exclusiveRules: [], discoveredCollections: [collection],
            foundFranchises: franchises)

        let snap = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: Self.identity)).snapshot
        let rows = try XCTUnwrap(snap.foundFranchiseRows)
        XCTAssertEqual(rows.map(\.id), ["dict:JOHN WICK", "tmdb:10"])
        XCTAssertEqual(rows[0].movieRatingKeys, movies.map(\.id))
        XCTAssertEqual(rows[0].tvRatingKeys, tv.map(\.id))
        XCTAssertEqual(rows[1].movieRatingKeys, [all[5].id])
        XCTAssertEqual(rows[1].coveredByChannelID, 100)
        XCTAssertEqual(snap.discoveredCollectionRows.first?.foldedIntoFranchise, "JOHN WICK")
    }

    /// A 1.0.26 meta.json has no franchise fields; it restores as "nothing found yet".
    func testSnapshotWithoutFranchisesRestoresAsNoneFound() throws {
        let f = fixture(20)
        try save(f)
        let metaURL = LibrarySnapshotStore.snapshotDirectoryURL!
            .appendingPathComponent(generationDirectories()[0]).appendingPathComponent("meta.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metaURL)) as? [String: Any])
        XCTAssertNotNil(json["foundFranchiseRows"])
        for key in ["foundFranchiseRows", "foundFranchiseMovieItems", "foundFranchiseTVItems"] { json[key] = nil }
        try JSONSerialization.data(withJSONObject: json).write(to: metaURL)

        let snap = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: Self.identity)).snapshot
        XCTAssertNil(snap.foundFranchiseRows)
        XCTAssertNil(snap.discoveredCollectionRows.first?.foldedIntoFranchise)
        assertMatches(snap, f)
    }

    func testEmptyLibraryRoundTrips() throws {
        let f = Fixture(items: [], channels: [], collections: [], bundles: [])
        try save(f)
        let loaded = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: Self.identity))
        XCTAssertTrue(loaded.snapshot.allItems.isEmpty)
    }

    func testOtherIdentityGetsNothingAndKeepsTheFiles() throws {
        try save(fixture(50))
        XCTAssertNil(try LibrarySnapshotStore.loadSnapshot(identity: "plex|another-server"))
        XCTAssertNotNil(try LibrarySnapshotStore.loadSnapshot(identity: Self.identity))
    }

    func testOldSnapshotReadsAsStale() throws {
        try save(fixture(50), lastLoad: Int(Date().timeIntervalSince1970) - LibrarySnapshotStore.refreshAfterSeconds - 60)
        let loaded = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: Self.identity))
        XCTAssertTrue(loaded.isStale)
        XCTAssertNil(try LibrarySnapshotStore.loadIfValid(identity: Self.identity))
    }

    // MARK: - Killed mid-save

    private struct Killed: Error {}

    /// A second save that dies after its first chunk (jetsam, a crash, a force quit) must
    /// leave the first snapshot exactly as it was. Never zero snapshots.
    func testKillMidSaveLeavesPreviousSnapshot() throws {
        let first = fixture(2 * LibrarySnapshotStore.chunkSize + 10, tag: "FIRST")
        try save(first, signature: "first")

        // The hook copies the half-written generation aside before failing, so the files a
        // real kill would leave behind (no defer runs under jetsam) stay on disk too.
        let root = LibrarySnapshotStore.snapshotDirectoryURL!
        let liveGeneration = generationDirectories()[0]
        LibrarySnapshotStore.afterChunkWritten = { index in
            guard index == 1 else { return }
            let fm = FileManager.default
            for name in try fm.contentsOfDirectory(atPath: root.path) where name.hasPrefix("g-") && name != liveGeneration {
                try fm.copyItem(at: root.appendingPathComponent(name), to: root.appendingPathComponent("g-KILLED"))
            }
            throw Killed()
        }
        let second = fixture(3 * LibrarySnapshotStore.chunkSize, tag: "SECOND")
        XCTAssertThrowsError(try save(second, signature: "second"))
        LibrarySnapshotStore.afterChunkWritten = nil
        XCTAssertTrue(generationDirectories().contains("g-KILLED"), "the partial write is on disk, as after a real kill")

        let loaded = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: Self.identity),
                                   "a killed save must not leave the device with no snapshot")
        XCTAssertEqual(loaded.snapshot.librarySignature, "first")
        assertMatches(loaded.snapshot, first)

        // The next good save sweeps the leftovers.
        let third = fixture(120, tag: "THIRD")
        try save(third, signature: "third")
        XCTAssertEqual(generationDirectories().count, 1, "leftover generations are removed: \(generationDirectories())")
        let after = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: Self.identity))
        XCTAssertEqual(after.snapshot.librarySignature, "third")
        assertMatches(after.snapshot, third)
    }

    /// A manifest pointing at a chunk that is gone (storage purge, disk trouble) is an
    /// error, not a short library: the caller falls back to a scan.
    func testMissingChunkThrowsInsteadOfRestoringAShortLibrary() throws {
        try save(fixture(LibrarySnapshotStore.chunkSize + 10))
        let gen = LibrarySnapshotStore.snapshotDirectoryURL!.appendingPathComponent(generationDirectories()[0])
        try FileManager.default.removeItem(at: gen.appendingPathComponent("items-0001.json"))
        XCTAssertThrowsError(try LibrarySnapshotStore.loadSnapshot(identity: Self.identity))
    }

    // MARK: - Ordering

    func testNewerBackgroundSaveWins() throws {
        let a = fixture(300, tag: "A"), b = fixture(200, tag: "B")
        LibrarySnapshotStore.saveInBackground(payload(a))
        LibrarySnapshotStore.saveInBackground(payload(b))
        LibrarySnapshotStore.waitForPendingSaves()
        let loaded = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: Self.identity))
        assertMatches(loaded.snapshot, b)
        XCTAssertEqual(generationDirectories().count, 1)
    }

    /// Disconnect while a save is queued or running: the clear wins, whatever the timing.
    func testClearDuringBackgroundSaveLeavesNothing() throws {
        for _ in 0..<5 {
            LibrarySnapshotStore.saveInBackground(payload(fixture(LibrarySnapshotStore.chunkSize + 500)))
            LibrarySnapshotStore.clear()
            LibrarySnapshotStore.waitForPendingSaves()
            XCTAssertNil(try LibrarySnapshotStore.loadSnapshot(identity: Self.identity))
        }
    }

    // MARK: - Legacy single-file migration

    func testLegacyFileLoadsOnceThenIsReplacedByChunks() async throws {
        let f = fixture(1_200)
        _ = try writeLegacyFile(f)

        let store = InMemoryStore()
        let state = AppState(credentialStore: store)
        state.completePlexSignIn(token: "plex-account-token", servers: [
            AppState.ServerRef(machineIdentifier: Self.serverID, name: "Vault", baseURL: "http://127.0.0.1:9", owned: true, token: "srv")
        ])
        XCTAssertEqual(state.snapshotIdentitySeed, Self.identity)

        let restored = await state.restoreLibraryFromSnapshotIfNeeded()
        XCTAssertTrue(restored, "a legacy snapshot under the migration cap restores")
        XCTAssertEqual(state.allItems.count, f.items.count)
        XCTAssertEqual(state.librarySignature, "legacy-sig")

        // The restore re-saved it in the new format; that commit deletes the old file.
        LibrarySnapshotStore.waitForPendingSaves()
        XCTAssertFalse(FileManager.default.fileExists(atPath: LibrarySnapshotStore.legacySnapshotURL!.path),
                       "legacy file is gone after the migration save")
        let loaded = try XCTUnwrap(LibrarySnapshotStore.loadSnapshot(identity: Self.identity))
        XCTAssertFalse(loaded.fromLegacyFile)
        XCTAssertEqual(loaded.snapshot.allItems.count, f.items.count)
        XCTAssertEqual(loaded.snapshot.librarySignature, "legacy-sig")
        XCTAssertEqual(Set(loaded.snapshot.allItems.map(\.id)), Set(f.items.map(\.id)))
    }

    func testLegacyFileOverTheCapIsDiscardedForOneRescan() throws {
        let bytes = try writeLegacyFile(fixture(400))
        LibrarySnapshotStore.legacyMaxBytes = UInt64(bytes - 1)
        XCTAssertNil(try LibrarySnapshotStore.loadSnapshot(identity: Self.identity))
        XCTAssertFalse(FileManager.default.fileExists(atPath: LibrarySnapshotStore.legacySnapshotURL!.path),
                       "an oversized legacy file is deleted so it is never decoded")
    }

    func testClearRemovesLegacyFileToo() throws {
        _ = try writeLegacyFile(fixture(10))
        LibrarySnapshotStore.clear()
        XCTAssertNil(try LibrarySnapshotStore.loadSnapshot(identity: Self.identity))
    }
}
