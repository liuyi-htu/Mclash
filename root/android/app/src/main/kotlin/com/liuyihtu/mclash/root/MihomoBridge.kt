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
        return RootRuntimeConfig.build(source.readText(), settings.debugLoggingEnabled, settings.coreMode, settings.rootIpv6, settings.rootProxyMode == "tun", settings.rootTunStack)
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
        initialize(context)
        check(!daemonAlive(home!!)) { "Root 代理已在运行" }
        val directory = prepare(context)
        val core = binary(context)
        val config = File(directory, "runtime.yaml").apply { writeText(previewConfig(context, source)) }
        val ipv6 = AppPreferences(context).rootIpv6
        val tun = AppPreferences(context).rootProxyMode == "tun"
        val appUid = android.os.Process.myUid()
        val ready = File(directory, "ready").apply { writeText("") }
        val ports = File(directory, "ports-ready").apply { delete() }
        File(directory, "stop").delete()
        val log = File(directory, "mihomo.log").apply { writeText("") }
        File(directory, "supervisor.log").writeText("")
        File(directory, "supervisor.pid").writeText("")
        File(directory, "supervisor.stamp").writeText("")
        File(directory, "sharing.policy").writeText(AppPreferences(context).let { HotspotRules.sharingPolicy(it.networkSharingEnabled, it.sharedInterfaces) })
        File(directory, "sharing.applied").delete()
        File(directory, "hotspot.snapshot").delete()
        File(directory, "log-maintenance.sh").writeText(DebugLogLimits.maintenanceScript())
        File(directory, "hotspot-monitor.sh").writeText(RootHotspotMonitor.script(AppPreferences(context).rootBypassLan, ipv6, tun))
        File(directory, "install.sh").apply { writeText(rules) }
        File(directory, "cleanup.sh").apply { writeText(TProxyRules.cleanup()) }
        File(directory, "sharing-watch.sh").writeText(RootSupervisor.sharingWatcher())
        File(directory, "log-writer.sh").writeText(RootSupervisor.logWriter())
        File(directory, "protocol").writeText(RootSupervisor.PROTOCOL)
        val script = File(directory, "supervisor.sh").apply {
            writeText(RootSupervisor.script(directory, core, appUid, tun, ipv6))
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
                if (ready.readText().trim() == "ready") {
                    lastHealth = true; lastHealthAt = System.nanoTime()
                    return
                }
                Thread.sleep(200)
            }
            error("Root 代理启动超时：\n${diagnostics(directory)}")
        } catch (error: Throwable) {
            stop()
            throw error
        }
    }

    /** Apply through the supervisor so refresh, stop and rule updates cannot race. */
    @Synchronized
    fun setNetworkSharing(context: Context, enabled: Boolean, interfaces: Set<String>): Map<String, Any> {
        check(!ProxyTProxyService.starting && verifiedRunning(context)) {
            "请先开启代理再设置网络共享"
        }
        require(interfaces.all { it != "lo" && it.matches(Regex("[a-zA-Z0-9_.-]{1,15}")) }) {
            "共享接口名称无效"
        }
        val directory = File(context.filesDir, "mihomo")
        val policy = File(directory, "sharing.policy")
        val previous = policy.readText()
        val settings = AppPreferences(context)
        val oldInterfaces = settings.sharedInterfaces
        val oldEnabled = settings.networkSharingEnabled
        val available = if (enabled) networkSharingInterfaces() else emptySet()
        require(!enabled || (interfaces - oldInterfaces).all { it in available }) {
            "接口已断开，请刷新后重新选择"
        }
        val content = HotspotRules.sharingPolicy(enabled, interfaces)
        fun write(value: String) {
            val temporary = File(directory, "sharing.policy.tmp")
            temporary.writeText(value)
            check(temporary.renameTo(policy)) { "无法保存网络共享设置" }
        }
        val usesSignals = File(directory, "protocol").takeIf(File::isFile)?.readText()?.trim() == RootSupervisor.PROTOCOL
        write(content)
        try {
            if (usesSignals) signal(directory, "USR1")
            awaitSharingApplied(directory)
            check(isRunning()) { "代理已停止" }
            settings.saveNetworkSharing(enabled, interfaces)
        } catch (error: Throwable) {
            write(previous)
            runCatching { settings.saveNetworkSharing(oldEnabled, oldInterfaces) }
            runCatching { if (usesSignals) signal(directory, "USR1"); awaitSharingApplied(directory) }
            throw error
        }
        return mapOf(
            "enabled" to enabled,
            "interfaces" to interfaces.sorted(),
            "availableInterfaces" to available.sorted(),
        )
    }

    private fun awaitSharingApplied(directory: File) {
        RootShell.run("""
                cd ${RootShell.quote(directory.absolutePath)}
                n=0
                while ! cmp -s ./sharing.policy ./sharing.applied; do
                    [ ! -f ./stop ] && [ "${'$'}(cat ./ready)" = ready ] || exit 1
                    [ "${'$'}n" -lt 150 ] || { echo '网络共享规则更新超时'; exit 1; }
                    sleep 0.1; n=${'$'}((n + 1))
                done
            """.trimIndent(), 20)
    }

    fun networkSharingInterfaces(): Set<String> {
        val dump = RootShell.run("set -eu; dumpsys tethering | sed -n '/Tether state:/,/Hardware offload:/p'")
        check(dump.contains("Tether state:")) { "无法读取可共享接口" }
        return HotspotRules.interfaces(dump)
    }

    @Synchronized
    fun networkSharing(context: Context): Map<String, Any> {
        initialize(context)
        val active = !ProxyTProxyService.starting && isRunning()
        val policy = if (active) File(context.filesDir, "mihomo/sharing.policy").takeIf { it.isFile }?.readLines().orEmpty() else emptyList()
        val settings = AppPreferences(context)
        val enabled = if (active) policy.firstOrNull() == "1" else settings.networkSharingEnabled
        return mapOf(
            "enabled" to enabled,
            "interfaces" to settings.sharedInterfaces.sorted(),
            "availableInterfaces" to if (active && enabled) networkSharingInterfaces().sorted() else emptyList<String>(),
        )
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

    internal fun identityCheck(directory: File, pid: Int, stamp: String): String =
        RootProcessIdentity.supervisor(directory, pid, stamp)

    private fun signal(directory: File, signal: String) {
        require(signal in setOf("TERM", "USR1"))
        val pid = File(directory, "supervisor.pid").readText().trim().toInt()
        val stamp = File(directory, "supervisor.stamp").readText().trim()
        check(pid > 1 && stamp.matches(Regex("[0-9]+"))) { "Root 进程身份无效" }
        RootShell.run(RootProcessIdentity.functions() + "\nif " + RootProcessIdentity.supervisorCheck(directory, pid, stamp) +
            "; then " + (if (signal == "TERM")
                "printf 'stopping\\n' > ${RootShell.quote(File(directory, "ready.control.tmp").absolutePath)}; " +
                "chown ${android.os.Process.myUid()}:${android.os.Process.myUid()} ${RootShell.quote(File(directory, "ready.control.tmp").absolutePath)}; " +
                "mv -f ${RootShell.quote(File(directory, "ready.control.tmp").absolutePath)} ${RootShell.quote(File(directory, "ready").absolutePath)}; " else "") +
            "kill -$signal $pid; else echo 'Root 进程身份已变化'; exit 1; fi", 5)
    }

    fun initialize(context: Context) { home = File(context.filesDir, "mihomo") }
    fun hasCleanupFailure(): Boolean = home?.let {
        File(it, "ready").takeIf(File::isFile)?.readText()?.trim() == "cleanup_failed"
    } ?: false

    fun verifiedRunning(context: Context): Boolean {
        initialize(context)
        return daemonAlive(home!!)
    }

    fun requireStopped(context: Context) {
        initialize(context)
        check(!ProxyTProxyService.starting && !ProxyTProxyService.tileStopPending && !verifiedRunning(context) && !hasCleanupFailure()) {
            "请先停止代理并完成规则清理，再修改配置或设置"
        }
    }

    @Volatile private var lastOwnerAlive: Boolean? = null
    private fun daemonAlive(directory: File): Boolean {
        val identity = runCatching {
            File(directory, "supervisor.pid").readText().trim().toInt() to
                File(directory, "supervisor.stamp").readText().trim()
        }.getOrNull()
        if (identity == null || identity.first <= 1 || !identity.second.matches(Regex("[0-9]+"))) {
            lastOwnerAlive = false
            return false
        }
        // A root authorization/command failure must reject mutations, not masquerade as a stopped daemon.
        val result = RootShell.run(RootProcessIdentity.functions() + "\nif " +
            RootProcessIdentity.supervisorCheck(directory, identity.first, identity.second) +
            "; then printf alive; else printf absent; fi", 5).trim() == "alive"
        lastOwnerAlive = result
        return result
    }

    @Volatile private var lastHealthAt = 0L
    @Volatile private var lastHealth = false
    /** Read-only UI hint. Root identity is always revalidated before mutations. */
    fun isRunning(): Boolean = runCatching {
        val directory = home ?: return false
        lastOwnerAlive != false && lastHealth && File(directory, "ready").takeIf(File::isFile)?.readText()?.trim() in setOf("ready", "stopping", "cleanup_failed")
    }.getOrDefault(false)

    fun status(starting: Boolean, stopping: Boolean): String {
        val marker = home?.let { File(it, "ready").takeIf(File::isFile)?.readText()?.trim() }
        return rootProxyStatus(marker, starting, stopping, probeRunning(), lastOwnerAlive)
    }

    /** Called on a native worker, never the Android main thread. */
    fun probeRunning(): Boolean = runCatching {
        val directory = home ?: return false
        // attach() already verified ownership once on resume. Do not let open
        // ports of an orphan core undo that result or spawn su on UI refreshes.
        if (lastOwnerAlive == false) {
            lastHealth = false; lastHealthAt = 0; return false
        }
        if (File(directory, "ready").takeIf(File::isFile)?.readText()?.trim() !in setOf("ready", "stopping", "cleanup_failed")) {
            lastHealth = false; lastHealthAt = 0; return false
        }
        val now = System.nanoTime()
        if (now - lastHealthAt > 2_000_000_000L) {
            lastHealth = canConnect(RootRuntimeConfig.CONTROLLER_PORT) && canConnect(RootRuntimeConfig.MIXED_PORT)
            lastHealthAt = now
        }
        lastHealth
    }.getOrDefault(false)

    @Synchronized
    fun attach(context: Context): Boolean {
        initialize(context)
        val directory = home!!
        // Always verify ownership, including transitional markers from a prior app process.
        val ownerAlive = daemonAlive(directory)
        val marker = File(directory, "ready").takeIf { it.isFile }?.readText()?.trim()
        val active = ownerAlive && marker in setOf("ready", "cleanup_failed") &&
            canConnect(RootRuntimeConfig.MIXED_PORT) && canConnect(RootRuntimeConfig.CONTROLLER_PORT)
        lastHealth = active
        lastHealthAt = System.nanoTime()
        if (active && File(directory, "protocol").takeIf(File::isFile)?.readText()?.trim() != RootSupervisor.PROTOCOL) {
            StartupLog.append(context, "已连接旧版 Root 守护进程；下次手动停止并启动后启用低功耗 Supervisor")
        }
        return active
    }

    @Synchronized
    fun stop(): Boolean {
        val directory = home ?: return false
        if (!daemonAlive(directory)) return false
        // Older installed supervisors only watch the stop file. Never rewrite a
        // running supervisor's script or mistake it for the new signal protocol.
        if (File(directory, "protocol").takeIf(File::isFile)?.readText()?.trim() == RootSupervisor.PROTOCOL) {
            signal(directory, "TERM")
        } else {
            File(directory, "stop").writeText("stop")
        }
        val deadline = System.currentTimeMillis() + 90_000
        while (System.currentTimeMillis() < deadline) {
            when (File(directory, "ready").readText().trim()) {
                "cleanup_failed" -> error("Root 规则清理失败，请重试停止或恢复")
                "stopped" -> if (!daemonAlive(directory)) { lastHealth = false; lastHealthAt = 0; return true }
            }
            Thread.sleep(100)
        }
        error("Root 清理尚未完成，请检查启动日志")
    }

    fun recover(context: Context): String {
        initialize(context)
        check(!daemonAlive(home!!)) { "请先停止代理" }
        val directory = prepare(context)
        // Keep orphan identification separate from stale state files; never signal
        // a reused supervisor PID. Cleanup remains scoped to private rules/chains.
        RootShell.run(RootSupervisor.orphanHelper(directory, "sharing"), 10)
        val cleanup = RootShell.run("timeout 45 /system/bin/sh -c " + RootShell.quote(TProxyRules.cleanup()), 50)
        RootShell.run(orphanCleanup(directory))
        RootShell.run(RootSupervisor.orphanHelper(directory, "logger"), 10)
        RootShell.run("rmdir " + RootShell.quote(File(directory, "daemon.lock").absolutePath) + " 2>/dev/null || true")
        val marker = File(directory, "ready.tmp").apply { writeText("stopped") }
        check(marker.renameTo(File(directory, "ready")))
        lastHealth = false; lastHealthAt = 0
        return cleanup
    }

    internal fun orphanCleanup(directory: File): String = RootProcessIdentity.functions() + """
        set -eu
        for entry in /proc/[0-9]*/cmdline; do
            [ -r "${'$'}entry" ] || continue
            # Shell builtins avoid spawning tr/grep for every Android process.
            IFS= read -r name < "${'$'}{entry%/cmdline}/comm" 2>/dev/null || continue
            [ "${'$'}name" = libmihomo.so ] || continue
            args=${'$'}(timeout -s KILL 1 tr '\000' '\n' < "${'$'}entry" 2>/dev/null) || continue
            printf '%s\n' "${'$'}args" | grep -F -x ${RootShell.quote(directory.absolutePath)} >/dev/null || continue
            executable=${'$'}(printf '%s\n' "${'$'}args" | sed -n '1p')
            case "${'$'}executable" in
                ${RootShell.quote(File(directory, "core").absolutePath)}/core-*/libmihomo.so) ;;
                *) printf '%s\n' "${'$'}executable" | grep -E '^/data/app/.*/lib/[^/]+/libmihomo\.so${'$'}' >/dev/null || continue ;;
            esac
            pid=${'$'}{entry#/proc/}; pid=${'$'}{pid%/cmdline}
            stamp=${'$'}(proc_stamp "${'$'}pid") || continue
            owned_core() {
                same_process "${'$'}pid" "${'$'}stamp" &&
                timeout -s KILL 1 tr '\000' '\n' < "${'$'}entry" | grep -F -x ${RootShell.quote(directory.absolutePath)} >/dev/null &&
                [ "${'$'}(timeout -s KILL 1 tr '\000' '\n' < "${'$'}entry" | sed -n '1p')" = "${'$'}executable" ]
            }
            owned_core || continue
            kill "${'$'}pid" 2>/dev/null || true
            n=0
            while owned_core && [ "${'$'}n" -lt 3 ]; do
                sleep 1; n=${'$'}((n + 1))
            done
            # Confirm identity again before SIGKILL; never target a reused PID.
            if owned_core; then
                kill -9 "${'$'}pid" 2>/dev/null || true
                n=0
                while owned_core; do
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
