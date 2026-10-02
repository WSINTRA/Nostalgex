package app.nostalgex.config

import kotlinx.serialization.Serializable

/** Wire format of channels.json. Kept internal: callers only see core-model types. */
@Serializable
internal data class ConfigDto(
    val version: Int,
    val exclusiveRules: List<ExclusiveRuleDto>? = null,
    val bundles: List<BundleDto>? = null,
    val channels: List<ChannelDto>,
)

@Serializable
internal data class ChannelDto(
    val id: Int,
    val number: Int,
    val name: String,
    val colorHex: String,
    val category: String? = null,
    val minItems: Int? = null,
    val isPremiereChannel: Boolean? = null,
    val rules: RulesDto? = null,
    val timeRestrictions: TimeRestrictionsDto? = null,
)

@Serializable internal data class GenreDto(val include: List<String>? = null, val requireAll: List<String>? = null, val exclude: List<String>? = null)
@Serializable internal data class RangeDto(val min: Int? = null, val max: Int? = null)

@Serializable
internal data class RulesDto(
    val type: String? = null,
    val source: String? = null,
    val genres: GenreDto? = null,
    val studios: List<String>? = null,
    val yearRange: RangeDto? = null,
    val contentRatings: List<String>? = null,
    val allowUnrated: Boolean? = null,
    val ratingMin: Double? = null,
    val durationRange: RangeDto? = null,
    val watchedOnly: Boolean? = null,
    val unwatchedOnly: Boolean? = null,
    val rewatched: Boolean? = null,
    val titleContains: List<String>? = null,
    val titleExcludes: List<String>? = null,
    val editorialOverrides: List<String>? = null,
    val addedWithinDays: Int? = null,
    val releasedWithinMonths: Int? = null,
    val keywords: List<String>? = null,
    val keywordsRequireAll: List<String>? = null,
    val keywordsExclude: List<String>? = null,
    val manifestOnly: Boolean? = null,
)

@Serializable internal data class BlockRatingsDto(val ratings: List<String>, val blockBefore: Int? = null, val blockAfter: Int? = null)

@Serializable
internal data class TimeRestrictionsDto(
    val blockRatings: BlockRatingsDto? = null,
    val tvOnlyBefore: Int? = null,
    val onlyAfterHour: Int? = null,
)

@Serializable
internal data class BundleDto(
    val id: String,
    val name: String,
    val description: String? = null,
    val channelIDs: List<Int>,
    val activeMonths: List<Int>? = null,
)

@Serializable
internal data class ExclusiveRuleDto(
    val channelID: Int? = null, // legacy single-owner form
    val channelIDs: List<Int>? = null,
    val genres: List<String>? = null,
    val titleContains: List<String>? = null,
    val editorialTitles: List<String>? = null,
    val manifestExclusive: Boolean? = null,
)
