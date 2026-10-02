package app.nostalgex.model

data class GenreRules(
    val include: List<String> = emptyList(),
    val requireAll: List<String> = emptyList(),
    val exclude: List<String> = emptyList(),
)

data class IntRange2(val min: Int? = null, val max: Int? = null)

/** Subset of tvOS `ChannelRules`. Enrichment-only fields are carried but not yet evaluated. */
data class ChannelRules(
    val type: MediaType? = null,
    val source: LibrarySource? = null,
    val genres: GenreRules? = null,
    val studios: List<String>? = null,
    val yearRange: IntRange2? = null,
    val contentRatings: List<String>? = null,
    val allowUnrated: Boolean = false,
    val ratingMin: Double? = null,
    val durationRange: IntRange2? = null,
    val watchedOnly: Boolean = false,
    val unwatchedOnly: Boolean = false,
    val rewatched: Boolean = false,
    val titleContains: List<String>? = null,
    val titleExcludes: List<String>? = null,
    val editorialOverrides: List<String>? = null,
    val addedWithinDays: Int? = null,
    val releasedWithinMonths: Int? = null,
    // Not evaluated in the prototype (need TMDB/OMDb enrichment):
    val keywords: List<String>? = null,
    val keywordsRequireAll: List<String>? = null,
    val keywordsExclude: List<String>? = null,
    val manifestOnly: Boolean = false,
)

data class BlockRatings(val ratings: List<String>, val blockBefore: Int? = null, val blockAfter: Int? = null)

data class TimeRestrictions(
    val blockRatings: BlockRatings? = null,
    val tvOnlyBefore: Int? = null,
    val onlyAfterHour: Int? = null,
)

data class Channel(
    val id: Int,
    val number: Int,
    val name: String,
    val colorHex: String,
    val category: String? = null,
    val rules: ChannelRules = ChannelRules(),
    val timeRestrictions: TimeRestrictions? = null,
    val minItems: Int = 50,
    val isPremiereChannel: Boolean = false,
)

data class ChannelBundle(
    val id: String,
    val name: String,
    val description: String?,
    val channelIds: List<Int>,
    val activeMonths: List<Int>? = null,
)

/** Content owned by a set of channels and blocked from all others (e.g. anime). */
data class ExclusiveRule(
    val channelIds: List<Int>,
    val genres: List<String> = emptyList(),
    val titleContains: List<String> = emptyList(),
    val editorialTitles: List<String> = emptyList(),
    val manifestExclusive: Boolean = false,
)

data class ChannelConfig(
    val version: Int,
    val channels: List<Channel>,
    val bundles: List<ChannelBundle>,
    val exclusiveRules: List<ExclusiveRule>,
)
