package app.nostalgex.tv

import android.app.Application

class NostalgexApp : Application() {
    val container: AppContainer by lazy { AppContainer(this) }
}
