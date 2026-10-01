package com.liuyihtu.mclash.root

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class MihomoRecoveryTest {
    @Test fun fastRecoveryKillsOnlyCoresUsingThisAppsDataDirectory() {
        val temporary = Files.createTempDirectory("mihomo-recovery").toFile()
        try {
            val proc = File(temporary, "proc").apply { mkdirs() }
            val home = File(temporary, "app's data")
            fun process(pid: Int, comm: String, directory: String): File {
                val folder = File(proc, pid.toString()).apply { mkdirs() }
                File(folder, "comm").writeText("$comm\n")
                return File(folder, "cmdline").apply {
                    writeText("/data/app/example/lib/arm64/libmihomo.so\u0000-d\u0000$directory\u0000-f\u0000runtime.yaml\u0000")
                }
            }
            val owned = process(100, "libmihomo.so", home.absolutePath)
            val foreign = process(101, "libmihomo.so", "/another/app")
            val unrelated = process(102, "another-process", home.absolutePath)
            val killed = File(temporary, "killed")
            val script = """
                kill() {
                    [ "${'$'}1" != -0 ] || return 1
                    for pid in "${'$'}@"; do :; done
                    echo "${'$'}pid" >> ${RootShell.quote(killed.absolutePath)}
                    : > ${RootShell.quote(proc.absolutePath)}/"${'$'}pid"/cmdline
                }
            """.trimIndent() + "\n" + MihomoProcess.orphanCleanup(home)
                .replace("/proc/", proc.absolutePath + "/")
            val execution = ProcessBuilder("/bin/sh", "-c", script).redirectErrorStream(true).start()
            val output = execution.inputStream.bufferedReader().readText()
            assertEquals(output, 0, execution.waitFor())
            assertEquals("100\n", killed.readText())
            assertEquals(0, owned.length())
            assertTrue(foreign.length() > 0)
            assertTrue(unrelated.length() > 0)
        } finally {
            temporary.deleteRecursively()
        }
    }
}
