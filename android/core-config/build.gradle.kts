plugins { alias(libs.plugins.kotlin.jvm); alias(libs.plugins.kotlin.serialization) }
dependencies {
    api(project(":core-model"))
    implementation(libs.kotlinx.serialization.json)
}
// Copy the repo-root channel config into test resources (mirrors the tvOS "Sync channel config" step).
