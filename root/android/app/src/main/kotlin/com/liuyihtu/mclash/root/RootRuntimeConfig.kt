package com.liuyihtu.mclash.root

import org.yaml.snakeyaml.DumperOptions
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.constructor.SafeConstructor

/** Only the generated runtime copy is changed; imported profiles stay editable. */
internal object RootRuntimeConfig {
    const val MIXED_PORT = 17890
    const val TPROXY_PORT = 17894
    const val DNS_PORT = 11053
    const val IPV6_DNS_TPROXY_PORT = 17895
    const val CONTROLLER_PORT = 9090
    const val BYPASS_MARK = 0x40000000

    fun build(source: String, debug: Boolean, mode: String? = null, ipv6: Boolean = false): String {
        val loader = Yaml(SafeConstructor(LoaderOptions().apply {
            codePointLimit = 8 * 1024 * 1024
            isAllowDuplicateKeys = false
        }))
        val content = SubscriptionConfig.runtimeMetadata(source)
        val original = loader.load<Any>(content) as? Map<*, *>
            ?: error("配置必须是 Mihomo YAML 对象")
        val config = linkedMapOf<String, Any?>()
        original.forEach { (key, value) ->
            require(key is String) { "配置字段必须是字符串" }
            if (key !in CONTROLLED_KEYS) config[key] = value
        }
        if (mode != null && RootRuntimeMode.valid(mode)) config["mode"] = mode
        val dns = linkedMapOf<String, Any?>()
        (original["dns"] as? Map<*, *>)?.forEach { (key, value) ->
            require(key is String) { "DNS 字段必须是字符串" }
            dns[key] = value
        }
        dns["enable"] = true
        // PREROUTING REDIRECT targets the hotspot interface's local address.
        dns["listen"] = if (ipv6) "[::]:$DNS_PORT" else "0.0.0.0:$DNS_PORT"
        dns["ipv6"] = ipv6
        // Real addresses avoid depending on a VPN interface's fake-IP route.
        dns["enhanced-mode"] = "redir-host"
        if ((dns["nameserver"] as? List<*>).isNullOrEmpty()) {
            dns["nameserver"] = listOf("114.114.114.114")
        }
        config["dns"] = dns
        val injected = linkedMapOf<String, Any?>(
            "mixed-port" to MIXED_PORT,
            "tproxy-port" to TPROXY_PORT,
            "allow-lan" to false,
            "bind-address" to "127.0.0.1",
            "ipv6" to ipv6,
            "routing-mark" to BYPASS_MARK,
            "log-level" to if (debug) "debug" else "error",
            "external-controller" to "127.0.0.1:$CONTROLLER_PORT",
            "secret" to "",
            "external-ui" to "dashboard",
        )
        if (ipv6) {
            val proxies = (config["proxies"] as? List<*>)?.toMutableList() ?: mutableListOf()
            val names = (proxies + ((config["proxy-groups"] as? List<*>) ?: emptyList<Any>()))
                .mapNotNull { (it as? Map<*, *>)?.get("name") }.toSet()
            var dnsProxy = "Mclash-IPv6-DNS"
            while (dnsProxy in names) dnsProxy += "_"
            val groups = (config["proxy-groups"] as? List<*>)?.toMutableList() ?: mutableListOf()
            // Mihomo's implicit GLOBAL includes every outbound. Preserve its original
            // members explicitly, before appending the private DNS outbound.
            if (groups.none { (it as? Map<*, *>)?.get("name") == "GLOBAL" }) {
                val members = listOf("DIRECT", "REJECT") + (proxies + groups).mapNotNull { item ->
                    val entry = item as? Map<*, *>
                    if (entry?.get("type") in listOf("pass", "pass-rule")) null
                    else entry?.get("name")?.toString()
                }
                groups.add(linkedMapOf("name" to "GLOBAL", "type" to "select", "proxies" to members))
            }
            // include-all groups can also collect the private outbound. Append an
            // exact exclusion while retaining each group's existing filter and policy.
            config["proxy-groups"] = groups.map { item ->
                require(item is Map<*, *>) { "代理组必须是 YAML 映射" }
                val group = linkedMapOf<String, Any?>()
                item.forEach { (key, value) ->
                    require(key is String) { "代理组字段必须是字符串" }
                    group[key] = value
                }
                val previous = group["exclude-filter"]?.toString().orEmpty()
                val internalFilter = "^$dnsProxy$"
                group["exclude-filter"] = if (previous.isEmpty()) internalFilter else "$previous`$internalFilter"
                group
            }
            proxies.add(mapOf("name" to dnsProxy, "type" to "dns"))
            config["proxies"] = proxies
            injected["listeners"] = listOf(mapOf(
                "name" to "mclash-tproxy-ipv6", "type" to "tproxy",
                "listen" to "::1", "port" to TPROXY_PORT, "udp" to true,
            ), mapOf(
                "name" to "mclash-dns-ipv6", "type" to "tproxy", "listen" to "::1",
                "port" to IPV6_DNS_TPROXY_PORT, "udp" to true, "proxy" to dnsProxy,
            ))
        }
        injected["external-controller-cors"] = mapOf(
            "allow-origins" to listOf("*"), "allow-private-network" to true,
        )
        // YAML loading discards the comments that store Mclash profile settings.
        val metadata = content.lineSequence()
            .filter { it.startsWith("# Mclash ") }
            .joinToString("") { "$it\n" }
        val dumper = Yaml(DumperOptions().apply {
            defaultFlowStyle = DumperOptions.FlowStyle.BLOCK
            isPrettyFlow = true
        })
        return metadata + dumper.dump(config) +
            (if (ipv6) "# Generated by Mclash Root; IPv4/IPv6 TProxy, local device only.\n" else "# Generated by Mclash Root; IPv4 TProxy, local device only.\n") +
            dumper.dump(injected)
    }

    private val CONTROLLED_KEYS = setOf(
        "mixed-port", "socks-port", "port", "redir-port", "tproxy-port", "tun", "listeners",
        "allow-lan", "bind-address", "ipv6", "routing-mark", "log-level", "dns",
        "external-controller", "external-controller-tls", "external-controller-unix",
        "external-controller-pipe", "external-controller-cors", "external-controller-routing-mark",
        "external-ui", "external-ui-name", "external-ui-url", "secret",
    )
}
