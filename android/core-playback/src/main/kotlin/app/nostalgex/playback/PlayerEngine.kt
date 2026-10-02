package app.nostalgex.playback

data class PlayRequest(val url: String, val headers: Map<String, String>, val startPositionMs: Long)

/** The video player seen by the controller. Android implements it with Media3; tests use a fake. */
interface PlayerEngine {
    interface Listener {
        /** First frame is ready: the stream works. */
        fun onReady()
        fun onEnded()
        fun onError(cause: Throwable)
    }

    var listener: Listener?
    fun play(request: PlayRequest)
    fun stop()
}
