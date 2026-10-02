package app.nostalgex.playback

import app.nostalgex.model.Channel
import app.nostalgex.model.ScheduleBlock

sealed interface PlaybackState {
    data object Idle : PlaybackState
    data class Playing(val channel: Channel, val block: ScheduleBlock, val upNext: ScheduleBlock?) : PlaybackState
    data class Failed(val channel: Channel?, val reason: String) : PlaybackState
}
