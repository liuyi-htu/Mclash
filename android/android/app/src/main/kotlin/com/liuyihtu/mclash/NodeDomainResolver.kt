package com.liuyihtu.mclash

import java.net.InetAddress
import java.net.Inet4Address
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.DumperOptions
import org.yaml.snakeyaml.constructor.SafeConstructor

/** Convert a working copy only; subscription caches always retain original domains. */
internal object NodeDomainResolver {
    fun resolve(content: String, lookup: (String) -> List<InetAddress> = { InetAddress.getAllByName(it).toList() }): String {
        val yaml = Yaml(SafeConstructor(LoaderOptions().apply { codePointLimit = 8 * 1024 * 1024 }))
        val root = yaml.load<Map<String, Any?>>(content)
        val nodes = (root["proxies"] as? List<*>)?.mapNotNull { node ->
            (node as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value }?.toMutableMap()
        } ?: return content
        val domains = nodes.mapNotNull { it["server"] as? String }.filter { !isIp(it) }.distinct()
        if (domains.isEmpty()) return content
        val pool = Executors.newFixedThreadPool(4) { task -> Thread(task, "mclash-node-dns").apply { isDaemon = true } }
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
        val pending = domains.associateWith { host -> pool.submit<String?> {
            runCatching {
                val addresses = lookup(host)
                (addresses.firstOrNull { it is Inet4Address } ?: addresses.firstOrNull())?.hostAddress
            }.getOrNull()
        } }
        val resolved = mutableMapOf<String, String>()
        try {
            for ((host, future) in pending) {
                val remaining = (deadline - System.nanoTime()).coerceAtLeast(0)
                val address = runCatching { future.get(remaining, TimeUnit.NANOSECONDS) }.getOrNull()
                if (address != null && isIp(address)) resolved[host] = address
            }
        } finally {
            pending.values.forEach { it.cancel(true) }
            pool.shutdownNow()
        }
        for (node in nodes) {
            val host = node["server"] as? String ?: continue
            val address = resolved[host] ?: continue
            preserveIdentity(node, host)
            node["server"] = address
        }
        if (resolved.isEmpty()) return content
        return Yaml(DumperOptions().apply { defaultFlowStyle = DumperOptions.FlowStyle.BLOCK }).dump(root.toMutableMap().apply { put("proxies", nodes) })
    }

    private fun isIp(host: String): Boolean = host.contains(':') ||
        (host.split('.').size == 4 && host.split('.').all { it.toIntOrNull() in 0..255 })

    private fun preserveIdentity(node: MutableMap<String, Any?>, host: String) {
        val type = node["type"]?.toString()?.lowercase()
        if (node["tls"] == true || type in listOf("trojan", "hysteria", "hysteria2", "tuic", "anytls")) {
            val key = if (type in listOf("vmess", "vless")) "servername" else "sni"
            if ((node[key] as? String).isNullOrEmpty()) node[key] = host
        }
        if (node["network"] == "ws") {
            val opts = (node["ws-opts"] as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value }?.toMutableMap() ?: mutableMapOf()
            val headers = (opts["headers"] as? Map<*, *>)?.entries?.associate { it.key.toString() to it.value }?.toMutableMap() ?: mutableMapOf()
            if (headers.keys.none { it.equals("Host", ignoreCase = true) }) headers["Host"] = host
            opts["headers"] = headers
            node["ws-opts"] = opts
        }
    }
}
