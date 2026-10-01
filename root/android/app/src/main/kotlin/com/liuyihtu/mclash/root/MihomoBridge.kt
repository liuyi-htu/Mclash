package com.liuyihtu.mclash.root

import android.content.Context
import java.io.File
import java.io.FileNotFoundException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.TimeUnit

/** The privileged supervisor owns both the core and its rules, including crash cleanup. */
internal object MihomoProcess {
    @Volatile private var process: Process? = null
    private var home: File? = null
    private var outputReader: Thread? = null
    @Volatile private var lastOutput = ""

    fun prepare(context: Context): File {
        val directory = File(context.filesDir, "mihomo").apply { mkdirs() }
        home = directory
        for ((asset, name) in listOf("geosite.dat" to "GeoSite.dat", "geoip.dat" to "GeoIP.dat", "country.mmdb" to "Country.mmdb")) {
            val target = File(directory, name)
            if (target.isFile && target.length() > 0) continue
            try {
                context.assets.open("geodata/$asset").use { input -> target.outputStream().use(input::copyTo) }
            } catch (_: FileNotFoundException) {
                // Configurations that do not use geodata can still be validated locally.
            }
        }
        return directory
    }

    fun previewConfig(context: Context, source: File): String {
        val settings = AppPreferences(context)
        return RootRuntimeConfig.build(source.readText(), settings.debugLoggingEnabled)
    }

    fun validateConfig(context: Context, source: File) {
        val directory = prepare(context)
        val config = File.createTempFile("validate-", ".yaml", directory)
        val log = File.createTempFile("validate-", ".log", directory)
        var validator: Process? = null
        try {
            config.writeText(previewConfig(context, source))
            validator = ProcessBuilder(binary(context).absolutePath, "-t", "-d", directory.absolutePath, "-f", config.absolutePath)
                .redirectErrorStream(true).redirectOutput(log).start()
            check(validator.waitFor(30, TimeUnit.SECONDS)) { "配置校验超时" }
            check(validator.exitValue() == 0) { "运行配置校验失败：\n${log.readText().takeLast(16384)}" }
        } finally {
            validator?.let { if (it.isAlive) it.destroyForcibly() }
            config.delete(); log.delete()
        }
    }

    @Synchronized
    fun start(context: Context, source: File, rules: String, cancelled: () -> Boolean) {
        check(process?.isAlive != true) { "Root 代理已在运行" }
        val directory = prepare(context)
        val core = binary(context)
        val config = File(directory, "runtime.yaml").apply { writeText(previewConfig(context, source)) }
        val appPid = android.os.Process.myPid()
        val appUid = android.os.Process.myUid()
        val ready = File(directory, "ready").apply { writeText("") }
        val ports = File(directory, "ports-ready").apply { delete() }
        File(directory, "stop").delete()
        val log = File(directory, "mihomo.log").apply { writeText("") }
        File(directory, "supervisor.log").writeText("")
        File(directory, "supervisor.pid").writeText("")
        File(directory, "install.sh").apply { writeText(rules) }
        File(directory, "cleanup.sh").apply { writeText(TProxyRules.cleanup()) }
        val script = File(directory, "supervisor.sh").apply {
            writeText("""
                #!/system/bin/sh
                set -eu
                umask 077
                cd ${RootShell.quote(directory.absolutePath)}
                [ "${'$'}(id -u)" = 0 ] || { echo '未获得 Root 权限'; exit 1; }
                echo ${'$'}${'$'} > ./supervisor.pid
                app_stamp=${'$'}(awk '{print ${'$'}22}' /proc/$appPid/stat)
                core_pid=''
                # Cache rollback before launch; uninstall may remove this directory.
                cleanup_rules=${'$'}(cat ./cleanup.sh)
                cleanup() {
                    trap - EXIT HUP INT TERM
                    while ! /system/bin/sh -c "${'$'}cleanup_rules"; do
                        { echo cleanup_failed > ./ready; } 2>/dev/null || true
                        sleep 2
                    done
                    if [ -n "${'$'}core_pid" ]; then
                        kill "${'$'}core_pid" 2>/dev/null || true
                        n=0
                        while kill -0 "${'$'}core_pid" 2>/dev/null && [ "${'$'}n" -lt 30 ]; do
                            # An exited child remains a zombie until wait reaps it.
                            # kill -0 alone otherwise forces the entire grace period.
                            IFS=' ' read -r child_pid child_name child_state child_rest < /proc/"${'$'}core_pid"/stat 2>/dev/null || break
                            [ "${'$'}child_state" != Z ] || break
                            sleep 0.1; n=${'$'}((n + 1))
                        done
                        kill -9 "${'$'}core_pid" 2>/dev/null || true
                        wait "${'$'}core_pid" 2>/dev/null || true
                    fi
                    chown -R $appUid:$appUid ${RootShell.quote(directory.absolutePath)} 2>/dev/null || true
                    { echo stopped > ./ready; } 2>/dev/null || true
                }
                trap cleanup EXIT
                trap 'exit 1' HUP INT TERM
                owner_alive() {
                    [ ! -f ./stop ] &&
                    [ "${'$'}(awk '{print ${'$'}22}' /proc/$appPid/stat 2>/dev/null)" = "${'$'}app_stamp" ]
                }
                ${RootShell.quote(core.absolutePath)} -d ${RootShell.quote(directory.absolutePath)} -f ${RootShell.quote(config.absolutePath)} >> ${RootShell.quote(log.absolutePath)} 2>&1 &
                core_pid=${'$'}!
                n=0
                while [ ! -f ./ports-ready ]; do
                    owner_alive && kill -0 "${'$'}core_pid" 2>/dev/null || { echo '启动期间进程退出或被取消'; exit 1; }
                    [ "${'$'}n" -lt 900 ] || { echo '等待内核监听超时'; exit 1; }
                    sleep 0.1; n=${'$'}((n + 1))
                done
                /system/bin/sh ./install.sh >> ./supervisor.log 2>&1 || { cat ./supervisor.log; exit 1; }
                echo ready > ./ready
                echo 'TPROXY_READY'
                while owner_alive && kill -0 "${'$'}core_pid" 2>/dev/null; do sleep 1; done
                echo 'Root supervisor stopped; removing routing rules'
            """.trimIndent() + "\n")
        }
        lastOutput = ""
        val next = RootShell.start("exec /system/bin/sh ${RootShell.quote(script.absolutePath)}")
        process = next
        outputReader = Thread({
            next.inputStream.bufferedReader().useLines { lines ->
                lines.forEach { line ->
                    lastOutput = (lastOutput + line + "\n").takeLast(8192)
                    runCatching { File(directory, "supervisor.log").appendText(line + "\n") }
                }
            }
        }, "root-supervisor-output").apply { isDaemon = true; start() }
        val deadline = System.currentTimeMillis() + 100_000
        try {
            while (System.currentTimeMillis() < deadline) {
                check(!cancelled()) { "启动已取消" }
                check(next.isAlive) { diagnostics(directory) }
                if (!ports.exists() && canConnect(RootRuntimeConfig.MIXED_PORT) && canConnect(RootRuntimeConfig.CONTROLLER_PORT)) {
                    // Both test connections were made before any interception rules were installed.
                    ports.writeText("ready")
                }
                if (ready.readText().trim() == "ready") return
                Thread.sleep(200)
            }
            error("TProxy 启动超时：\n${diagnostics(directory)}")
        } catch (error: Throwable) {
            stop()
            throw error
        }
    }

    fun isRunning(): Boolean = process?.isAlive == true

    @Synchronized
    fun stop(): Boolean {
        val current = process ?: return false
        home?.resolve("stop")?.writeText("stop")
        // Supervisor removes rules first, then terminates the core. Do not kill it mid-cleanup.
        check(current.waitFor(20, TimeUnit.SECONDS)) { "Root 清理尚未完成，请检查启动日志" }
        outputReader?.join(1000)
        process = null
        // "stopped" is written only after the supervisor verifies rule removal
        // and reaps the core. A killed supervisor requires full recovery instead.
        return home?.resolve("ready")?.readText()?.trim() == "stopped"
    }

    fun recover(context: Context): String {
        check(!isRunning()) { "请先停止代理" }
        val directory = prepare(context)
        File(directory, "stop").writeText("stop")
        val oldPid = File(directory, "supervisor.pid").takeIf { it.isFile }
            ?.readText()?.trim()?.toIntOrNull()
        if (oldPid != null && oldPid > 1) {
            val scriptPath = RootShell.quote(File(directory, "supervisor.sh").absolutePath)
            RootShell.run("""
                set -eu
                n=0
                while [ -r /proc/$oldPid/cmdline ] && tr '\000' '\n' < /proc/$oldPid/cmdline | grep -F -x $scriptPath >/dev/null; do
                    [ "${'$'}n" -lt 25 ] || { echo '旧 Root 服务尚未退出'; exit 1; }
                    sleep 1; n=${'$'}((n + 1))
                done
            """.trimIndent())
        }
        val cleanup = RootShell.run(TProxyRules.cleanup())
        // A package update or a process-group kill can kill the supervisor before
        // its trap runs. Only terminate cores using this app's exact data directory.
        RootShell.run(orphanCleanup(directory))
        File(directory, "ready").writeText("stopped")
        return cleanup
    }

    internal fun orphanCleanup(directory: File): String = """
        set -eu
        for entry in /proc/[0-9]*/cmdline; do
            [ -r "${'$'}entry" ] || continue
            # Shell builtins avoid spawning tr/grep for every Android process.
            IFS= read -r name < "${'$'}{entry%/cmdline}/comm" 2>/dev/null || continue
            [ "${'$'}name" = libmihomo.so ] || continue
            args=${'$'}(tr '\000' '\n' < "${'$'}entry" 2>/dev/null) || continue
            printf '%s\n' "${'$'}args" | grep -F -x ${RootShell.quote(directory.absolutePath)} >/dev/null || continue
            printf '%s\n' "${'$'}args" | grep -E '^/data/app/.*/lib/[^/]+/libmihomo\.so${'$'}' >/dev/null || continue
            pid=${'$'}{entry#/proc/}; pid=${'$'}{pid%/cmdline}
            kill "${'$'}pid" 2>/dev/null || true
            n=0
            while kill -0 "${'$'}pid" 2>/dev/null && [ "${'$'}n" -lt 3 ]; do
                sleep 1; n=${'$'}((n + 1))
            done
            # Confirm identity again before SIGKILL; never target a reused PID.
            if [ -r "${'$'}entry" ] && tr '\000' '\n' < "${'$'}entry" | grep -F -x ${RootShell.quote(directory.absolutePath)} >/dev/null; then
                kill -9 "${'$'}pid" 2>/dev/null || true
                n=0
                while [ -r "${'$'}entry" ] && tr '\000' '\n' < "${'$'}entry" | grep -F -x ${RootShell.quote(directory.absolutePath)} >/dev/null; do
                    [ "${'$'}n" -lt 3 ] || { echo '残留内核未能停止'; exit 1; }
                    sleep 1; n=${'$'}((n + 1))
                done
            fi
        done
    """.trimIndent()

    fun clearDebugLog(context: Context) { File(context.filesDir, "mihomo/mihomo.log").writeText("") }

    private fun binary(context: Context): File = File(context.applicationInfo.nativeLibraryDir, "libmihomo.so").also {
        require(it.isFile && it.canExecute()) { "APK 中缺少可执行的当前架构 Mihomo 内核" }
    }
    private fun canConnect(port: Int): Boolean = runCatching {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 200) }; true
    }.getOrDefault(false)
    private fun diagnostics(directory: File): String = buildString {
        appendLine(lastOutput)
        for (name in listOf("supervisor.log", "mihomo.log")) {
            appendLine("$name:")
            appendLine(runCatching { File(directory, name).readText().takeLast(8192) }.getOrDefault("无法读取"))
        }
    }
}
