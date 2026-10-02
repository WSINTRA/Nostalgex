package app.nostalgex.store

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Writes via a temp file in the same directory then moves into place, so readers never see a partial file. */
internal fun atomicWrite(target: File, text: String) {
    target.parentFile.mkdirs()
    val tmp = File.createTempFile("write", ".tmp", target.parentFile)
    try {
        tmp.writeText(text)
        Files.move(tmp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
    } finally {
        tmp.delete()
    }
}
