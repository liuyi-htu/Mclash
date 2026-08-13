package com.liuyihtu.mclash

import android.content.Context
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal object StartupLog {
    private const val MAX_FILE_BYTES = 512 * 1024

    private fun file(context: Context): File =
        File(context.filesDir, "runtime/startup.log")

    private fun enabled(context: Context): Boolean =
        AppPreferences(context).debugLoggingEnabled

    @Synchronized
    fun reset(context: Context) {
        if (!enabled(context)) return
        val target = file(context)
        target.parentFile?.mkdirs()
        target.writeText("${timestamp()} debug log reset\n", Charsets.UTF_8)
    }

    @Synchronized
    fun append(context: Context, message: String) {
        if (!enabled(context)) return

        val target = file(context)
        target.parentFile?.mkdirs()

        if (target.exists() && target.length() > MAX_FILE_BYTES) {
            val tail = target.readLines(Charsets.UTF_8).takeLast(200)
            target.writeText(tail.joinToString("\n", postfix = "\n"), Charsets.UTF_8)
        }

        target.appendText("${timestamp()} $message\n", Charsets.UTF_8)
    }

    @Synchronized
    fun read(context: Context, maxLines: Int = 250): String {
        val target = file(context)
        if (!target.isFile) return "尚未生成 App 调试日志"
        return target.readLines(Charsets.UTF_8)
            .takeLast(maxLines)
            .joinToString("\n")
            .ifBlank { "App 调试日志为空" }
    }

    @Synchronized
    fun clear(context: Context) {
        val target = file(context)
        if (!target.exists()) return
        target.writeText("", Charsets.UTF_8)
    }

    private fun timestamp(): String =
        SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US).format(Date())
}
