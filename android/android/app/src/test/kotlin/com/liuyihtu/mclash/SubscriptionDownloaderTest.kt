package com.liuyihtu.mclash

import org.junit.Assert.*
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.Executors
import java.util.zip.GZIPOutputStream

class SubscriptionDownloaderTest {
    private class Request(private val socket: Socket, val headers: Map<String, String>) {
        val responseHeaders = mutableMapOf<String, String>()
        val responseBody get() = socket.getOutputStream()
        fun sendResponseHeaders(code: Int, size: Long) {
            val head = "HTTP/1.1 $code Response\r\nConnection: close\r\n" +
                (if (size >= 0) "Content-Length: $size\r\n" else "") +
                responseHeaders.entries.joinToString("") { "${it.key}: ${it.value}\r\n" } + "\r\n"
            responseBody.write(head.toByteArray())
            responseBody.flush()
        }
        fun close() = socket.close()
    }

    private class TestServer {
        private val socket = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        private val executor = Executors.newCachedThreadPool { Thread(it).apply { isDaemon = true } }
        private val handlers = java.util.concurrent.ConcurrentHashMap<String, (Request) -> Unit>()
        val url = "http://127.0.0.1:${socket.localPort}"
        init {
            executor.submit {
                try {
                    while (!socket.isClosed) {
                        val client = socket.accept()
                        executor.submit {
                            try {
                                client.use {
                                    val reader = it.getInputStream().bufferedReader()
                                    val path = reader.readLine().split(" ")[1]
                                    val headers = mutableMapOf<String, String>()
                                    while (true) {
                                        val line = reader.readLine() ?: break
                                        if (line.isEmpty()) break
                                        headers[line.substringBefore(":").lowercase()] = line.substringAfter(":").trim()
                                    }
                                    handlers.getValue(path)(Request(it, headers))
                                }
                            } catch (_: Exception) { }
                        }
                    }
                } catch (_: Exception) { }
            }
        }
        fun createContext(path: String, handler: (Request) -> Unit) { handlers[path] = handler }
        fun close() { socket.close(); executor.shutdownNow() }
    }

    private fun withServer(block: (TestServer, String) -> Unit) {
        val server = TestServer()
        try { block(server, server.url) } finally { server.close() }
    }

    @Test fun downloadsGzipThroughRedirectWithClashHeaders() = withServer { server, base ->
        val text = "proxies: [{name: KR, type: http, server: example.org, port: 80}]"
        server.createContext("/redirect") {
            it.responseHeaders["Location"] = "$base/gzip"
            it.sendResponseHeaders(302, -1)
            it.close()
        }
        server.createContext("/gzip") {
            assertEquals("clash.meta", it.headers["user-agent"])
            val bytes = ByteArrayOutputStream().apply {
                GZIPOutputStream(this).use { gzip -> gzip.write(text.toByteArray()) }
            }.toByteArray()
            it.responseHeaders["Content-Encoding"] = "gzip"
            it.sendResponseHeaders(200, bytes.size.toLong())
            it.responseBody.use { body -> body.write(bytes) }
        }
        assertEquals(text, SubscriptionDownloader.download("$base/redirect").toString(Charsets.UTF_8))
    }

    @Test fun totalDeadlineStopsContinuousSlowChunks() = withServer { server, base ->
        server.createContext("/slow") {
            try {
                it.sendResponseHeaders(200, 100)
                repeat(100) { _ ->
                    it.responseBody.write("p".toByteArray())
                    it.responseBody.flush()
                    Thread.sleep(40)
                }
            } catch (_: Exception) { } finally { it.close() }
        }
        val start = System.nanoTime()
        assertThrows(SocketTimeoutException::class.java) {
            SubscriptionDownloader.download("$base/slow", timeoutMs = 400)
        }
        assertTrue((System.nanoTime() - start) / 1_000_000 < 2000)
    }

    @Test fun stalledResponseReturnsWithoutWaitingForServer() = withServer { server, base ->
        server.createContext("/stall") {
            try { Thread.sleep(5000) } catch (_: InterruptedException) { } finally { it.close() }
        }
        val start = System.nanoTime()
        assertThrows(SocketTimeoutException::class.java) {
            SubscriptionDownloader.download("$base/stall", timeoutMs = 300)
        }
        assertTrue((System.nanoTime() - start) / 1_000_000 < 2000)
    }

    @Test fun rejectsHttpErrorsAndOversizedDecompressedContent() = withServer { server, base ->
        server.createContext("/error") { it.sendResponseHeaders(503, -1); it.close() }
        server.createContext("/large") {
            val bytes = ByteArrayOutputStream().apply {
                GZIPOutputStream(this).use { gzip -> gzip.write(ByteArray(2000)) }
            }.toByteArray()
            it.responseHeaders["Content-Encoding"] = "gzip"
            it.sendResponseHeaders(200, bytes.size.toLong())
            it.responseBody.use { body -> body.write(bytes) }
        }
        assertThrows(IllegalArgumentException::class.java) { SubscriptionDownloader.download("$base/error") }
        assertThrows(IllegalArgumentException::class.java) { SubscriptionDownloader.download("$base/large", maxBytes = 1024) }
    }
}
