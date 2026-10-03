package com.liuyihtu.mclash.root

import android.content.Context
import android.os.Build
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.util.UUID

internal object CoreUpdater {
    private const val RELEASE_URL = "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
    private fun home(context: Context) = File(context.filesDir, "mihomo/core").apply { mkdirs() }
    private fun selection(context: Context) = File(home(context), "active")

    fun selectionName(context: Context): String? = selection(context).takeIf { it.isFile }?.readText()

    fun restoreSelection(context: Context, name: String?) {
        if (name == null) {
            val active = selection(context)
            check(!active.exists() || active.delete()) { "无法恢复内置内核" }
        } else {
            val temporary = File(home(context), "active.tmp")
            try {
                temporary.writeText(name)
                check(temporary.renameTo(selection(context))) { "无法恢复原内核" }
            } finally { temporary.delete() }
        }
    }

    fun binary(context: Context): File {
        val selected = selection(context)
        val binary = if (selected.isFile) {
            val name = selected.readText().trim()
            require(name.matches(Regex("core-[a-f0-9-]{36}"))) { "已安装内核记录无效" }
            File(home(context), "$name/libmihomo.so")
        } else File(context.applicationInfo.nativeLibraryDir, "libmihomo.so")
        require(binary.isFile && binary.canExecute()) { "缺少可执行的 Mihomo 内核" }
        return binary
    }

    fun info(context: Context): Map<String, Any> {
        val core = binary(context)
        val installed = core.parentFile?.parentFile == home(context)
        val version = if (installed) File(core.parentFile, "version").readText().trim()
            else runCatching { context.assets.open("geodata/mihomo-version.txt").bufferedReader().use { it.readText().trim() } }
                .getOrElse { CoreArchive.version(RootShell.run("${RootShell.quote(core.absolutePath)} -v")) }
        return mapOf("version" to version, "installed" to installed)
    }

    @Synchronized
    fun update(context: Context, config: File?, beforeSwitch: () -> Unit): Map<String, Any> {
        requireProxyRunning()
        require(Build.SUPPORTED_ABIS.contains("arm64-v8a")) { "当前内核更新仅支持 ARM64" }
        val release = latestRelease()
        val version = release.getString("tag_name")
        if (info(context)["version"] == version) return info(context) + ("updated" to false)
        val assets = release.getJSONArray("assets")
        val matches = (0 until assets.length()).map { assets.getJSONObject(it) }
            .filter { it.getString("name") == "mihomo-android-arm64-v8-$version.gz" }
        require(matches.size == 1) { "官方 Release 缺少匹配的 Android ARM64 内核" }
        val asset = matches.single()
        val url = asset.getString("browser_download_url")
        require(url.startsWith("https://github.com/MetaCubeX/mihomo/releases/download/$version/")) { "官方内核下载地址无效" }
        val expectedSize = asset.optLong("size", -1)
        require(expectedSize == -1L || expectedSize in 1..CoreArchive.MAX_BYTES) { "官方内核大小无效" }
        val directory = File(home(context), "core-${UUID.randomUUID()}").apply { check(mkdir()) }
        val archive = File(directory, "download.gz")
        val candidate = File(directory, "libmihomo.so")
        val pointer = File(home(context), "active.tmp")
        var activated = false
        try {
            request(url) { connection ->
                connection.inputStream.use { input -> archive.outputStream().use { CoreArchive.copyLimited(input, it) } }
            }
            check(expectedSize == -1L || archive.length() == expectedSize) { "内核下载不完整" }
            CoreArchive.unpack(archive, candidate, asset.optString("digest"))
            check(candidate.setExecutable(true, true)) { "无法设置内核执行权限" }
            check(CoreArchive.version(RootShell.run("${RootShell.quote(candidate.absolutePath)} -v")) == version) { "内核版本与官方 Release 不一致" }
            beforeSwitch()
            if (config != null) MihomoProcess.validateWithBinary(context, config, candidate)
            File(directory, "version").writeText(version)
            archive.delete()
            pointer.writeText(directory.name)
            check(pointer.renameTo(selection(context))) { "无法切换到新内核" }
            activated = true
            return info(context) + ("updated" to true)
        } finally {
            pointer.delete()
            if (!activated) directory.deleteRecursively()
        }
    }

    fun checkUpdate(context: Context): Map<String, Any> {
        requireProxyRunning()
        val current = info(context)["version"] as String
        val latest = try { apiRelease().getString("tag_name") }
            catch (_: Exception) { pageVersion() }
        return mapOf("currentVersion" to current, "latestVersion" to latest,
            "updateAvailable" to (current != latest))
    }

    private fun latestRelease(): JSONObject = try { apiRelease() } catch (_: Exception) {
        val version = pageVersion()
        val html = request("https://github.com/MetaCubeX/mihomo/releases/expanded_assets/$version", ::readText)
        val name = "mihomo-android-arm64-v8-$version.gz"
        JSONObject().put("tag_name", version).put("assets", org.json.JSONArray().put(
            JSONObject().put("name", name)
                .put("browser_download_url", "https://github.com/MetaCubeX/mihomo/releases/download/$version/$name")
                .put("digest", CoreReleasePage.digest(version, html))))
    }

    private fun pageVersion(): String = request("https://github.com/MetaCubeX/mihomo/releases/latest") {
        CoreReleasePage.version(it.url.toString())
    }

    private fun readText(connection: HttpURLConnection): String {
        val output = java.io.ByteArrayOutputStream()
        connection.inputStream.use { CoreArchive.copyLimited(it, output) }
        return output.toString("UTF-8")
    }

    private fun apiRelease(): JSONObject {
        val release = JSONObject(request(RELEASE_URL, ::readText))
        val version = release.getString("tag_name")
        require(version.matches(Regex("v[0-9]+\\.[0-9]+\\.[0-9]+")) &&
            !release.optBoolean("prerelease") && !release.optBoolean("draft")) { "官方稳定版信息无效" }
        return release
    }

    private fun requireProxyRunning() {
        check(ProxyTProxyService.running && !ProxyTProxyService.starting &&
            !ProxyTProxyService.restoring && MihomoProcess.isRunning()) { "请先开启代理再检测或更新内核" }
    }

    private fun <T> request(url: String, block: (HttpURLConnection) -> T): T {
        requireProxyRunning()
        val connection = CoreProxyConnection.open(url, RootRuntimeConfig.MIXED_PORT)
        try {
            connection.connectTimeout = 10_000
            connection.readTimeout = 30_000
            connection.setRequestProperty("User-Agent", "Mclash-Root")
            if (url == RELEASE_URL) connection.setRequestProperty("Accept", "application/vnd.github+json")
            check(connection.responseCode == 200) { "HTTP ${connection.responseCode}" }
            require(connection.url.protocol == "https") { "内核下载必须使用 HTTPS" }
            return block(connection)
        } catch (error: Exception) {
            throw java.io.IOException("通过本机 SOCKS5 代理连接 GitHub 失败，请检查节点连接（${error.message}）", error)
        } finally { connection.disconnect() }
    }
}
