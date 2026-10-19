package com.liuyihtu.mclash.root

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** Temporary operation host, never the owner of a running Root proxy. */
class ProxyTProxyService : Service() {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val pending = AtomicInteger()
    private val operations = RootOperationState(pendingStarts)
    private var latestStartId = 0

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("root-proxy", "Root 代理操作", NotificationManager.IMPORTANCE_LOW),
        )
        MihomoProcess.initialize(this)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        latestStartId = startId
        if (intent?.action !in setOf(ACTION_START, ACTION_STOP, ACTION_TOGGLE)) {
            if (pending.get() == 0) stopSelfResult(startId)
            return START_NOT_STICKY
        }
        val action = if (intent!!.action == ACTION_TOGGLE && tileActive(this)) ACTION_STOP else intent.action
        val stop = action == ACTION_STOP
        startForeground(2, notification(if (stop) "正在停止并清理 Root 代理" else "正在启动 Root 代理"))
        pending.incrementAndGet()
        try {
            if (stop) {
                operations.admit(startId, true)
                tileStopPending = true
            } else {
                RuntimeEdits.start { operations.admit(startId, false) }
            }
        } catch (error: Throwable) {
            lastError = error.message
            pending.decrementAndGet()
            finishRequest()
            return START_NOT_STICKY
        }
        QuickSettingsTileUpdater.request(this)
        worker.execute {
            try {
                lastError = null
                if (stop || (action == ACTION_TOGGLE && MihomoProcess.attach(this))) {
                    stopProxy()
                } else {
                    startProxy { operations.cancelled(startId) }
                }
            } catch (error: Throwable) {
                lastError = error.message ?: error.javaClass.simpleName
                StartupLog.append(this, "Root 操作失败：$lastError")
            } finally {
                operations.complete(stop)
                pending.decrementAndGet()
                main.post { finishRequest() }
            }
        }
        return START_NOT_STICKY
    }

    private fun finishRequest() {
        if (pending.get() != 0) return
        tileStopPending = false
        QuickSettingsTileUpdater.request(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelfResult(latestStartId)
    }

    private fun startProxy(cancelled: () -> Boolean) {
        if (MihomoProcess.attach(this)) return
        try {
            StartupLog.reset(this)
            StartupLog.append(this, "Root 代理启动；ABI=${Build.SUPPORTED_ABIS.joinToString()}")
            StartupLog.append(this, RootShell.requireRoot())
            val preferences = AppPreferences(this)
            val store = ConfigStore(this)
            require(Settings.Global.getString(contentResolver, "private_dns_mode") != "hostname") {
                "请先在 Android 网络设置中关闭严格私人 DNS，再启动代理"
            }
            MihomoProcess.recover(this)
            require(store.exists()) { "请先选择有效配置" }
            val onlySelected = preferences.appProxyMode == AppPreferences.MODE_ONLY_SELECTED
            val uids = preferences.selectedPackages.mapNotNull { name ->
                runCatching { packageManager.getApplicationInfo(name, 0).uid }.getOrNull()
            }.filter { it != android.os.Process.myUid() && it > 0 }.toSet()
            val rules = TProxyRules.install(android.os.Process.myUid(), onlySelected, uids,
                preferences.rootBypassLan, preferences.rootIpv6, preferences.rootProxyMode == "tun")
            check(!cancelled()) { "启动已取消" }
            MihomoProcess.start(this, store.configFile, rules, cancelled)
            StartupLog.append(this, "${preferences.rootProxyMode.uppercase()} 接管完成；Root Supervisor 独立运行，Android 操作服务退出")
        } catch (error: Throwable) {
            // Never hide a rollback failure behind the original startup failure.
            try {
                if (!MihomoProcess.stop()) MihomoProcess.recover(this)
            } catch (cleanup: Throwable) {
                throw IllegalStateException("启动失败且规则清理失败：${cleanup.message}", error)
            }
            throw error
        }
    }

    private fun stopProxy() {
        RootRuntimeMode.capture(this)
        if (!MihomoProcess.stop()) MihomoProcess.recover(this)
        StartupLog.append(this, "Root 代理已停止，接管规则已清理")
    }

    override fun onDestroy() {
        // No stop, mode capture, polling or cleanup when Android destroys us.
        worker.shutdown()
        super.onDestroy()
    }

    private fun notification(text: String) = NotificationCompat.Builder(this, "root-proxy")
        .setSmallIcon(R.drawable.ic_qs_clash)
        .setContentTitle("Mclash Root")
        .setContentText(text)
        .setOngoing(true)
        .setContentIntent(PendingIntent.getActivity(this, 0,
            packageManager.getLaunchIntentForPackage(packageName), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        .build()

    companion object {
        private const val ACTION_TOGGLE = "com.liuyihtu.mclash.root.TOGGLE"
        private const val ACTION_START = "com.liuyihtu.mclash.root.START"
        private const val ACTION_STOP = "com.liuyihtu.mclash.root.STOP"
        private val pendingStarts = AtomicInteger()
        // Compatibility accessors: no Android-service lifetime flag is retained.
        val running: Boolean get() = MihomoProcess.isRunning()
        val starting: Boolean get() = pendingStarts.get() > 0
        @Volatile var tileStopPending = false; private set
        @Volatile var lastError: String? = null; private set
        fun clearLastError() { lastError = null }
        fun restore(context: Context) { MihomoProcess.initialize(context) }
        fun tileActive(context: Context): Boolean {
            restore(context)
            return starting || running || MihomoProcess.hasCleanupFailure()
        }
        private fun dispatch(context: Context, action: String) {
            restore(context)
            ContextCompat.startForegroundService(context, Intent(context, ProxyTProxyService::class.java).setAction(action))
        }
        fun toggle(context: Context) {
            val stop = tileActive(context)
            tileStopPending = stop
            try { dispatch(context, if (stop) ACTION_STOP else ACTION_TOGGLE) }
            catch (error: Throwable) { tileStopPending = false; throw error }
        }
        fun start(context: Context) = dispatch(context, ACTION_START)
        fun stop(context: Context) {
            tileStopPending = true
            lastError = null
            try { dispatch(context, ACTION_STOP) }
            catch (error: Throwable) { tileStopPending = false; throw error }
        }
    }
}
