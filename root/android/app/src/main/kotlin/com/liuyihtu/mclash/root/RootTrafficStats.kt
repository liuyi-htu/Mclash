package com.liuyihtu.mclash.root

import java.net.HttpURLConnection
import java.net.Proxy
import java.net.URL
import org.json.JSONObject

/** Read one core sample; /traffic is a stream, so never read until EOF. */
internal object RootTrafficStats {
    fun decode(sample: Map<String, Long>, totals: Map<String, Long> = emptyMap()): Map<String, Long> = mapOf(
        "rxBytes" to (sample["downTotal"] ?: totals["downloadTotal"] ?: 0L).coerceAtLeast(0),
        "txBytes" to (sample["upTotal"] ?: totals["uploadTotal"] ?: 0L).coerceAtLeast(0),
        "rxBytesPerSecond" to (sample["down"] ?: 0L).coerceAtLeast(0),
        "txBytesPerSecond" to (sample["up"] ?: 0L).coerceAtLeast(0),
    )

    fun read(): Map<String, Long> {
        val sample = fetch("traffic", true)
        val totals = if (sample.containsKey("upTotal") && sample.containsKey("downTotal")) emptyMap() else fetch("connections", false)
        return decode(sample, totals)
    }

    private fun fetch(path: String, firstLine: Boolean): Map<String, Long> {
        val connection = URL("http://127.0.0.1:${RootRuntimeConfig.CONTROLLER_PORT}/$path").openConnection(Proxy.NO_PROXY) as HttpURLConnection
        try {
            connection.connectTimeout = 1000
            connection.readTimeout = 2500
            val body = connection.inputStream.bufferedReader().use { if (firstLine) it.readLine() else it.readText() }
            val json = JSONObject(requireNotNull(body) { "内核未返回流量统计" })
            return listOf("up", "down", "upTotal", "downTotal", "uploadTotal", "downloadTotal")
                .filter { json.has(it) && !json.isNull(it) }.associateWith { json.getLong(it) }
        } finally { connection.disconnect() }
    }
}
