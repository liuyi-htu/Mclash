package com.liuyihtu.mclash.root

/** Parse only GitHub's official stable release redirect and exact asset digest. */
internal object CoreReleasePage {
    fun version(url: String): String = Regex("^https://github\\.com/MetaCubeX/mihomo/releases/tag/(v[0-9]+\\.[0-9]+\\.[0-9]+)$")
        .matchEntire(url)?.groupValues?.get(1) ?: error("官方稳定版页面地址无效")

    fun digest(version: String, html: String): String {
        require(version.matches(Regex("v[0-9]+\\.[0-9]+\\.[0-9]+")))
        val name = "mihomo-android-arm64-v8-$version.gz"
        val attributes = Regex("<clipboard-copy\\b[^>]*>").findAll(html)
            .map { it.value }.filter { it.contains("aria-label=\"Copy to clipboard digest for $name\"") }.toList()
        require(attributes.size == 1) { "官方页面缺少 ARM64 内核 SHA-256 校验值" }
        return Regex("\\bvalue=\"(sha256:[a-fA-F0-9]{64})\"").find(attributes.single())
            ?.groupValues?.get(1) ?: error("官方页面内核 SHA-256 校验值无效")
    }
}
