import XCTest
@testable import Nostalgex

final class LibraryDiagnosticsTests: XCTestCase {
    private func item(_ id: Int, type: MediaType, title: String,
                      genres: [String] = ["Comedy"], tmdb: String? = "123") -> PlexMediaItem {
        PlexMediaItem(id: "\(id)", title: title, artist: nil, episodeTitle: nil, seTag: nil,
                      summary: "", year: 1995, originallyAvailableAt: nil, contentRating: "PG",
                      duration: 90, ratingKey: "\(id)", partKey: nil, container: nil,
                      videoCodec: nil, audioCodec: nil, videoProfile: nil, bitrate: nil,
                      genres: genres, rating: 7, userRating: 0, type: type, thumb: nil, art: nil,
                      viewCount: 0, addedAt: 0, studio: nil, tmdbID: tmdb, imdbID: nil,
                      librarySource: type == .movie ? .movie : .tv, serverID: nil)
    }

    func testEmptyLibrarySaysSoPlainly() {
        XCTAssertEqual(LibraryDiagnostics.summary([]), "No titles loaded — the scan came back empty.")
    }

    func testCountsMoviesEpisodesAndShows() {
        let items = [
            item(1, type: .movie, title: "Jaws"),
            item(2, type: .movie, title: "Alien"),
            item(3, type: .episode, title: "Suits"),
            item(4, type: .episode, title: "Suits"),
            item(5, type: .episode, title: "Lost"),
        ]
        let s = LibraryDiagnostics.summary(items)
        XCTAssertTrue(s.contains("5 titles"), s)
        XCTAssertTrue(s.contains("2 movies"), s)
        XCTAssertTrue(s.contains("3 episodes from 2 shows"), s)
    }

    /// The case that would have ended the Jellyfin thread on day one: a server holding
    /// thousands of titles, an app holding two.
    func testATinyCountIsVisible() {
        let s = LibraryDiagnostics.summary([item(1, type: .movie, title: "Blood Diamond"),
                                            item(2, type: .movie, title: "Shin Godzilla")])
        XCTAssertTrue(s.contains("2 titles"), s)
    }

    func testFlagsUnscrapedMetadata() {
        let items = (0..<4).map { item($0, type: .movie, title: "M\($0)", genres: [], tmdb: nil) }
        let s = LibraryDiagnostics.summary(items)
        XCTAssertTrue(s.contains("0% with genres"), s)
        XCTAssertTrue(s.contains("0% matched to TMDB"), s)
    }

    func testThousandsAreGrouped() {
        let items = (0..<2629).map { item($0, type: $0 < 349 ? .movie : .episode, title: "T\($0 % 80)") }
        XCTAssertTrue(LibraryDiagnostics.summary(items).contains("2,629 titles"))
    }

    func testPercentRounds() {
        XCTAssertEqual(LibraryDiagnostics.pct(1, 3), 33)
        XCTAssertEqual(LibraryDiagnostics.pct(2, 3), 67)
        XCTAssertEqual(LibraryDiagnostics.pct(0, 0), 0)
    }
}
