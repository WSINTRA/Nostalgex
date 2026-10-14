import XCTest
@testable import Nostalgex

/// Tests for "pick the highest-quality version" (Change: prefer best media instead of the
/// first). Mirrors the decode-based style of JellyfinAPITests.
final class VersionPickerTests: XCTestCase {

    // MARK: - Jellyfin

    private func decodeJellyfin(_ json: String) throws -> JellyfinItem {
        try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))
    }
    private func jfService() -> JellyfinAPIService {
        JellyfinAPIService(serverURL: "http://jelly.local:8096", accessToken: "TKN", userId: "u", serverID: "s")
    }

    func testJellyfinPicksHighestBitrateSource() throws {
        let item = try decodeJellyfin("""
        { "Id": "m1", "Name": "Heat", "RunTimeTicks": 60000000000,
          "MediaSources": [
            { "Id": "sd",  "Container": "mp4", "Bitrate": 4000000,  "MediaStreams": [ {"Type":"Video","Codec":"h264","Height":1080} ] },
            { "Id": "uhd", "Container": "mkv", "Bitrate": 20000000, "MediaStreams": [ {"Type":"Video","Codec":"hevc","Height":2160} ] }
          ] }
        """)
        let mapped = try XCTUnwrap(jfService().parseMovieItem(item, isMusicSection: false))
        XCTAssertEqual(mapped.partKey, "uhd")   // MediaSourceId of the chosen high-bitrate source
        XCTAssertEqual(mapped.bitrate, 20000)   // bps -> kbps
        XCTAssertEqual(mapped.container, "mkv")
        XCTAssertEqual(mapped.videoCodec, "hevc")
    }

    func testJellyfinTieBreaksByHeight() throws {
        let item = try decodeJellyfin("""
        { "Id":"m","Name":"X","MediaSources":[
          {"Id":"a","Bitrate":5000000,"MediaStreams":[{"Type":"Video","Height":720}]},
          {"Id":"b","Bitrate":5000000,"MediaStreams":[{"Type":"Video","Height":1080}]}
        ]}
        """)
        XCTAssertEqual(JellyfinItem.bestMediaSource(item.MediaSources)?.Id, "b")
    }

    func testJellyfinFallsBackToFirstWhenNoBitrate() throws {
        let item = try decodeJellyfin("""
        { "Id":"m","Name":"X","MediaSources":[
          {"Id":"a","MediaStreams":[{"Type":"Video","Height":480}]},
          {"Id":"b","MediaStreams":[{"Type":"Video","Height":1080}]}
        ]}
        """)
        XCTAssertEqual(JellyfinItem.bestMediaSource(item.MediaSources)?.Id, "a")
    }

    // MARK: - Plex

    private func decodePlex(_ json: String) throws -> PlexRawItem {
        try JSONDecoder().decode(PlexRawItem.self, from: Data(json.utf8))
    }

    func testPlexPicksHighestBitrateMedia() throws {
        let item = try decodePlex("""
        { "ratingKey": "1", "title": "X", "Media": [
          { "bitrate": 4000,  "videoResolution": "1920x1080", "Part": [{"key": "/sd"}] },
          { "bitrate": 12000, "videoResolution": "3840x2160", "Part": [{"key": "/4k"}] }
        ] }
        """)
        let best = try XCTUnwrap(item.bestMedia)
        XCTAssertEqual(best.Part?.first?.key, "/4k")
        XCTAssertEqual(best.bitrate, 12000)
        XCTAssertEqual(item.bestMediaIndex, 1)
    }

    func testPartDescriptorsKeepDurationAndOwnCodecs() throws {
        let item = try decodePlex("""
        {"ratingKey":"1","title":"X","Media":[{"container":"mkv","videoCodec":"hevc","audioCodec":"aac","Part":[
          {"key":"/one","duration":60000,"Stream":[{"streamType":1,"codec":"hevc","bitDepth":10,"DOVIProfile":7}]},
          {"key":"/two","duration":120000,"container":"mp4","Stream":[{"streamType":1,"codec":"h264","bitDepth":8},{"streamType":2,"codec":"ac3"}]},
          {"key":"/three","duration":30000}
        ]}]}
        """)
        let parts = try XCTUnwrap(item.bestMedia?.playbackParts)
        XCTAssertEqual(parts.map(\.key), ["/one","/two","/three"])
        XCTAssertEqual(parts.map(\.durationSeconds), [60,120,30])
        XCTAssertEqual(parts[1].container, "mp4"); XCTAssertEqual(parts[1].videoCodec, "h264")
        XCTAssertEqual(parts[1].audioCodec, "ac3"); XCTAssertNil(parts[1].doviProfile)
    }

    func testPlexTieBreaksByResolution() throws {
        let item = try decodePlex("""
        { "ratingKey": "1", "title": "X", "Media": [
          { "bitrate": 8000, "videoResolution": "1280x720", "Part": [{"key": "/720"}] },
          { "bitrate": 8000, "videoResolution": "1920x1080", "Part": [{"key": "/1080"}] }
        ] }
        """)
        XCTAssertEqual(item.bestMedia?.Part?.first?.key, "/1080")
    }

    func testPlexFallsBackToFirstWhenNoBitrate() throws {
        let item = try decodePlex("""
        { "ratingKey": "1", "title": "X", "Media": [
          { "videoResolution": "720",  "Part": [{"key": "/a"}] },
          { "videoResolution": "1080", "Part": [{"key": "/b"}] }
        ] }
        """)
        XCTAssertEqual(item.bestMedia?.Part?.first?.key, "/a")
    }
}
