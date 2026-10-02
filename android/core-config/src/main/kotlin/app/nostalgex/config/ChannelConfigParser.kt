package app.nostalgex.config

import app.nostalgex.model.BlockRatings
import app.nostalgex.model.Channel
import app.nostalgex.model.ChannelBundle
import app.nostalgex.model.ChannelConfig
import app.nostalgex.model.ChannelRules
import app.nostalgex.model.ExclusiveRule
import app.nostalgex.model.GenreRules
import app.nostalgex.model.IntRange2
import app.nostalgex.model.LibrarySource
import app.nostalgex.model.MediaType
import app.nostalgex.model.TimeRestrictions
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

class ConfigParseException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** Turns channels.json text into core-model types. Pure: no I/O. */
class ChannelConfigParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun parse(text: String): ChannelConfig {
        val dto = try {
            json.decodeFromString(ConfigDto.serializer(), text)
        } catch (e: SerializationException) {
            throw ConfigParseException("Invalid channels.json: ${e.message}", e)
        } catch (e: IllegalArgumentException) {
            throw ConfigParseException("Invalid channels.json: ${e.message}", e)
        }
        return ChannelConfig(
            version = dto.version,
            channels = dto.channels.map { it.toModel() },
            bundles = dto.bundles.orEmpty().map { ChannelBundle(it.id, it.name, it.description, it.channelIDs, it.activeMonths) },
            exclusiveRules = dto.exclusiveRules.orEmpty().map { it.toModel() },
        )
    }

    private fun ChannelDto.toModel() = Channel(
        id = id, number = number, name = name, colorHex = colorHex, category = category,
        rules = rules?.toModel() ?: ChannelRules(),
        timeRestrictions = timeRestrictions?.let { tr ->
            TimeRestrictions(
                blockRatings = tr.blockRatings?.let { BlockRatings(it.ratings, it.blockBefore, it.blockAfter) },
                tvOnlyBefore = tr.tvOnlyBefore,
                onlyAfterHour = tr.onlyAfterHour,
            )
        },
        minItems = minItems ?: 50,
        isPremiereChannel = isPremiereChannel ?: false,
    )

    private fun RulesDto.toModel() = ChannelRules(
        type = type?.let { MEDIA_TYPES[it] },
        source = source?.let { SOURCES[it] },
        genres = genres?.let { GenreRules(it.include.orEmpty(), it.requireAll.orEmpty(), it.exclude.orEmpty()) },
        studios = studios,
        yearRange = yearRange?.let { IntRange2(it.min, it.max) },
        contentRatings = contentRatings,
        allowUnrated = allowUnrated ?: false,
        ratingMin = ratingMin,
        durationRange = durationRange?.let { IntRange2(it.min, it.max) },
        watchedOnly = watchedOnly ?: false,
        unwatchedOnly = unwatchedOnly ?: false,
        rewatched = rewatched ?: false,
        titleContains = titleContains,
        titleExcludes = titleExcludes,
        editorialOverrides = editorialOverrides,
        addedWithinDays = addedWithinDays,
        releasedWithinMonths = releasedWithinMonths,
        keywords = keywords,
        keywordsRequireAll = keywordsRequireAll,
        keywordsExclude = keywordsExclude,
        manifestOnly = manifestOnly ?: false,
    )

    private fun ExclusiveRuleDto.toModel() = ExclusiveRule(
        channelIds = channelIDs ?: channelID?.let { listOf(it) } ?: emptyList(),
        genres = genres.orEmpty(),
        titleContains = titleContains.orEmpty(),
        editorialTitles = editorialTitles.orEmpty(),
        manifestExclusive = manifestExclusive ?: false,
    )

    private companion object {
        val MEDIA_TYPES = mapOf("movie" to MediaType.MOVIE, "episode" to MediaType.EPISODE)
        val SOURCES = mapOf("movie" to LibrarySource.MOVIE, "tv" to LibrarySource.TV, "musicVideo" to LibrarySource.MUSIC_VIDEO)
    }
}
