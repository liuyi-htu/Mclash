package com.liuyihtu.mclash

import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.util.concurrent.ExecutionException
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicReference
import java.util.zip.GZIPInputStream

internal object SubscriptionDownloader {
    const val TOTAL_TIMEOUT_MS = 25_000L

    fun download(
        rawUrl: String,
        timeoutMs: Long = TOTAL_TIMEOUT_MS,
        maxBytes: Int = 8 * 1024 * 1024,
    ): ByteArray {
        val url = URL(rawUrl)
        require(url.protocol == "http" || url.protocol == "https") {
            "订阅链接只支持 http:// 或 https://"
        }
        val active = AtomicReference<HttpURLConnection?>()
        val task = FutureTask {
            val connection = url.openConnection() as HttpURLConnection
            active.set(connection)
            try {
                if (Thread.currentThread().isInterrupted) throw InterruptedException()
                connection.instanceFollowRedirects = true
                connection.connectTimeout = minOf(10_000L, timeoutMs).toInt()
                connection.readTimeout = minOf(10_000L, timeoutMs).toInt()
                connection.requestMethod = "GET"
                connection.setRequestProperty("User-Agent", "clash.meta")
                connection.setRequestProperty("Accept", "application/yaml, text/yaml, text/plain, application/octet-stream, */*")
                connection.setRequestProperty("Accept-Encoding", "gzip")
                val code = connection.responseCode
                require(code in 200..299) { "订阅下载失败：HTTP $code" }
                require(connection.contentLengthLong <= maxBytes || connection.contentLengthLong < 0) {
                    "订阅内容超过 ${maxBytes / 1024 / 1024} MB"
                }
                val raw = connection.inputStream
                val input = if (connection.contentEncoding?.contains("gzip", true) == true) GZIPInputStream(raw) else raw
                input.use {
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(16 * 1024)
                    while (true) {
                        if (Thread.currentThread().isInterrupted) throw InterruptedException()
                        val count = it.read(buffer)
                        if (count < 0) break
                        require(output.size() + count <= maxBytes) { "订阅内容超过 ${maxBytes / 1024 / 1024} MB" }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
            } finally {
                connection.disconnect()
                active.set(null)
            }
        }
        Thread(task, "mclash-subscription-download").apply { isDaemon = true }.start()
        try {
            return task.get(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (error: TimeoutException) {
            throw SocketTimeoutException("订阅下载超时，请检查网络或订阅链接后重试")
        } catch (error: ExecutionException) {
            val cause = error.cause ?: error
            if (cause is SocketTimeoutException) {
                throw SocketTimeoutException("订阅下载超时，请检查网络或订阅链接后重试")
            }
            throw cause
        } finally {
            if (!task.isDone) {
                task.cancel(true)
                // Disconnect can wait for a blocked read; do not hold the caller up.
                Thread({ active.get()?.disconnect() }, "mclash-subscription-cancel")
                    .apply { isDaemon = true }.start()
            }
        }
    }
}
