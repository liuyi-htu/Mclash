package com.liuyihtu.mclash

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import hev.htproxy.TProxyService
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.ScheduledFuture

class ProxyVpnService : VpnService() {
    private val mainHandler = Handler(Looper.getMainLooper())

    private val logMaintenance = Executors.newSingleThreadScheduledExecutor()
    private var logMaintenanceTask: ScheduledFuture<*>? = null

    private var latestStartId = 0
    private var cleanupQueued = false
    private var cleanupComplete = false
    private var cleanupRequest: VpnLifecycle.StopRequest? = null
    private var destroyed = false
    private var session = 0
    private var activeConfigName = "未命名配置"

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        latestStartId = startId
        when (intent?.action) {
            ACTION_STOP -> {
                requestStop(startId)
            }
            else -> startProxy()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onDestroy() {
        destroyed = true
        logMaintenance.shutdownNow()
        if (cleanupComplete) {
            lifecycle.finishStop(success = true, request = cleanupRequest)
            QuickSettingsTileUpdater.request(this)
        } else {
            requestStop(null)
        }
        super.onDestroy()
    }

    override fun onRevoke() {
        lifecycle.requestStop()
        mainHandler.post { requestStop(latestStartId) }
    }

    private fun startProxy() {
        if (destroyed || running || starting || stopping) return
        lastError = null
        try {
            RuntimeEdits.start {
                check(lifecycle.beginStart()) { "代理启动已取消或正在停止" }
            }
        } catch (error: Throwable) {
            lifecycle.cancelStartRequest()
            lastError = error.message
            stopSelf()
            return
        }
        cleanupComplete = false
        val currentSession = ++session
        QuickSettingsTileUpdater.request(this)
        StartupLog.reset(this)
        StartupLog.append(this, "收到启动请求；ABI=${Build.SUPPORTED_ABIS.joinToString()}")
        try {
            startForeground(NOTIFICATION_ID, buildNotification("正在启动 mihomo"))
        } catch (error: Throwable) {
            lastError = "无法启动前台 VPN 服务：${error.message}"
            StartupLog.append(this, lastError.orEmpty())
            requestStop(latestStartId)
            return
        }

        worker.execute {
            try {
                val configStore = ConfigStore(this)
                activeConfigName = configStore.activeProfile()?.name ?: "未命名配置"
                StartupLog.append(
                    this,
                    "检查配置：path=${configStore.configFile.absolutePath}, " +
                        "exists=${configStore.exists()}, size=${configStore.configFile.length()}",
                )
                require(configStore.exists()) { "请先上传配置文件" }

                val preferences = AppPreferences(this)
                // No periodic disk checks when both native logs are disabled.
                if (preferences.debugLoggingEnabled) {
                    logMaintenanceTask = logMaintenance.scheduleWithFixedDelay({
                        for (path in listOf("mihomo/mihomo.log", "runtime/hev.log")) {
                            runCatching { DebugLogLimits.trim(File(filesDir, path)) }
                                .onFailure { StartupLog.append(this, "日志维护失败：${it.message}") }
                        }
                    }, 0, 2, TimeUnit.SECONDS)
                }
                val vpnMtu = preferences.vpnMtu
                val tcpBufferSize = preferences.tcpBufferSize
                val ipv4DnsServers = listOf(VpnDnsRuntime.VPN_DNS_ADDRESS)
                val ipv6Enabled = preferences.vpnIpv6Enabled
                val bypassLan = preferences.vpnBypassLan
                StartupLog.append(
                    this,
                    "分应用模式=${preferences.appProxyMode}, " +
                        "selected=${preferences.selectedPackages.size}",
                )
                if (
                    preferences.appProxyMode == AppPreferences.MODE_ONLY_SELECTED &&
                    preferences.selectedPackages.none { it != packageName }
                ) {
                    error("“仅代理选中的应用”模式下至少选择一个应用")
                }

                // Start official mihomo first, while the process still has an ordinary network route.
                StartupLog.append(this, "开始启动官方 mihomo")
                val socksPort = MihomoProcess.start(
                    this, configStore.configFile,
                    cancelled = { stopping },
                    onExit = { code -> componentExited(currentSession, "mihomo 已退出：code=$code") },
                )
                StartupLog.append(this, "mihomo 已监听 127.0.0.1:$socksPort")
                if (stopping) error("启动已取消")

                StartupLog.append(this, "开始配置 Android VpnService.Builder")
                val builder = Builder()
                    .setSession("Mclash")
                    .setMtu(vpnMtu)
                    .addAddress("198.18.0.1", 30)
                    .setBlocking(false)

                if (ipv6Enabled) {
                    builder.addAddress(IPV6_TUN_ADDRESS, 128)
                }
                addVpnRoutes(builder, ipv6Enabled, bypassLan)
                ipv4DnsServers.forEach(builder::addDnsServer)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    builder.setMetered(false)
                }

                applyPerAppFilter(builder, preferences)

                val tun = builder.establish() ?: error("无法创建 VPN 接口")
                tunDescriptor = tun
                StartupLog.append(
                    this,
                        "VPN TUN 创建成功：fd=${tun.fd}, mtu=$vpnMtu, " +
                        "dns4=${ipv4DnsServers.joinToString()}, " +
                        "ipv6=$ipv6Enabled (setting), bypassLan=$bypassLan",
                )

                val hevConfig = writeHevConfig(socksPort, vpnMtu, tcpBufferSize, ipv6Enabled)
                StartupLog.append(
                    this,
                    "启动 HevSocks5Tunnel：config=${hevConfig.absolutePath}, fd=${tun.fd}",
                )
                TProxyService.onExit = { code ->
                    componentExited(currentSession, "HevSocks5Tunnel 已退出：code=$code")
                }
                tunnelListenerInstalled = true
                check(TProxyService.TProxyStartService(hevConfig.absolutePath, tun.fd)) {
                    "HevSocks5Tunnel 启动失败"
                }
                tunnelStarted = true
                StartupLog.append(this, "HevSocks5Tunnel 启动调用完成")

                if (stopping) error("启动已取消")
                mainHandler.post {
                    if (destroyed || stopping || currentSession != session) return@post
                    if (!MihomoProcess.isRunning() || !TProxyService.TProxyIsRunning()) {
                        componentExited(currentSession, "原生组件在启动完成前退出")
                        return@post
                    }
                    if (!lifecycle.finishStart()) return@post
                    QuickSettingsTileUpdater.request(this)
                    StartupLog.append(this, "代理启动完成（Hev 初始化就绪）")
                    val manager = getSystemService(NotificationManager::class.java)
                    manager.notify(
                        NOTIFICATION_ID,
                        buildNotification("运行配置：$activeConfigName"),
                    )
                }
            } catch (error: Throwable) {
                lastError = error.message ?: error.javaClass.simpleName
                StartupLog.append(
                    this,
                    "启动失败：${error.javaClass.name}: ${error.message}\n" +
                        error.stackTraceToString(),
                )
                // Keep admission closed until queued cleanup has completed.
                lifecycle.requestStop()
                mainHandler.post { requestStop(latestStartId) }
            }
        }
    }

    private fun writeHevConfig(
        socksPort: Int,
        mtu: Int,
        tcpBufferSize: Int,
        ipv6Enabled: Boolean,
    ): File {
        val directory = File(filesDir, "runtime").apply { mkdirs() }
        val debugLoggingEnabled = AppPreferences(this).debugLoggingEnabled
        val hevLog = File(directory, "hev.log")
        if (debugLoggingEnabled) {
            hevLog.writeText("", Charsets.UTF_8)
        }
        val logTarget = if (debugLoggingEnabled) hevLog.absolutePath else "/dev/null"
        val logLevel = if (debugLoggingEnabled) "debug" else "error"
        val taskStackSize = tcpBufferSize + 20480

        return File(directory, "hev.yml").apply {
            writeText(
                buildString {
                    appendLine("tunnel:")
                    appendLine("  mtu: $mtu")
                    appendLine("  ipv4: 198.18.0.1")
                    if (ipv6Enabled) {
                        appendLine("  ipv6: '$IPV6_TUN_ADDRESS'")
                    }
                    appendLine("socks5:")
                    appendLine("  address: 127.0.0.1")
                    appendLine("  port: $socksPort")
                    appendLine("  dns-port: ${VpnDnsRuntime.SOCKS_PORT}")
                    appendLine("  udp: 'udp'")
                    appendLine("misc:")
                    appendLine("  log-file: '$logTarget'")
                    appendLine("  log-level: $logLevel")
                    appendLine("  task-stack-size: $taskStackSize")
                    appendLine("  tcp-buffer-size: $tcpBufferSize")
                },
                Charsets.UTF_8,
            )
        }
    }

    private fun addVpnRoutes(builder: Builder, ipv6Enabled: Boolean, bypassLan: Boolean) {
        val ipv4Routes = if (bypassLan) {
            resources.getStringArray(R.array.bypass_lan_ipv4_routes).asList()
        } else {
            listOf("0.0.0.0/0")
        }
        ipv4Routes.forEach { route -> addRoute(builder, route) }

        if (ipv6Enabled) {
            val ipv6Routes = if (bypassLan) {
                resources.getStringArray(R.array.bypass_lan_ipv6_routes).asList()
            } else {
                listOf("::/0")
            }
            ipv6Routes.forEach { route -> addRoute(builder, route) }
        }
    }

    private fun addRoute(builder: Builder, cidr: String) {
        val (address, prefixLength) = cidr.split('/', limit = 2)
        builder.addRoute(address, prefixLength.toInt())
    }

    private fun applyPerAppFilter(builder: Builder, preferences: AppPreferences) {
        PerAppFilter.apply(
            onlySelected = preferences.appProxyMode != AppPreferences.MODE_EXCLUDE_SELECTED,
            selected = preferences.selectedPackages,
            ownPackage = packageName,
            // Some Android/OEM Builders accept stale names without throwing.
            // Check installation explicitly; successful Builder calls alone are insufficient.
            isInstalled = { name ->
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        packageManager.getApplicationInfo(name, PackageManager.ApplicationInfoFlags.of(0))
                    } else {
                        @Suppress("DEPRECATION")
                        packageManager.getApplicationInfo(name, 0)
                    }
                    true
                } catch (_: PackageManager.NameNotFoundException) { false }
            },
            allow = { name ->
                try { builder.addAllowedApplication(name); true }
                catch (_: PackageManager.NameNotFoundException) { false }
            },
            disallow = { name ->
                try { builder.addDisallowedApplication(name); true }
                catch (_: PackageManager.NameNotFoundException) { false }
            },
        )
    }

    private fun componentExited(currentSession: Int, message: String) {
        mainHandler.post {
            if (destroyed || stopping || currentSession != session || (!starting && !running)) return@post
            lastError = message
            StartupLog.append(this, message)
            requestStop(latestStartId)
        }
    }

    private fun requestStop(startId: Int?) {
        cleanupRequest = lifecycle.requestStop()
        QuickSettingsTileUpdater.request(this)
        if (cleanupQueued || worker.isShutdown) return
        cleanupQueued = true
        worker.execute {
            StartupLog.append(this, "收到停止请求：startId=$startId")
            val failure = runCatching { stopNativeComponents() }.exceptionOrNull()
            mainHandler.post {
                cleanupQueued = false
                if (failure != null) {
                    lastError = "代理清理失败：${failure.message}"
                    StartupLog.append(this, "$lastError\n${failure.stackTraceToString()}")
                    // Preserve stopping and resource handles for an explicit retry.
                } else {
                    cleanupComplete = true
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    // A successful stopSelfResult schedules onDestroy. Keep admission closed
                    // until that old Service instance can no longer cancel a new start.
                    if (destroyed || !stopSelfResult(latestStartId)) {
                        lifecycle.finishStop(success = true, request = cleanupRequest)
                    }
                }
                QuickSettingsTileUpdater.request(this)
            }
        }
    }

    private fun stopNativeComponents() {
        val failures = mutableListOf<Throwable>()
        // Do not initialize a failed/missing JNI library during rollback.
        if (tunnelListenerInstalled) {
            runCatching { TProxyService.onExit = null; tunnelListenerInstalled = false }
                .onFailure { failures += it }
        }
        if (tunnelStarted) {
            logTunnelStats()
            runCatching {
                check(TProxyService.TProxyStopService()) { "Hev 原生线程停止失败" }
                tunnelStarted = false
            }.onFailure { failures += it }
        }
        // Closing TUN also removes the VPN route when another component fails.
        runCatching { tunDescriptor?.close(); tunDescriptor = null }.onFailure { failures += it }
        runCatching { MihomoProcess.stop() }.onFailure { failures += it }
        logMaintenanceTask?.cancel(false)
        logMaintenanceTask = null
        if (failures.isNotEmpty()) {
            val error = IllegalStateException(failures.joinToString("；") { it.message ?: it.javaClass.simpleName })
            failures.forEach(error::addSuppressed)
            throw error
        }
    }

    private fun logTunnelStats() {
        runCatching { TProxyService.TProxyGetStats() }
            .onSuccess { stats ->
                if (stats.size >= 4) {
                    StartupLog.append(
                        this,
                        "HEV 统计：txPackets=${stats[0]}, txBytes=${stats[1]}, " +
                            "rxPackets=${stats[2]}, rxBytes=${stats[3]}",
                    )
                } else {
                    StartupLog.append(this, "HEV 统计返回长度异常：${stats.size}")
                }
            }
            .onFailure { error ->
                StartupLog.append(
                    this,
                    "读取 HEV 统计失败：${error.javaClass.simpleName}: ${error.message}",
                )
            }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "代理服务",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    private fun buildNotification(text: String) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(android.R.drawable.ic_lock_lock)
        .setContentTitle("Mclash")
        .setContentText(text)
        .setOngoing(true)
        .setContentIntent(
            PendingIntent.getActivity(
                this,
                0,
                packageManager.getLaunchIntentForPackage(packageName),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            ),
        )
        .build()

    companion object {
        const val ACTION_START = "com.liuyihtu.mclash.START"
        const val ACTION_STOP = "com.liuyihtu.mclash.STOP"

        private val lifecycle = VpnLifecycle()
        // JNI and Mihomo are process-wide singletons. Keep their handles and serial
        // worker across Service destruction so a later explicit stop can retry cleanup.
        private val worker = Executors.newSingleThreadExecutor { task ->
            Thread(task, "mclash-vpn-worker").apply { isDaemon = true }
        }
        private var tunDescriptor: ParcelFileDescriptor? = null
        private var tunnelStarted = false
        private var tunnelListenerInstalled = false

        val running: Boolean get() = lifecycle.phase == VpnLifecycle.Phase.RUNNING
        val starting: Boolean get() = lifecycle.phase == VpnLifecycle.Phase.STARTING
        val stopping: Boolean get() = lifecycle.phase == VpnLifecycle.Phase.STOPPING

        @Volatile
        var lastError: String? = null
            private set

        private const val CHANNEL_ID = "proxy"
        private const val NOTIFICATION_ID = 1001
        private const val IPV6_TUN_ADDRESS = "fc00::1"

        val startRequested: Boolean get() = lifecycle.phase == VpnLifecycle.Phase.REQUESTED

        fun start(context: android.content.Context) {
            RuntimeEdits.start {
                if (!lifecycle.requestStart()) return@start
                lastError = null
                try {
                    val intent = Intent(context, ProxyVpnService::class.java).setAction(ACTION_START)
                    ContextCompat.startForegroundService(context, intent)
                } catch (error: Throwable) {
                    lifecycle.cancelStartRequest()
                    throw error
                }
            }
        }

        fun stop(context: android.content.Context) {
            val previous = lifecycle.requestStop()
            try {
                context.startService(Intent(context, ProxyVpnService::class.java).setAction(ACTION_STOP))
            } catch (error: Throwable) {
                lifecycle.restoreFailedStopDelivery(previous)
                lastError = "无法发送停止请求：${error.message}"
                throw error
            }
        }

        fun clearLastError() {
            lastError = null
        }
    }
}
