import Testing
import Foundation
@testable import Nostalgex

/// Exclusive rules lock content to specific channels by blocking it from every
/// other channel. When an editorial title fails to match, the title does not
/// disappear, it leaks onto channels it was meant to be kept off. That failure
/// is silent, which is why it went unnoticed: HOLIDAZE carries 49 editorial
/// titles and SCREAM ADULTS carries 8, and Plex's TMDB agent routinely stores
/// films with a " (YYYY)" suffix that the exact match did not account for.
struct ExclusiveRuleTests {

    private func movie(_ title: String, genres: [String] = []) -> PlexMediaItem {
        PlexMediaItem(
            id: "1",
            title: title,
            artist: nil,
            episodeTitle: nil,
            seTag: nil,
            summary: "",
            year: nil,
            originallyAvailableAt: nil,
            contentRating: nil,
            duration: 90,
            ratingKey: "1",
            partKey: nil,
            container: "mkv",
            videoCodec: nil,
            audioCodec: nil,
            videoProfile: nil,
            bitrate: nil,
            genres: genres,
            rating: 0,
            userRating: 0,
            type: .movie,
            thumb: nil,
            art: nil,
            viewCount: 0,
            addedAt: 0,
            studio: nil,
            tmdbID: nil,
            imdbID: nil,
            librarySource: .movie
        )
    }

    private var holidazeRule: ExclusiveRule {
        ExclusiveRule(
            channelIDs: [130],
            genres: ["Holiday", "Christmas"],
            titleContains: ["Christmas", "Santa"],
            editorialTitles: ["Elf", "Home Alone", "It's a Wonderful Life"],
            manifestExclusive: false
        )
    }

    @Test func editorialTitleMatchesExactly() {
        #expect(holidazeRule.matches(movie("Elf")))
        #expect(holidazeRule.matches(movie("home alone")))
    }

    // The regression: Plex stores "Elf (2003)", the config says "Elf".
    @Test func editorialTitleMatchesDespitePlexYearSuffix() {
        #expect(holidazeRule.matches(movie("Elf (2003)")))
        #expect(holidazeRule.matches(movie("Home Alone (1990)")))
        #expect(holidazeRule.matches(movie("It's a Wonderful Life (1946)")))
    }

    @Test func unrelatedTitleIsNotClaimed() {
        #expect(!holidazeRule.matches(movie("Die Hard (1988)")))
        #expect(!holidazeRule.matches(movie("Elf Quest (1999)")))
    }

    // A year in the middle of a title is part of the title, not a Plex suffix.
    @Test func onlyATrailingYearSuffixIsIgnored() {
        let rule = ExclusiveRule(
            channelIDs: [130],
            genres: [],
            titleContains: [],
            editorialTitles: ["Blade Runner 2049"],
            manifestExclusive: false
        )
        #expect(rule.matches(movie("Blade Runner 2049")))
        #expect(rule.matches(movie("Blade Runner 2049 (2017)")))
    }

    // Title words match whole words, like a channel's titleContains. A substring test
    // locked Kicking & Screaming away from every channel and caught Santana with "Santa".
    @Test func titleWordsMatchWholeWordsOnly() {
        let scream = ExclusiveRule(channelIDs: [132], genres: [], titleContains: ["Scream"],
                                   editorialTitles: [], manifestExclusive: false)
        #expect(!scream.matches(movie("Kicking & Screaming (2005)")))
        #expect(scream.matches(movie("Scream 4")))
        #expect(!holidazeRule.matches(movie("Santana")))
        #expect(holidazeRule.matches(movie("The Santa Clause")))
        let holiday = ExclusiveRule(channelIDs: [130], genres: [], titleContains: ["Holiday"],
                                    editorialTitles: [], manifestExclusive: false)
        #expect(!holiday.matches(movie("Holidays (2016)")))
        #expect(holiday.matches(movie("Holiday Inn")))
    }

    // A music video's artist is not part of its title, on either platform.
    @Test func aMusicVideoLockReadsTheSongNotTheArtist() {
        var video = movie("Smooth")
        video = PlexMediaItem(
            id: video.id, title: video.title, artist: "Santana", episodeTitle: nil, seTag: nil,
            summary: "", year: nil, originallyAvailableAt: nil, contentRating: nil, duration: 4,
            ratingKey: "1", partKey: nil, container: nil, videoCodec: nil, audioCodec: nil,
            videoProfile: nil, bitrate: nil, genres: [], rating: 0, userRating: 0, type: .movie,
            thumb: nil, art: nil, viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: .musicVideo
        )
        #expect(!holidazeRule.matches(video))
    }

    // A scoped lock (type + source) only applies to films in a movie library. The
    // holiday lock used to read show names and song titles too, and locked them to
    // movie channels that can never air them.
    @Test func aScopedLockSkipsEpisodesAndMusicVideos() {
        let scoped = ExclusiveRule(channelIDs: [130], genres: [], titleContains: ["Christmas"],
                                   editorialTitles: [], manifestExclusive: false,
                                   type: .movie, source: .movie)
        #expect(scoped.matches(movie("A Christmas Story")))
        let song = PlexMediaItem(
            id: "2", title: "Last Christmas", artist: "Wham!", episodeTitle: nil, seTag: nil,
            summary: "", year: nil, originallyAvailableAt: nil, contentRating: nil, duration: 4,
            ratingKey: "2", partKey: nil, container: nil, videoCodec: nil, audioCodec: nil,
            videoProfile: nil, bitrate: nil, genres: [], rating: 0, userRating: 0, type: .movie,
            thumb: nil, art: nil, viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: .musicVideo
        )
        #expect(!scoped.applies(to: song))
        #expect(!scoped.matches(song))
        let episode = PlexMediaItem(
            id: "3", title: "Christmas Show Name", artist: nil, episodeTitle: "Pilot", seTag: nil,
            summary: "", year: nil, originallyAvailableAt: nil, contentRating: nil, duration: 22,
            ratingKey: "3", partKey: nil, container: nil, videoCodec: nil, audioCodec: nil,
            videoProfile: nil, bitrate: nil, genres: [], rating: 0, userRating: 0, type: .episode,
            thumb: nil, art: nil, viewCount: 0, addedAt: 0, studio: nil, tmdbID: nil, imdbID: nil,
            librarySource: .tv
        )
        #expect(!scoped.matches(episode))
        // Unscoped, the same rule still reads them, as before.
        let unscoped = ExclusiveRule(channelIDs: [130], genres: [], titleContains: ["Christmas"],
                                     editorialTitles: [], manifestExclusive: false)
        #expect(unscoped.matches(song))
        #expect(unscoped.matches(episode))
    }

    @Test func titleContainsAndGenreStillMatch() {
        #expect(holidazeRule.matches(movie("The Christmas Chronicles (2018)")))
        #expect(holidazeRule.matches(movie("Some Winter Film", genres: ["Holiday"])))
        #expect(!holidazeRule.matches(movie("Some Winter Film", genres: ["Drama"])))
    }
}
