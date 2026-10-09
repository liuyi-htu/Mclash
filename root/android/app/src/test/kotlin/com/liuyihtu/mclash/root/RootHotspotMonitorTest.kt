package com.liuyihtu.mclash.root

import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class RootHotspotMonitorTest {
    @Test fun refreshesBothFamiliesAndClearsAfterHotspotStops() {
        val dir = Files.createTempDirectory("root-monitor").toFile()
        try {
            val bin = File(dir, "bin").apply { mkdirs() }
            fun tool(name: String, body: String) {
                File(bin, name).apply { writeText("#!/bin/sh\n$body\n"); setExecutable(true) }
            }
            File(dir, "tether").writeText("Tether state:\n wlan2 - TetheredState - lastError = 0\nHardware offload:\n")
            tool("dumpsys", "cat ./tether")
            tool("ip", "case \"${'$'}*\" in *-4*) echo '1: lo inet 127.0.0.1/8';; *) echo '1: lo inet6 ::1/128';; esac")
            tool("iptables-restore", "cat >> ./restore.calls")
            tool("ip6tables-restore", "cat >> ./restore.calls")
            val script = File(dir, "monitor.sh").apply { writeText(RootHotspotMonitor.script(true, true)) }
            fun run(): Int {
                val builder = ProcessBuilder("/bin/sh", script.absolutePath).directory(dir).redirectErrorStream(true)
                builder.environment()["PATH"] = bin.absolutePath + ":" + System.getenv("PATH")
                val process = builder.start()
                assertTrue(process.waitFor(10, TimeUnit.SECONDS))
                val output = process.inputStream.bufferedReader().readText()
                assertEquals(output, 0, process.exitValue())
                return process.exitValue()
            }
            run()
            assertTrue(File(dir, "hotspot-dns4.restore").readText().contains("--to-ports 11053"))
            assertTrue(File(dir, "hotspot-dns6.restore").readText().contains("--on-port 17895"))
            val data6 = File(dir, "hotspot-data6.restore").readText()
            assertTrue(data6.contains("--dport 546 -j RETURN"))
            assertTrue(data6.contains("-d fc00::/7 -j RETURN"))
            val count = File(dir, "restore.calls").length()
            run()
            assertEquals(count, File(dir, "restore.calls").length())
            File(dir, "tether").writeText("Tether state:\nHardware offload:\n")
            run()
            assertEquals("*mangle\n-F MCLASH_R_HOT6\nCOMMIT\n", File(dir, "hotspot-data6.restore").readText())
            assertFalse(File(dir, "hotspot-dns4.restore").readText().contains("-A "))
        } finally { dir.deleteRecursively() }
    }

    @Test fun disabledIpv6BlocksForwardedTraffic() {
        val script = RootHotspotMonitor.script(false, false)
        assertTrue(script.startsWith("BYPASS_LAN=0\nIPV6=0\n"))
        assertTrue(script.contains("-p ${'$'}proto -j REJECT"))
        assertTrue(script.contains("iptables-restore -w 5 --noflush"))
    }
}
