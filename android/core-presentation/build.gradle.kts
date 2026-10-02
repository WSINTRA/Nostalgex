plugins { alias(libs.plugins.kotlin.jvm) }
dependencies {
    api(project(":core-store"))
    api(libs.kotlinx.coroutines.core)
    testImplementation(libs.kotlinx.coroutines.test)
}
