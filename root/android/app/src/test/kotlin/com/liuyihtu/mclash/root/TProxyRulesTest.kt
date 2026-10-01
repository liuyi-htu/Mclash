package com.liuyihtu.mclash.root

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class TProxyRulesTest {
    @Test fun systemResolverDnsIsCapturedWhileCoreDnsBypassesRedirection() {
        val script = TProxyRules.install(10001, false, emptySet(), true)
        assertFalse(script.contains("-A MCLASH_R_DNS -m owner --uid-owner 0 -j RETURN"))
        val coreBypass = "-A MCLASH_R_DNS -m mark --mark 0x40000000/0x40000000 -j RETURN"
        assertTrue(script.contains(coreBypass))
        for (protocol in listOf("tcp", "udp")) {
            val redirect = "-A MCLASH_R_DNS -p $protocol --dport 53 -j REDIRECT --to-ports 11053"
            assertTrue(script.contains(redirect))
            assertTrue(script.indexOf(coreBypass) < script.indexOf(redirect))
        }
    }

    @Test fun transparentRepliesLoseCaptureMarkBeforeBypassWithoutChangingNetworkBits() {
        val script = TProxyRules.install(10001, false, emptySet(), true)
        for (match in listOf(
            "-m mark --mark 0x40000000/0x40000000",
            "-m owner --uid-owner 0",
            "-m owner --uid-owner 10001",
        )) {
            val clear = "-A MCLASH_R_OUT $match -j MARK --set-xmark 0x0/0x20000000"
            val bypass = "-A MCLASH_R_OUT $match -j RETURN"
            assertTrue(script.contains(clear))
            assertTrue(script.indexOf(clear) < script.indexOf(bypass))
        }
        val networkAndCapture = 0x200101b3
        assertEquals(0x101b3, networkAndCapture and 0x20000000.inv())
    }

    @Test(expected = IllegalArgumentException::class) fun missingSelectedAppsCannotStart() {
        TProxyRules.install(10001, true, emptySet(), true)
    }

    @Test fun onlySelectedModeRestrictsDataAndIpv6ButCapturesSystemDns() {
        val script = TProxyRules.install(10001, true, setOf(10002), true)
        assertTrue(script.contains("-p tcp -m owner --uid-owner 10002 -j MARK"))
        assertTrue(script.contains("-p udp -m owner --uid-owner 10002 -j REJECT"))
        assertFalse(script.contains("-p tcp -j MARK"))
        assertTrue(script.contains("-A MCLASH_R_DNS -p udp --dport 53 -j REDIRECT"))
        assertTrue(script.contains("-i lo -m mark --mark ${TProxyRules.CAPTURE}"))
    }

    @Test fun rollbackPreservesForeignRulesAcrossFailuresAndCollisions() {
        val directory = Files.createTempDirectory("root-rule-test").toFile()
        try {
            val install = File(directory, "install.sh").apply {
                writeText(TProxyRules.install(10001, false, setOf(10002), true))
            }
            val cleanup = File(directory, "cleanup.sh").apply { writeText(TProxyRules.cleanup()) }
            val hotspot = File(directory, "hotspot.sh").apply {
                writeText(HotspotRules.update(setOf("wlan2"), true))
            }
            val project = generateSequence(File(System.getProperty("user.dir")!!).canonicalFile) { it.parentFile }
                .first { File(it, "scripts/test-rules.py").isFile }
            val process = ProcessBuilder("python3", File(project, "scripts/test-rules.py").absolutePath,
                install.absolutePath, cleanup.absolutePath, hotspot.absolutePath).redirectErrorStream(true).start()
            val output = process.inputStream.bufferedReader().readText()
            assertEquals(output, 0, process.waitFor())
        } finally { directory.deleteRecursively() }
    }

    @Test fun shellQuotingKeepsPathsAsLiteralArguments() {
        val input = "a'b ${'$'}(id) `id`\nnext"
        val process = ProcessBuilder("/bin/sh", "-c", "printf '%s' ${RootShell.quote(input)}").start()
        assertEquals(input, process.inputStream.bufferedReader().readText())
        assertEquals(0, process.waitFor())
    }
}
