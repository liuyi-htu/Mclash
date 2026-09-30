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
        val previous = previousConfig?.let { loader.load<Any>(it) } as? Map<*, *>
        val filters = (previous?.get("proxy-groups") as? List<*>)
            .orEmpty().filterIsInstance<Map<*, *>>()
            .mapNotNull { group ->
                val name = group["name"] as? String
                val filter = group["filter"] as? String
                if (name != null && filter != null) name to filter else null
            }.toMap()
        config["proxy-groups"] = groups.map { item ->
            @Suppress("UNCHECKED_CAST")
            val group = (item as Map<String, Any?>).toMutableMap()
            group.remove("use")
            filters[group["name"]]?.let { group["filter"] = it }
            group["include-all-proxies"] = true
            group["empty-fallback"] = "DIRECT"
            group["proxies"] = (group["proxies"] as? List<*>).orEmpty()
            group
        }
        return Yaml(DumperOptions().apply {
            defaultFlowStyle = DumperOptions.FlowStyle.BLOCK
        }).dump(config)
    }
}
