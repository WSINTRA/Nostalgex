import XCTest
@testable import Nostalgex

/// Hits the real Deezer API. Skipped unless TEST_RUNNER_NOSTALGEX_DEEZER_LIVE=1, so CI
/// never depends on it; run it by hand when the parser or the genre map changes.
final class DeezerLiveHarness: XCTestCase {
    func testRealTitlesFromTheLibraryResolveWithGenres() async throws {
        guard ProcessInfo.processInfo.environment["NOSTALGEX_DEEZER_LIVE"] == "1" else {
            throw XCTSkip("set NOSTALGEX_DEEZER_LIVE=1 to hit api.deezer.com")
        }
        let titles = ["Ruff_Ryders_-_Get_Wild_[MMV]", "Slipknot - Snuff (2009)", "Chicken_Fried",
                      "Nelly ft. Akon ft. Ashanti - Body On Me", "Beatles - I'm A Loser - Boys(Shindig 1964)", "Anaconda"]
        let deezer = DeezerService()
        var withGenres = 0
        for t in titles {
            let p = MusicTitleParser.parse(t)
            let m = try await deezer.resolve(song: p.song, artist: p.artist)
            print("[DEEZER] \(t) -> \(m.map { "\($0.artist) / \($0.title) \($0.rawGenres) -> \($0.genres) \($0.releaseYear ?? 0)" } ?? "NO MATCH")")
            if let m, !m.genres.isEmpty { withGenres += 1 }
        }
        XCTAssertGreaterThanOrEqual(withGenres, 5, "expected the measured sample to resolve")
    }
}
