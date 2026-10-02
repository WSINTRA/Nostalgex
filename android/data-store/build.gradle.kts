plugins { alias(libs.plugins.android.library); alias(libs.plugins.kotlin.android) }

android {
    namespace = "app.nostalgex.datastore"
    compileSdk = 35
    defaultConfig { minSdk = 25 // Fire OS 6 (Fire TV Stick 4K gen 1) and later
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
}

dependencies { api(project(":core-store")) }
