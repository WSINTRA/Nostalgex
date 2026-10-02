package app.nostalgex.store

import app.nostalgex.backend.jellyfin.JellyfinSession

/** Top-level screens. The UI renders whichever route it is given. */
sealed interface AppRoute {
    data object Connect : AppRoute
    data class LoadLibrary(val session: JellyfinSession) : AppRoute
}

/** Decides where the app starts, so that choice is testable without Android. */
class StartupRouter(private val sessions: SessionStore) {
    fun initialRoute(): AppRoute = sessions.load()?.let { AppRoute.LoadLibrary(it) } ?: AppRoute.Connect

    fun signOut(): AppRoute { sessions.clear(); return AppRoute.Connect }
}
