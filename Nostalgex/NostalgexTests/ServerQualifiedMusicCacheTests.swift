import XCTest
@testable import Nostalgex

@MainActor
final class ServerQualifiedMusicCacheTests: XCTestCase {
    private func item(_ server: String, source: LibrarySource = .musicVideo) -> PlexMediaItem {
        PlexMediaItem(id: "\(server):42", title: "Song (1988)", artist: nil, episodeTitle: nil, seTag: nil,
            summary: "", year: 1970, originallyAvailableAt: nil, contentRating: nil, duration: 4,
            ratingKey: "42", partKey: "/part", container: "mkv", videoCodec: "hevc", audioCodec: "dts",
            videoProfile: nil, bitrate: nil, genres: [], rating: 0, userRating: 0, type: .movie,
            thumb: nil, art: nil, viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: source, serverID: server, additionalPartKeys: ["/second"],
            videoBitDepth: 10, doviProfile: 8, videoWidth: 3840, videoHeight: 2160)
    }
    private func row(_ title: String) -> MusicVideoEnrichment {
        MusicVideoEnrichment(ratingKey: "42", recordingTitle: title, artist: "Artist", musicBrainzID: nil,
            genres: ["Rock"], releaseYear: 1988, fetchedAt: Date(timeIntervalSince1970: 0))
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testDistinctServerRowsSurviveDiskReloadAndDisplayMerge() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let rows = ["A:42": row("First server"), "B:42": row("Second server")]
        try JSONEncoder().encode(rows).write(to: dir.appendingPathComponent("music_video_enrichments_v2.json"))
        for order in [[item("A"), item("B")], [item("B"), item("A")]] {
            let service = MusicEnrichmentService(cacheDirectory: dir); service.loadDiskCache()
            let output = service.itemsWithDisplayMetadata(order)
            XCTAssertEqual(output.map(\.title), order.map { rows[$0.id]!.recordingTitle })
            XCTAssertEqual(output.map(\.serverID), order.map(\.serverID))
            XCTAssertEqual(service.enrichment(for: item("A"))?.recordingTitle, "First server")
            XCTAssertEqual(service.enrichment(for: item("B"))?.recordingTitle, "Second server")
        }
    }
    func testUnqualifiedLegacyRowsAreNotAssignedToEitherServer() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try JSONEncoder().encode(["42": row("Ambiguous")]).write(to: dir.appendingPathComponent("music_video_enrichments.json"))
        let service = MusicEnrichmentService(cacheDirectory: dir); service.loadDiskCache()
        XCTAssertNil(service.enrichment(for: item("A"))); XCTAssertNil(service.enrichment(for: item("B")))
    }
    func testPoolRefreshKeepsBothServerIdentitiesRegardlessOfInputOrder() {
        let a = item("A"), b = item("B")
        let channel = Channel(id: 1, number: 1, name: "Fixture", color: .blue, category: nil,
            rules: nil, timeRestrictions: nil, minItems: 0, itemPool: [a,b])
        for order in [[a,b],[b,a]] {
            let output = MusicEnrichmentService().refreshChannelPools([channel], from: order)[0].itemPool
            XCTAssertEqual(output.map(\.id), [a.id,b.id])
            XCTAssertEqual(output.map(\.serverID), ["A","B"])
        }
    }
    func testMovieWithMatchingIDDoesNotReceiveMusicMetadata() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try JSONEncoder().encode(["A:42": row("Song title")]).write(to: dir.appendingPathComponent("music_video_enrichments_v2.json"))
        let service = MusicEnrichmentService(cacheDirectory: dir); service.loadDiskCache()
        let movie = item("A", source: .movie)
        XCTAssertEqual(service.itemsWithDisplayMetadata([movie])[0], movie)
    }
    func testMusicCopiesRetainServerAndPlaybackCompatibilityFacts() {
        let original = item("A")
        for copy in [original.applyingMusicEnrichment(row("Enriched")),original.applyingTrustedMusicYear()] {
            XCTAssertEqual(copy.serverID, original.serverID)
            XCTAssertEqual(copy.additionalPartKeys, original.additionalPartKeys)
            XCTAssertEqual(copy.videoBitDepth, 10); XCTAssertEqual(copy.doviProfile, 8)
            XCTAssertEqual(copy.videoWidth, 3840); XCTAssertEqual(copy.videoHeight, 2160)
        }
    }
}
