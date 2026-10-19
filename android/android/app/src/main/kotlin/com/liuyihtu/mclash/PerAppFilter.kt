package com.liuyihtu.mclash

/** Count successful Builder additions, rather than trusting persisted package names. */
internal object PerAppFilter {
    fun apply(
        onlySelected: Boolean,
        selected: Set<String>,
        ownPackage: String,
        isInstalled: (String) -> Boolean,
        allow: (String) -> Boolean,
        disallow: (String) -> Boolean,
    ) {
        val packages = selected.filterNot { it == ownPackage }.filter(isInstalled).sorted()
        if (onlySelected) {
            val added = packages.count(allow)
            require(added > 0) { "“仅代理选中的应用”模式下至少选择一个已安装的其他应用" }
        } else {
            check(disallow(ownPackage)) { "无法排除 Mclash 自身，拒绝创建 VPN" }
            packages.forEach { disallow(it) }
        }
    }
}
