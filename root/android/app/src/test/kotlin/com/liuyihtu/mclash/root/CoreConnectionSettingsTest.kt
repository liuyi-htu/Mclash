package com.liuyihtu.mclash.root

import java.io.File
import org.junit.Assert.*
import org.junit.Test
import org.yaml.snakeyaml.Yaml

class CoreConnectionSettingsTest {
    @Test fun injectsCustomControllerSecretAndMixedPort() {
        val settings = CoreConnectionSettings("0.0.0.0:9191", "test:#' key", 7891)
        val text = RootRuntimeConfig.build("proxies: []\n", false, connection = settings)
        val yaml = Yaml().load<Map<String, Any>>(text)
        assertEquals(settings.controller, yaml["external-controller"])
        assertEquals(settings.secret, yaml["secret"])
        assertEquals(7891, yaml["mixed-port"])
        val file = File.createTempFile("runtime-", ".yaml")
        try {
            file.writeText(text)
            assertEquals(settings, CoreConnectionSettings.fromRuntime(file))
        } finally { file.delete() }
    }
    @Test fun wildcardAndIpv6ConnectionHosts() {
        assertEquals("127.0.0.1", CoreConnectionSettings("0.0.0.0:9191").host)
        val ipv6 = CoreConnectionSettings("[::]:9191")
        ipv6.validate()
        assertEquals("::1", ipv6.host)
    }
    @Test fun rejectsInvalidAndReservedPorts() {
        for (value in listOf(CoreConnectionSettings(mixedPort = 0), CoreConnectionSettings(mixedPort = 9090), CoreConnectionSettings(mixedPort = 11053), CoreConnectionSettings("127.0.0.1:17894"), CoreConnectionSettings("example.org:9090"), CoreConnectionSettings(secret = "test\nvalue"))) {
            assertTrue(runCatching { value.validate() }.isFailure)
        }
    }
    @Test fun supervisorWaitsForCustomizedListeners() {
        val script = RootSupervisor.script(File("/data/test"), File("/data/core"), 1234, false, false, CoreConnectionSettings("127.0.0.1:9191", mixedPort = 7891))
        assertTrue(script.contains(":1ED3"))
        assertTrue(script.contains(":23E7"))
        assertFalse(script.contains(":45E2"))
    }
}
