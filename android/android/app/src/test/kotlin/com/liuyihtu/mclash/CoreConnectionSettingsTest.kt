package com.liuyihtu.mclash

import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.yaml.snakeyaml.Yaml

class CoreConnectionSettingsTest {
    @Test fun customRuntimePreservesSourceAndInternalDnsPort() {
        val directory = java.nio.file.Files.createTempDirectory("vpn-core-settings").toFile()
        val source = File(directory, "source.yaml").apply { writeText("proxies: []\n") }
        val settings = CoreConnectionSettings("[::]:9191", "test:#' key", 7892)
        try {
            val runtime = MihomoProcess.prepareRuntimeConfig(source, directory, false, false, connection = settings)
            val config = Yaml().load<Map<String, Any>>(runtime.readText())
            assertEquals(settings.controller, config["external-controller"])
            assertEquals(settings.secret, config["secret"])
            assertEquals(settings.mixedPort, config["mixed-port"])
            assertEquals(settings, CoreConnectionSettings.fromRuntime(runtime))
            assertEquals("proxies: []\n", source.readText())
            assertTrue((config["listeners"] as List<*>).any { (it as Map<*, *>)["port"] == VpnDnsRuntime.SOCKS_PORT })
        } finally { directory.deleteRecursively() }
    }
    @Test fun rejectsDnsPortCollisionsAndInvalidAddress() {
        for (value in listOf(CoreConnectionSettings(mixedPort = 7891), CoreConnectionSettings("127.0.0.1:7891"), CoreConnectionSettings(mixedPort = 9090), CoreConnectionSettings("example.org:9090"), CoreConnectionSettings(secret = "test\nvalue"))) {
            assertTrue(runCatching { value.validate() }.isFailure)
        }
    }
}
