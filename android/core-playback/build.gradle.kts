plugins { alias(libs.plugins.kotlin.jvm) }
dependencies {
    api(project(":core-model"))
    api(project(":core-filter"))
    api(project(":core-schedule"))
    api(project(":data-backend"))
}
