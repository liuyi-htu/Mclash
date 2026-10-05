package com.liuyihtu.mclash.root

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.Proxy
import java.net.URL

/** Record dashboard changes independently of the Flutter activity's lifetime. */
internal object RootRuntimeMode {
    fun valid(mode: String) = mode in setOf("rule", "global", "direct")

    fun capture(context: Context) {
        // Best effort: an unavailable controller must never prevent stop/recovery.
        runCatching {
            val connection = URL("http://127.0.0.1:${RootRuntimeConfig.CONTROLLER_PORT}/configs")
                .openConnection(Proxy.NO_PROXY) as HttpURLConnection
            try {
                connection.connectTimeout = 1000
                connection.readTimeout = 1000
                val mode = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
                    .optString("mode").lowercase()
                if (valid(mode)) AppPreferences(context).coreMode = mode
            } finally {
                connection.disconnect()
            }
        }
    }
}
