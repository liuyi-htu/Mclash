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
        if (intent?.action == ACTION_STOP) {
            stopping = true
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
                lastError = error.message
                stopSelf()
                return START_NOT_STICKY
            }
            startForeground(2, notification("正在启动 Root TProxy"))
            QuickSettingsTileUpdater.request(this)
            worker.execute { startProxy() }
        }
        restoring = false
        return if (intent?.action == ACTION_STOP) START_NOT_STICKY else START_STICKY
    }

    private fun startProxy() {
        try {
            StartupLog.reset(this)
            StartupLog.append(this, "Root TProxy 启动；ABI=${Build.SUPPORTED_ABIS.joinToString()}")
            StartupLog.append(this, RootShell.requireRoot())
            require(Settings.Global.getString(contentResolver, "private_dns_mode") != "hostname") {
                "请先在 Android 网络设置中关闭严格私人 DNS，再启动 TProxy"
            }
            RootRuntimeMode.capture(this)
            MihomoProcess.recover(this)
            val preferences = AppPreferences(this)
            val store = ConfigStore(this)
            require(store.exists()) { "请先选择有效配置" }
            val onlySelected = preferences.appProxyMode == AppPreferences.MODE_ONLY_SELECTED
            val uids = preferences.selectedPackages.mapNotNull { name ->
                runCatching { packageManager.getApplicationInfo(name, 0).uid }.getOrNull()
            }.filter { it != android.os.Process.myUid() && it > 0 }.toSet()
            val rules = TProxyRules.install(android.os.Process.myUid(), onlySelected, uids, preferences.rootBypassLan)
            check(!stopping) { "启动已取消" }
            MihomoProcess.start(this, store.configFile, rules) { stopping }
            var hotspotSnapshot = HotspotRules.snapshot(RootShell.run(HotspotRules.SNAPSHOT_COMMAND, 10))
            RootShell.run(HotspotRules.update(hotspotSnapshot.interfaces, preferences.rootBypassLan, hotspotSnapshot.localAddresses))
            running = true
            starting = false
            StartupLog.append(this, "IPv4 TProxy 接管完成；热点默认接管：${hotspotSnapshot.interfaces.joinToString().ifBlank { "等待热点开启" }}；IPv6 按应用及热点阻断")
            getSystemService(NotificationManager::class.java).notify(2,
                notification("TProxy · ${store.activeProfile()?.name ?: "当前配置"}"))
            QuickSettingsTileUpdater.request(this)
            Thread({
                while (running && !stopping && MihomoProcess.isRunning()) {
                    Thread.sleep(2000)
                    if (!running || stopping || !MihomoProcess.isRunning()) break
                    RootRuntimeMode.capture(this)
                    try {
                        val current = HotspotRules.snapshot(RootShell.run(HotspotRules.SNAPSHOT_COMMAND, 10))
                        if (current != hotspotSnapshot && running && !stopping) {
                            RootShell.run(HotspotRules.update(current.interfaces, preferences.rootBypassLan, current.localAddresses))
                            hotspotSnapshot = current
                            StartupLog.append(this, "热点接管接口：${current.interfaces.joinToString().ifBlank { "热点已关闭" }}")
                        }
                    } catch (error: Throwable) {
                        if (running && !stopping) {
                            lastError = "热点规则更新失败：${error.message}"
                            StartupLog.append(this, lastError!!)
                            worker.execute { stopProxy() }
                            return@Thread
                        }
                    }
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
        try {
            RootRuntimeMode.capture(this)
            if (!MihomoProcess.stop()) MihomoProcess.recover(this)
            running = false
            starting = false
            StartupLog.append(this, "Root 服务已停止，接管规则已清理")
            QuickSettingsTileUpdater.request(this)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        } catch (error: Throwable) {
            lastError = "停止清理失败：${error.message}"
            StartupLog.append(this, lastError!!)
            // Keep the foreground service and busy state until cleanup can be retried.
            getSystemService(NotificationManager::class.java).notify(2, notification(lastError!!))
        }
    }

    override fun onDestroy() {
        stopping = true
        if (running || starting) worker.execute {
            RootRuntimeMode.capture(this)
            runCatching { if (!MihomoProcess.stop()) MihomoProcess.recover(this) }
                .onSuccess { running = false; starting = false }
                .onFailure { lastError = "停止清理失败：${it.message}" }
        }
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
        private const val ACTION_START = "com.liuyihtu.mclash.root.START"
        private const val ACTION_STOP = "com.liuyihtu.mclash.root.STOP"
        @Volatile var running = false; private set
        @Volatile var starting = false; private set
        @Volatile var restoring = false; private set
        @Volatile var lastError: String? = null; private set
        fun clearLastError() { lastError = null }
        fun restore(context: Context) {
            if (!running && !starting && !restoring && java.io.File(context.filesDir, "mihomo/ready")
                    .takeIf { it.isFile }?.readText()?.trim() == "ready") {
                restoring = true
                try { start(context) } catch (error: Throwable) { restoring = false; throw error }
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
