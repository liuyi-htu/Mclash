package com.liuyihtu.mclash.root

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class MihomoRecoveryTest {
    @Test fun ipv6ReadinessRequiresBothTransparentSocketsAndDualStackDns() {
        val temporary = Files.createTempDirectory("mihomo-ipv6-listeners").toFile()
        try {
            val tcp = File(temporary, "tcp6")
            val udp = File(temporary, "udp6")
            tcp.writeText("0: 00000000000000000000000001000000:45E6 0:0 0A\n2: 00000000000000000000000001000000:45E7 0:0 0A\n1: 00000000000000000000000000000000:2B2D 0:0 0A\n")
            udp.writeText("0: 00000000000000000000000001000000:45E6 0:0 07\n2: 00000000000000000000000001000000:45E7 0:0 07\n1: 00000000000000000000000000000000:2B2D 0:0 07\n")
            val check = MihomoProcess.ipv6ListenerCheck().replace("/proc/net/", temporary.absolutePath + "/")
            val prefix = "owner_alive() { return 1; }\ncore_pid=0\n"
            fun run(): Int {
                val process = ProcessBuilder("/bin/sh", "-c", prefix + check).redirectErrorStream(true).start()
                process.inputStream.bufferedReader().readText()
                return process.waitFor()
            }
            assertEquals(0, run())
            udp.writeText("0: 00000000000000000000000001000000:45E6 0:0 07\n")
            assertNotEquals(0, run())
        } finally { temporary.deleteRecursively() }
    }

    @Test fun fastRecoveryKillsOnlyCoresUsingThisAppsDataDirectory() {
        val temporary = Files.createTempDirectory("mihomo-recovery").toFile()
        try {
            val proc = File(temporary, "proc").apply { mkdirs() }
            val home = File(temporary, "app's data")
            fun process(pid: Int, comm: String, directory: String, binary: String = "/data/app/example/lib/arm64/libmihomo.so"): File {
                val folder = File(proc, pid.toString()).apply { mkdirs() }
                File(folder, "comm").writeText("$comm\n")
                return File(folder, "cmdline").apply {
                    writeText("$binary\u0000-d\u0000$directory\u0000-f\u0000runtime.yaml\u0000")
                }
            }
            val owned = process(100, "libmihomo.so", home.absolutePath)
            val foreign = process(101, "libmihomo.so", "/another/app")
            val unrelated = process(102, "another-process", home.absolutePath)
            val updated = process(103, "libmihomo.so", home.absolutePath, File(home, "core/core-123/libmihomo.so").absolutePath)
            val foreignCore = process(104, "libmihomo.so", home.absolutePath, "/another/app/core/core-123/libmihomo.so")
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
            assertEquals("100\n103\n", killed.readText())
            assertEquals(0, owned.length())
            assertEquals(0, updated.length())
            assertTrue(foreignCore.length() > 0)
            assertTrue(foreign.length() > 0)
            assertTrue(unrelated.length() > 0)
        } finally {
            temporary.deleteRecursively()
        }
    }
}
