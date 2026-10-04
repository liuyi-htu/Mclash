package com.liuyihtu.mclash.root

import java.io.ByteArrayOutputStream
import java.io.InputStream

internal fun readConfigStream(stream: InputStream, limit: Int): ByteArray {
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(16 * 1024)
    var total = 0L
    while (true) {
        val count = stream.read(buffer)
        if (count < 0) break
        total += count
        require(total <= limit) { "配置内容超过 8 MB" }
        output.write(buffer, 0, count)
    }
    return output.toByteArray()
}
