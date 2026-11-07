package com.liuyihtu.mclash.root

import java.net.InetAddress
import org.junit.Assert.*
import org.junit.Test
import org.yaml.snakeyaml.Yaml

class NodeDomainResolverTest {
    @Test fun resolvesOncePrefersIpv4AndPreservesTlsAndHost() {
        val source = """
            proxies:
              - {name: A, type: vmess, server: node.example, tls: true, network: ws}
              - {name: B, type: trojan, server: node.example, sni: custom.example, network: ws, ws-opts: {headers: {Host: custom.example}}}
              - {name: IP, type: http, server: 192.0.2.3}
              - {name: Failed, type: http, server: fail.example}
        """.trimIndent()
        val calls = mutableListOf<String>()
        val output = NodeDomainResolver.resolve(source) { host ->
            synchronized(calls) { calls.add(host) }
            if (host == "fail.example") error("offline")
            listOf(InetAddress.getByName("2001:db8::1"), InetAddress.getByName("192.0.2.1"))
        }
        val nodes = Yaml().load<Map<String, List<Map<String, Any>>>>(output)["proxies"]!!
        assertEquals("192.0.2.1", nodes[0]["server"])
        assertEquals("node.example", nodes[0]["servername"])
        assertEquals("node.example", ((nodes[0]["ws-opts"] as Map<*, *>)["headers"] as Map<*, *>)["Host"])
        assertEquals("custom.example", nodes[1]["sni"])
        assertEquals("custom.example", ((nodes[1]["ws-opts"] as Map<*, *>)["headers"] as Map<*, *>)["Host"])
        assertEquals("192.0.2.3", nodes[2]["server"])
        assertEquals("fail.example", nodes[3]["server"])
        assertEquals(1, calls.count { it == "node.example" })
    }

    @Test fun retainsOriginalOnFailureAndSupportsIpv6Only() {
        val source = "proxies: [{name: A, type: http, server: node.example, tls: true}]"
        assertEquals(source, NodeDomainResolver.resolve(source) { error("no DNS") })
        val output = NodeDomainResolver.resolve(source) { listOf(InetAddress.getByName("2001:db8::1")) }
        val node = Yaml().load<Map<String, List<Map<String, Any>>>>(output)["proxies"]!!.single()
        assertTrue(node["server"].toString().contains(':'))
        assertEquals("node.example", node["sni"])
    }
}
