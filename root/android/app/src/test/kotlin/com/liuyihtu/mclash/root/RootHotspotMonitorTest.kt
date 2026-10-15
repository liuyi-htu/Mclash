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
            // Android's external printf has an argument-size limit; history can exceed it.
            File(dir, "tether").writeText("Tether state:\n wlan2 - TetheredState - lastError = 0\n rndis0 - TetheredState - lastError = 0\nHardware offload:\n" +
                "previously wlan9 - TetheredState - lastError = 0\n".repeat(8000))
            tool("dumpsys", "cat ./tether")
            tool("ip", "case \"${'$'}*\" in *-4*) echo '1: lo inet 127.0.0.1/8';; *) echo '1: lo inet6 ::1/128';; esac")
            tool("iptables-restore", "cat >> ./restore.calls")
            tool("ip6tables-restore", "cat >> ./restore.calls")
            val script = File(dir, "monitor.sh").apply { writeText("printf() { /usr/bin/printf \"${'$'}@\"; }\n" + RootHotspotMonitor.script(true, true)) }
            fun run(): Int {
                val builder = ProcessBuilder("/bin/sh", script.absolutePath).directory(dir).redirectErrorStream(true)
                builder.environment()["PATH"] = bin.absolutePath + ":" + System.getenv("PATH")
                val process = builder.start()
                assertTrue(process.waitFor(10, TimeUnit.SECONDS))
                val output = process.inputStream.bufferedReader().readText()
                assertEquals(output, 0, process.exitValue())
                return process.exitValue()
            }
            // Missing policy and an enabled switch with no selection share nothing.
            run()
            assertFalse(File(dir, "restore.calls").readText().contains("-A "))
            File(dir, "sharing.policy").writeText("1\n")
            run()
            assertFalse(File(dir, "hotspot-data6.restore").readText().contains("-A "))
            assertEquals("1\n", File(dir, "sharing.applied").readText())
            File(dir, "sharing.policy").writeText("1\nwlan2\n")
            run()
            assertFalse(File(dir, "hotspot-data4.restore").readText().contains("rndis0"))
            assertTrue(File(dir, "hotspot-dns4.restore").readText().contains("--to-ports 11053"))
            assertTrue(File(dir, "hotspot-dns6.restore").readText().contains("--on-port 17895"))
            val data6 = File(dir, "hotspot-data6.restore").readText()
            assertTrue(data6.contains("--dport 546 -j RETURN"))
            assertTrue(data6.contains("-d fc00::/7 -j RETURN"))
            val count = File(dir, "restore.calls").length()
            run()
            assertEquals(count, File(dir, "restore.calls").length())
            // A new supervisor restores the saved enabled policy and selection.
            File(dir, "hotspot.snapshot").delete()
            File(dir, "sharing.applied").delete()
            run()
            assertEquals("1\nwlan2\n", File(dir, "sharing.applied").readText())
            assertTrue(File(dir, "hotspot-data4.restore").readText().contains("-i wlan2"))
            assertFalse(File(dir, "hotspot-data4.restore").readText().contains("rndis0"))
            File(dir, "sharing.policy").writeText(HotspotRules.sharingPolicy(false, setOf("wlan2")))
            run()
            assertFalse(File(dir, "hotspot-data4.restore").readText().contains("-A "))
            assertFalse(File(dir, "hotspot-dns6.restore").readText().contains("-A "))
            assertEquals("0\nwlan2\n", File(dir, "sharing.policy").readText())
            File(dir, "sharing.policy").writeText(HotspotRules.sharingPolicy(true, setOf("wlan2")))
            File(dir, "tether").writeText("Tether state:\n rndis0 - TetheredState - lastError = 0\nHardware offload:\n")
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
