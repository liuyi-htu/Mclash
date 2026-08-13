package com.liuyihtu.mclash

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.net.TrafficStats
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
    private lateinit var rootManager: RootManager
    private var pendingConfigResult: MethodChannel.Result? = null
    private var pendingDeviceRegistrationExportResult: MethodChannel.Result? = null
    private var pendingDeviceRegistrationExportJson: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        preferences = AppPreferences(this)
        configStore = ConfigStore(this)
        rootManager = RootManager(this, preferences, configStore)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler(
            ::handleMethodCall,
        )
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
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
                "switchToRootMode" -> runAsync(result, "mclash-mode-root") {
                    rootManager.switchToRoot()
                    "root"
                }
                "hasRootPermission" -> runAsync(result, "mclash-root-permission") {
                    rootManager.hasPermission()
                }
                "getRootStatus" -> runAsync(result, "mclash-root-status") {
                    rootManager.status()
                }
                "installRootModule" -> runAsync(result, "mclash-root-install") {
                    rootManager.installModule()
                }
                "getRootModuleVersion" -> runAsync(result, "mclash-root-version") {
                    rootManager.moduleVersion()
                }
                "getRootSettings" -> result.success(rootManager.settings())
                "saveRootSettings" -> saveRootSettings(call, result)
                "syncRootRuntime" -> runAsync(result, "mclash-root-sync") {
                    rootManager.syncRuntime()
                    null
                }
                "startRoot" -> runAsync(result, "mclash-root-start") {
                    rootManager.start()
                    null
                }
                "stopRoot" -> runAsync(result, "mclash-root-stop") {
                    rootManager.stop()
                    null
                }
                "isRootRunning" -> runAsync(result, "mclash-root-running") {
                    rootManager.isRunning()
                }
                "readRootLog" -> readRootLog(call, result)
                "clearRootLog" -> clearRootLog(call, result)
                "checkRootCoreVersion" -> checkRootCoreVersion(call, result)
                "updateRootCore" -> updateRootCore(call, result)
                "getRootCoreUpdateStatus" -> result.success(rootManager.updateStatus())
                "cancelRootCoreUpdate" -> {
                    rootManager.cancelUpdate()
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
                "getConfigInfo" -> result.success(configInfo())
                "getConfigs" -> result.success(configStore.listMaps())
                "getProxyGroupOrder" -> result.success(configStore.proxyGroupOrder())
                "importConfigs" -> importConfigs(result)
                "addSubscription" -> addSubscription(call, result)
                "updateSubscription" -> updateSubscription(call, result)
                "refreshSubscription" -> refreshSubscription(call, result)
                "getConfigContent" -> getConfigContent(call, result)
                "saveConfigContent" -> saveConfigContent(call, result)
                "testSubscriptionUrl" -> testSubscriptionUrl(call, result)
                "selectConfig" -> selectConfig(call, result)
                "renameConfig" -> renameConfig(call, result)
                "deleteConfig" -> deleteConfig(call, result)
                "getInstalledApps" -> result.success(getInstalledApps())
                "getMode" -> result.success(preferences.appProxyMode)
                "getSelectedPackages" -> result.success(preferences.selectedPackages.toList())
                "saveAppFilter" -> saveAppFilter(call, result)
                "start" -> startProxy(result)
                "stop" -> runAsync(result, "mclash-root-stop") { rootManager.stop(); null }
                "isRunning" -> runAsync(result, "mclash-root-running") {
                    rootManager.isRunning()
                }
                "getTrafficStats" -> result.success(
                    mapOf(
                        "rxBytes" to TrafficStats.getUidRxBytes(android.os.Process.myUid()),
                        "txBytes" to TrafficStats.getUidTxBytes(android.os.Process.myUid()),
                    ),
                )
                "getDelayResults" -> result.success(preferences.delayResultsJson)
                "setDelayResults" -> {
                    preferences.delayResultsJson = call.argument<String>("json") ?: "{}"
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
        requireProxyNotStarting()
        val id = call.argument<String>("id") ?: error("配置 ID 不能为空")
        val name = call.argument<String>("name") ?: error("订阅名称不能为空")
        val url = call.argument<String>("url") ?: error("订阅链接不能为空")
        runAsync(result, "mclash-update-subscription") {
            configStore.updateSubscription(id, name, url)
            configStore.listMaps()
        }
    }

    private fun refreshSubscription(call: MethodCall, result: MethodChannel.Result) {
        requireProxyNotStarting()
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
        requireProxyNotStarting()
        val id = call.argument<String>("id") ?: error("配置 ID 不能为空")
        val content = call.argument<String>("content") ?: error("配置内容不能为空")
        runAsync(result, "mclash-save-config-content") {
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

    private fun requireProxyStopped() {
        require(!rootManager.isRunning()) {
            "请先停止代理再修改配置"
        }
    }

    private fun requireProxyNotStarting() {
        // Root lifecycle operations are serialized by the module controller.
    }

    private fun runAsync(
        result: MethodChannel.Result,
        threadName: String,
        block: () -> Any?,
    ) {
        Thread({
            try {
                val value = block()
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
        runAsync(result, "mclash-root-start") { rootManager.start(); null }
    }

    private fun saveAppFilter(call: MethodCall, result: MethodChannel.Result) {
        val mode = call.argument<String>("mode") ?: AppPreferences.MODE_EXCLUDE
        require(
            mode == AppPreferences.MODE_INCLUDE ||
                mode == AppPreferences.MODE_EXCLUDE,
        ) { "未知分应用模式" }

        val packages = call.argument<List<String>>("packageNames")?.toSet() ?: emptySet()
        preferences.appProxyMode = mode
        preferences.selectedPackages = packages
        runAsync(result, "mclash-root-app-filter") {
            if (rootManager.isRunning()) {
                rootManager.stop()
                rootManager.start()
            } else if (rootManager.hasPermission()) {
                runCatching { rootManager.syncRuntime() }
            }
            null
        }
    }

    private fun saveRootSettings(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val arguments = call.arguments as? Map<String, Any?> ?: emptyMap()
        runAsync(result, "mclash-root-settings") { rootManager.saveSettings(arguments) }
    }

    private fun readRootLog(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name") ?: error("缺少日志名称")
        runAsync(result, "mclash-root-log") { rootManager.readLog(name) }
    }

    private fun clearRootLog(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name") ?: error("缺少日志名称")
        runAsync(result, "mclash-root-log-clear") { rootManager.clearLog(name); null }
    }

    private fun checkRootCoreVersion(call: MethodCall, result: MethodChannel.Result) {
        val manifestUrl = call.argument<String>("manifestUrl") ?: error("缺少更新 manifest 地址")
        runAsync(result, "mclash-root-update-check") { rootManager.checkCoreVersion(manifestUrl) }
    }

    private fun updateRootCore(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val arguments = call.arguments as? Map<String, Any?> ?: error("缺少更新信息")
        runAsync(result, "mclash-root-update") { rootManager.updateCore(arguments) }
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

        val store = ConfigStore(this)
        if (!store.exists()) {
            Toast.makeText(this, "请先添加配置", Toast.LENGTH_SHORT)
                .apply { setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL, 0, 96) }
                .show()
            QuickSettingsTileUpdater.request(this)
            return
        }

        runAsync(
            object : MethodChannel.Result {
                override fun success(result: Any?) = QuickSettingsTileUpdater.request(this@MainActivity)
                override fun error(code: String, message: String?, details: Any?) {
                    Toast.makeText(this@MainActivity, message ?: "Root 启动失败", Toast.LENGTH_LONG).show()
                }
                override fun notImplemented() = Unit
            },
            "mclash-root-tile-start",
        ) { rootManager.start(); null }
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
        const val EXTRA_START_FROM_TILE = "start_from_quick_settings_tile"

        private const val CHANNEL = "mclash/native"
        private const val REQUEST_CONFIG = 7001
        private const val REQUEST_DEVICE_REGISTRATION_EXPORT = 7004
        private const val USAGE_NOTICE_VERSION = 1
    }
}
