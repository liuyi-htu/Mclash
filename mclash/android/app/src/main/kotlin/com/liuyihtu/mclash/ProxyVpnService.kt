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

class ProxyVpnService : VpnService() {
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var stopping = false

    private var tunDescriptor: ParcelFileDescriptor? = null
    private var tunnelStarted = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopProxy()
                stopSelf()
            }
            else -> startProxy()
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onDestroy() {
        stopProxy()
        super.onDestroy()
    }

    private fun startProxy() {
        if (running || starting) return
        lastError = null
        stopping = false
        starting = true
        QuickSettingsTileUpdater.request(this)
        StartupLog.reset(this)
        StartupLog.append(this, "收到启动请求；ABI=${Build.SUPPORTED_ABIS.joinToString()}")
        startForeground(NOTIFICATION_ID, buildNotification("正在启动 mihomo"))

        Thread({
            try {
                val configStore = ConfigStore(this)
                StartupLog.append(
                    this,
                    "检查配置：path=${configStore.configFile.absolutePath}, " +
                        "exists=${configStore.exists()}, size=${configStore.configFile.length()}",
                )
                require(configStore.exists()) { "请先上传配置文件" }

                val preferences = AppPreferences(this)
                val vpnMtu = preferences.vpnMtu
                val tcpBufferSize = preferences.tcpBufferSize
                val ipv4DnsServers = preferences.vpnIpv4DnsServers
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
                val socksPort = MihomoProcess.start(this, configStore.configFile)
                StartupLog.append(this, "mihomo 已监听 127.0.0.1:$socksPort")
                if (stopping) error("启动已取消")

                StartupLog.append(this, "开始配置 Android VpnService.Builder")
                val builder = Builder()
                    .setSession("Mclash")
                    .setMtu(vpnMtu)
                    .addAddress("198.18.0.1", 30)
                    .setBlocking(false)

                if (ipv6Enabled) {
                    builder.addAddress("fc00::1", 126)
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
                        "ipv6=$ipv6Enabled, bypassLan=$bypassLan",
                )

                val hevConfig = writeHevConfig(socksPort, vpnMtu, tcpBufferSize, ipv6Enabled)
                StartupLog.append(
                    this,
                    "启动 HevSocks5Tunnel：config=${hevConfig.absolutePath}, fd=${tun.fd}",
                )
                TProxyService.TProxyStartService(hevConfig.absolutePath, tun.fd)
                tunnelStarted = true
                StartupLog.append(this, "HevSocks5Tunnel 启动调用完成")

                if (stopping) error("启动已取消")
                running = true
                starting = false
                QuickSettingsTileUpdater.request(this)
                StartupLog.append(this, "代理启动完成")
                mainHandler.post {
                    val manager = getSystemService(NotificationManager::class.java)
                    manager.notify(NOTIFICATION_ID, buildNotification("mihomo 正在代理"))
                }
            } catch (error: Throwable) {
                lastError = error.message ?: error.javaClass.simpleName
                StartupLog.append(
                    this,
                    "启动失败：${error.javaClass.name}: ${error.message}\n" +
                        error.stackTraceToString(),
                )
                running = false
                starting = false
                QuickSettingsTileUpdater.request(this)
                stopNativeComponents()
                mainHandler.post {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }, "mclash-proxy-start").start()
    }

    private fun writeHevConfig(
        socksPort: Int,
        mtu: Int,
        tcpBufferSize: Int,
        ipv6Enabled: Boolean,
    ): File {
        val directory = File(filesDir, "runtime").apply { mkdirs() }
        val debugLoggingEnabled = AppPreferences(this).debugLoggingEnabled
        val logTarget = if (debugLoggingEnabled) "stderr" else "/dev/null"
        val logLevel = if (debugLoggingEnabled) "warn" else "error"
        val taskStackSize = tcpBufferSize + 20480

        val ipv6Line = if (ipv6Enabled) "\n  ipv6: 'fc00::1'" else ""
        return File(directory, "hev.yml").apply {
            writeText(
                """
                tunnel:
                  mtu: $mtu
                  ipv4: 198.18.0.1$ipv6Line
                socks5:
                  address: 127.0.0.1
                  port: $socksPort
                  udp: 'udp'
                misc:
                  log-file: $logTarget
                  log-level: $logLevel
                  task-stack-size: $taskStackSize
                  tcp-buffer-size: $tcpBufferSize
                """.trimIndent() + "\n",
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
        val selected = preferences.selectedPackages
            .filterNot { it == packageName }
            .sorted()

        when (preferences.appProxyMode) {
            AppPreferences.MODE_EXCLUDE_SELECTED -> {
                // The mihomo child process shares this app UID. Excluding this package prevents a VPN loop.
                addDisallowedSafely(builder, packageName)
                selected.forEach { addDisallowedSafely(builder, it) }
            }
            else -> {
                // The app itself is absent from the allow list, so mihomo's outbound sockets bypass the VPN.
                selected.forEach { addAllowedSafely(builder, it) }
            }
        }
    }

    private fun addAllowedSafely(builder: Builder, packageName: String) {
        try {
            builder.addAllowedApplication(packageName)
        } catch (_: PackageManager.NameNotFoundException) {
            // Ignore stale package names.
        }
    }

    private fun addDisallowedSafely(builder: Builder, packageName: String) {
        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: PackageManager.NameNotFoundException) {
            // Ignore stale package names.
        }
    }

    private fun stopProxy() {
        StartupLog.append(this, "收到停止请求")
        stopping = true
        stopNativeComponents()
        running = false
        starting = false
        QuickSettingsTileUpdater.request(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    @Synchronized
    private fun stopNativeComponents() {
        if (tunnelStarted) {
            runCatching { TProxyService.TProxyStopService() }
            tunnelStarted = false
        }
        runCatching { tunDescriptor?.close() }
        tunDescriptor = null
        runCatching { MihomoProcess.stop() }
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

        @Volatile
        var running: Boolean = false
            private set

        @Volatile
        var starting: Boolean = false
            private set

        @Volatile
        var lastError: String? = null
            private set

        private const val CHANNEL_ID = "proxy"
        private const val NOTIFICATION_ID = 1001

        fun start(context: android.content.Context) {
            lastError = null
            val intent = Intent(context, ProxyVpnService::class.java).setAction(ACTION_START)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: android.content.Context) {
            context.startService(Intent(context, ProxyVpnService::class.java).setAction(ACTION_STOP))
        }

        fun clearLastError() {
            lastError = null
        }
    }
}
