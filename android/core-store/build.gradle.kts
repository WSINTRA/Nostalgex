plugins { alias(libs.plugins.kotlin.jvm); alias(libs.plugins.kotlin.serialization) }
dependencies {
    api(project(":core-model"))
    api(project(":core-schedule"))
    api(project(":data-backend"))
    implementation(libs.kotlinx.serialization.json)
}
