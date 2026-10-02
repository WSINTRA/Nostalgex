package app.nostalgex.filter

import app.nostalgex.model.Channel
import app.nostalgex.model.ChannelRules
import app.nostalgex.model.LibrarySource
import app.nostalgex.model.MediaItem

/**
 * Decides which library items belong on a channel. Pure: no I/O, no clock.
 * Semantics follow scripts/nostalgex-channel-filter.cjs (itself in parity with tvOS
 * `AppState+Channels.filterItems`). Each check is a small named function so it can be
 * read and tested on its own.
 */
class ChannelFilter {

    fun pool(library: List<MediaItem>, channel: Channel): List<MediaItem> =
        library.filter { passes(it, channel) }

    fun passes(item: MediaItem, channel: Channel): Boolean {
        val rules = channel.rules
        val genres = item.genres.map { it.lowercase() }
        return passesSource(item, rules) &&
            passesFamilySafety(item, channel) &&
            passesGenreLocks(genres, rules, channel) &&
            passesType(item, rules) &&
            passesYear(item, rules) &&
            passesContentRatings(item, rules) &&
            passesDuration(item, rules) &&
            passesGenreExcludeAndRequireAll(genres, rules) &&
            passesContentMatch(item, genres, rules)
    }

    // --- individual checks (internal for focused tests) ---

    internal fun passesSource(item: MediaItem, rules: ChannelRules): Boolean {
        val itemSource = item.librarySource ?: LibrarySource.MOVIE
        return if (rules.source != null) itemSource == rules.source else itemSource != LibrarySource.MUSIC_VIDEO
    }

    internal fun passesFamilySafety(item: MediaItem, channel: Channel): Boolean {
        val familySafe = channel.category == "kids" ||
            includeList(channel.rules).any { it.equals("family", ignoreCase = true) }
        return !(familySafe && item.contentRating in ADULT_RATINGS)
    }

    internal fun passesGenreLocks(itemGenres: List<String>, rules: ChannelRules, channel: Channel): Boolean {
        val studioChannel = !rules.studios.isNullOrEmpty() && includeList(rules).isEmpty()
        val curatedByTitle = !rules.titleContains.isNullOrEmpty()
        return GenreLock.entries.none { lock ->
            val itemHasLocked = itemGenres.any { it in lock.genres }
            val channelOptsIn = studioChannel || includes(rules, lock) ||
                (lock == GenreLock.ANIMATION && (channel.category == "kids" || curatedByTitle))
            itemHasLocked && !channelOptsIn
        } && passesExplicitReality(itemGenres, rules)
    }

    private fun passesExplicitReality(itemGenres: List<String>, rules: ChannelRules): Boolean =
        !includes(rules, GenreLock.REALITY) || itemGenres.any { it in GenreLock.REALITY.genres }

    internal fun passesType(item: MediaItem, rules: ChannelRules) = rules.type == null || item.type == rules.type

    internal fun passesYear(item: MediaItem, rules: ChannelRules): Boolean {
        val range = rules.yearRange ?: return true
        val year = releaseYear(item) ?: return true
        return (range.min == null || year >= range.min!!) && (range.max == null || year <= range.max!!)
    }

    internal fun passesContentRatings(item: MediaItem, rules: ChannelRules): Boolean {
        val allowed = rules.contentRatings
        if (allowed.isNullOrEmpty()) return true
        val rating = item.contentRating.orEmpty()
        return if (rating.isEmpty() && rules.allowUnrated) true else rating in allowed
    }

    internal fun passesDuration(item: MediaItem, rules: ChannelRules): Boolean {
        val range = rules.durationRange ?: return true
        return (range.min == null || item.durationMinutes >= range.min!!) &&
            (range.max == null || item.durationMinutes <= range.max!!)
    }

    internal fun passesGenreExcludeAndRequireAll(itemGenres: List<String>, rules: ChannelRules): Boolean {
        val g = rules.genres ?: return true
        if (g.exclude.any { e -> itemGenres.any { it.contains(e.lowercase()) } }) return false
        return g.requireAll.all { r -> itemGenres.any { it.contains(r.lowercase()) } }
    }

    /** Studio and genre-include rules. (Title rules arrive in the next commit.) */
    internal fun passesContentMatch(item: MediaItem, itemGenres: List<String>, rules: ChannelRules): Boolean {
        val include = includeList(rules)
        val hasStudio = !rules.studios.isNullOrEmpty()
        val hasGenre = include.isNotEmpty()
        if (!hasStudio && !hasGenre) return true
        val studioOk = !hasStudio || matchesStudio(item, rules.studios!!)
        val genreOk = !hasGenre || itemGenres.any { g -> include.any { g.contains(it.lowercase()) } }
        return studioOk && genreOk
    }

    // --- helpers ---

    private fun matchesStudio(item: MediaItem, studios: List<String>): Boolean =
        item.studios.any { s -> studios.any { s.lowercase().contains(it.lowercase()) } }

    private fun includeList(rules: ChannelRules) = rules.genres?.include.orEmpty()

    private fun includes(rules: ChannelRules, lock: GenreLock) =
        includeList(rules).any { it.lowercase() in lock.genres }

    /** Item year, else the year of its premiere date (`YYYY-MM-DD`). */
    internal fun releaseYear(item: MediaItem): Int? =
        item.year ?: item.premiereDate?.let { PREMIERE_YEAR.find(it)?.groupValues?.get(1)?.toInt() }

    private companion object {
        val PREMIERE_YEAR = Regex("""^(\d{4})-\d{2}-\d{2}""")
    }
}
