plugins { alias(libs.plugins.kotlin.jvm) }
dependencies { api(project(":core-model")) }

// Parity: expose the repo's JS golden-vector file to tests, so Kotlin is checked against the
// same strings the web tuner is, not a hand-copied duplicate.
val syncParityVectors by tasks.registering(Copy::class) {
    from(rootProject.projectDir.parentFile.resolve("scripts/nostalgex-schedule-order-smoke.mjs"))
    into(layout.buildDirectory.dir("generated/parity-resources"))
}
sourceSets.test { resources.srcDir(syncParityVectors.map { it.destinationDir }) }
tasks.named("processTestResources") { dependsOn(syncParityVectors) }
