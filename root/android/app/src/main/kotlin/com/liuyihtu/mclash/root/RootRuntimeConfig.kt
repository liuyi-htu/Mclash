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
    const val CONTROLLER_PORT = 9090
    const val BYPASS_MARK = 0x40000000

    fun build(source: String, debug: Boolean): String {
        val loader = Yaml(SafeConstructor(LoaderOptions().apply {
            codePointLimit = 8 * 1024 * 1024
            isAllowDuplicateKeys = false
        }))
        val content = source.removePrefix("\uFEFF")
        val original = loader.load<Any>(content) as? Map<*, *>
            ?: error("配置必须是 Mihomo YAML 对象")
        val config = linkedMapOf<String, Any?>()
        original.forEach { (key, value) ->
            require(key is String) { "配置字段必须是字符串" }
            if (key !in CONTROLLED_KEYS) config[key] = value
        }
        val dns = linkedMapOf<String, Any?>()
        (original["dns"] as? Map<*, *>)?.forEach { (key, value) ->
            require(key is String) { "DNS 字段必须是字符串" }
            dns[key] = value
        }
        dns["enable"] = true
        // PREROUTING REDIRECT targets the hotspot interface's local address.
        dns["listen"] = "0.0.0.0:$DNS_PORT"
        dns["ipv6"] = false
        // Real addresses avoid depending on a VPN interface's fake-IP route.
        dns["enhanced-mode"] = "redir-host"
        if ((dns["nameserver"] as? List<*>).isNullOrEmpty()) {
            dns["nameserver"] = listOf("114.114.114.114")
        }
        config["dns"] = dns
        config["mixed-port"] = MIXED_PORT
        config["tproxy-port"] = TPROXY_PORT
        config["allow-lan"] = false
        config["bind-address"] = "127.0.0.1"
        config["ipv6"] = false
        config["routing-mark"] = BYPASS_MARK
        config["log-level"] = if (debug) "debug" else "error"
        config["external-controller"] = "127.0.0.1:$CONTROLLER_PORT"
        config["secret"] = ""
        config["external-controller-cors"] = mapOf(
            "allow-origins" to listOf("*"), "allow-private-network" to true,
        )
        // YAML loading discards the comments that store Mclash profile settings.
        val metadata = content.lineSequence()
            .filter { it.startsWith("# Mclash ") }
            .joinToString("") { "$it\n" }
        return metadata +
            Yaml(DumperOptions().apply {
                defaultFlowStyle = DumperOptions.FlowStyle.BLOCK
                isPrettyFlow = true
            }).dump(config)
    }

    private val CONTROLLED_KEYS = setOf(
        "mixed-port", "socks-port", "port", "redir-port", "tproxy-port", "tun", "listeners",
        "allow-lan", "bind-address", "ipv6", "routing-mark", "log-level", "dns",
        "external-controller", "external-controller-tls", "external-controller-unix",
        "external-controller-pipe", "external-controller-cors", "external-controller-routing-mark",
        "external-ui", "external-ui-name", "external-ui-url", "secret",
    )
}
