package com.liuyihtu.mclash.root

import org.junit.Assert.*
import org.junit.Test
import org.yaml.snakeyaml.Yaml

class RootRuntimeConfigTest {
    @Test fun runtimeOverridesConflictingListenersButRetainsRoutingAndUpstreamDns() {
        val source = """
            mixed-port: 9999
            tproxy-port: 8888
            tun: {enable: true, auto-route: true}
            listeners: [{name: public, type: mixed, port: 7777, listen: 0.0.0.0}]
            external-controller-tls: 0.0.0.0:4443
            external-controller-unix: /tmp/core.sock
            external-ui-url: https://example.com/ui.zip
            routing-mark: 123
            secret: imported-secret
            dns:
              enable: false
              listen: 0.0.0.0:53
              ipv6: true
              enhanced-mode: fake-ip
              nameserver: [https://dns.example/dns-query]
              default-nameserver: [8.8.8.8]
              nameserver-policy: {example.com: 1.1.1.1}
            proxies: [{name: a, type: socks5, server: example.com, port: 1080}]
            rules: [MATCH,a]
        """.trimIndent()
        val runtime = Yaml().load<Map<String, Any>>(RootRuntimeConfig.build(source, false))
        assertFalse(runtime.containsKey("tun"))
        assertFalse(runtime.containsKey("listeners"))
        assertFalse(runtime.containsKey("external-controller-tls"))
        assertFalse(runtime.containsKey("external-controller-unix"))
        assertFalse(runtime.containsKey("external-ui-url"))
        assertEquals(RootRuntimeConfig.TPROXY_PORT, runtime["tproxy-port"])
        assertEquals("127.0.0.1", runtime["bind-address"])
        assertEquals("", runtime["secret"])
        assertEquals(listOf("MATCH", "a"), runtime["rules"])
        val dns = runtime["dns"] as Map<*, *>
        assertEquals(listOf("https://dns.example/dns-query"), dns["nameserver"])
        assertEquals(mapOf("example.com" to "1.1.1.1"), dns["nameserver-policy"])
        assertEquals("0.0.0.0:${RootRuntimeConfig.DNS_PORT}", dns["listen"])
        assertEquals(false, dns["ipv6"])
        assertEquals("redir-host", dns["enhanced-mode"])
        assertEquals(listOf("8.8.8.8"), dns["default-nameserver"])
    }

    @Test fun missingDnsGetsUsableLocalResolver() {
        val runtime = Yaml().load<Map<String, Any>>(RootRuntimeConfig.build("rules: ['MATCH,DIRECT']", true))
        val dns = runtime["dns"] as Map<*, *>
        assertEquals(true, dns["enable"])
        assertEquals(listOf("114.114.114.114"), dns["nameserver"])
        assertEquals("debug", runtime["log-level"])
    }

    @Test(expected = Exception::class) fun ambiguousDuplicateSettingsAreRejected() {
        RootRuntimeConfig.build("dns: {}\ndns: {enable: false}", false)
    }
}
