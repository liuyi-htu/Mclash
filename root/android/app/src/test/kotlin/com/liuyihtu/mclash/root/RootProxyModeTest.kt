package com.liuyihtu.mclash.root

import org.junit.Assert.*
import org.junit.Test
import org.yaml.snakeyaml.Yaml
import java.io.File
import java.nio.file.Files

class RootProxyModeTest {
    @Test fun allSupportedTunStacksReachTheRuntimeConfig() {
        for (stack in RootRuntimeConfig.TUN_STACKS) {
            val config = Yaml().load<Map<String, Any>>(RootRuntimeConfig.build("rules: ['MATCH,DIRECT']", false, tun = true, tunStack = stack))
            assertEquals(stack, (config["tun"] as Map<*, *>)["stack"])
        }
    }

    @Test(expected = IllegalArgumentException::class) fun invalidTunStackIsRejected() {
        RootRuntimeConfig.build("rules: ['MATCH,DIRECT']", false, tun = true, tunStack = "invalid")
    }

    @Test fun tunConfigReplacesImportedListenersWithoutChangingGroups() {
        for (ipv6 in listOf(false, true)) {
            val source = "tun: {enable: false}\nlisteners: [{type: http, port: 8888}]\nrules: ['MATCH,DIRECT']"
            val config = Yaml().load<Map<String, Any>>(RootRuntimeConfig.build(source, false, ipv6 = ipv6, tun = true))
            val tun = config["tun"] as Map<*, *>
            assertEquals(true, tun["enable"])
            assertEquals(false, tun["auto-route"])
            assertEquals("mclash0", tun["device"])
            assertEquals(ipv6, config["ipv6"])
            assertFalse(config.containsKey("tproxy-port"))
            assertFalse(config.containsKey("listeners"))
            assertFalse(config.containsKey("proxy-groups"))
            assertEquals(listOf("MATCH,DIRECT"), config["rules"])
        }
        val legacy = Yaml().load<Map<String, Any>>(RootRuntimeConfig.build("rules: ['MATCH,DIRECT']", false))
        assertFalse(legacy.containsKey("tun"))
        assertEquals(RootRuntimeConfig.TPROXY_PORT, legacy["tproxy-port"])
    }

    @Test fun tunRollbackPreservesForeignRulesAcrossPartialFailures() {
        val directory = Files.createTempDirectory("mclash-tun-lifecycle").toFile()
        try {
            val install = File(directory, "install.sh").apply {
                writeText(TProxyRules.install(10001, false, setOf(10002), true, true, tun = true))
            }
            val cleanup = File(directory, "cleanup.sh").apply { writeText(TProxyRules.cleanup()) }
            val sharing = File(directory, "sharing.sh").apply {
                writeText(HotspotRules.update(setOf("wlan2"), true, ipv6Enabled = true, tun = true))
            }
            val project = generateSequence(File(System.getProperty("user.dir")!!).canonicalFile) { it.parentFile }
                .first { File(it, "scripts/test-rules.py").isFile }
            val process = ProcessBuilder("python3", File(project, "scripts/test-rules.py").absolutePath,
                install.absolutePath, cleanup.absolutePath, sharing.absolutePath).redirectErrorStream(true).start()
            val output = process.inputStream.bufferedReader().readText()
            assertEquals(output, 0, process.waitFor())
        } finally { directory.deleteRecursively() }
    }

    @Test fun tunRoutesPreserveUidPolicyAndAvoidTransparentSocketTargets() {
        for (ipv6 in listOf(false, true)) {
            val script = TProxyRules.install(10001, true, setOf(10002), true, ipv6, tun = true)
            assertTrue(script.contains("ip -4 route add default dev mclash0 table 20230"))
            assertTrue(script.contains("ip -4 rule add pref 8999 to 198.18.0.0/30 lookup 20230"))
            assertEquals(ipv6, script.contains("ip -6 rule add pref 8999 to fdfe:dcba:9876::/126 lookup 20230"))
            assertTrue(script.contains("-p tcp -m owner --uid-owner 10002 -j MARK"))
            assertFalse(script.contains("-p tcp -j MARK"))
            assertFalse(script.contains("-j TPROXY"))
            assertFalse(script.contains("route add local"))
            assertEquals(ipv6, script.contains("ip -6 route add default dev mclash0"))
            assertTrue(script.contains("-o mclash0 -m mark --mark ${TProxyRules.CAPTURE} -j ACCEPT"))
            val generatedSharing = HotspotRules.update(setOf("wlan2"), true, ipv6Enabled = ipv6, tun = true)
            assertFalse(generatedSharing.contains("-j TPROXY"))
            val sharing = RootHotspotMonitor.script(true, ipv6, tun = true)
            assertFalse(sharing.contains("-j TPROXY"))
            assertTrue(sharing.contains("-j MARK --set-xmark ${TProxyRules.CAPTURE}"))
            for (text in listOf(script, sharing, TProxyRules.cleanup())) {
                val file = Files.createTempFile("mclash-tun-syntax", ".sh").toFile()
                try {
                    file.writeText(text)
                    val process = ProcessBuilder("/bin/sh", "-n", file.absolutePath).redirectErrorStream(true).start()
                    val output = process.inputStream.bufferedReader().readText()
                    assertEquals(output, 0, process.waitFor())
                } finally { file.delete() }
            }
        }
        val cleanup = TProxyRules.cleanup()
        assertTrue(cleanup.contains("ip -4 rule del pref 8999 to 198.18.0.0/30 lookup 20230"))
        assertTrue(cleanup.contains("ip -6 rule del pref 8999 to fdfe:dcba:9876::/126 lookup 20230"))
        assertTrue(cleanup.contains("ip -4 route del default dev mclash0"))
        assertTrue(cleanup.contains("ip -6 route del default dev mclash0"))
    }
}
