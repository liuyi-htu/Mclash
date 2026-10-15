package com.liuyihtu.mclash.root

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
    @Test fun shellMaintenanceKeepsRecentOutputAndOpenAppendDescriptors() {
        val directory = Files.createTempDirectory("bounded-root-log").toFile()
        try {
            val core = File(directory, "mihomo.log")
            val supervisor = File(directory, "supervisor.log")
            for (file in listOf(core, supervisor)) file.writeText("旧内容\n".repeat(DebugLogLimits.MAX_BYTES) + "recent\n")
            FileOutputStream(core, true).use { writer ->
                val process = ProcessBuilder("/bin/sh", "-c", DebugLogLimits.maintenanceScript())
                    .directory(directory).redirectErrorStream(true).start()
                val output = process.inputStream.bufferedReader().readText()
                assertEquals(output, 0, process.waitFor())
                for (file in listOf(core, supervisor)) {
                    assertTrue(file.length() <= DebugLogLimits.KEEP_BYTES)
                    assertTrue(file.readText().endsWith("recent\n"))
                    assertFalse(file.readText().contains('\uFFFD'))
                }
                writer.write("still writing\n".toByteArray())
            }
            assertTrue(core.readText().endsWith("still writing\n"))
        } finally { directory.deleteRecursively() }
    }

}
