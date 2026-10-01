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
        assertEquals(listOf("DIRECT", "上海专线"), (groups[0] as Map<*, *>)["proxies"])
        assertEquals(listOf("DIRECT"), (groups[1] as Map<*, *>)["proxies"])
    }

    @Test fun preservesFiltersWhenRefreshingNodes() {
        val source = "proxies: [{name: KR, type: ss}, {name: 广州, type: ss}]"
        val previous = SubscriptionConfig.build(template, source)
            .replace("# Mclash 国内正则: \"上海\"", "# Mclash 国内正则: \"广州\"")
            .replace("# Mclash 国外正则: \"KR\"", "# Mclash 国外正则: \"\"")
        val text = SubscriptionConfig.build(template, source, previous)
        val result = Yaml().load<Map<String, Any>>(text)
        val groups = result["proxy-groups"] as List<*>
        assertEquals(listOf("DIRECT", "广州"), (groups[0] as Map<*, *>)["proxies"])
        assertEquals(listOf("KR", "广州"), (groups[1] as Map<*, *>)["proxies"])
        assertFalse((groups[1] as Map<*, *>).containsKey("filter"))
        assertTrue(text.contains("# Mclash 国内正则: \"广州\""))
    }


    @Test fun preservesHostForVmessHttpAndWsOnlyOnRefresh() {
        val source = """
            proxies:
              - {name: KR-http, type: vmess, network: http, server: origin.example, servername: tls.example, http-opts: {path: [/abc], headers: {host: [old.example], X-Test: [keep]}}}
              - {name: KR-ws, type: vmess, network: ws, ws-opts: {path: /ws, headers: {Host: old.example, X-Test: keep}}}
              - {name: KR-new, type: vmess, network: ws}
              - {name: KR-vless, type: vless, network: ws, ws-opts: {headers: {Host: original.example}}}
              - {name: KR-h2, type: vmess, network: h2, h2-opts: {host: [original.example]}}
              - {name: KR-tcp, type: vmess, network: tcp}
        """.trimIndent()
        val previous = "# Mclash HTTP/WS Host: \"new.example\"\n" + SubscriptionConfig.build(template, source)
        val text = SubscriptionConfig.build(template, source, previous)
        val nodes = Yaml().load<Map<String, Any>>(text)["proxies"] as List<*>
        val original = Yaml().load<Map<String, Any>>(source)["proxies"] as List<*>
        val httpNode = nodes[0] as Map<*, *>
        val httpOptions = httpNode["http-opts"] as Map<*, *>
        val httpHeaders = httpOptions["headers"] as Map<*, *>
        assertEquals(listOf("new.example"), httpHeaders["Host"])
        assertFalse(httpHeaders.containsKey("host"))
        assertEquals(listOf("keep"), httpHeaders["X-Test"])
        assertEquals(listOf("/abc"), httpOptions["path"])
        assertEquals("origin.example", httpNode["server"])
        assertEquals("tls.example", httpNode["servername"])
        for (i in 1..2) {
            assertEquals("new.example", (((nodes[i] as Map<*, *>)["ws-opts"] as Map<*, *>)["headers"] as Map<*, *>)["Host"])
        }
        assertEquals("/ws", ((nodes[1] as Map<*, *>)["ws-opts"] as Map<*, *>)["path"])
        for (i in 3..5) assertEquals(original[i], nodes[i])
        assertTrue(text.contains("# Mclash HTTP/WS Host: \"new.example\""))
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
        assertEquals(listOf("DIRECT"), (groups[1] as Map<*, *>)["proxies"])
    }
    @Test fun refreshPreservesManualNodesAndTheirHost() {
        val source = "proxies: [{name: KR, type: ss}]"
        val previous = """
            # Mclash 手动节点: ["上海手动"]
            proxies: [{name: 上海手动, type: vmess, network: ws, ws-opts: {headers: {Host: preset.example}}}]
        """.trimIndent()
        val text = SubscriptionConfig.build(template, source, previous)
        val nodes = Yaml().load<Map<String, Any>>(text)["proxies"] as List<*>
        assertEquals(2, nodes.size)
        assertEquals("上海手动", (nodes[1] as Map<*, *>)["name"])
        assertEquals("preset.example", ((((nodes[1] as Map<*, *>)["ws-opts"] as Map<*, *>)["headers"] as Map<*, *>)["Host"]))
        assertTrue(text.contains("# Mclash 手动节点: [\"上海手动\"]"))
        val repeated = SubscriptionConfig.build(template, "proxies: [{name: 上海手动, type: ss}]", text)
        val refreshedNodes = Yaml().load<Map<String, Any>>(repeated)["proxies"] as List<*>
        assertEquals(1, refreshedNodes.size)
        assertEquals("vmess", (refreshedNodes[0] as Map<*, *>)["type"])
    }

}
