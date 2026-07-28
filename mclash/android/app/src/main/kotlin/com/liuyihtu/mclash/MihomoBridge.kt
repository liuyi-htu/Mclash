package com.liuyihtu.mclash

import android.content.Context
import java.io.File
import java.io.FileNotFoundException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.TimeUnit

/** Runs the official prebuilt mihomo Android executable shipped in jniLibs. */
internal object MihomoProcess {
    private const val START_TIMEOUT_MS = 90_000L
    private const val LOCAL_PROXY_PORT = 7890
    private const val LOCAL_CONTROLLER_HOST = "127.0.0.1"
    private const val LOCAL_CONTROLLER_PORT = 9090
    private val BUNDLED_GEODATA = listOf(
        "geosite.dat" to "GeoSite.dat",
        "geoip.dat" to "GeoIP.dat",
        "country.mmdb" to "Country.mmdb",
    )

    @Volatile
    private var process: Process? = null

    @Synchronized
    fun start(context: Context, importedConfig: File): Int {
        require(importedConfig.isFile && importedConfig.length() > 0) {
            "mihomo 配置不存在或为空"
        }
        check(process?.isAlive != true) { "mihomo 已在运行" }

        val binary = File(context.applicationInfo.nativeLibraryDir, "libmihomo.so")
        require(binary.isFile) { "APK 中没有当前 CPU 架构的 mihomo 内核" }
        require(binary.canExecute()) { "mihomo 内核不可执行：${binary.absolutePath}" }

        val home = File(context.filesDir, "mihomo").apply { mkdirs() }
        installBundledGeodata(context, home)
        val preferences = AppPreferences(context)
        // Keep the selected profile unchanged. Create a shared runtime copy.
        val runtimeConfig = prepareRuntimeConfig(
            importedConfig = importedConfig,
            home = home,
            ipv6Enabled = preferences.vpnIpv6Enabled,
        )

        val debugLoggingEnabled = preferences.debugLoggingEnabled
        val logFile = File(home, "mihomo.log")
        if (debugLoggingEnabled) {
            logFile.writeText(
                "=== Mclash mihomo start ${System.currentTimeMillis()} ===\n" +
                    "binary=${binary.absolutePath}\n" +
                    "config=${runtimeConfig.absolutePath}\n" +
                    "proxy=127.0.0.1:$LOCAL_PROXY_PORT\n" +
                    "controller=$LOCAL_CONTROLLER_HOST:$LOCAL_CONTROLLER_PORT\n",
            )
        }

        val processBuilder = ProcessBuilder(
            binary.absolutePath,
            "-d", home.absolutePath,
            "-f", runtimeConfig.absolutePath,
        )
            .directory(home)
            .redirectErrorStream(true)

        processBuilder.redirectOutput(
            if (debugLoggingEnabled) {
                ProcessBuilder.Redirect.appendTo(logFile)
            } else {
                ProcessBuilder.Redirect.to(File("/dev/null"))
            },
        )

        val next = processBuilder.start()

        process = next
        try {
            waitForPort(
                process = next,
                host = "127.0.0.1",
                port = LOCAL_PROXY_PORT,
                logFile = logFile,
                label = "本地代理端口",
                debugLoggingEnabled = debugLoggingEnabled,
            )
            waitForPort(
                process = next,
                host = LOCAL_CONTROLLER_HOST,
                port = LOCAL_CONTROLLER_PORT,
                logFile = logFile,
                label = "外部控制器",
                debugLoggingEnabled = debugLoggingEnabled,
            )
        } catch (error: Throwable) {
            stop()
            throw error
        }
        return LOCAL_PROXY_PORT
    }

    @Synchronized
    fun stop() {
        val current = process ?: return
        process = null
        if (!current.isAlive) return
        current.destroy()
        if (!current.waitFor(3, TimeUnit.SECONDS)) {
            current.destroyForcibly()
            current.waitFor(2, TimeUnit.SECONDS)
        }
    }

    fun isRunning(): Boolean = process?.isAlive == true

    fun clearDebugLog(context: Context) {
        val logFile = File(context.filesDir, "mihomo/mihomo.log")
        if (logFile.exists()) {
            // Truncate instead of deleting: a running mihomo process may still
            // hold the file descriptor open in append mode.
            logFile.writeText("", Charsets.UTF_8)
        }
    }

    private fun installBundledGeodata(context: Context, home: File) {
        BUNDLED_GEODATA.forEach { (assetName, targetName) ->
            val target = File(home, targetName)
            if (target.isFile && target.length() > 0L) return@forEach

            val temporary = File(home, ".$targetName.tmp")
            try {
                context.assets.open("geodata/$assetName").use { input ->
                    temporary.outputStream().use { output -> input.copyTo(output) }
                }
                require(temporary.length() > 0L) { "内置 $targetName 为空" }
                if (!temporary.renameTo(target)) {
                    temporary.copyTo(target, overwrite = true)
                    temporary.delete()
                }
            } catch (_: FileNotFoundException) {
                temporary.delete()
                // Source-only local builds may omit generated workflow assets.
                return@forEach
            } catch (cause: Throwable) {
                temporary.delete()
                error("无法安装内置 $targetName：${cause.message}")
            }
        }
    }


    private fun prepareRuntimeConfig(
        importedConfig: File,
        home: File,
        ipv6Enabled: Boolean,
    ): File {
        val controlledKeys = setOf(
            "mixed-port",
            "socks-port",
            "port",
            "redir-port",
            "tproxy-port",
            "allow-lan",
            "ipv6",
            "bind-address",
            "log-level",
            "external-controller",
            "external-controller-tls",
            "external-controller-unix",
            "external-controller-pipe",
            "external-controller-cors",
            "external-controller-routing-mark",
            "external-ui",
            "external-ui-name",
            "external-ui-url",
            "secret",
        )

        val original = importedConfig.readText(Charsets.UTF_8)
            .removePrefix("\uFEFF")

        val filtered = removeTopLevelKeys(original, controlledKeys).trimEnd()

        val runtime = File(home, "runtime.yaml")
        runtime.writeText(
            buildString {
                append(filtered)
                if (filtered.isNotEmpty()) append('\n')
                append(
                    """
                    # Injected by Mclash for Android VpnService.
                    mixed-port: $LOCAL_PROXY_PORT
                    allow-lan: false
                    ipv6: $ipv6Enabled
                    bind-address: 127.0.0.1
                    log-level: error
                    external-controller: "$LOCAL_CONTROLLER_HOST:$LOCAL_CONTROLLER_PORT"
                    secret: ""
                    external-controller-cors:
                      allow-origins:
                        - '*'
                      allow-private-network: true
                    """.trimIndent(),
                )
                append('\n')
            },
            Charsets.UTF_8,
        )
        return runtime
    }

    private fun removeTopLevelKeys(
        yaml: String,
        controlledKeys: Set<String>,
    ): String {
        val kept = mutableListOf<String>()
        var skippingControlledBlock = false

        for (line in yaml.lineSequence()) {
            val trimmed = line.trimStart()
            val isComment = trimmed.startsWith("#")
            val isTopLevel = line.isNotBlank() &&
                line.firstOrNull()?.isWhitespace() == false &&
                !isComment

            if (isTopLevel) {
                val key = line.substringBefore(':', missingDelimiterValue = "").trim()
                skippingControlledBlock = key in controlledKeys
                if (skippingControlledBlock) continue
            }

            if (!skippingControlledBlock) {
                kept += line
            }
        }

        return kept.joinToString("\n")
    }

    private fun waitForPort(
        process: Process,
        host: String,
        port: Int,
        logFile: File,
        label: String,
        debugLoggingEnabled: Boolean,
    ) {
        val deadline = System.currentTimeMillis() + START_TIMEOUT_MS

        while (System.currentTimeMillis() < deadline) {
            if (!process.isAlive) {
                error(
                    "mihomo 启动后立即退出。\n${readLogTail(logFile, debugLoggingEnabled)}",
                )
            }

            if (canConnect(host, port)) {
                return
            }

            Thread.sleep(200)
        }

        val state = if (process.isAlive) {
            "进程仍在运行，但端口没有监听"
        } else {
            "进程已经退出"
        }
        error(
            "mihomo 启动超时（90 秒）：$label $state。\n" +
                "等待地址：$host:$port\n" +
                readLogTail(logFile, debugLoggingEnabled),
        )
    }

    private fun canConnect(host: String, port: Int): Boolean =
        try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), 400)
            }
            true
        } catch (_: Throwable) {
            false
        }

    private fun readLogTail(
        logFile: File,
        debugLoggingEnabled: Boolean,
    ): String {
        if (!debugLoggingEnabled) {
            return "调试日志已关闭；启用后重新启动代理可记录 mihomo 输出"
        }
        return runCatching {
            val lines = logFile.readLines(Charsets.UTF_8).takeLast(40)
            if (lines.isEmpty()) {
                "mihomo.log 没有输出"
            } else {
                "mihomo.log 最后 ${lines.size} 行：\n${lines.joinToString("\n")}"
            }
        }.getOrElse { error ->
            "无法读取 mihomo.log：${error.message}"
        }
    }
}
