package app.nostalgex.player

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import app.nostalgex.playback.PlayRequest
import app.nostalgex.playback.PlayerEngine

/** Thin ExoPlayer adapter. No decisions live here; they are in PlaybackController. */
class Media3PlayerEngine(context: Context) : PlayerEngine {
    override var listener: PlayerEngine.Listener? = null

    private val http = DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(true)
    val player: ExoPlayer = ExoPlayer.Builder(context)
        .setMediaSourceFactory(DefaultMediaSourceFactory(context).setDataSourceFactory(http))
        .build()
        .apply {
            playWhenReady = true
            addListener(object : Player.Listener {
                private var reportedReady = false
                override fun onPlaybackStateChanged(state: Int) {
                    when (state) {
                        Player.STATE_READY -> if (!reportedReady) { reportedReady = true; listener?.onReady() }
                        Player.STATE_ENDED -> listener?.onEnded()
                        Player.STATE_IDLE, Player.STATE_BUFFERING -> Unit
                    }
                }
                override fun onPlayerError(error: PlaybackException) { listener?.onError(error) }
                override fun onMediaItemTransition(item: MediaItem?, reason: Int) { reportedReady = false }
            })
        }

    override fun play(request: PlayRequest) {
        http.setDefaultRequestProperties(request.headers)
        player.setMediaItem(MediaItem.fromUri(request.url), request.startPositionMs)
        player.prepare()
    }

    override fun stop() { player.stop(); player.clearMediaItems() }

    fun release() { listener = null; player.release() }
}
