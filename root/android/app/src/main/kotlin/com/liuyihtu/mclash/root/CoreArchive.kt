package com.liuyihtu.mclash.root

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest
import java.util.zip.GZIPInputStream

/** Limits both download and decompression; only official Android ARM64 ELF cores are accepted. */
internal object CoreArchive {
    const val MAX_BYTES = 128L * 1024 * 1024

    fun copyLimited(input: InputStream, output: OutputStream) {
        val buffer = ByteArray(8192)
        var total = 0L
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            check(total <= MAX_BYTES) { "内核文件过大" }
            output.write(buffer, 0, count)
        }
    }

    fun unpack(archive: File, target: File, digest: String) {
        require(digest.matches(Regex("sha256:[0-9a-fA-F]{64}"))) { "官方内核缺少 SHA-256 校验值" }
        val hash = MessageDigest.getInstance("SHA-256")
        archive.inputStream().use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
        }
        val actual = hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
        check(actual.equals(digest.removePrefix("sha256:"), ignoreCase = true)) { "内核 SHA-256 校验失败" }
        GZIPInputStream(archive.inputStream()).use { input ->
            target.outputStream().use { copyLimited(input, it) }
        }
        val header = ByteArray(20)
        target.inputStream().use { require(it.read(header) == header.size) { "内核 ELF 文件不完整" } }
        require(header[0] == 0x7f.toByte() && header[1] == 'E'.code.toByte() &&
            header[2] == 'L'.code.toByte() && header[3] == 'F'.code.toByte() &&
            header[4] == 2.toByte() && header[5] == 1.toByte() &&
            header[18] == 0xb7.toByte() && header[19] == 0.toByte()) { "内核不是 Android ARM64 ELF 文件" }
    }

    fun version(text: String): String = Regex("\\bMihomo\\s+(?:Meta\\s+)?(v[0-9]+\\.[0-9]+\\.[0-9]+)\\b", RegexOption.IGNORE_CASE)
        .find(text)?.groupValues?.get(1) ?: error("无法识别 Mihomo 内核版本")
}
