package com.liuyihtu.mclash.root

import org.junit.Assert.*
import org.junit.Test
import org.yaml.snakeyaml.Yaml
import java.io.File

class SubscriptionConfigTest {
    private val template = File("../../../assets/default-config.yaml").readText()

    @Test fun linksNormalizeAndValidateEveryUrl() {
        assertEquals(listOf("https://example.org/a", "https://example.org/b"),
            SubscriptionConfig.links(" https://example.org/a\r\n\r\nhttps://example.org/b\nhttps://example.org/a "))
        assertThrows(IllegalArgumentException::class.java) { SubscriptionConfig.links("https://example.org/a\nfile:///tmp/a") }
    }

    @Test fun mergeSourcesPrefixesNamesAndRetainsNestedOptionsAndDialers() {
        val content = SubscriptionConfig.mergeSources(listOf(
            "proxies: [{name: Same, type: http}, {name: 'Same (订阅 2)', type: http}]",
            "proxies: [{name: Same, type: vmess, ws-opts: {headers: {Host: example.org}}}, {name: Child, type: http, dialer-proxy: Same}]",
        ))
        val nodes = Yaml().load<Map<String, Any>>(content)["proxies"] as List<Map<String, Any>>
        assertEquals(listOf("1-Same", "1-Same (订阅 2)", "2-Same", "2-Child"), nodes.map { it["name"] })
        assertEquals("2-Same", nodes.last()["dialer-proxy"])
        assertEquals(mapOf("headers" to mapOf("Host" to "example.org")), nodes[2]["ws-opts"])
        val result = Yaml().load<Map<String, Any>>(SubscriptionConfig.build(template, content))
        assertEquals(nodes, result["proxies"])
    }

    @Test fun mergeRejectsInvalidOrEmptySubscriptionInsteadOfDroppingIt() {
        for (invalid in listOf("proxies: []", "proxies: [{name: A}]", "proxies: [{name: A, type: http}, {name: A, type: http}]")) {
            assertThrows(IllegalArgumentException::class.java) {
                SubscriptionConfig.mergeSources(listOf("proxies: [{name: Good, type: http}]", invalid))
            }
        }
    }

    @Test fun multipleChainSetsRefreshIndependentlyIncludingManualBackNodes() {
        val previous = """
            # Mclash 链路设置: {"1":{"front":["wap"],"frontTargets":["上海"]},"2":{"front":["front2"],"frontTargets":["KR"]},"3":{"back":["back1"],"backTargets":["US"]}}
            # Mclash 手动节点: ["back1"]
            proxies: [{name: back1, type: http}]
        """.trimIndent()
        val source = "proxies: [{name: 上海, type: http}, {name: KR, type: http}, {name: US, type: http}, {name: wap, type: http}, {name: front2, type: http}]"
        val result = SubscriptionConfig.build(template, source, previous)
        val nodes = (Yaml().load<Map<String, Any>>(result)["proxies"] as List<*>).associateBy { (it as Map<*, *>)["name"] }
        assertEquals("wap", (nodes["上海"] as Map<*, *>)["dialer-proxy"])
        assertEquals("front2", (nodes["KR"] as Map<*, *>)["dialer-proxy"])
        assertEquals("US", (nodes["back1"] as Map<*, *>)["dialer-proxy"])
        assertTrue(result.contains("# Mclash 节点链路 1: {\"上海\":\"wap\"}"))
        assertTrue(result.contains("# Mclash 节点链路 2: {\"KR\":\"front2\"}"))
        assertTrue(result.contains("# Mclash 节点链路 3: {\"back1\":\"US\"}"))
        val runtime = SubscriptionConfig.runtimeMetadata(result)
        assertFalse(runtime.contains("# Mclash 节点链路: "))
        assertFalse(runtime.contains("# Mclash 链路设置: "))
        assertTrue(runtime.contains("# Mclash 节点链路 3: "))
        val removed = SubscriptionConfig.build(template, source.replace("{name: KR, type: http}, ", ""), result)
        assertTrue(removed.contains("# Mclash 节点链路 2: {}"))
        val bad = previous.replace("\"frontTargets\":[\"KR\"]", "\"frontTargets\":[\"上海\"]")
        assertTrue(runCatching { SubscriptionConfig.build(template, source, bad) }.isFailure)
    }

    @Test fun runtimeMetadataFollowsMenuSectionsAndChainDirections() {
        val metadata = """
            # Mclash 代理组正则: {"测速":"^JP"}
            # Mclash 链路设置: {"1":{"back":["A"]},"2":{"front":["B"]},"3":{"back":["C"]}}
            # Mclash 节点链路 3: {"C":"JP"}
            # Mclash 节点链路 1: {"A":"JP"}
            # Mclash 链路代理组: {"Chain":["JP"]}
            # Mclash HTTP/WS Host: "gw.alicdn.com"
            # Mclash 节点链路 2: {"JP":"B"}
            # Mclash 手动节点: ["A"]
        """.trimIndent()
        val nodes = listOf(metadata.lines()[7], metadata.lines()[5], metadata.lines()[6], metadata.lines()[3], metadata.lines()[2])
        val groups = listOf(metadata.lines()[4], metadata.lines()[0])
        for (groupsFirst in listOf(false, true)) {
            val body = if (groupsFirst) "proxy-groups: []\nproxies: []\nrules: []\n" else "proxies: []\nproxy-groups: []\nrules: []\n"
            val source = metadata + "\n" + body + "description: |\n  # Mclash HTTP/WS Host: literal text\n"
            val result = SubscriptionConfig.runtimeMetadata("\uFEFF" + source.replace("\n", "\r\n"))
            assertEquals(if (groupsFirst) groups + nodes else nodes + groups, result.lines().filter { it.startsWith("# Mclash ") })
            assertEquals(Yaml().load<Any>(source), Yaml().load<Any>(result))
            assertEquals(result, SubscriptionConfig.runtimeMetadata(result))
        }
    }

    @Test fun runtimeMetadataConsolidatesFiltersAndKeepsEffectiveNodeChains() {
        val source = """
            # Mclash 全局链路: {"front":["wap"]}
            # Mclash 节点链路: {"JP":"wap"}
            # Mclash 国内正则: "北京"
            # Mclash 国外正则: "JP"
            # Mclash 代理组正则: {"🚀 国内":"old","🌍 国外":"old","测速":"^JP"}
            proxies: [{name: wap, type: http}, {name: JP, type: http, dialer-proxy: wap}]
            proxy-groups: [{name: 测速, type: select, proxies: [JP]}]
        """.trimIndent()
        val result = SubscriptionConfig.runtimeMetadata("\uFEFF" + source.replace("\n", "\r\n"))
        assertTrue(result.contains("# Mclash 代理组正则: {\"🚀 国内\":\"北京\",\"🌍 国外\":\"JP\",\"测速\":\"^JP\"}\n"))
        assertTrue(result.startsWith("# Mclash 节点链路: "))
        assertFalse(result.contains("# Mclash 全局链路:"))
        assertFalse(result.contains("# Mclash 国内正则:"))
        assertFalse(result.contains("# Mclash 国外正则:"))
        assertTrue(result.contains("# Mclash 节点链路: {\"JP\":\"wap\"}"))
        assertEquals(Yaml().load<Any>(source), Yaml().load<Any>(result))
        assertEquals(result, SubscriptionConfig.runtimeMetadata(result))
    }

    @Test fun refreshRetainsCustomRulesGroupsAndArbitraryFilters() {
        val previous = """
            # Mclash 代理组正则: {"测速":"^JP"}
            proxies: [{name: Old, type: http}, {name: Keep, type: http}]
            proxy-groups:
              - {name: 手选, type: select, proxies: [Old, Keep]}
              - {name: 空组, type: select, proxies: [Old]}
              - {name: 测速, type: url-test, proxies: [Old], url: 'https://example.org', interval: 60, tolerance: 30}
              - {name: 总组, type: select, proxies: [手选, 测速]}
            rules: ['DOMAIN-SUFFIX,example.org,总组', 'MATCH,DIRECT']
        """.trimIndent()
        val text = SubscriptionConfig.build(template,
            "proxies: [{name: Keep, type: http}, {name: JP New, type: http}, {name: US New, type: http}]", previous)
        val yaml = Yaml()
        val result = yaml.load<Map<String, Any>>(text)
        assertEquals(yaml.load<Map<String, Any>>(previous)["rules"], result["rules"])
        val groups = (result["proxy-groups"] as List<*>).filterIsInstance<Map<*, *>>()
        assertEquals(listOf("手选", "空组", "测速", "总组"), groups.map { it["name"] })
        assertEquals(listOf("Keep"), groups[0]["proxies"])
        assertEquals(listOf("DIRECT"), groups[1]["proxies"])
        assertEquals(listOf("JP New"), groups[2]["proxies"])
        assertEquals(60, groups[2]["interval"])
        assertEquals(30, groups[2]["tolerance"])
        assertEquals(listOf("手选", "测速"), groups[3]["proxies"])
        assertTrue(text.contains("# Mclash 代理组正则: {\"测速\":\"^JP\"}"))
        assertFalse(text.contains("# Mclash 代理组「测速」正则:"))
        assertTrue(text.indexOf("# Mclash 代理组正则:") < text.indexOf("proxies:"))
    }

    @Test fun emptyFilterMapKeepsRegionalManualSelection() {
        val previous = """
            # Mclash 代理组正则: {}
            proxies: [{name: Keep, type: http}]
            proxy-groups: [{name: 🚀 国内, type: select, proxies: [Keep]}]
            rules: ['MATCH,🚀 国内']
        """.trimIndent()
        val result = Yaml().load<Map<String, Any>>(SubscriptionConfig.build(template,
            "proxies: [{name: Keep, type: http}, {name: New, type: http}]", previous))
        assertEquals(listOf("Keep"), ((result["proxy-groups"] as List<*>)[0] as Map<*, *>)["proxies"])
    }

    @Test fun missingNodeReferencedByRuleRejectsRefresh() {
        val previous = "# Mclash 代理组正则: {}\nproxies: [{name: Old, type: http}]\nproxy-groups: [{name: Custom, type: select, proxies: [Old]}]\nrules: ['IP-CIDR,1.1.1.0/24,Old,no-resolve,src']"
        val error = assertThrows(IllegalArgumentException::class.java) {
            SubscriptionConfig.build(template, "proxies: [{name: New, type: http}]", previous)
        }
        assertTrue(error.message!!.contains("仍被规则引用"))
    }

    @Test fun refreshDoesNotRewriteManualHostOrDialer() {
        val previous = """
            # Mclash 手动节点: ["Manual"]
            # Mclash HTTP/WS Host: "preset.example"
            # Mclash 节点链路: {"Manual":"KR New"}
            proxies: [{name: Manual, type: vmess, server: manual.example, port: 443, uuid: test, network: ws, dialer-proxy: KR, ws-opts: {headers: {Host: custom.example}}, udp: true}, {name: KR, type: http, server: old.example, port: 80}]
        """.trimIndent()
        val incoming = "proxies: [{name: Manual, type: http, server: overwritten.example, port: 80}, {name: KR, type: http, server: updated.example, port: 80}, {name: KR New, type: http, server: new.example, port: 80}]"
        val yaml = Yaml()
        val result = yaml.load<Map<String, Any>>(SubscriptionConfig.build(template, incoming, previous))
        val nodes = (result["proxies"] as List<*>).filterIsInstance<Map<*, *>>()
        assertEquals((yaml.load<Map<String, Any>>(previous)["proxies"] as List<*>)[0], nodes.first { it["name"] == "Manual" })
        assertEquals("updated.example", nodes.first { it["name"] == "KR" }["server"])
    }

    @Test fun globalFrontNodesConnectSeriallyInSavedOrder() {
        val subscription = "proxies: [{name: 上海, type: http}, {name: KR, type: http}, {name: wap, type: http}]"
        for (front in listOf(listOf("wap", "KR"), listOf("KR", "wap"))) {
            val previous = "# Mclash 全局链路: {\"front\":[${front.joinToString(",") { "\"$it\"" }}]}\nproxies: []"
            val result = Yaml().load<Map<String, Any>>(SubscriptionConfig.build(template, subscription, previous))
            val nodes = (result["proxies"] as List<*>).filterIsInstance<Map<*, *>>().associateBy { it["name"] }
            assertEquals(front.last(), nodes["上海"]!!["dialer-proxy"])
            assertEquals(front.first(), nodes[front.last()]!!["dialer-proxy"])
            assertNull(nodes[front.first()]!!["dialer-proxy"])
        }
    }

    @Test fun globalChainsCoverNewNodesAndAvoidFrontBackCycles() {
        val previous = "# Mclash 全局链路: {\"front\":[\"wap\"],\"back\":[\"exit\"]}\nproxies: []"
        val subscription = "proxies: [{name: 上海, type: http}, {name: KR, type: http}, {name: wap, type: http}, {name: exit, type: http}]"
        val result = Yaml().load<Map<String, Any>>(SubscriptionConfig.build(template, subscription, previous))
        val nodes = (result["proxies"] as List<*>).filterIsInstance<Map<*, *>>()
        assertEquals("wap", nodes[0]["dialer-proxy"])
        assertEquals("wap", nodes[1]["dialer-proxy"])
        assertNull(nodes[2]["dialer-proxy"])
        val groups = (result["proxy-groups"] as List<*>).filterIsInstance<Map<*, *>>()
        val group = groups.first { it["name"] == nodes[3]["dialer-proxy"] }
        assertEquals(listOf("上海", "KR"), group["proxies"])
    }

    @Test fun explicitChainTargetsDoNotExpandWhenSubscriptionRefreshes() {
        val previous = "# Mclash 全局链路: {\"front\":[\"wap\"],\"back\":[\"exit\"],\"frontTargets\":[\"A\"],\"backTargets\":[\"A\"]}\nproxies: []"
        val source = "proxies: [{name: A, type: http}, {name: B, type: http}, {name: New, type: http}, {name: wap, type: http}, {name: exit, type: http}]"
        val nodes = (Yaml().load<Map<String, Any>>(SubscriptionConfig.build(template, source, previous))["proxies"] as List<*>)
            .filterIsInstance<Map<*, *>>().associateBy { it["name"] }
        assertEquals("wap", nodes["A"]!!["dialer-proxy"])
        assertEquals("A", nodes["exit"]!!["dialer-proxy"])
        assertNull(nodes["B"]!!["dialer-proxy"])
        assertNull(nodes["New"]!!["dialer-proxy"])
        val missing = SubscriptionConfig.build(template,
            "proxies: [{name: B, type: http}, {name: wap, type: http}, {name: exit, type: http}]", previous)
        val remaining = (Yaml().load<Map<String, Any>>(missing)["proxies"] as List<*>)
            .filterIsInstance<Map<*, *>>()
        assertTrue(remaining.all { it["dialer-proxy"] == null })
    }

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
        assertEquals(listOf("DIRECT", "上海专线", "hk Premium"), (groups[0] as Map<*, *>)["proxies"])
        assertEquals(listOf("上海专线", "hk Premium"), (groups[1] as Map<*, *>)["proxies"])
    }

    @Test fun missingFilterMetadataDefaultsToEmptyAndIncludesAllNodes() {
        val bareTemplate = template.lineSequence()
            .filterNot { it.startsWith("# Mclash 国内正则:") || it.startsWith("# Mclash 国外正则:") }
            .joinToString("\n")
        val source = "proxies: [{name: 广州, type: http}, {name: 美国, type: http}]"
        val text = SubscriptionConfig.build(bareTemplate, source)
        assertTrue(text.contains("# Mclash 代理组正则: {\"🚀 国内\":\"\",\"🌍 国外\":\"\"}"))
        assertFalse(text.contains("# Mclash 国内正则:"))
        assertFalse(text.contains("# Mclash 国外正则:"))
        val groups = Yaml().load<Map<String, Any>>(text)["proxy-groups"] as List<*>
        assertEquals(listOf("DIRECT", "广州", "美国"), (groups[0] as Map<*, *>)["proxies"])
        assertEquals(listOf("广州", "美国"), (groups[1] as Map<*, *>)["proxies"])
    }

    @Test fun preservesFiltersWhenRefreshingNodes() {
        val source = "proxies: [{name: KR, type: ss}, {name: 广州, type: ss}]"
        val previous = SubscriptionConfig.build(
            template.replace("# Mclash 国外正则: \"\"", "# Mclash 国外正则: \"KR\""), source)
            .replace("\"🚀 国内\":\"\"", "\"🚀 国内\":\"广州\"")
            .replace("\"🌍 国外\":\"KR\"", "\"🌍 国外\":\"\"")
        val text = SubscriptionConfig.build(template, source, previous)
        val result = Yaml().load<Map<String, Any>>(text)
        val groups = result["proxy-groups"] as List<*>
        assertEquals(listOf("DIRECT", "广州"), (groups[0] as Map<*, *>)["proxies"])
        assertEquals(listOf("KR", "广州"), (groups[1] as Map<*, *>)["proxies"])
        assertFalse((groups[1] as Map<*, *>).containsKey("filter"))
        assertTrue(text.contains("\"🚀 国内\":\"广州\""))
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
        val filteredTemplate = template.replace("# Mclash 国外正则: \"\"", "# Mclash 国外正则: \"KR\"")
        val result = Yaml().load<Map<String, Any>>(SubscriptionConfig.build(filteredTemplate,
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

    @Test fun refreshPreservesProxyChainsAndRejectsCycles() {
        val source = "proxies: [{name: KR, type: ss}, {name: wap, type: http}]"
        val previous = "# Mclash 节点链路: {\"KR\":\"wap\"}\n" + SubscriptionConfig.build(template, source)
        val text = SubscriptionConfig.build(template, source, previous)
        val nodes = Yaml().load<Map<String, Any>>(text)["proxies"] as List<*>
        assertEquals("wap", (nodes[0] as Map<*, *>)["dialer-proxy"])
        assertFalse((nodes[1] as Map<*, *>).containsKey("dialer-proxy"))
        assertTrue(text.contains("# Mclash 节点链路:"))
        val cycle = "# Mclash 节点链路: {\"KR\":\"wap\",\"wap\":\"KR\"}\n"
        assertTrue(runCatching { SubscriptionConfig.build(template, source, cycle) }.isFailure)
        val missing = SubscriptionConfig.build(template, "proxies: [{name: KR, type: ss}]", previous)
        val remaining = Yaml().load<Map<String, Any>>(missing)["proxies"] as List<*>
        assertFalse((remaining[0] as Map<*, *>).containsKey("dialer-proxy"))
    }

    @Test fun refreshPreservesBatchChainGroupsAndDetectsGroupCycles() {
        val source = "proxies: [{name: KR, type: ss}, {name: 广州, type: ss}, {name: wap, type: http}, {name: other, type: http}]"
        val metadata = """
            # Mclash 节点链路: {"KR":"Front","广州":"Front"}
            # Mclash 链路代理组: {"Front":["wap","other"]}
        """.trimIndent()
        val text = SubscriptionConfig.build(template, source, metadata)
        val config = Yaml().load<Map<String, Any>>(text)
        val nodes = config["proxies"] as List<*>
        assertEquals("Front", (nodes[0] as Map<*, *>)["dialer-proxy"])
        assertEquals("Front", (nodes[1] as Map<*, *>)["dialer-proxy"])
        val groups = config["proxy-groups"] as List<*>
        assertEquals(listOf("wap", "other"), (groups.last() as Map<*, *>)["proxies"])
        assertTrue(text.contains("# Mclash 链路代理组:"))
        val cycle = metadata.replace("[\"wap\",\"other\"]", "[\"KR\",\"other\"]")
        assertTrue(runCatching { SubscriptionConfig.build(template, source, cycle) }.isFailure)
    }

}
