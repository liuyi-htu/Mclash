package com.liuyihtu.mclash

import java.io.ByteArrayInputStream
import java.io.InputStream
import org.junit.Assert.*
import org.junit.Test

class ConfigReadLimitTest {
    @Test fun acceptsAtLimitAndRejectsBeforeReadingWholeFile() {
        assertArrayEquals(byteArrayOf(1, 2, 3), readConfigStream(ByteArrayInputStream(byteArrayOf(1, 2, 3)), 3))
        var consumed = 0
        val stream = object : InputStream() {
            override fun read(): Int = error("buffered reads required")
            override fun read(bytes: ByteArray, offset: Int, length: Int): Int {
                consumed += length
                return length
            }
        }
        try {
            readConfigStream(stream, 32 * 1024)
            fail("oversized input must be rejected")
        } catch (_: IllegalArgumentException) {
            assertEquals(48 * 1024, consumed)
        }
    }
}
