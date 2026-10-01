package com.liuyihtu.mclash.root

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import android.view.Gravity
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private lateinit var preferences: AppPreferences
    private lateinit var configStore: ConfigStore
    private var pendingConfigResult: MethodChannel.Result? = null
    private var pendingDeviceRegistrationExportResult: MethodChannel.Result? = null
    private var pendingDeviceRegistrationExportJson: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        preferences = AppPreferences(this)
        configStore = ConfigStore(this)
        ProxyTProxyService.restore(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler(
            ::handleMethodCall,
        )
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method in MUTATING_METHODS) requireProxyStopped()
            when (call.method) {
                "getUsageNoticeAccepted" -> result.success(
                    preferences.acceptedUsageNoticeVersion >= USAGE_NOTICE_VERSION,
                )
                "acceptUsageNotice" -> {
                    preferences.acceptedUsageNoticeVersion = USAGE_NOTICE_VERSION
                    result.success(null)
                }
                "getDeveloperModeEnabled" -> result.success(preferences.developerModeEnabled)
                "enableDeveloperMode" -> {
                    preferences.developerModeEnabled = true
                    result.success(null)
                }
                "disableDeveloperMode" -> {
                    preferences.developerModeEnabled = false
                    result.success(null)
                }
                "getDeviceRegistration" -> {
                    val registration = DeviceIdentity.createRegistration(this)
                    result.success(
                        mapOf(
                            "json" to registration.json,
                            "fingerprint" to registration.fingerprint,
                            "installationId" to registration.installationId,
                            "createdAtEpochSeconds" to registration.createdAtEpochSeconds,
                        ),
                    )
                }
                "exportDeviceRegistration" -> exportDeviceRegistration(result)
                "getConfigInfo" -> runAsync(result, "mclash-config-info") {
                    configInfo()
                }
                "getConfigs" -> runAsync(result, "mclash-config-list") {
                    configStore.listMaps()
                }
                "getProxyGroupOrder" -> result.success(configStore.proxyGroupOrder())
                "importConfigs" -> importConfigs(result)
                "addSubscription" -> addSubscription(call, result)
                "updateSubscription" -> updateSubscription(call, result)
                "refreshSubscription" -> refreshSubscription(call, result)
                "getRuntimeConfigContent" -> runAsync(result, "mclash-runtime-config") {
                    val runtime = File(filesDir, "mihomo/runtime.yaml")
                    if (ProxyTProxyService.running || ProxyTProxyService.starting) {
                        check(runtime.isFile) { "运行配置尚未生成" }
                        runtime.readText(Charsets.UTF_8)
                    } else {
                        val name = configStore.activeProfile()?.name ?: "未选择配置"
                        "# 运行配置预览（当前启用：$name）\n" +
                            MihomoProcess.previewConfig(this, configStore.configFile)
                    }
                }
                "getConfigContent" -> getConfigContent(call, result)
                "saveConfigContent" -> saveConfigContent(call, result)
                "testSubscriptionUrl" -> testSubscriptionUrl(call, result)
                "selectConfig" -> selectConfig(call, result)
                "renameConfig" -> renameConfig(call, result)
                "deleteConfig" -> deleteConfig(call, result)
                "getRootSettings" -> result.success(rootSettings())
                "saveRootSettings" -> saveRootSettings(call, result)
                "getInstalledApps" -> result.success(getInstalledApps())
                "getMode" -> result.success(preferences.appProxyMode)
                "getSelectedPackages" -> result.success(preferences.selectedPackages.toList())
                "saveAppFilter" -> saveAppFilter(call, result)
                "prepareRoot" -> runAsync(result, "root-authorization") { RootShell.requireRoot(); true }
                "start" -> startProxy(result)
                "stop" -> {
                    ProxyTProxyService.stop(this)
                    runAsync(result, "root-stop-waiter") {
                        val deadline = System.currentTimeMillis() + STOP_TIMEOUT_MS
                        while ((ProxyTProxyService.running || ProxyTProxyService.starting) && System.currentTimeMillis() < deadline) Thread.sleep(100)
                        check(!ProxyTProxyService.running && !ProxyTProxyService.starting) { "Root 规则清理未完成，请查看日志" }
                        null
                    }
                }
                "restart" -> restartProxy(result)
                "isRunning" -> runAsync(result, "root-status") {
                    val deadline = System.currentTimeMillis() + START_TIMEOUT_MS
                    while ((ProxyTProxyService.starting || ProxyTProxyService.restoring) && System.currentTimeMillis() < deadline) Thread.sleep(100)
                    ProxyTProxyService.running && MihomoProcess.isRunning()
                }
                "getTrafficStats" -> runAsync(result, "root-traffic") {
                    if (!ProxyTProxyService.running) mapOf("rxBytes" to 0L, "txBytes" to 0L)
                    else {
                        val connection = java.net.URL("http://127.0.0.1:9090/connections").openConnection() as java.net.HttpURLConnection
                        try {
                            connection.connectTimeout = 500; connection.readTimeout = 500
                            val json = org.json.JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
                            mapOf("rxBytes" to json.optLong("downloadTotal"), "txBytes" to json.optLong("uploadTotal"))
                        } finally { connection.disconnect() }
                    }
                }
                "getStartupLog" -> result.success(startupDiagnostics())
                "getDebugLog" -> result.success(readDebugLog(call))
                "getDebugLoggingEnabled" -> result.success(preferences.debugLoggingEnabled)
                "getDelayResults" -> result.success(preferences.delayResultsJson)
                "setDelayResults" -> {
                    preferences.delayResultsJson = call.argument<String>("json") ?: "{}"
                    result.success(null)
                }
                "setDebugLoggingEnabled" -> {
                    preferences.debugLoggingEnabled =
                        call.argument<Boolean>("enabled") ?: false
                    result.success(null)
                }
                "clearDebugLogs" -> {
                    StartupLog.clear(this)
                    MihomoProcess.clearDebugLog(this)
                    File(filesDir, "mihomo/supervisor.log").takeIf { it.isFile }?.writeText("")
                    ProxyTProxyService.clearLastError()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("native_error", error.message, null)
        }
    }

    private fun configInfo(): Map<String, Any?> {
        val active = configStore.activeProfile()
        return mapOf(
            "exists" to configStore.exists(),
            "fileName" to active?.name,
        )
    }

    private fun rootSettings(): Map<String, Any> = mapOf(
        "bypassLan" to preferences.rootBypassLan,
    )

    private fun importConfigs(result: MethodChannel.Result) {
        requireProxyStopped()
        check(pendingConfigResult == null) { "文件选择器已打开" }
        pendingConfigResult = result

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        startActivityForResult(intent, REQUEST_CONFIG)
    }

    private fun exportDeviceRegistration(result: MethodChannel.Result) {
        check(pendingDeviceRegistrationExportResult == null) { "设备登记保存窗口已打开" }
        val registration = DeviceIdentity.createRegistration(this)
        pendingDeviceRegistrationExportResult = result
        pendingDeviceRegistrationExportJson = registration.json
        startActivityForResult(
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "application/json"
                putExtra(
                    Intent.EXTRA_TITLE,
                    "mclash-device-${registration.fingerprint.take(12)}.json",
                )
            },
            REQUEST_DEVICE_REGISTRATION_EXPORT,
        )
    }

    private fun addSubscription(call: MethodCall, result: MethodChannel.Result) {
        requireProxyStopped()
        val name = call.argument<String>("name") ?: error("订阅名称不能为空")
        val url = call.argument<String>("url") ?: error("订阅链接不能为空")
        runAsync(result, "mclash-add-subscription") {
            configStore.addSubscription(name, url)
            configStore.listMaps()
        }
    }

    private fun updateSubscription(call: MethodCall, result: MethodChannel.Result) {
        requireProxyStopped()
        val id = call.argument<String>("id") ?: error("配置 ID 不能为空")
        val name = call.argument<String>("name") ?: error("订阅名称不能为空")
        val url = call.argument<String>("url") ?: error("订阅链接不能为空")
        runAsync(result, "mclash-update-subscription") {
            configStore.updateSubscription(id, name, url)
            configStore.listMaps()
        }
    }

    private fun refreshSubscription(call: MethodCall, result: MethodChannel.Result) {
        requireProxyStopped()
        val id = call.argument<String>("id") ?: error("配置 ID 不能为空")
        runAsync(result, "mclash-refresh-subscription") {
            configStore.refreshSubscription(id)
            configStore.listMaps()
        }
    }

    private fun getConfigContent(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id") ?: error("配置 ID 不能为空")
        runAsync(result, "mclash-get-config-content") { configStore.getContent(id) }
    }

    private fun saveConfigContent(call: MethodCall, result: MethodChannel.Result) {
        requireProxyStopped()
        val id = call.argument<String>("id") ?: error("配置 ID 不能为空")
        val content = call.argument<String>("content") ?: error("配置内容不能为空")
        runAsync(result, "mclash-save-config-content") {
            requireProxyStopped()
            configStore.saveContent(id, content)
            configStore.listMaps()
        }
    }

    private fun testSubscriptionUrl(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id") ?: error("配置 ID 不能为空")
        runAsync(result, "mclash-test-subscription-url") { configStore.testSubscriptionUrl(id) }
    }

    private fun selectConfig(call: MethodCall, result: MethodChannel.Result) {
        requireProxyStopped()
        val id = call.argument<String>("id") ?: error("配置 ID 不能为空")
        configStore.select(id)
        result.success(configInfo())
    }

    private fun renameConfig(call: MethodCall, result: MethodChannel.Result) {
        requireProxyStopped()
        val id = call.argument<String>("id") ?: error("配置 ID 不能为空")
        val name = call.argument<String>("name") ?: error("配置名称不能为空")
        configStore.rename(id, name)
        result.success(configStore.listMaps())
    }

    private fun deleteConfig(call: MethodCall, result: MethodChannel.Result) {
        requireProxyStopped()
        val id = call.argument<String>("id") ?: error("配置 ID 不能为空")
        configStore.delete(id)
        result.success(configStore.listMaps())
    }

    private fun saveRootSettings(call: MethodCall, result: MethodChannel.Result) {
        requireProxyStopped()
        preferences.rootBypassLan = call.argument<Boolean>("bypassLan") ?: true
        result.success(rootSettings())
    }

    private fun requireProxyStopped() {
        require(!ProxyTProxyService.running && !ProxyTProxyService.starting &&
            !ProxyTProxyService.restoring && !MihomoProcess.isRunning()) {
            "请先停止代理再修改配置或设置"
        }
    }

    private fun runAsync(
        result: MethodChannel.Result,
        threadName: String,
        block: () -> Any?,
    ) {
        Thread({
            try {
                val value = if (threadName in CONFIG_WRITE_WORKERS) {
                    RuntimeEdits.edit(::requireProxyStopped, block)
                } else block()
                runOnUiThread { result.success(value) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "native_error",
                        error.message ?: error.javaClass.simpleName,
                        null,
                    )
                }
            }
        }, threadName).start()
    }

    private fun startProxy(result: MethodChannel.Result) {
        require(configStore.exists()) { "请先选择有效的配置文件" }
        ProxyTProxyService.clearLastError()
        ProxyTProxyService.start(this)

        Thread({
            val deadline = System.currentTimeMillis() + START_TIMEOUT_MS
            while (System.currentTimeMillis() < deadline) {
                if (ProxyTProxyService.running) {
                    runOnUiThread { result.success(null) }
                    return@Thread
                }
                ProxyTProxyService.lastError?.let { message ->
                    runOnUiThread { result.error("start_failed", message, null) }
                    return@Thread
                }
                Thread.sleep(100)
            }
            runOnUiThread {
                result.error("start_timeout", "mihomo 启动超时", null)
            }
        }, "mclash-start-waiter").start()
    }

    private fun restartProxy(result: MethodChannel.Result) {
        ProxyTProxyService.stop(this)
        Thread({
            val deadline = System.currentTimeMillis() + STOP_TIMEOUT_MS
            while (
                System.currentTimeMillis() < deadline &&
                (ProxyTProxyService.running || ProxyTProxyService.starting)
            ) {
                Thread.sleep(100)
            }
            if (ProxyTProxyService.running || ProxyTProxyService.starting) {
                runOnUiThread {
                    result.error("restart_timeout", "代理停止超时，无法应用新配置", null)
                }
                return@Thread
            }
            runOnUiThread { startProxy(result) }
        }, "mclash-restart-waiter").start()
    }

    private fun startupDiagnostics(): String {
        val binary = File(applicationInfo.nativeLibraryDir, "libmihomo.so")
        val config = configStore.configFile
        val active = configStore.activeProfile()
        val home = File(filesDir, "mihomo")
        val runtime = File(home, "runtime.yaml")
        val mihomoLog = File(home, "mihomo.log")
        val supervisorLog = File(filesDir, "mihomo/supervisor.log")

        fun describe(file: File): String =
            "path=${file.absolutePath}\n" +
                "exists=${file.isFile}, size=${if (file.exists()) file.length() else 0}, " +
                "readable=${file.canRead()}, executable=${file.canExecute()}"

        fun tail(file: File, lines: Int): String =
            runCatching {
                if (!file.isFile) {
                    "文件不存在"
                } else {
                    file.readLines(Charsets.UTF_8)
                        .takeLast(lines)
                        .joinToString("\n")
                        .ifBlank { "文件为空" }
                }
            }.getOrElse { "读取失败：${it.javaClass.simpleName}: ${it.message}" }

        val runtimeKeys = runCatching {
            if (!runtime.isFile) {
                "runtime.yaml 尚未生成"
            } else {
                runtime.readLines(Charsets.UTF_8)
                    .filter { line ->
                        val trimmed = line.trim()
                        trimmed.startsWith("mixed-port:") ||
                            trimmed.startsWith("socks-port:") ||
                            trimmed.startsWith("tproxy-port:") ||
                            trimmed.startsWith("routing-mark:") ||
                        trimmed.startsWith("allow-lan:") ||
                            trimmed.startsWith("ipv6:") ||
                            trimmed.startsWith("bind-address:") ||
                            trimmed.startsWith("external-controller:") ||
                            trimmed.startsWith("external-ui:") ||
                            trimmed.startsWith("external-ui-name:") ||
                            trimmed.startsWith("external-ui-url:") ||
                            trimmed.startsWith("secret:")
                    }
                    .takeLast(20)
                    .joinToString("\n")
                    .ifBlank { "未找到运行时监听字段" }
            }
        }.getOrElse { "读取 runtime.yaml 失败：${it.message}" }

        return buildString {
            appendLine("===== Mclash 启动诊断 =====")
            appendLine("package=$packageName")
            appendLine("debugLoggingEnabled=${preferences.debugLoggingEnabled}")
            appendLine("abis=${Build.SUPPORTED_ABIS.joinToString()}")
            appendLine("nativeLibraryDir=${applicationInfo.nativeLibraryDir}")
            appendLine(
                "service: running=${ProxyTProxyService.running}, " +
                    "starting=${ProxyTProxyService.starting}",
            )
            appendLine("mihomoProcess=${MihomoProcess.isRunning()}")
            appendLine("lastError=${ProxyTProxyService.lastError ?: "(无)"}")
            appendLine("externalController=127.0.0.1:9090")

            appendLine()
            appendLine("----- mihomo 内核 -----")
            appendLine(describe(binary))

            appendLine()
            appendLine("----- 当前配置 -----")
            appendLine(describe(config))
            appendLine("displayName=${active?.name ?: "(未选择)"}")
            appendLine("type=${active?.type ?: "(未知)"}")
            appendLine("profileCount=${configStore.listMaps().size}")

            appendLine()
            appendLine("----- runtime.yaml 监听摘要 -----")
            appendLine(runtimeKeys)

            appendLine()
            appendLine("----- App 调试日志 -----")
            appendLine(StartupLog.read(this@MainActivity))

            appendLine()
            appendLine("----- mihomo.log 最后 200 行 -----")
            appendLine(
                if (preferences.debugLoggingEnabled || mihomoLog.length() > 0) {
                    tail(mihomoLog, 200)
                } else {
                    "调试日志已关闭，且没有已有 mihomo 日志"
                },
            )

            appendLine()
            appendLine("----- supervisor.log 最后 200 行 -----")
            appendLine(
                if (preferences.debugLoggingEnabled || supervisorLog.length() > 0) {
                    tail(supervisorLog, 200)
                } else {
                    "调试日志已关闭，且没有已有 Root 守护进程日志"
                },
            )
        }
    }

    private fun readDebugLog(call: MethodCall): String {
        val name = call.argument<String>("name") ?: error("缺少日志名称")
        val file = when (name) {
            "Mclash.log" -> File(filesDir, "runtime/startup.log")
            "mihomo.log" -> File(filesDir, "mihomo/mihomo.log")
            "supervisor.log" -> File(filesDir, "mihomo/supervisor.log")
            else -> error("未知日志：$name")
        }
        if (!file.isFile) return "$name 尚未生成"
        return file.readLines(Charsets.UTF_8)
            .takeLast(500)
            .joinToString("\n")
            .ifBlank { "$name 为空" }
    }

    private fun saveAppFilter(call: MethodCall, result: MethodChannel.Result) {
        val mode = call.argument<String>("mode") ?: AppPreferences.MODE_EXCLUDE_SELECTED
        require(
            mode == AppPreferences.MODE_ONLY_SELECTED ||
                mode == AppPreferences.MODE_EXCLUDE_SELECTED,
        ) { "未知分应用模式" }

        val packages = call.argument<List<String>>("packageNames")?.toSet() ?: emptySet()
        preferences.appProxyMode = mode
        preferences.selectedPackages = packages
        result.success(null)
    }

    override fun onPostResume() {
        super.onPostResume()
        handleTileStartRequest()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleTileStartRequest()
    }

    private fun handleTileStartRequest() {
        if (!intent.getBooleanExtra(EXTRA_START_FROM_TILE, false)) return
        intent.removeExtra(EXTRA_START_FROM_TILE)

        if (ProxyTProxyService.running || ProxyTProxyService.starting) {
            QuickSettingsTileUpdater.request(this)
            return
        }

        val store = ConfigStore(this)
        if (!store.exists()) {
            Toast.makeText(this, "请先添加配置", Toast.LENGTH_SHORT)
                .apply { setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL, 0, 96) }
                .show()
            QuickSettingsTileUpdater.request(this)
            return
        }

        ProxyTProxyService.start(this)
        QuickSettingsTileUpdater.request(this)
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val packageManager = packageManager
        val applications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getInstalledApplications(
                android.content.pm.PackageManager.ApplicationInfoFlags.of(0),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstalledApplications(0)
        }

        return applications
            .asSequence()
            .filter { info ->
                info.packageName != packageName &&
                    packageManager.getLaunchIntentForPackage(info.packageName) != null
            }
            .map { info ->
                val isSystemApp =
                    (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                        (info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                mapOf(
                    "packageName" to info.packageName,
                    "label" to packageManager.getApplicationLabel(info).toString(),
                    "isSystemApp" to isSystemApp,
                )
            }
            .sortedBy { it["label"].toString().lowercase() }
            .toList()
    }

    @Deprecated("Required by FlutterActivity for document results")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_DEVICE_REGISTRATION_EXPORT -> {
                val result = pendingDeviceRegistrationExportResult ?: return
                pendingDeviceRegistrationExportResult = null
                val json = pendingDeviceRegistrationExportJson
                pendingDeviceRegistrationExportJson = null
                if (resultCode != Activity.RESULT_OK || data?.data == null || json == null) {
                    result.error("cancelled", "未保存设备登记文件", null)
                    return
                }
                runCatching {
                    contentResolver.openOutputStream(data.data!!, "wt")!!.use { stream ->
                        stream.write(json.toByteArray(Charsets.UTF_8))
                        stream.flush()
                    }
                }.onSuccess {
                    result.success(data.data.toString())
                }.onFailure { error ->
                    result.error("export_failed", error.message, null)
                }
            }
            REQUEST_CONFIG -> {
                val result = pendingConfigResult ?: return
                pendingConfigResult = null
                if (resultCode != Activity.RESULT_OK || data == null) {
                    result.error("cancelled", "未选择配置文件", null)
                    return
                }

                val uris = mutableListOf<Uri>()
                data.clipData?.let { clipData ->
                    for (index in 0 until clipData.itemCount) {
                        uris += clipData.getItemAt(index).uri
                    }
                }
                data.data?.let { uri ->
                    if (uri !in uris) uris += uri
                }

                if (uris.isEmpty()) {
                    result.error("cancelled", "未选择配置文件", null)
                    return
                }

                runAsync(result, "mclash-import-configs") {
                    configStore.import(uris)
                    configStore.listMaps()
                }
            }

        }
    }

    companion object {
        private val MUTATING_METHODS = setOf(
            "enableDeveloperMode", "disableDeveloperMode", "saveAppFilter",
            "saveRootSettings", "setDebugLoggingEnabled", "clearDebugLogs",
            "importConfigs", "addSubscription", "updateSubscription", "refreshSubscription",
            "saveConfigContent", "selectConfig", "renameConfig", "deleteConfig",
        )
        private val CONFIG_WRITE_WORKERS = setOf(
            "mclash-import-configs", "mclash-add-subscription", "mclash-update-subscription",
            "mclash-refresh-subscription", "mclash-save-config-content",
        )
        const val EXTRA_START_FROM_TILE = "start_from_quick_settings_tile"

        private const val CHANNEL = "mclash/native"
        private const val REQUEST_CONFIG = 7001
        private const val REQUEST_DEVICE_REGISTRATION_EXPORT = 7004
        private const val USAGE_NOTICE_VERSION = 1
        private const val START_TIMEOUT_MS = 200_000L
        private const val STOP_TIMEOUT_MS = 30_000L
    }
}
