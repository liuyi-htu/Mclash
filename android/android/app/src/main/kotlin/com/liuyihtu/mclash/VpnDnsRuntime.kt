package com.liuyihtu.mclash

import org.yaml.snakeyaml.DumperOptions
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.constructor.SafeConstructor

/** A dedicated SOCKS inbound sends port 53 traffic to Mihomo's internal resolver in every mode. */
internal object VpnDnsRuntime {
    const val SOCKS_PORT = 7891
    // Android needs a DNS destination. Hev intercepts its port 53 before it reaches this address.
    const val VPN_DNS_ADDRESS = "114.114.114.114"

    fun build(source: String, ipv6: Boolean): String {
        val yaml = Yaml(SafeConstructor(LoaderOptions()))
        val loaded = yaml.load<Any>(source)
        require(loaded is Map<*, *>) { "配置必须是 YAML 映射" }
        val config = loaded.entries.associateTo(linkedMapOf<String, Any?>()) { (k, v) -> k.toString() to v }
        val dns = (config["dns"] as? Map<*, *>)?.entries
            ?.associateTo(linkedMapOf<String, Any?>()) { (k, v) -> k.toString() to v }
            ?: linkedMapOf()
        dns["enable"] = true
        dns["ipv6"] = ipv6
        if ((dns["nameserver"] as? List<*>)?.isNotEmpty() != true) {
            dns["nameserver"] = listOf("114.114.114.114", "223.5.5.5")
        }
        config["dns"] = dns
        val proxies = (config["proxies"] as? List<*>)?.toMutableList() ?: mutableListOf()
        val groups = (config["proxy-groups"] as? List<*>)?.toMutableList() ?: mutableListOf()
        val names = (proxies + groups).mapNotNull { (it as? Map<*, *>)?.get("name") }.toSet()
        var name = "Mclash 内部 DNS"
        var suffix = 1
        while (name in names) name = "Mclash 内部 DNS ${suffix++}"
        // Keep the injected resolver out of all ordinary selection and automatic groups.
        val originalMembers = listOf("DIRECT", "REJECT") +
            (proxies + groups).mapNotNull { item ->
                val entry = item as? Map<*, *>
                if (entry?.get("type") in listOf("pass", "pass-rule")) null
                else entry?.get("name")?.toString()
            }
        if (groups.none { (it as? Map<*, *>)?.get("name") == "GLOBAL" }) {
            groups.add(linkedMapOf("name" to "GLOBAL", "type" to "select", "proxies" to originalMembers))
        }
        config["proxy-groups"] = groups.map { item ->
            require(item is Map<*, *>) { "代理组必须是 YAML 映射" }
            val group = item.entries.associateTo(linkedMapOf<String, Any?>()) { (k, v) -> k.toString() to v }
            val previous = group["exclude-filter"]?.toString().orEmpty()
            val internalFilter = "^$name$"
            group["exclude-filter"] = if (previous.isEmpty()) internalFilter else "$previous`$internalFilter"
            group
        }
        proxies.add(linkedMapOf("name" to name, "type" to "dns"))
        config["proxies"] = proxies
        val listeners = (config["listeners"] as? List<*>)?.toMutableList() ?: mutableListOf()
        require(listeners.none { ((it as? Map<*, *>)?.get("port")?.toString()) == SOCKS_PORT.toString() }) {
            "配置中的监听端口 7891 与 VPN DNS 接管冲突"
        }
        val listenerNames = listeners.mapNotNull { (it as? Map<*, *>)?.get("name") }.toSet()
        var listenerName = "mclash-vpn-dns"
        suffix = 1
        while (listenerName in listenerNames) listenerName = "mclash-vpn-dns-${suffix++}"
        listeners.add(linkedMapOf(
            "name" to listenerName, "type" to "socks", "listen" to "127.0.0.1",
            "port" to SOCKS_PORT, "udp" to true, "proxy" to name,
        ))
        config["listeners"] = listeners
        val options = DumperOptions().apply { defaultFlowStyle = DumperOptions.FlowStyle.BLOCK }
        val metadata = source.lineSequence().filter { it.startsWith("# Mclash ") }.joinToString("") { "$it\n" }
        return metadata + Yaml(options).dump(config)
    }
}
