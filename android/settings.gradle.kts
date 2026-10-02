pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "nostalgex-android"

include(
    ":core-model",
    ":core-config",
    ":core-filter",
    ":core-schedule",
    ":data-backend",
    ":core-store",
    ":data-store",
    ":core-playback",
    ":core-presentation",
    ":player",
    ":app",
)
