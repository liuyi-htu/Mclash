package com.liuyihtu.mclash

import java.util.concurrent.TimeUnit

/** Reap before releasing ownership; close every Java-side pipe after exit. */
internal object ProcessCleanup {
    fun terminate(process: Process, gracefulSeconds: Long = 3, forceFallback: (() -> Unit)? = null) {
        if (process.isAlive) {
            if (gracefulSeconds > 0) process.destroy()
            if (gracefulSeconds == 0L || !process.waitFor(gracefulSeconds, TimeUnit.SECONDS)) {
                process.destroyForcibly()
                if (!process.waitFor(2, TimeUnit.SECONDS)) {
                    check(forceFallback != null) { "mihomo 在强制停止后仍未退出" }
                    forceFallback()
                    check(process.waitFor(2, TimeUnit.SECONDS)) { "mihomo 在 SIGKILL 后仍未退出" }
                }
            }
        }
        check(!process.isAlive) { "mihomo 进程尚未回收" }
        val failures = mutableListOf<Throwable>()
        listOf(process.inputStream, process.errorStream, process.outputStream).forEach { stream ->
            runCatching { stream.close() }.onFailure { failures += it }
        }
        if (failures.isNotEmpty()) {
            val error = IllegalStateException("mihomo 输出管道关闭失败", failures.first())
            failures.drop(1).forEach(error::addSuppressed)
            throw error
        }
    }
}
