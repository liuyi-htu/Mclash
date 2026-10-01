package com.liuyihtu.mclash.root

import java.util.concurrent.TimeUnit

internal object RootShell {
    fun quote(value: String): String = "'" + value.replace("'", "'\\''") + "'"

    fun start(script: String): Process = ProcessBuilder("su", "-c", script)
        .redirectErrorStream(true).start()

    fun run(script: String, timeoutSeconds: Long = 30): String {
        val process = start(script)
        val output = StringBuilder()
        val reader = Thread({
            runCatching {
                process.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { line ->
                        synchronized(output) {
                            output.appendLine(line)
                            if (output.length > 32768) output.delete(0, output.length - 32768)
                        }
                    }
                }
            }
        }, "root-shell-output").apply { isDaemon = true; start() }
        try {
            check(process.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
                "Root 命令超时，请检查 su 授权"
            }
            reader.join(1000)
            val text = synchronized(output) { output.toString() }
            check(process.exitValue() == 0) { text.ifBlank { "Root 命令执行失败：${process.exitValue()}" } }
            return text
        } finally {
            if (process.isAlive) process.destroyForcibly()
        }
    }

    fun requireRoot(): String = run("""
        set -eu
        [ "${'$'}(id -u)" = 0 ] || { echo '请授予 Mclash Root 超级用户权限'; exit 1; }
        for tool in ip iptables ip6tables iptables-restore ip6tables-restore dumpsys sed awk tr grep; do
            command -v "${'$'}tool" >/dev/null || { echo "缺少命令：${'$'}tool"; exit 1; }
        done
        iptables -w 5 -t mangle -S OUTPUT >/dev/null || { echo '无法访问 IPv4 mangle 表'; exit 1; }
        iptables -w 5 -t nat -S OUTPUT >/dev/null || { echo '无法访问 IPv4 nat 表'; exit 1; }
        ip6tables -w 5 -t filter -S OUTPUT >/dev/null || { echo '无法访问 IPv6 filter 表，不能保证 IPv6 阻断'; exit 1; }
        echo 'Root 授权及系统命令检查通过'
    """.trimIndent())
}
