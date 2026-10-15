package com.liuyihtu.mclash.root

import java.io.File
import java.io.RandomAccessFile

internal object DebugLogLimits {
    const val MAX_BYTES = 512 * 1024
    const val KEEP_BYTES = 256 * 1024

    // Rewrite the same inode: native writers keep their append descriptors open.
    @Synchronized
    fun trim(file: File) {
        if (!file.isFile || file.length() <= MAX_BYTES) return
        RandomAccessFile(file, "rw").use { output ->
            val length = output.length()
            if (length <= MAX_BYTES) return
            val bytes = ByteArray(KEEP_BYTES)
            output.seek(length - bytes.size)
            output.readFully(bytes)
            var start = 0
            while (start < bytes.size && (bytes[start].toInt() and 0xc0) == 0x80) start++
            output.seek(0)
            output.write(bytes, start, bytes.size - start)
            output.setLength((bytes.size - start).toLong())
        }
    }

    fun maintenanceScript(): String = """
        umask 077
        for log in ./mihomo.log ./supervisor.log; do
            [ -f "${'$'}log" ] || continue
            size=${'$'}(wc -c < "${'$'}log") || continue
            [ "${'$'}size" -gt $MAX_BYTES ] || continue
            temporary="${'$'}log.trim"
            # Keep the original inode so open append descriptors remain valid.
            if tail -c $KEEP_BYTES "${'$'}log" > "${'$'}temporary"; then
                sed '1d' "${'$'}temporary" > "${'$'}log" || true
            fi
            rm -f "${'$'}temporary"
        done
    """.trimIndent() + "\n"

}
