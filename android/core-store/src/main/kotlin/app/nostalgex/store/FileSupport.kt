package app.nostalgex.store

import java.io.File
import java.io.IOException

/**
 * Writes via a temp file in the same directory then renames into place, so readers never see a
 * partial file. Uses java.io only: java.nio.file does not exist on Fire OS 6 (API 25).
 */
internal fun atomicWrite(target: File, text: String) {
    target.parentFile.mkdirs()
    val tmp = File.createTempFile("write", ".tmp", target.parentFile)
    try {
        tmp.writeText(text)
        // rename(2) replaces an existing file atomically on Android/Linux.
        if (!tmp.renameTo(target)) {
            target.delete()
            if (!tmp.renameTo(target)) throw IOException("Could not write ${target.name}")
        }
    } finally {
        if (tmp.exists()) tmp.delete()
    }
}
