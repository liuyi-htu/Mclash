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
        val missing = (previous?.get("proxies") as? List<*>).orEmpty().filterIsInstance<Map<*, *>>().map { it["name"] }.toSet() - names.toSet()
        val subRules = previous?.get("sub-rules") as? Map<*, *>
        val savedRules = (previous?.get("rules") as? List<*>).orEmpty() + subRules?.values.orEmpty().flatMap { (it as? List<*>).orEmpty() }
        for (rule in savedRules.filterIsInstance<String>()) {
            val parts = rule.split(',').map { it.trim() }
            if (parts.first() == "SUB-RULE") continue
            val target = parts.dropLastWhile { it in listOf("no-resolve", "src") }.lastOrNull()
            require(target !in missing) { "节点 $target 已从订阅移除，但仍被规则引用，请先修改规则；原配置已保留" }
        }
        val config = loader.load<Map<String, Any?>>(template).toMutableMap()
        previous?.forEach { (key, value) -> config[key as String] = value }
        val globalPrefix = "# Mclash 全局链路: "
        val globalComment = previousConfig?.lineSequence()?.firstOrNull { it.startsWith(globalPrefix) }
        val globalRoles = globalComment?.let { loader.load<Map<String, List<String>>>(it.removePrefix(globalPrefix)) }.orEmpty()
        val chainGroupPrefix = "# Mclash 链路代理组: "
        val chainGroupComment = previousConfig?.lineSequence()?.firstOrNull { it.startsWith(chainGroupPrefix) }
        val oldChainGroups = chainGroupComment?.let { loader.load<Map<String, List<String>>>(it.removePrefix(chainGroupPrefix)) }.orEmpty()
        val chainGroups = oldChainGroups.toMutableMap()
        val chainPrefix = "# Mclash 节点链路: "
        val chainComment = previousConfig?.lineSequence()?.firstOrNull { it.startsWith(chainPrefix) }
        val chainOverrides = chainComment?.let { loader.load<Map<String, String>>(it.removePrefix(chainPrefix)) }.orEmpty().toMutableMap()
        val baseGroups = (config["proxy-groups"] as List<*>).filter { (it as Map<*, *>)["name"] !in oldChainGroups }
        if (globalRoles.isNotEmpty()) {
            chainGroups.clear()
            chainOverrides.clear()
            val front = globalRoles["front"].orEmpty().filter { it in names }
            val back = globalRoles["back"].orEmpty().filter { it in names }
            require(front.none { it in back }) { "前置和后置不能选择同一个节点" }
            val normal = names.filter { it !in front && it !in back }
            require(normal.isNotEmpty()) { "请保留至少一个节点作为作用对象" }
            val usedNames = names.toMutableSet().apply { addAll(baseGroups.map { (it as Map<*, *>)["name"] as String }) }
            fun connect(targets: List<String>, upstreams: List<String>, base: String) {
                if (upstreams.isEmpty() || targets.isEmpty()) return
                var upstream = upstreams.first()
                if (upstreams.size > 1) {
                    upstream = base
                    var index = 2
                    while (upstream in usedNames) upstream = "$base (${index++})"
                    usedNames.add(upstream)
                    chainGroups[upstream] = upstreams
                }
                for (target in targets) chainOverrides[target] = upstream
            }
            for (index in 1 until front.size) chainOverrides[front[index]] = front[index - 1]
            if (front.isNotEmpty()) connect((globalRoles["frontTargets"] ?: normal).filter { it in normal }, listOf(front.last()), "🔗 前置代理")
            connect(back, (globalRoles["backTargets"] ?: normal).filter { it in normal }, "🔗 后置入口")
        }
        val groups = baseGroups + chainGroups.map { (name, members) ->
            mapOf("name" to name, "type" to "select", "proxies" to members.filter { it in names }.ifEmpty { listOf("DIRECT") })
        }
        val reserved = setOf("DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL") +
            groups.map { (it as Map<*, *>)["name"] }
        require(names.none { it in reserved }) { "订阅节点名称与默认策略冲突" }
        config.remove("proxy-providers")
        val chainedNodes = nodes.map { item ->
            @Suppress("UNCHECKED_CAST")
            val node = item as Map<String, Any?>
            val upstream = chainOverrides[node["name"]]
            if (node["name"] !in retainedNames && upstream != null && (upstream in names || groups.any { (it as Map<*, *>)["name"] == upstream })) node.toMutableMap().apply { this["dialer-proxy"] = upstream }
            else node
        }
        val hostPrefix = "# Mclash HTTP/WS Host: "
        val hostComment = (previousConfig ?: template).lineSequence()
            .firstOrNull { it.startsWith(hostPrefix) }
        val host = hostComment?.let { loader.load<String>(it.removePrefix(hostPrefix)) }
        config["proxies"] = if (host.isNullOrEmpty()) chainedNodes else {
            require(host.none { it.isWhitespace() || it in "/\\?#" }) { "Host 格式无效" }
            chainedNodes.map { item ->
                @Suppress("UNCHECKED_CAST")
                val node = item as Map<String, Any?>
                val network = node["network"]
                if (node["name"] in retainedNames || node["type"] != "vmess" || (network != "http" && network != "ws")) node
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
        val filterPrefix = "# Mclash 代理组正则: "
        val filterSource = previousConfig ?: template
        val genericComment = filterSource.lineSequence().firstOrNull { it.startsWith(filterPrefix) }
        val filters = mutableMapOf<String, String>()
        if (genericComment != null) {
            filters.putAll(loader.load<Map<String, String>>(genericComment.removePrefix(filterPrefix)))
        } else {
            for (item in groups.filterIsInstance<Map<*, *>>()) {
                val name = item["name"] as String
                val region = regionNames.indexOf(name)
                val comment = if (region < 0) null else filterSource.lineSequence().firstOrNull { it.startsWith(prefixes[region]) }
                if (comment != null) filters[name] = loader.load<String>(comment.removePrefix(prefixes[region]))
                else if (item["filter"] is String || region >= 0) filters[name] = item["filter"] as? String ?: ""
            }
        }
        for (index in regionNames.indices) {
            val comment = filterSource.lineSequence().firstOrNull { it.startsWith(prefixes[index]) }
            if (filters.containsKey(regionNames[index]) && comment != null) filters[regionNames[index]] = loader.load<String>(comment.removePrefix(prefixes[index]))
        }
        filters.keys.retainAll(groups.map { (it as Map<*, *>)["name"] })
        val validMembers = names.toSet() + reserved
        config["proxy-groups"] = groups.map { item ->
            @Suppress("UNCHECKED_CAST")
            val group = (item as Map<String, Any?>).toMutableMap()
            val name = group["name"] as String
            if (filters.containsKey(name)) {
                val pattern = Regex(filters.getValue(name))
                val selected = (if (name == regionNames[0]) listOf("DIRECT") else emptyList()) + names.filter { pattern.containsMatchIn(it) }
                for (key in listOf("filter", "use", "include-all-proxies", "include-all", "include-all-providers", "empty-fallback")) group.remove(key)
                group["proxies"] = selected.ifEmpty { listOf("DIRECT") }
            } else {
                val selected = (group["proxies"] as? List<*>).orEmpty().filter { it in validMembers }
                group.remove("use")
                group["proxies"] = selected.ifEmpty { listOf("DIRECT") }
            }
            group
        }
        val graph = mutableMapOf<String, List<String>>()
        for (node in chainedNodes) {
            (node["dialer-proxy"] as? String)?.let { graph[node["name"] as String] = listOf(it) }
        }
        for (group in (config["proxy-groups"] as List<*>).filterIsInstance<Map<*, *>>()) {
            graph[group["name"] as String] = (group["proxies"] as? List<*>).orEmpty().filterIsInstance<String>()
        }
        val active = mutableSetOf<String>()
        val complete = mutableSetOf<String>()
        fun visit(name: String) {
            require(name !in active) { "代理链路形成循环，请选择其他节点" }
            if (!complete.add(name)) return
            active.add(name)
            for (child in graph[name].orEmpty()) visit(child)
            active.remove(name)
        }
        for (name in graph.keys) visit(name)
        val header = (globalComment?.let { "$it\n" } ?: "") + filterPrefix + "{" + filters.entries.joinToString(",") { quote(it.key) + ":" + quote(it.value) } + "}" +
            regionNames.indices.filter { filters.containsKey(regionNames[it]) }.joinToString("") { "\n" + prefixes[it] + quote(filters.getValue(regionNames[it])) } +
            (if (host.isNullOrEmpty()) "" else "\n$hostPrefix${quote(host)}") +
            (if (manualNames.isEmpty()) "" else "\n$manualPrefix[${manualNames.joinToString(",", transform = ::quote)}]") +
            (if (chainOverrides.isEmpty()) "" else "\n$chainPrefix{${chainOverrides.entries.joinToString(",") { quote(it.key) + ":" + quote(it.value) }}}") +
            (if (chainGroups.isEmpty()) "" else "\n$chainGroupPrefix{${chainGroups.entries.joinToString(",") { quote(it.key) + ":[" + it.value.joinToString(",", transform = ::quote) + "]" }}}")
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
