package com.liuyihtu.mclash.root

import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL

internal object CoreProxyConnection {
    fun open(url: String, port: Int): HttpURLConnection = URL(url).openConnection(
        Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", port)),
    ) as HttpURLConnection
}
