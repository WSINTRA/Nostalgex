plugins { alias(libs.plugins.kotlin.jvm); alias(libs.plugins.kotlin.serialization) }

dependencies {
    api(project(":core-model"))
    implementation(libs.kotlinx.serialization.json)
}

// Copy the repo-root channel config into test resources, mirroring the tvOS
// "Sync channel config" build step. The repo-root file stays the single source of truth.
val syncChannelsJson by tasks.registering(Copy::class) {
    from(rootProject.projectDir.parentFile.resolve("channels.json"))
    into(layout.buildDirectory.dir("generated/channels-resources"))
}

sourceSets.test { resources.srcDir(syncChannelsJson.map { it.destinationDir }) }
tasks.named("processTestResources") { dependsOn(syncChannelsJson) }
