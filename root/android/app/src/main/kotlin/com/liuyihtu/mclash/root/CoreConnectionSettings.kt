package com.liuyihtu.mclash.root

import java.io.File
import java.net.URI
import java.net.InetAddress
import org.json.JSONObject
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.constructor.SafeConstructor

internal data class CoreConnectionSettings(
    val controller: String = "127.0.0.1:9090",
    val secret: String = "",
    val mixedPort: Int = RootRuntimeConfig.MIXED_PORT,
) {
    val uri: URI get() = URI("http://$controller")
    val port: Int get() = uri.port
    val host: String get() = when (val value = uri.host.removeSurrounding("[", "]")) {
        "0.0.0.0", "*" -> "127.0.0.1"
        "::" -> "::1"
        else -> value
    }
    fun validate() {
        val address = uri
        val ip = address.host?.removeSurrounding("[", "]") ?: error("控制接口必须为 IP:端口")
        require(address.port in 1..65535 && address.rawPath.isNullOrEmpty() && address.rawQuery == null && address.rawFragment == null && address.rawUserInfo == null) { "控制接口必须为 IP:端口" }
        require(if (ip.contains(':')) runCatching { InetAddress.getByName(ip).address.size == 16 }.getOrDefault(false)
            else ip.split('.').let { parts -> parts.size == 4 && parts.all { it.isNotEmpty() && it.all(Char::isDigit) && (it.toIntOrNull() ?: -1) in 0..255 } }) { "监听地址必须为有效 IP" }
        require(mixedPort in 1..65535 && mixedPort != port) { "代理端口范围为 1–65535，且不能与控制接口端口相同" }
        val reserved = setOf(RootRuntimeConfig.TPROXY_PORT, RootRuntimeConfig.DNS_PORT, RootRuntimeConfig.IPV6_DNS_TPROXY_PORT)
        require(port !in reserved && mixedPort !in reserved) { "端口与 Root 内部转发或 DNS 端口冲突" }
        require(!secret.contains('\r') && !secret.contains('\n')) { "密钥不能包含换行" }
    }
    fun toMap(): Map<String, Any> = mapOf("controller" to controller, "secret" to secret, "mixedPort" to mixedPort)
    fun toJson(): String = JSONObject(toMap()).toString()
    companion object {
        fun fromJson(text: String): CoreConnectionSettings = JSONObject(text).let {
            CoreConnectionSettings(it.optString("controller", "127.0.0.1:9090"), it.optString("secret", ""), it.optInt("mixedPort", RootRuntimeConfig.MIXED_PORT))
        }
        fun fromRuntime(file: File): CoreConnectionSettings {
            if (!file.isFile) return CoreConnectionSettings()
            val yaml = Yaml(SafeConstructor(LoaderOptions().apply { codePointLimit = 8 * 1024 * 1024 }))
            val config = yaml.load<Any>(file.readText()) as Map<*, *>
            return CoreConnectionSettings(config["external-controller"]?.toString() ?: "127.0.0.1:9090", config["secret"]?.toString() ?: "", (config["mixed-port"] as? Number)?.toInt() ?: RootRuntimeConfig.MIXED_PORT)
        }
    }
}
