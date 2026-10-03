package com.liuyihtu.mclash.root

import java.io.DataInputStream
import java.net.ServerSocket
import java.net.InetAddress
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class CoreProxyConnectionTest {
    @Test fun sendsHostnameThroughLocalSocksInsteadOfResolvingOrConnectingDirectly() {
        ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { server ->
            val executor = Executors.newSingleThreadExecutor()
            try {
                val handshake = executor.submit<String> {
                    server.accept().use { socket ->
                        socket.soTimeout = 5000
                        val input = DataInputStream(socket.getInputStream())
                        val output = socket.getOutputStream()
                        check(input.readUnsignedByte() == 5)
                        val methods = ByteArray(input.readUnsignedByte())
                        input.readFully(methods)
                        output.write(byteArrayOf(5, 0)); output.flush()
                        check(input.readUnsignedByte() == 5 && input.readUnsignedByte() == 1)
                        input.readUnsignedByte()
                        check(input.readUnsignedByte() == 3)
                        val domain = ByteArray(input.readUnsignedByte())
                        input.readFully(domain)
                        check(input.readUnsignedShort() == 80)
                        output.write(byteArrayOf(5, 0, 0, 1, 127, 0, 0, 1, 0, 80)); output.flush()
                        val reader = input.bufferedReader()
                        while (!reader.readLine().isNullOrEmpty()) { /* Read HTTP request headers. */ }
                        output.write("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok".toByteArray()); output.flush()
                        String(domain)
                    }
                }
                val connection = CoreProxyConnection.open("http://unresolvable.invalid/test", server.localPort)
                try {
                    connection.connectTimeout = 5000; connection.readTimeout = 5000
                    assertEquals("ok", connection.inputStream.bufferedReader().readText())
                    assertEquals("unresolvable.invalid", handshake.get(5, TimeUnit.SECONDS))
                } finally { connection.disconnect() }
            } finally { executor.shutdownNow() }
        }
    }
}
