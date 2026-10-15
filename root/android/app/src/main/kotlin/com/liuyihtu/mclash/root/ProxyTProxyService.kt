package com.liuyihtu.mclash.root

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.Executors

class ProxyTProxyService : Service() {
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var stopping = false

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("root-proxy", "Root 代理服务", NotificationManager.IMPORTANCE_LOW),
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val stopRequested = intent?.action == ACTION_STOP ||
            (intent?.action == ACTION_TOGGLE && (running || starting))
        if (stopRequested) {
            stopping = true
            tileStopPending = true
            QuickSettingsTileUpdater.request(this)
            worker.execute { stopProxy() }
        } else if (!running && !starting) {
            try {
                RuntimeEdits.start {
                    stopping = false
                    starting = true
                    lastError = null
                }
            } catch (error: Throwable) {
                restoring = false
                tileStopPending = false
                QuickSettingsTileUpdater.request(this)
                lastError = error.message
                stopSelf()
                return START_NOT_STICKY
            }
            startForeground(2, notification("正在启动 Root 代理"))
            QuickSettingsTileUpdater.request(this)
            worker.execute {
                // A surviving Root daemon may outlive the application's process.
                if (intent?.action == ACTION_TOGGLE) {
                    try {
                        if (MihomoProcess.attach(this)) {
                            stopProxy()
                            return@execute
                        }
                    } catch (error: Throwable) {
                        lastError = error.message ?: error.javaClass.simpleName
                        StartupLog.append(this, "快捷开关状态检查失败：$lastError")
                        stopProxy()
                        return@execute
                    }
                }
                tileStopPending = false
                QuickSettingsTileUpdater.request(this)
                startProxy()
            }
        }
        restoring = false
        return if (stopRequested) START_NOT_STICKY else START_STICKY
    }

    private fun startProxy() {
        try {
            StartupLog.reset(this)
            StartupLog.append(this, "Root 代理启动；ABI=${Build.SUPPORTED_ABIS.joinToString()}")
            StartupLog.append(this, RootShell.requireRoot())
            val preferences = AppPreferences(this)
            val store = ConfigStore(this)
            if (!MihomoProcess.attach(this)) {
                require(Settings.Global.getString(contentResolver, "private_dns_mode") != "hostname") {
                    "请先在 Android 网络设置中关闭严格私人 DNS，再启动代理"
                }
                RootRuntimeMode.capture(this)
                MihomoProcess.recover(this)
                require(store.exists()) { "请先选择有效配置" }
                val onlySelected = preferences.appProxyMode == AppPreferences.MODE_ONLY_SELECTED
                val uids = preferences.selectedPackages.mapNotNull { name ->
                    runCatching { packageManager.getApplicationInfo(name, 0).uid }.getOrNull()
                }.filter { it != android.os.Process.myUid() && it > 0 }.toSet()
                val rules = TProxyRules.install(android.os.Process.myUid(), onlySelected, uids, preferences.rootBypassLan, preferences.rootIpv6, preferences.rootProxyMode == "tun")
                check(!stopping) { "启动已取消" }
                MihomoProcess.start(this, store.configFile, rules) { stopping }
            }
            running = true
            starting = false
            StartupLog.append(this, "${preferences.rootProxyMode.uppercase()} 接管完成；网络共享${if (preferences.networkSharingEnabled) "开启" else "关闭"}，仅接管手动选择的接口；IPv6 ${if (preferences.rootIpv6) "TCP/UDP 接管" else "按应用及热点阻断"}")
            getSystemService(NotificationManager::class.java).notify(2,
                notification("${preferences.rootProxyMode.uppercase()} · ${store.activeProfile()?.name ?: "当前配置"}"))
            QuickSettingsTileUpdater.request(this)
            Thread({
                while (running && !stopping && MihomoProcess.isRunning()) {
                    Thread.sleep(2000)
                    if (!running || stopping || !MihomoProcess.isRunning()) break
                    RootRuntimeMode.capture(this)

                }
                if (running && !stopping) {
                    lastError = "Root 内核或守护进程已退出，请查看启动日志"
                    worker.execute { stopProxy() }
                }
            }, "root-proxy-monitor").apply { isDaemon = true; start() }
        } catch (error: Throwable) {
            lastError = error.message ?: error.javaClass.simpleName
            StartupLog.append(this, "启动失败：$lastError")
            stopProxy()
        }
    }

    private fun stopProxy() {
        stopping = true
        tileStopPending = true
        QuickSettingsTileUpdater.request(this)
        try {
            RootRuntimeMode.capture(this)
            if (!MihomoProcess.stop()) MihomoProcess.recover(this)
            running = false
            starting = false
            tileStopPending = false
            if (lastError?.startsWith("停止清理失败：") == true) lastError = null
            StartupLog.append(this, "Root 服务已停止，接管规则已清理")
            QuickSettingsTileUpdater.request(this)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        } catch (error: Throwable) {
            lastError = "停止清理失败：${error.message}"
            tileStopPending = false
            QuickSettingsTileUpdater.request(this)
            StartupLog.append(this, lastError!!)
            // Keep the foreground service and busy state until cleanup can be retried.
            getSystemService(NotificationManager::class.java).notify(2, notification(lastError!!))
        }
    }

    override fun onDestroy() {
        stopping = true
        // Explicit STOP owns shutdown. Activity/service destruction must not stop the daemon.
        running = false
        starting = false
        tileStopPending = false
        worker.shutdown()
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        worker.execute { RootRuntimeMode.capture(this) }
        super.onTaskRemoved(rootIntent)
    }

    private fun notification(text: String) = NotificationCompat.Builder(this, "root-proxy")
        .setSmallIcon(R.drawable.ic_qs_clash)
        .setContentTitle("Mclash Root")
        .setContentText(text)
        .setOngoing(true)
        .setContentIntent(PendingIntent.getActivity(this, 0,
            packageManager.getLaunchIntentForPackage(packageName), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        .addAction(0, "停止", PendingIntent.getService(this, 1,
            Intent(this, ProxyTProxyService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE))
        .build()

    companion object {
        private const val ACTION_TOGGLE = "com.liuyihtu.mclash.root.TOGGLE"
        private const val ACTION_START = "com.liuyihtu.mclash.root.START"
        private const val ACTION_STOP = "com.liuyihtu.mclash.root.STOP"
        @Volatile var running = false; private set
        @Volatile var starting = false; private set
        @Volatile var restoring = false; private set
        @Volatile var tileStopPending = false; private set
        @Volatile var lastError: String? = null; private set
        fun clearLastError() { lastError = null }
        fun restore(context: Context) {
            if (!running && !starting && !restoring && java.io.File(context.filesDir, "mihomo/ready")
                    .takeIf { it.isFile }?.readText()?.trim() == "ready") {
                restoring = true
                try { start(context) } catch (error: Throwable) { restoring = false; throw error }
            }
        }
        fun tileActive(context: Context): Boolean = running || starting || restoring || runCatching {
            java.io.File(context.filesDir, "mihomo/ready")
                .takeIf { it.isFile }?.readText()?.trim() == "ready"
        }.getOrDefault(false)
        fun toggle(context: Context) {
            tileStopPending = tileActive(context)
            try {
                ContextCompat.startForegroundService(context,
                    Intent(context, ProxyTProxyService::class.java).setAction(ACTION_TOGGLE))
            } catch (error: Throwable) {
                tileStopPending = false
                throw error
            }
        }
        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, ProxyTProxyService::class.java).setAction(ACTION_START))
        }
        fun stop(context: Context) {
            if (running || starting || MihomoProcess.isRunning()) {
                context.startService(Intent(context, ProxyTProxyService::class.java).setAction(ACTION_STOP))
            }
        }
    }
}
