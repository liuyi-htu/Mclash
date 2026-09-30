package com.liuyihtu.mclash

import org.junit.Assert.*
import org.junit.Test
import org.yaml.snakeyaml.Yaml
import java.io.File

class SubscriptionConfigTest {
    private val template = File("../../../assets/default-config.yaml").readText()

    @Test fun embedsNodesWithDefaultPolicy() {
        val subscription = """
            proxies:
              - {name: 上海专线, type: ss, password: 'secret:#'}
              - {name: hk Premium, type: vmess, ws-opts: {headers: {Host: example.org}}}
            rules: [MATCH,REJECT]
            dns: {enable: false}
        """.trimIndent()
        val yaml = Yaml()
        val result = yaml.load<Map<String, Any>>(SubscriptionConfig.build(template, subscription))
        val original = yaml.load<Map<String, Any>>(template)
        assertFalse(result.containsKey("proxy-providers"))
        assertEquals(yaml.load<Map<String, Any>>(subscription)["proxies"], result["proxies"])
        assertEquals(original["dns"], result["dns"])
        assertEquals(original["rules"], result["rules"])
        val groups = result["proxy-groups"] as List<*>
        assertEquals(listOf("DIRECT"), (groups[0] as Map<*, *>)["proxies"])
        assertEquals(emptyList<String>(), (groups[1] as Map<*, *>)["proxies"])
    }

    @Test fun preservesFiltersWhenRefreshingNodes() {
        val source = "proxies: [{name: KR, type: ss}]"
        val previous = SubscriptionConfig.build(template, source)
            .replace("filter: 上海", "filter: 广州")
            .replace("filter: KR", "filter: ''")
        val result = Yaml().load<Map<String, Any>>(SubscriptionConfig.build(template, source, previous))
        val groups = result["proxy-groups"] as List<*>
        assertEquals("广州", (groups[0] as Map<*, *>)["filter"])
        assertEquals("", (groups[1] as Map<*, *>)["filter"])
        assertEquals(true, (groups[1] as Map<*, *>)["include-all-proxies"])
    }

    @Test fun rejectsInvalidNodesAndFallsBackForMissingRegions() {
        for (source in listOf("proxies: []", "proxy-providers: {}", "proxies: [bad]",
            "proxies: [{name: DIRECT, type: ss}]",
            "proxies: [{name: duplicate, type: ss}, {name: duplicate, type: ss}]")) {
            assertTrue(runCatching { SubscriptionConfig.build(template, source) }.isFailure)
        }
        val result = Yaml().load<Map<String, Any>>(SubscriptionConfig.build(template,
            "proxies: [{name: 美国, type: ss}]"))
        val groups = result["proxy-groups"] as List<*>
        assertEquals("DIRECT", (groups[1] as Map<*, *>)["empty-fallback"])
    }
}
