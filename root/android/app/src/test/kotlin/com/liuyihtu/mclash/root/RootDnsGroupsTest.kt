package com.liuyihtu.mclash.root

import org.junit.Assert.*
import org.junit.Test
import org.yaml.snakeyaml.Yaml

class RootDnsGroupsTest {
    private fun runtime(source: String, ipv6: Boolean = true): Map<String, Any> =
        Yaml().load(RootRuntimeConfig.build(source, false, ipv6 = ipv6))

    @Test fun implicitGlobalRetainsOriginalOrderWithoutPrivateDns() {
        val source = """
            mode: global
            proxies: [{name: node, type: direct}, {name: skip, type: pass}]
            proxy-groups: [{name: selected, type: select, proxies: [node, DIRECT]}]
            rules: ['MATCH,selected']
            dns: {nameserver: [https://dns.alidns.com/dns-query], nameserver-policy: {+.qq.com: 223.5.5.5}}
        """.trimIndent()
        val config = runtime(source)
        val groups = config["proxy-groups"] as List<*>
        val global = groups.last() as Map<*, *>
        assertEquals("GLOBAL", global["name"])
        assertEquals(listOf("DIRECT", "REJECT", "node", "selected"), global["proxies"])
        assertEquals("global", config["mode"])
        assertEquals(listOf("MATCH,selected"), config["rules"])
        val dns = config["dns"] as Map<*, *>
        assertEquals(listOf("https://dns.alidns.com/dns-query"), dns["nameserver"])
        assertEquals(mapOf("+.qq.com" to "223.5.5.5"), dns["nameserver-policy"])
        val dnsProxy = (config["proxies"] as List<*>).last() as Map<*, *>
        assertEquals("dns", dnsProxy["type"])
        val listener = (config["listeners"] as List<*>).last() as Map<*, *>
        assertEquals(dnsProxy["name"], listener["proxy"])
        assertEquals(RootRuntimeConfig.IPV6_DNS_TPROXY_PORT, listener["port"])
    }

    @Test fun existingGlobalAndAutomaticGroupsKeepPoliciesAndFilters() {
        val source = """
            proxies: [{name: node, type: direct}]
            proxy-groups:
              - {name: GLOBAL, type: select, include-all: true, proxies: [node], exclude-filter: blocked}
              - {name: automatic, type: url-test, include-all-proxies: true, interval: 600, url: 'https://example.com'}
              - {name: fallback, type: fallback, include-all: true}
              - {name: balanced, type: load-balance, include-all-proxies: true}
        """.trimIndent()
        val config = runtime(source)
        val groups = config["proxy-groups"] as List<*>
        assertEquals(4, groups.size)
        val global = groups.first() as Map<*, *>
        assertEquals(true, global["include-all"])
        assertEquals(listOf("node"), global["proxies"])
        assertEquals("blocked`^Mclash-IPv6-DNS$", global["exclude-filter"])
        for (group in groups.drop(1)) assertEquals("^Mclash-IPv6-DNS$", (group as Map<*, *>)["exclude-filter"])
        val automatic = groups[1] as Map<*, *>
        assertEquals(600, automatic["interval"])
        assertEquals("https://example.com", automatic["url"])
    }

    @Test fun existingNodeWithSameNameIsNotExcluded() {
        val config = runtime("proxies: [{name: Mclash-IPv6-DNS, type: direct}]\nproxy-groups: [{name: all, type: select, include-all: true}]")
        val privateDns = (config["proxies"] as List<*>).last() as Map<*, *>
        assertEquals("Mclash-IPv6-DNS_", privateDns["name"])
        val global = (config["proxy-groups"] as List<*>).last() as Map<*, *>
        assertTrue((global["proxies"] as List<*>).contains("Mclash-IPv6-DNS"))
        assertFalse((global["proxies"] as List<*>).contains("Mclash-IPv6-DNS_"))
        assertEquals("^Mclash-IPv6-DNS_$", global["exclude-filter"])
    }

    @Test fun ipv6OffLeavesGroupsAndProxiesUnchanged() {
        val source = "proxies: [{name: node, type: direct}]\nproxy-groups: [{name: selected, type: select, proxies: [node]}]"
        val original = Yaml().load<Map<String, Any>>(source)
        val config = runtime(source, false)
        assertEquals(original["proxy-groups"], config["proxy-groups"])
        assertEquals(original["proxies"], config["proxies"])
        assertFalse(config.containsKey("listeners"))
    }
}
