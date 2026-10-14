import XCTest
@testable import Nostalgex

/// Plex films keep their real titles. The "Artist - Song" parser is for music videos;
/// run on every film it showed "Star Wars: Episode I - The Phantom Menace" as
/// "The Phantom Menace", "Breaking Dawn - Part 1" as "Part 1" and "Spider-Man" as "Man"
/// (all seen in a real library's guide), and hid them from title-matched channels.
final class PlexMovieTitleTests: XCTestCase {

    private func movie(_ title: String, minutes: Int = 120, genres: [String] = ["Action"]) throws -> PlexRawItem {
        let genreJSON = genres.map { #"{"tag":"\#($0)"}"# }.joined(separator: ",")
        let json = """
        {"ratingKey":"1","title":"\(title)","duration":\(minutes * 60000),"Genre":[\(genreJSON)]}
        """
        return try JSONDecoder().decode(PlexRawItem.self, from: Data(json.utf8))
    }

    private let api = PlexAPIService(serverURL: "https://server", token: "tok")

    func testFilmsKeepTheirFullTitle() throws {
        let titles = [
            "Star Wars: Episode I - The Phantom Menace",
            "The Twilight Saga: Breaking Dawn - Part 1",
            "The Hunger Games: Mockingjay - Part 1",
            "Mission: Impossible - Fallout",
            "Spider-Man",
            "X-Men",
        ]
        for title in titles {
            let item = try XCTUnwrap(api.parseMovieItem(try movie(title), isMusicSection: false))
            XCTAssertEqual(item.title, title)
            XCTAssertNil(item.artist, "\(title) is a film, not a music video")
            XCTAssertEqual(item.librarySource, .movie)
        }
    }

    func testMusicVideosStillSplitArtistAndSong() throws {
        let inSection = try XCTUnwrap(api.parseMovieItem(try movie("Toto - Africa", minutes: 5), isMusicSection: true))
        XCTAssertEqual(inSection.title, "Africa")
        XCTAssertEqual(inSection.artist, "Toto")

        // A short Music-genre item in a regular library is treated as a music video too.
        let fallback = try XCTUnwrap(api.parseMovieItem(
            try movie("a-ha - Take On Me", minutes: 4, genres: ["Music"]), isMusicSection: false))
        XCTAssertEqual(fallback.title, "Take On Me")
        XCTAssertEqual(fallback.artist, "a-ha")
    }

    func testHungerGamesCollectionIsAFranchiseWithRealTitles() throws {
        let titles = ["The Hunger Games: Catching Fire",
                      "The Hunger Games: Mockingjay - Part 1",
                      "The Hunger Games: Mockingjay - Part 2"]
        let items = try titles.map { try XCTUnwrap(api.parseMovieItem(try movie($0), isMusicSection: false)) }
        XCTAssertEqual(CollectionClassifier.classify(title: "Hunger Games", items: items), .franchises)
    }
}
