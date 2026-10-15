package com.liuyihtu.mclash

import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class DebugLogLimitsTest {
    @Test fun trimsHugeUnicodeOutputAndKeepsAppendDescriptorUsable() {
        val directory = Files.createTempDirectory("bounded-log").toFile()
        try {
            val file = File(directory, "core.log")
            file.writeText("中".repeat(DebugLogLimits.MAX_BYTES) + "recent marker\n")
            FileOutputStream(file, true).use { writer ->
                DebugLogLimits.trim(file)
                assertTrue(file.length() <= DebugLogLimits.KEEP_BYTES)
                assertTrue(file.readText().endsWith("recent marker\n"))
                assertFalse(file.readText().contains('\uFFFD'))
                writer.write("after trim\n".toByteArray())
            }
            assertTrue(file.readText().endsWith("after trim\n"))
            val before = file.readBytes()
            DebugLogLimits.trim(file)
            assertArrayEquals(before, file.readBytes())
        } finally { directory.deleteRecursively() }
    }

}
