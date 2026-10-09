package com.liuyihtu.mclash.root

import android.content.Context
import java.io.File
import java.io.FileNotFoundException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.TimeUnit

/** The privileged supervisor owns both the core and its rules, including crash cleanup. */
internal object MihomoProcess {
    private var home: File? = null
    @Volatile private var lastOutput = ""

    fun prepare(context: Context): File {
        val directory = File(context.filesDir, "mihomo").apply { mkdirs() }
        home = directory
        BundledDashboard.install(context, directory)
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
        return RootRuntimeConfig.build(source.readText(), settings.debugLoggingEnabled, settings.coreMode, settings.rootIpv6)
    }

    fun validateConfig(context: Context, source: File) = validateWithBinary(context, source, binary(context))

    fun validateWithBinary(context: Context, source: File, core: File) {
        val directory = prepare(context)
        val config = File.createTempFile("validate-", ".yaml", directory)
        val log = File.createTempFile("validate-", ".log", directory)
        var validator: Process? = null
        try {
            config.writeText(previewConfig(context, source))
            validator = if (core.parentFile?.absolutePath == context.applicationInfo.nativeLibraryDir) {
                ProcessBuilder(core.absolutePath, "-t", "-d", directory.absolutePath, "-f", config.absolutePath)
                    .redirectErrorStream(true).redirectOutput(log).start()
            } else RootShell.start("${RootShell.quote(core.absolutePath)} -t -d ${RootShell.quote(directory.absolutePath)} -f ${RootShell.quote(config.absolutePath)} > ${RootShell.quote(log.absolutePath)} 2>&1")
            check(validator.waitFor(30, TimeUnit.SECONDS)) { "配置校验超时" }
            check(validator.exitValue() == 0) { "运行配置校验失败：\n${log.readText().takeLast(16384)}" }
        } finally {
            validator?.let { if (it.isAlive) it.destroyForcibly() }
            config.delete(); log.delete()
        }
    }

    @Synchronized
    fun start(context: Context, source: File, rules: String, cancelled: () -> Boolean) {
        check(!isRunning()) { "Root 代理已在运行" }
        val directory = prepare(context)
        val core = binary(context)
        val config = File(directory, "runtime.yaml").apply { writeText(previewConfig(context, source)) }
        val ipv6 = AppPreferences(context).rootIpv6
        val appUid = android.os.Process.myUid()
        val ready = File(directory, "ready").apply { writeText("") }
        val ports = File(directory, "ports-ready").apply { delete() }
        File(directory, "stop").delete()
        val log = File(directory, "mihomo.log").apply { writeText("") }
        File(directory, "supervisor.log").writeText("")
        File(directory, "supervisor.pid").writeText("")
        File(directory, "supervisor.stamp").writeText("")
        File(directory, "hotspot.snapshot").delete()
        File(directory, "hotspot-monitor.sh").writeText(RootHotspotMonitor.script(AppPreferences(context).rootBypassLan, ipv6))
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
                awk '{print ${'$'}22}' /proc/${'$'}${'$'}/stat > ./supervisor.stamp
                # Never inherit the application's freezer group.
                if grep -q '/uid_$appUid/' /proc/${'$'}${'$'}/cgroup; then
                    echo ${'$'}${'$'} > /sys/fs/cgroup/cgroup.procs
                fi
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
                    [ ! -f ./stop ] && [ -f ./runtime.yaml ]
                }
                ${RootShell.quote(core.absolutePath)} -d ${RootShell.quote(directory.absolutePath)} -f ${RootShell.quote(config.absolutePath)} >> ${RootShell.quote(log.absolutePath)} 2>&1 &
                core_pid=${'$'}!
                listener_ready() {
                    awk '${'$'}2 ~ /:45E2${'$'}/ && ${'$'}4 == "0A" {found=1} END {exit !found}' /proc/net/tcp /proc/net/tcp6 &&
                    awk '${'$'}2 ~ /:2382${'$'}/ && ${'$'}4 == "0A" {found=1} END {exit !found}' /proc/net/tcp /proc/net/tcp6
                }
                core_alive() {
                    kill -0 "${'$'}core_pid" 2>/dev/null || return 1
                    IFS=' ' read -r child_pid child_name child_state child_rest < /proc/"${'$'}core_pid"/stat 2>/dev/null || return 1
                    [ "${'$'}child_state" != Z ]
                }
                n=0
                while ! listener_ready; do
                    owner_alive && core_alive || { echo '启动期间进程退出或被取消'; exit 1; }
                    [ "${'$'}n" -lt 900 ] || { echo '等待内核监听超时'; exit 1; }
                    sleep 0.1; n=${'$'}((n + 1))
                done
                echo ready > ./ports-ready
                ${if (ipv6) ipv6ListenerCheck() else ""}
                /system/bin/sh ./install.sh >> ./supervisor.log 2>&1 || { cat ./supervisor.log; exit 1; }
                timeout 15 /system/bin/sh ./hotspot-monitor.sh
                echo ready > ./ready
                echo 'TPROXY_READY'
                while owner_alive && core_alive; do
                    timeout 15 /system/bin/sh ./hotspot-monitor.sh
                    sleep 2
                done
                echo 'Root supervisor stopped; removing routing rules'
            """.trimIndent() + "\n")
        }
        lastOutput = ""
        RootShell.run("nohup setsid /system/bin/sh ${RootShell.quote(script.absolutePath)} >> ${RootShell.quote(File(directory, "supervisor.log").absolutePath)} 2>&1 < /dev/null &")
        val deadline = System.currentTimeMillis() + 100_000
        try {
            while (System.currentTimeMillis() < deadline) {
                check(!cancelled()) { "启动已取消" }
                val stamp = File(directory, "supervisor.stamp").readText().trim()
                if (stamp.isNotEmpty()) check(daemonAlive(directory)) { diagnostics(directory) }
                check(ready.readText().trim() != "stopped") { diagnostics(directory) }
                if (ready.readText().trim() == "ready") return
                Thread.sleep(200)
            }
            error("TProxy 启动超时：\n${diagnostics(directory)}")
        } catch (error: Throwable) {
            stop()
            throw error
        }
    }

    internal fun ipv6ListenerCheck(): String = """
        n=0
        while ! (
            awk '${'$'}2 == "00000000000000000000000001000000:${RootRuntimeConfig.TPROXY_PORT.toString(16).uppercase()}" && ${'$'}4 == "0A" {found=1} END {exit !found}' /proc/net/tcp6 &&
            awk '${'$'}2 == "00000000000000000000000001000000:${RootRuntimeConfig.TPROXY_PORT.toString(16).uppercase()}" && ${'$'}4 == "07" {found=1} END {exit !found}' /proc/net/udp6 &&
            awk '${'$'}2 == "00000000000000000000000001000000:${RootRuntimeConfig.IPV6_DNS_TPROXY_PORT.toString(16).uppercase()}" && ${'$'}4 == "0A" {found=1} END {exit !found}' /proc/net/tcp6 &&
            awk '${'$'}2 == "00000000000000000000000001000000:${RootRuntimeConfig.IPV6_DNS_TPROXY_PORT.toString(16).uppercase()}" && ${'$'}4 == "07" {found=1} END {exit !found}' /proc/net/udp6 &&
            awk '${'$'}2 == "00000000000000000000000000000000:${RootRuntimeConfig.DNS_PORT.toString(16).uppercase()}" && ${'$'}4 == "07" {found=1} END {exit !found}' /proc/net/udp6 &&
            awk '${'$'}2 == "00000000000000000000000000000000:${RootRuntimeConfig.DNS_PORT.toString(16).uppercase()}" && ${'$'}4 == "0A" {found=1} END {exit !found}' /proc/net/tcp6
        ); do
            owner_alive && kill -0 "${'$'}core_pid" 2>/dev/null || exit 1
            [ "${'$'}n" -lt 100 ] || { echo 'IPv6 TProxy 或 DNS 监听未就绪，请检查内核支持'; exit 1; }
            sleep 0.1; n=${'$'}((n + 1))
        done
    """.trimIndent()

    internal fun identityCheck(directory: File, pid: Int, stamp: String): String = """
        [ "${'$'}(awk '{print ${'$'}22}' /proc/$pid/stat 2>/dev/null)" = ${RootShell.quote(stamp)} ] &&
        tr '\000' '\n' < /proc/$pid/cmdline | grep -F -x ${RootShell.quote(File(directory, "supervisor.sh").absolutePath)} >/dev/null
    """.trimIndent()

    private fun daemonAlive(directory: File): Boolean = runCatching {
        val pid = File(directory, "supervisor.pid").readText().trim().toInt()
        val stamp = File(directory, "supervisor.stamp").readText().trim()
        check(pid > 1 && stamp.matches(Regex("[0-9]+")))
        RootShell.run(identityCheck(directory, pid, stamp), 5)
        true
    }.getOrDefault(false)

    fun isRunning(): Boolean = home?.let(::daemonAlive) == true

    fun attach(context: Context): Boolean {
        val directory = File(context.filesDir, "mihomo")
        home = directory
        return File(directory, "ready").takeIf { it.isFile }?.readText()?.trim() == "ready" &&
            daemonAlive(directory) && canConnect(RootRuntimeConfig.MIXED_PORT) && canConnect(RootRuntimeConfig.CONTROLLER_PORT)
    }

    @Synchronized
    fun stop(): Boolean {
        val directory = home ?: return false
        if (!daemonAlive(directory)) return false
        File(directory, "stop").writeText("stop")
        val deadline = System.currentTimeMillis() + 30_000
        while (System.currentTimeMillis() < deadline) {
            if (File(directory, "ready").readText().trim() == "stopped" && !daemonAlive(directory)) return true
            Thread.sleep(200)
        }
        error("Root 清理尚未完成，请检查启动日志")
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
            executable=${'$'}(printf '%s\n' "${'$'}args" | sed -n '1p')
            case "${'$'}executable" in
                ${RootShell.quote(File(directory, "core").absolutePath)}/core-*/libmihomo.so) ;;
                *) printf '%s\n' "${'$'}executable" | grep -E '^/data/app/.*/lib/[^/]+/libmihomo\.so${'$'}' >/dev/null || continue ;;
            esac
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

    private fun binary(context: Context): File = CoreUpdater.binary(context)
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
