package com.liuyihtu.mclash

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.TimeUnit
import java.util.zip.GZIPInputStream

internal enum class RootState { DISABLED, INSTALLING, REBOOT_REQUIRED, READY, BROKEN }

internal data class ShellResult(val code: Int, val output: String) {
    fun requireSuccess(action: String): ShellResult {
        check(code == 0) { "$action 失败（退出码 $code）：${output.ifBlank { "无输出" }}" }
        return this
    }
}

/** Owns the complete privileged lifecycle. Flutter never assembles shell commands. */
internal class RootManager(
    private val context: Context,
    private val preferences: AppPreferences,
    private val configStore: ConfigStore,
) {
    @Volatile private var installing = false
    @Volatile private var updateCancelled = false
    @Volatile private var updateInProgress = false
    @Volatile private var activeUpdateConnection: HttpURLConnection? = null
    @Volatile private var updateStage = "idle"
    @Volatile private var updateProgress = 0.0

    fun hasPermission(): Boolean {
        val result = runCatching { shell("id", timeoutSeconds = 8) }.getOrNull()
            ?: return false
        return result.code == 0 && Regex("(?:^|\\s)uid=0(?:\\D|$)").containsMatchIn(result.output)
    }

    fun status(): Map<String, Any?> {
        if (!hasPermission()) {
            return statusMap(RootState.DISABLED, "未获得 Root 权限", hasRoot = false)
        }
        if (installing) return statusMap(RootState.INSTALLING, "正在安装 Root 模块")
        val pending = shell("test -d /data/adb/modules_update/mclash_root && echo yes")
        if (pending.output.contains("yes")) {
            return statusMap(RootState.REBOOT_REQUIRED, "模块安装成功，需要重启设备")
        }
        val module = shell("test -d $MODULE_DIR && echo yes || echo no")
        if (!module.output.lineSequence().any { it.trim() == "yes" }) {
            return statusMap(RootState.DISABLED, "Root 模块未安装")
        }
        val disabled = shell("test -e $MODULE_DIR/disable -o -e $MODULE_DIR/remove && echo yes")
        if (disabled.output.contains("yes")) {
            return statusMap(RootState.REBOOT_REQUIRED, "模块变更需要重启设备")
        }
        val check = shell(
            "test -x $CTL && test -x $MODULE_DIR/service.sh && " +
                "test -x $MODULE_DIR/scripts/apply-tproxy.sh && " +
                "test -x $MODULE_DIR/scripts/clear-tproxy.sh && " +
                "test -x $MODULE_DIR/scripts/apply-tun-hotspot.sh && " +
                "test -x $MODULE_DIR/scripts/clear-tun-hotspot.sh && echo ready",
        )
        if (!check.output.contains("ready")) {
            return statusMap(RootState.BROKEN, "Root 模块文件缺失或权限错误")
        }
        val core = shell("test -x $CORE && $CORE -v 2>&1 | head -n 1", timeoutSeconds = 15)
        if (core.code != 0 || core.output.isBlank()) {
            return statusMap(RootState.BROKEN, "mihomo 内核缺失、ABI 不匹配或不可执行")
        }
        return statusMap(
            RootState.READY,
            "Root 模块已就绪",
            core = core.output.trim(),
            module = runCatching { moduleVersion() }.getOrDefault(""),
            running = runCatching { isRunning() }.getOrDefault(false),
        )
    }

    fun installModule(): Map<String, Any?> {
        check(hasPermission()) { "未获得 Root 权限；请在 Root 管理器中授权 Mclash" }
        installing = true
        try {
            val zip = File(context.cacheDir, "mclash_root.zip")
            context.assets.open("root/mclash_root.zip").use { input ->
                zip.outputStream().use(input::copyTo)
            }
            require(zip.length() > 0) { "APK 内置 Root 模块为空" }
            val remoteZip = "/data/local/tmp/mclash_root-${android.os.Process.myPid()}.zip"
            shell("cp ${quote(zip.absolutePath)} $remoteZip && chmod 0600 $remoteZip")
                .requireSuccess("复制模块安装包")
            val installer = shell(
                "if command -v magisk >/dev/null 2>&1; then magisk --install-module $remoteZip; " +
                    "elif command -v ksud >/dev/null 2>&1; then ksud module install $remoteZip; " +
                    "elif command -v apd >/dev/null 2>&1; then apd module install $remoteZip; " +
                    "else echo '未找到 Magisk、KernelSU 或 APatch 模块安装器' >&2; exit 127; fi; " +
                    "rc=\$?; rm -f $remoteZip; exit \$rc",
                timeoutSeconds = 120,
            )
            installer.requireSuccess("安装 Root 模块")
            deployCore()
            return statusMap(RootState.REBOOT_REQUIRED, "模块安装成功，需要重启设备")
        } finally {
            installing = false
        }
    }

    fun switchToRoot(): Map<String, Any?> {
        check(hasPermission()) { "未获得 Root 权限；请在 Root 管理器中授权 Mclash" }
        val state = status()["state"] as String
        check(state == RootState.READY.name) {
            if (state == RootState.REBOOT_REQUIRED.name) "Root 模块需要重启后才能使用" else
                "Root 模块未就绪：$state"
        }
        return status()
    }

    fun settings(): Map<String, Any> = mapOf(
        "autoStart" to preferences.rootAutoStart,
        "loggingEnabled" to preferences.rootLoggingEnabled,
        "ipv6Enabled" to preferences.rootIpv6Enabled,
        "bypassLan" to preferences.rootBypassLan,
        "bypassCidrs" to preferences.rootBypassCidrs,
        "proxyMode" to preferences.rootProxyMode,
        "ipv6TproxySupported" to false,
    )

    fun saveSettings(arguments: Map<String, Any?>): Map<String, Any> {
        val cidrs = (arguments["bypassCidrs"] as? String).orEmpty()
            .lineSequence().map(String::trim).filter(String::isNotEmpty).distinct().toList()
        require(cidrs.isNotEmpty()) { "绕过网段不能为空" }
        cidrs.forEach(::validateCidr)
        val proxyMode = arguments["proxyMode"] as? String ?: error("缺少透明代理模式")
        require(proxyMode == "tun" || proxyMode == "tproxy") { "未知透明代理模式：$proxyMode" }
        val ipv6 = arguments["ipv6Enabled"] as? Boolean ?: false
        require(!(proxyMode == "tproxy" && ipv6)) { "IPv6 TProxy 暂不支持，请关闭 IPv6 或使用 TUN" }
        preferences.rootAutoStart = arguments["autoStart"] as? Boolean ?: false
        preferences.rootLoggingEnabled = arguments["loggingEnabled"] as? Boolean ?: false
        preferences.rootIpv6Enabled = ipv6
        preferences.rootBypassLan = arguments["bypassLan"] as? Boolean ?: true
        preferences.rootBypassCidrs = cidrs.joinToString("\n")
        preferences.rootProxyMode = proxyMode
        if (hasPermission() && status()["state"] == RootState.READY.name) syncRuntime()
        return settings()
    }

    fun syncRuntime() {
        check(hasPermission()) { "Root 权限已被撤销" }
        check(status()["state"] == RootState.READY.name) { "Root 模块未就绪" }
        val source = configStore.configFile
        require(source.isFile && source.length() > 0) { "请先选择有效的配置文件" }
        val staging = File(context.cacheDir, "root-sync").apply { mkdirs() }
        val sourceCopy = File(staging, "source.yaml").also { source.copyTo(it, overwrite = true) }
        val runtime = File(staging, "runtime.yaml").also { it.writeText(buildRuntime(source.readText())) }
        val env = File(staging, "root.env").also {
            it.writeText(
                "AUTO_START=${bool01(preferences.rootAutoStart)}\n" +
                    "PROXY_MODE=${preferences.rootProxyMode}\n" +
                    "IPV6=${bool01(preferences.rootIpv6Enabled)}\n" +
                    "APP_UID=${context.applicationInfo.uid}\n" +
                    "APP_FILTER_MODE=${preferences.appProxyMode}\n",
            )
        }
        val uids = File(staging, "app-uids.txt").also { it.writeText(resolveSelectedUids()) }
        val cidrs = File(staging, "bypass-cidrs.txt").also {
            val values = preferences.rootBypassCidrs.lineSequence().map(String::trim)
                .filter(String::isNotEmpty)
                .filter { preferences.rootIpv6Enabled || ':' !in it }
                .filter { preferences.rootBypassLan || it !in LAN_CIDRS }
                .distinct().toList()
            it.writeText(values.joinToString("\n", postfix = if (values.isEmpty()) "" else "\n"))
        }
        shell("mkdir -p $CONFIG_DIR $LOG_DIR $RUN_DIR && chmod 0700 $DATA_DIR $CONFIG_DIR $RUN_DIR")
            .requireSuccess("创建 Root 数据目录")
        listOf(sourceCopy, runtime, env, uids, cidrs).forEach { file ->
            shell("cp ${quote(file.absolutePath)} $CONFIG_DIR/${file.name}.tmp && " +
                "chmod 0600 $CONFIG_DIR/${file.name}.tmp && mv -f $CONFIG_DIR/${file.name}.tmp $CONFIG_DIR/${file.name}")
                .requireSuccess("同步 ${file.name}")
        }
    }

    fun start() {
        check(hasPermission()) { "Root 权限已被撤销" }
        check(status()["state"] == RootState.READY.name) { "Root 模块未就绪" }
        syncRuntime()
        shell("$CTL start", timeoutSeconds = 100).requireSuccess("启动 Root 代理")
        check(isRunning()) { "mihomo 启动后未持续运行，请查看 Root 日志" }
    }

    fun stop() {
        check(hasPermission()) { "Root 权限已被撤销，无法清理 Root 路由" }
        shell("$CTL stop", timeoutSeconds = 30).requireSuccess("停止 Root 代理")
        check(!isRunning()) { "mihomo 进程仍在运行" }
    }

    fun isRunning(): Boolean {
        if (!hasPermission()) return false
        val result = shell("$CTL status", timeoutSeconds = 8)
        return result.code == 0 && result.output.lineSequence().any { it.trim() == "RUNNING" }
    }

    fun readLog(name: String): String {
        require(name in LOG_NAMES) { "未知 Root 日志：$name" }
        check(hasPermission()) { "Root 权限已被撤销，无法读取日志" }
        val result = shell("test -f $LOG_DIR/$name && tail -n 1000 $LOG_DIR/$name || echo '${name} 尚未生成'")
        result.requireSuccess("读取 $name")
        return result.output.ifBlank { "$name 为空" }
    }

    fun clearLog(name: String) {
        require(name in LOG_NAMES) { "未知 Root 日志：$name" }
        check(hasPermission()) { "Root 权限已被撤销，无法清空日志" }
        shell(": > $LOG_DIR/$name").requireSuccess("清空 $name")
    }

    fun moduleVersion(): String {
        check(hasPermission()) { "Root 权限已被撤销" }
        val result = shell("sed -n 's/^version=//p' $MODULE_DIR/module.prop | head -n 1")
        result.requireSuccess("读取模块版本")
        return result.output.trim().ifBlank { "未知" }
    }

    fun checkCoreVersion(manifestUrl: String): Map<String, Any?> {
        check(hasPermission()) { "Root 权限已被撤销" }
        val rootStatus = status()
        check(rootStatus["state"] == RootState.READY.name) { "Root 模块或内核未就绪" }
        val currentOutput = rootStatus["coreVersion"]?.toString().orEmpty()
        val connection = openUpdateConnection(manifestUrl)
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("User-Agent", "Mclash/${context.packageManager.getPackageInfo(context.packageName, 0).versionName}")
        val body = try {
            val code = connection.responseCode
            check(code in 200..299) { "manifest 请求失败：HTTP $code" }
            connection.inputStream.bufferedReader().use { it.readText() }
        } finally {
            connection.disconnect()
        }
        val json = runCatching { JSONObject(body) }
            .getOrElse { throw IllegalArgumentException("更新 manifest 不是有效 JSON：${it.message}") }
        val releaseAsset = if (json.has("assets")) {
            val assets = json.getJSONArray("assets")
            (0 until assets.length())
                .map(assets::getJSONObject)
                .firstOrNull { asset ->
                    asset.optString("name").matches(
                        Regex("mihomo-android-arm64-v8-v[^/]+\\.gz"),
                    )
                } ?: error("官方发布中没有 arm64-v8 Android 内核")
        } else {
            null
        }
        val abi = releaseAsset?.let { "arm64-v8a" } ?: json.getString("abi")
        require(abi in Build.SUPPORTED_ABIS) { "更新内核 ABI $abi 与设备 ${Build.SUPPORTED_ABIS.joinToString()} 不匹配" }
        val latest = (releaseAsset?.let { json.getString("tag_name") } ?: json.getString("version"))
            .trim().removePrefix("v")
        require(latest.isNotEmpty()) { "manifest 版本号为空" }
        val downloadUrl = (releaseAsset?.getString("browser_download_url") ?: json.getString("url")).trim()
        require(URL(downloadUrl).protocol in setOf("http", "https")) { "内核下载地址无效" }
        val expectedHash = (
            releaseAsset?.optString("digest")?.removePrefix("sha256:")
                ?: json.getString("sha256")
            ).trim().lowercase()
        require(expectedHash.matches(Regex("[0-9a-f]{64}"))) { "manifest SHA-256 格式错误" }
        val current = Regex("v?(\\d+\\.\\d+\\.\\d+(?:[-+][0-9A-Za-z.-]+)?)")
            .find(currentOutput)?.groupValues?.get(1).orEmpty()
        return mapOf(
            "currentVersion" to current.ifBlank { currentOutput },
            "latestVersion" to latest,
            "hasUpdate" to (current != latest),
            "abi" to abi,
            "url" to downloadUrl,
            "sha256" to expectedHash,
            "size" to (releaseAsset?.optLong("size", -1L) ?: json.optLong("size", -1L)),
            "publishedAt" to (
                releaseAsset?.optString("updated_at", json.optString("published_at", ""))
                    ?: json.optString("publishedAt", "")
                ),
        )
    }

    @Synchronized
    fun updateCore(info: Map<String, Any?>): Map<String, Any?> {
        check(hasPermission()) { "Root 权限已被撤销" }
        check(!updateInProgress) { "已有内核更新正在进行" }
        val url = info["url"] as? String ?: error("更新地址缺失")
        val expected = (info["sha256"] as? String)?.lowercase() ?: error("SHA-256 缺失")
        require(expected.matches(Regex("[0-9a-f]{64}"))) { "SHA-256 格式错误" }
        updateInProgress = true
        updateCancelled = false
        updateStage = "downloading"
        updateProgress = 0.0
        val work = File(context.cacheDir, "root-core-update").apply { mkdirs() }
        val download = File(work, "core.download")
        val candidate = File(work, "mihomo.new")
        val wasRunning = isRunning()
        var oldCoreBackedUp = false
        try {
            appendUpdateLog("开始下载 $url")
            val connection = openUpdateConnection(url)
            activeUpdateConnection = connection
            connection.instanceFollowRedirects = true
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.setRequestProperty("User-Agent", "Mclash Root Core Updater")
            val responseCode = connection.responseCode
            check(responseCode in 200..299) { "内核下载失败：HTTP $responseCode" }
            val totalBytes = connection.contentLengthLong
            var downloadedBytes = 0L
            try {
                connection.inputStream.use { input ->
                    download.outputStream().use { output ->
                        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                        while (true) {
                            check(!updateCancelled) { "用户取消了内核更新" }
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                            downloadedBytes += count
                            if (totalBytes > 0) {
                                updateProgress = (downloadedBytes.toDouble() / totalBytes)
                                    .coerceIn(0.0, 1.0)
                            }
                        }
                    }
                }
            } finally {
                activeUpdateConnection = null
                connection.disconnect()
            }
            check(download.length() > 0) { "下载的内核文件为空" }
            updateStage = "verifying"
            updateProgress = 1.0
            check(sha256(download) == expected) { "下载文件 SHA-256 校验失败" }
            val gzip = download.inputStream().use { input ->
                input.read() == 0x1f && input.read() == 0x8b
            }
            if (gzip) {
                GZIPInputStream(download.inputStream()).use { input ->
                    candidate.outputStream().use(input::copyTo)
                }
            } else download.copyTo(candidate, overwrite = true)
            check(candidate.length() > 0) { "解压后的内核为空" }
            shell(
                "mkdir -p $DATA_DIR/update && cp ${quote(candidate.absolutePath)} $DATA_DIR/update/mihomo.new && " +
                    "chmod 0755 $DATA_DIR/update/mihomo.new && $DATA_DIR/update/mihomo.new -v",
                timeoutSeconds = 20,
            ).requireSuccess("验证新内核（可能 ABI 不匹配）")
            updateStage = "replacing"
            if (wasRunning) stop()
            shell("test -x $CORE && cp -p $CORE $DATA_DIR/update/mihomo.bak")
                .requireSuccess("备份旧内核")
            oldCoreBackedUp = true
            shell(
                "mv -f $DATA_DIR/update/mihomo.new $CORE && chmod 0755 $CORE",
            ).requireSuccess("原子替换内核")
            try {
                shell("$CORE -v", timeoutSeconds = 15).requireSuccess("验证新内核")
                updateStage = "restarting"
                if (wasRunning) start()
                shell("rm -f $DATA_DIR/update/mihomo.bak")
                oldCoreBackedUp = false
                appendUpdateLog("内核更新成功")
                updateStage = "success"
                return mapOf("success" to true, "rolledBack" to false, "message" to "内核更新成功")
            } catch (error: Throwable) {
                shell("test -f $DATA_DIR/update/mihomo.bak && " +
                    "mv -f $DATA_DIR/update/mihomo.bak $CORE && chmod 0755 $CORE")
                    .requireSuccess("恢复旧内核")
                oldCoreBackedUp = false
                val restartError = if (wasRunning) runCatching { start() }.exceptionOrNull() else null
                val recovery = if (restartError == null) {
                    "更新失败，已恢复旧内核${if (wasRunning) "并重启代理" else ""}"
                } else {
                    "更新失败，已恢复旧内核，但旧代理重启失败：${restartError.message}"
                }
                appendUpdateLog("$recovery；新内核错误：${error.message}")
                updateStage = "rolledBack"
                return mapOf("success" to false, "rolledBack" to true, "message" to recovery)
            }
        } catch (error: Throwable) {
            if (oldCoreBackedUp) {
                runCatching {
                    shell(
                        "test -f $DATA_DIR/update/mihomo.bak && " +
                            "mv -f $DATA_DIR/update/mihomo.bak $CORE && chmod 0755 $CORE",
                    ).requireSuccess("恢复旧内核")
                    if (wasRunning && !isRunning()) start()
                    updateStage = "rolledBack"
                }
            }
            if (updateStage != "rolledBack") updateStage = if (updateCancelled) "cancelled" else "failed"
            appendUpdateLog("内核更新失败：${error.message}")
            if (updateCancelled) throw IllegalStateException("用户取消了内核更新")
            throw error
        } finally {
            activeUpdateConnection = null
            updateInProgress = false
            if (hasPermission()) shell("rm -f $DATA_DIR/update/mihomo.new")
            download.delete()
            candidate.delete()
        }
    }

    fun cancelUpdate() {
        if (updateStage != "downloading") return
        updateCancelled = true
        activeUpdateConnection?.disconnect()
    }

    fun updateStatus(): Map<String, Any> = mapOf(
        "stage" to updateStage,
        "progress" to updateProgress,
    )

    private fun deployCore() {
        val binary = File(context.applicationInfo.nativeLibraryDir, "libmihomo.so")
        require(binary.isFile && binary.length() > 0) { "APK 中没有当前 ABI 的 mihomo 内核" }
        shell("mkdir -p $BIN_DIR $CONFIG_DIR $LOG_DIR $RUN_DIR && " +
            "cp ${quote(binary.absolutePath)} $CORE.tmp && chmod 0755 $CORE.tmp && mv -f $CORE.tmp $CORE && " +
            "$CORE -v", timeoutSeconds = 30).requireSuccess("部署 mihomo 内核")
    }

    private fun resolveSelectedUids(): String {
        val packageManager = context.packageManager
        val entries = mutableSetOf<Int>()
        preferences.selectedPackages.sorted().forEach { packageName ->
            val uid = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    packageManager.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0)).uid
                } else {
                    @Suppress("DEPRECATION") packageManager.getApplicationInfo(packageName, 0).uid
                }
            } catch (_: PackageManager.NameNotFoundException) {
                appendModuleLog("忽略不存在的包名：$packageName")
                null
            }
            if (uid != null && uid != context.applicationInfo.uid) entries += uid
        }
        return entries.sorted().joinToString("\n", postfix = if (entries.isEmpty()) "" else "\n")
    }

    private fun buildRuntime(source: String): String {
        val controlled = setOf(
            "tun",
            "tproxy-port",
            "redir-port",
            "mixed-port",
            "port",
            "socks-port",
            "allow-lan",
            "bind-address",
            "external-controller",
            "secret",
            "ipv6",
            "log-level",
            "routing-mark",
        )
        val lines = source.removePrefix("\uFEFF").lines()
        val kept = mutableListOf<String>()
        var skip = false
        lines.forEach { line ->
            val topLevel = line.isNotBlank() && !line.first().isWhitespace() && !line.trimStart().startsWith("#")
            if (topLevel) {
                skip = line.substringBefore(':').trim() in controlled
                if (skip) return@forEach
            }
            if (!skip) kept += line
        }
        return buildString {
            append(kept.joinToString("\n").trimEnd()).append('\n')
            append("# Injected by Mclash Root mode.\n")
            append("mixed-port: $LOCAL_UPDATE_PROXY_PORT\n")
            append("allow-lan: false\n")
            append("bind-address: 127.0.0.1\n")
            append("ipv6: ${preferences.rootIpv6Enabled}\n")
            append("external-controller: 127.0.0.1:9090\n")
            append("secret: \"\"\n")
            append("log-level: ${if (preferences.rootLoggingEnabled) "debug" else "error"}\n")
            // Mark only mihomo's outbound sockets. Root routing scripts use
            // this mark to bypass recapture without exempting UID 0 traffic.
            append("routing-mark: 9012\n")
            if (preferences.rootProxyMode == "tun") {
                append("tun:\n  enable: true\n  device: mclash0\n  stack: mixed\n")
                append("  auto-route: true\n  auto-detect-interface: true\n")
                // Reserve a private table/rule range for Mclash instead of the
                // mihomo defaults, which are commonly shared by other TUN apps.
                append("  iproute2-table-index: 2233\n  iproute2-rule-index: 23000\n")
                val bypassCidrs = preferences.rootBypassCidrs.lineSequence()
                    .map(String::trim)
                    .filter(String::isNotEmpty)
                    .filter { preferences.rootIpv6Enabled || ':' !in it }
                    .filter { preferences.rootBypassLan || it !in LAN_CIDRS }
                    .distinct()
                    .toList()
                if (bypassCidrs.isNotEmpty()) {
                    append("  route-exclude-address:\n")
                    bypassCidrs.forEach { append("    - $it\n") }
                }
                val uids = resolveSelectedUids().lineSequence().filter(String::isNotBlank).toList()
                if (preferences.appProxyMode == AppPreferences.MODE_INCLUDE) {
                    if (uids.isNotEmpty()) {
                        append("  include-uid:\n")
                        uids.forEach { append("    - $it\n") }
                    }
                } else {
                    if (uids.isNotEmpty()) {
                        append("  exclude-uid:\n")
                        uids.forEach { append("    - $it\n") }
                    }
                }
            } else {
                append("tun:\n  enable: false\n")
                append("tproxy-port: 7894\n")
            }
        }
    }

    private fun validateCidr(value: String) {
        val parts = value.split('/')
        require(parts.size == 2) { "网段缺少掩码：$value" }
        require(
            parts[0].matches(Regex("[0-9.]+")) ||
                (':' in parts[0] && parts[0].matches(Regex("[0-9a-fA-F:.]+"))),
        ) { "无效 IP 地址：$value" }
        val address = runCatching { InetAddress.getByName(parts[0]) }.getOrNull()
            ?: throw IllegalArgumentException("无效 IP 地址：$value")
        val prefix = parts[1].toIntOrNull() ?: throw IllegalArgumentException("无效掩码：$value")
        when (address) {
            is Inet4Address -> require(prefix in 0..32) { "IPv4 掩码必须为 0–32：$value" }
            is Inet6Address -> require(prefix in 0..128) { "IPv6 掩码必须为 0–128：$value" }
            else -> error("不支持的网段：$value")
        }
    }

    private fun openUpdateConnection(url: String): HttpURLConnection {
        val proxyRunning = isRunning()
        val connection = if (proxyRunning) {
            URL(url).openConnection(
                Proxy(
                    Proxy.Type.HTTP,
                    InetSocketAddress("127.0.0.1", LOCAL_UPDATE_PROXY_PORT),
                ),
            )
        } else {
            URL(url).openConnection()
        }
        appendUpdateLog(
            if (proxyRunning) {
                "网络请求强制使用本地代理 127.0.0.1:$LOCAL_UPDATE_PROXY_PORT"
            } else {
                "Root 代理未运行，网络请求使用直连"
            },
        )
        return connection as HttpURLConnection
    }

    private fun shell(command: String, timeoutSeconds: Long = 20): ShellResult {
        val process = ProcessBuilder("su", "-c", command).redirectErrorStream(true).start()
        val output = StringBuilder()
        val reader = Thread { process.inputStream.bufferedReader().useLines { lines -> lines.forEach { output.appendLine(it) } } }
        reader.start()
        if (!process.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
            process.destroyForcibly()
            reader.join(1000)
            return ShellResult(124, "命令执行超时\n$output".trim())
        }
        reader.join(1000)
        return ShellResult(process.exitValue(), output.toString().trim())
    }

    private fun statusMap(
        state: RootState,
        message: String,
        core: String = "",
        module: String = "",
        running: Boolean = false,
        hasRoot: Boolean = true,
    ): Map<String, Any?> = mapOf(
        "state" to state.name,
        "message" to message,
        "hasRootPermission" to hasRoot,
        "moduleVersion" to module,
        "coreVersion" to core,
        "running" to running,
    )

    private fun appendModuleLog(message: String) {
        if (hasPermission()) shell("mkdir -p $LOG_DIR; echo ${quote("[app] $message")} >> $LOG_DIR/module.log")
    }

    private fun appendUpdateLog(message: String) {
        if (hasPermission()) shell("mkdir -p $LOG_DIR; echo ${quote("[app] $message")} >> $LOG_DIR/update.log")
    }

    private fun sha256(file: File): String = MessageDigest.getInstance("SHA-256")
        .digest(file.readBytes()).joinToString("") { "%02x".format(it) }

    private fun bool01(value: Boolean) = if (value) "1" else "0"
    private fun quote(value: String) = "'${value.replace("'", "'\\''")}'"

    companion object {
        private const val MODULE_DIR = "/data/adb/modules/mclash_root"
        private const val DATA_DIR = "/data/adb/mclash"
        private const val BIN_DIR = "$DATA_DIR/bin"
        private const val CONFIG_DIR = "$DATA_DIR/config"
        private const val LOG_DIR = "$DATA_DIR/logs"
        private const val RUN_DIR = "$DATA_DIR/run"
        private const val CORE = "$BIN_DIR/mihomo"
        private const val CTL = "$MODULE_DIR/bin/mclashctl"
        private const val LOCAL_UPDATE_PROXY_PORT = 7789
        private val LOG_NAMES = setOf("mihomo.log", "module.log", "update.log")
        private val LAN_CIDRS = setOf("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "fc00::/7", "fe80::/10")
    }
}
