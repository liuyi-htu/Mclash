package com.liuyihtu.mclash

import org.junit.Assert.*
import org.junit.Test
import org.yaml.snakeyaml.Yaml

class VpnDnsRuntimeTest {
    @Test fun preservesDnsPoliciesRulesAndMetadata() {
        val original = """
            # Mclash 国内正则: 测试
            mode: global
            dns:
              enable: false
              ipv6: false
              enhanced-mode: fake-ip
              nameserver: [https://dns.alidns.com/dns-query]
              nameserver-policy: {+.qq.com: 223.5.5.5}
            proxies: [{name: Mclash 内部 DNS, type: direct}]
            rules: [MATCH,DIRECT]
        """.trimIndent()
        val output = VpnDnsRuntime.build(original, true)
        assertTrue(output.startsWith("# Mclash 国内正则: 测试\n"))
        val map = Yaml().load<Map<String, Any>>(output)
        val dns = map["dns"] as Map<*, *>
        assertEquals(true, dns["enable"])
        assertEquals(true, dns["ipv6"])
        assertEquals("fake-ip", dns["enhanced-mode"])
        assertEquals(listOf("https://dns.alidns.com/dns-query"), dns["nameserver"])
        assertEquals(mapOf("+.qq.com" to "223.5.5.5"), dns["nameserver-policy"])
        assertEquals("global", map["mode"])
        assertEquals(listOf("MATCH", "DIRECT"), map["rules"])
        val listener = (map["listeners"] as List<*>).single() as Map<*, *>
        assertEquals("Mclash 内部 DNS 1", listener["proxy"])
        assertEquals(true, listener["udp"])
        assertEquals("127.0.0.1", listener["listen"])
    }
    @Test fun addsResolverForConfigWithoutDns() {
        val map = Yaml().load<Map<String, Any>>(VpnDnsRuntime.build("mode: direct\n", false))
        val dns = map["dns"] as Map<*, *>
        assertEquals(false, dns["ipv6"])
        assertTrue((dns["nameserver"] as List<*>).isNotEmpty())
        assertEquals("direct", map["mode"])
    }
    @Test fun keepsInternalResolverOutOfAutomaticAndGlobalGroups() {
        val source = """
            proxies: [{name: test-node, type: direct}]
            proxy-groups: [{name: automatic, type: url-test, include-all-proxies: true, exclude-filter: blocked}]
        """.trimIndent()
        val map = Yaml().load<Map<String, Any>>(VpnDnsRuntime.build(source, true))
        val groups = map["proxy-groups"] as List<*>
        val automatic = groups[0] as Map<*, *>
        assertEquals("blocked`^Mclash 内部 DNS$", automatic["exclude-filter"])
        val global = groups[1] as Map<*, *>
        assertEquals(listOf("DIRECT", "REJECT", "test-node", "automatic"), global["proxies"])
        assertFalse((global["proxies"] as List<*>).contains("Mclash 内部 DNS"))
    }
    @Test(expected = IllegalArgumentException::class)
    fun refusesReservedPortCollision() {
        VpnDnsRuntime.build("listeners: [{name: existing, type: socks, port: 7891}]", true)
    }
}
