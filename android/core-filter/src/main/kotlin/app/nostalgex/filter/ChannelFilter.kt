package app.nostalgex.filter

import app.nostalgex.model.Channel
import app.nostalgex.model.ChannelRules
import app.nostalgex.model.LibrarySource
import app.nostalgex.model.ExclusiveRule
import app.nostalgex.model.MediaItem
import java.time.Clock
import java.time.LocalDate
import java.time.ZonedDateTime

/**
 * Decides which library items belong on a channel. Pure: no I/O, no clock.
 * Semantics follow scripts/nostalgex-channel-filter.cjs (itself in parity with tvOS
 * `AppState+Channels.filterItems`). Each check is a small named function so it can be
 * read and tested on its own.
 */
class ChannelFilter(
    private val exclusiveRules: List<ExclusiveRule> = emptyList(),
    private val clock: Clock = Clock.systemDefaultZone(),
) {

    fun pool(library: List<MediaItem>, channel: Channel): List<MediaItem> =
        library.filter { passes(it, channel) }

    fun passes(item: MediaItem, channel: Channel): Boolean {
        val rules = channel.rules
        val genres = item.genres.map { it.lowercase() }
        val title = item.titleWithoutYear.lowercase()
        if (!passesSource(item, rules) ||
            !passesFamilySafety(item, channel) ||
            !passesGenreLocks(genres, rules, channel)
        ) return false

        if (rules.editorialOverrides.orEmpty().any { it.lowercase() == title }) return true
        if (rules.manifestOnly) return false // membership only via a manifest we do not have
        if (rules.titleExcludes.orEmpty().any { containsWord(title, it) }) return false

        return passesExclusivity(item, title, genres, channel.id) &&
            passesType(item, rules) &&
            passesYear(item, rules) &&
            passesContentRatings(item, rules) &&
            passesDuration(item, rules) &&
            passesWatchHistory(item, rules) &&
            passesGenreExcludeAndRequireAll(genres, rules) &&
            passesRecency(item, rules) &&
            passesRatingMin(item, rules) &&
            passesContentMatch(item, title, genres, rules)
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

    internal fun passesExclusivity(item: MediaItem, title: String, genres: List<String>, channelId: Int): Boolean =
        exclusiveRules.none { rule ->
            channelId !in rule.channelIds && (
                rule.editorialTitles.any { it.lowercase() == title } ||
                    rule.titleContains.any { title.contains(it.lowercase()) } ||
                    (rule.genres.isNotEmpty() && genres.any { g -> rule.genres.any { g.contains(it.lowercase()) } })
                )
        }

    internal fun passesWatchHistory(item: MediaItem, rules: ChannelRules): Boolean {
        val year = item.year ?: 0
        val newRelease = year >= currentYear() - 1
        if (rules.watchedOnly && item.viewCount < 1 && !newRelease) return false
        if (rules.unwatchedOnly && (item.viewCount > 0 || newRelease)) return false
        if (rules.rewatched && item.viewCount < 3) return false
        return true
    }

    internal fun passesRecency(item: MediaItem, rules: ChannelRules): Boolean {
        rules.addedWithinDays?.takeIf { it > 0 }?.let { days ->
            if (item.addedAtEpochSec < clock.instant().epochSecond - days * 86_400L) return false
        }
        rules.releasedWithinMonths?.takeIf { it > 0 }?.let { months ->
            val released = item.premiereDate?.let { PREMIERE_DATE.find(it) }?.let {
                LocalDate.of(it.groupValues[1].toInt(), it.groupValues[2].toInt(), it.groupValues[3].toInt())
            }
            if (released != null) {
                if (released.isBefore(today().minusMonths(months.toLong()))) return false
            } else item.year?.let { year ->
                val yearsBack = (months + 11) / 12 - 1
                if (year < currentYear() - yearsBack) return false
            }
        }
        return true
    }

    internal fun passesRatingMin(item: MediaItem, rules: ChannelRules): Boolean =
        rules.ratingMin == null || item.communityRating >= rules.ratingMin!!

    /**
     * Title, keyword, studio and genre-include rules. Keyword rules need enrichment we do not
     * have, so they never match (tvOS behaviour with a missing enrichment record).
     */
    internal fun passesContentMatch(item: MediaItem, title: String, itemGenres: List<String>, rules: ChannelRules): Boolean {
        val include = includeList(rules)
        val hasTitle = !rules.titleContains.isNullOrEmpty()
        val hasStudio = !rules.studios.isNullOrEmpty()
        val hasGenre = include.isNotEmpty()
        val hasKeyword = !rules.keywords.isNullOrEmpty()
        if (!hasTitle && !hasStudio && !hasGenre && !hasKeyword) return true

        val titleHit = hasTitle && rules.titleContains!!.any { containsWord(title, it) }
        if (hasTitle && !hasStudio && !hasGenre && !hasKeyword) return titleHit // title-curated allow-list
        if (titleHit) return true

        val studioOk = hasStudio && matchesStudio(item, rules.studios!!)
        val genreOk = hasGenre && itemGenres.any { g -> include.any { g.contains(it.lowercase()) } }
        return when {
            hasStudio && hasGenre -> studioOk && genreOk
            hasStudio -> studioOk
            hasGenre -> genreOk
            else -> false // keyword-only: needs enrichment
        }
    }

    // --- helpers ---

    private fun containsWord(haystack: String, needle: String): Boolean {
        val n = needle.lowercase()
        return n.isNotEmpty() && Regex("""\b${Regex.escape(n)}\b""").containsMatchIn(haystack)
    }

    private fun today(): LocalDate = ZonedDateTime.now(clock).toLocalDate()
    private fun currentYear(): Int = today().year

    private fun matchesStudio(item: MediaItem, studios: List<String>): Boolean =
        item.studios.any { s -> studios.any { s.lowercase().contains(it.lowercase()) } }

    private fun includeList(rules: ChannelRules) = rules.genres?.include.orEmpty()

    private fun includes(rules: ChannelRules, lock: GenreLock) =
        includeList(rules).any { it.lowercase() in lock.genres }

    /** Item year, else the year of its premiere date (`YYYY-MM-DD`). */
    internal fun releaseYear(item: MediaItem): Int? =
        item.year ?: item.premiereDate?.let { PREMIERE_YEAR.find(it)?.groupValues?.get(1)?.toInt() }

    private companion object {
        val PREMIERE_DATE = Regex("""^(\d{4})-(\d{2})-(\d{2})""")
        val PREMIERE_YEAR = Regex("""^(\d{4})-\d{2}-\d{2}""")
    }
}
