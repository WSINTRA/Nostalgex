package app.nostalgex.filter

/**
 * Genres that stay off a channel unless it opts in (via `genres.include`), or is a
 * studio-only channel. Mirrors the sets in nostalgex-channel-filter.cjs.
 * Sport, music and history are deliberately NOT locked.
 */
internal enum class GenreLock(val genres: Set<String>) {
    HORROR(setOf("horror")),
    REALITY(setOf("reality", "game show", "game-show", "reality-tv")),
    ANIMATION(setOf("animation", "animated", "cartoon")),
    DOCUMENTARY(setOf("documentary", "docuseries")),
    WAR(setOf("war", "war & politics")),
    WESTERN(setOf("western")),
    TALK_SHOW(setOf("talk show", "talk", "news")),
}

internal val ADULT_RATINGS = setOf("R", "NC-17", "TV-MA", "18", "18+", "X", "NR")
