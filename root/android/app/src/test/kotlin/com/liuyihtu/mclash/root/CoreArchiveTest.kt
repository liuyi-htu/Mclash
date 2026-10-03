package com.liuyihtu.mclash.root

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import java.util.zip.GZIPOutputStream
import org.junit.Assert.*
import org.junit.Test

class CoreArchiveTest {
    @Test fun acceptsVerifiedArm64AndRejectsCorruptionOrWrongArchitecture() {
        val directory = Files.createTempDirectory("core-archive").toFile()
        try {
            val archive = File(directory, "core.gz")
            val binary = File(directory, "libmihomo.so")
            val header = ByteArray(64).apply {
                this[0] = 0x7f; this[1] = 'E'.code.toByte(); this[2] = 'L'.code.toByte()
                this[3] = 'F'.code.toByte(); this[4] = 2; this[5] = 1; this[18] = 0xb7.toByte()
            }
            fun pack(): String {
                GZIPOutputStream(archive.outputStream()).use { it.write(header) }
                return "sha256:" + MessageDigest.getInstance("SHA-256").digest(archive.readBytes())
                    .joinToString("") { "%02x".format(it.toInt() and 255) }
            }
            val digest = pack()
            CoreArchive.unpack(archive, binary, digest)
            assertArrayEquals(header, binary.readBytes())
            assertThrows(IllegalStateException::class.java) { CoreArchive.unpack(archive, binary, "sha256:" + "0".repeat(64)) }
            assertThrows(IllegalArgumentException::class.java) { CoreArchive.unpack(archive, binary, "") }
            header[18] = 0x3e
            assertThrows(IllegalArgumentException::class.java) { CoreArchive.unpack(archive, binary, pack()) }
        } finally { directory.deleteRecursively() }
    }

    @Test fun parsesOfficialVersionAndRejectsUnrelatedOutput() {
        assertEquals("v1.19.32", CoreArchive.version("Mihomo Meta v1.19.32 android arm64 with go1.25"))
        assertThrows(IllegalStateException::class.java) { CoreArchive.version("other v1.19.32") }
    }
}
