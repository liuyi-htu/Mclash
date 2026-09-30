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
        val nodes = source["proxies"] as? List<*>
        require(!nodes.isNullOrEmpty()) { "订阅没有可内置的 proxies 节点，请使用包含节点的 Mihomo 订阅" }
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
        config["proxies"] = nodes
        val regionNames = listOf("🚀 国内", "🌍 国外")
        val prefixes = listOf("# Mclash 国内正则: ", "# Mclash 国外正则: ")
        val previous = previousConfig?.let { loader.load<Any>(it) } as? Map<*, *>
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
        val header = prefixes.indices.joinToString("\n") { prefixes[it] + quote(filters[it]) }
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
