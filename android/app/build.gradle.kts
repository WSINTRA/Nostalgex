plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "app.nostalgex.tv"
    compileSdk = 35
    defaultConfig {
        applicationId = "app.nostalgex.tv"
        minSdk = 28 // Fire OS 7 (Android 9) and later
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
    }
    buildFeatures { compose = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
}

dependencies {
    implementation(project(":core-config"))
    implementation(project(":core-store"))
    implementation(project(":data-store"))
    implementation(project(":player"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.tv.material)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.media3.ui)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.coroutines.core)
}

// Same single source of truth as tvOS: bundle the repo-root channels.json into the APK assets.
val syncChannelsJson by tasks.registering(Copy::class) {
    from(rootProject.projectDir.parentFile.resolve("channels.json"))
    into(layout.buildDirectory.dir("generated/channels-assets"))
}
android.sourceSets.getByName("main").assets.srcDir(syncChannelsJson.map { it.destinationDir })
tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }.configureEach { dependsOn(syncChannelsJson) }
