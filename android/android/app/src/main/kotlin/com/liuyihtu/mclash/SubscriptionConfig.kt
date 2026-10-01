package com.liuyihtu.mclash

import org.yaml.snakeyaml.DumperOptions
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.constructor.SafeConstructor

internal object SubscriptionConfig {
    fun build(template: String, subscription: String, previousConfig: String? = null): String {
        val loader = Yaml(SafeConstructor(LoaderOptions().apply {
            codePointLimit = 8 * 1024 * 1024
            isAllowDuplicateKeys = false
        }))
        val source = loader.load<Any>(subscription.removePrefix("\uFEFF")) as? Map<*, *>
            ?: error("订阅内容必须是 mihomo YAML 配置")
        val downloaded = source["proxies"] as? List<*>
        require(!downloaded.isNullOrEmpty()) { "订阅没有可内置的 proxies 节点，请使用包含节点的 Mihomo 订阅" }
        val manualPrefix = "# Mclash 手动节点: "
        val manualComment = previousConfig?.lineSequence()?.firstOrNull { it.startsWith(manualPrefix) }
        val manualNames = manualComment?.let { loader.load<List<String>>(it.removePrefix(manualPrefix)) }.orEmpty()
        val previous = previousConfig?.let { loader.load<Any>(it) } as? Map<*, *>
        val manual = (previous?.get("proxies") as? List<*>).orEmpty().filterIsInstance<Map<*, *>>()
            .filter { it["name"] in manualNames }
        val retainedNames = manual.map { it["name"] }.toSet()
        val nodes = downloaded.filter { (it as? Map<*, *>)?.get("name") !in retainedNames } + manual
        val names = nodes.map { node ->
            require(node is Map<*, *>) { "订阅节点格式无效" }
            val name = node["name"] as? String
            require(!name.isNullOrBlank() && node["type"] is String) { "订阅节点缺少名称或类型" }
            name
        }
        require(names.distinct().size == names.size) { "订阅节点名称重复" }
        val config = loader.load<Map<String, Any?>>(template).toMutableMap()
        val groups = config["proxy-groups"] as List<*>
        val reserved = setOf("DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL") +
            groups.map { (it as Map<*, *>)["name"] }
        require(names.none { it in reserved }) { "订阅节点名称与默认策略冲突" }
        config.remove("proxy-providers")
        val hostPrefix = "# Mclash HTTP/WS Host: "
        val hostComment = (previousConfig ?: template).lineSequence()
            .firstOrNull { it.startsWith(hostPrefix) }
        val host = hostComment?.let { loader.load<String>(it.removePrefix(hostPrefix)) }
        config["proxies"] = if (host.isNullOrEmpty()) nodes else {
            require(host.none { it.isWhitespace() || it in "/\\?#" }) { "Host 格式无效" }
            nodes.map { item ->
                @Suppress("UNCHECKED_CAST")
                val node = item as Map<String, Any?>
                val network = node["network"]
                if (node["type"] != "vmess" || (network != "http" && network != "ws")) node
                else {
                    val key = if (network == "http") "http-opts" else "ws-opts"
                    @Suppress("UNCHECKED_CAST")
                    val options = (node[key] as? Map<String, Any?>).orEmpty().toMutableMap()
                    @Suppress("UNCHECKED_CAST")
                    val headers = (options["headers"] as? Map<String, Any?>).orEmpty().toMutableMap()
                    headers.keys.filter { it.equals("host", ignoreCase = true) }.forEach { headers.remove(it) }
                    headers["Host"] = if (network == "http") listOf(host) else host
                    options["headers"] = headers
                    node.toMutableMap().apply { this[key] = options }
                }
            }
        }
        val regionNames = listOf("🚀 国内", "🌍 国外")
        val prefixes = listOf("# Mclash 国内正则: ", "# Mclash 国外正则: ")
        val previousGroups = (previous?.get("proxy-groups") as? List<*>).orEmpty()
            .filterIsInstance<Map<*, *>>()
        val filters = regionNames.mapIndexed { index, name ->
            val comment = (previousConfig ?: template).lineSequence().firstOrNull { it.startsWith(prefixes[index]) }
            val oldGroup = previousGroups.firstOrNull { it["name"] == name }
            val defaultGroup = groups.filterIsInstance<Map<*, *>>().first { it["name"] == name }
            if (comment != null) loader.load<String>(comment.removePrefix(prefixes[index]))
            else (oldGroup?.get("filter") ?: defaultGroup["filter"] ?: if (index == 0) "上海" else "KR") as String
        }
        config["proxy-groups"] = groups.map { item ->
            @Suppress("UNCHECKED_CAST")
            val group = (item as Map<String, Any?>).toMutableMap()
            val region = regionNames.indexOf(group["name"])
            if (region >= 0) {
                val pattern = Regex(filters[region])
                val selected = (if (region == 0) listOf("DIRECT") else emptyList()) +
                    names.filter { pattern.containsMatchIn(it) }
                for (key in listOf("filter", "use", "include-all-proxies", "include-all", "include-all-providers", "empty-fallback")) {
                    group.remove(key)
                }
                group["proxies"] = selected.ifEmpty { listOf("DIRECT") }
            }
            group
        }
        val header = prefixes.indices.joinToString("\n") { prefixes[it] + quote(filters[it]) } +
            (if (host.isNullOrEmpty()) "" else "\n$hostPrefix${quote(host)}") +
            (if (manualNames.isEmpty()) "" else "\n$manualPrefix[${manualNames.joinToString(",", transform = ::quote)}]")
        return Yaml(DumperOptions().apply {
            defaultFlowStyle = DumperOptions.FlowStyle.BLOCK
        }).dump(config).let { "$header\n$it" }
    }

    private fun quote(value: String): String = buildString {
        append('"')
        for (char in value) {
            when (char) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (char.code < 32) append("\\u%04x".format(char.code)) else append(char)
            }
        }
        append('"')
    }
}
