package com.liuyihtu.mclash

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.zip.GZIPInputStream

internal data class ConfigProfile(
    val id: String,
    val name: String,
    val type: String,
    val url: String?,
    val updatedAt: Long,
    val subscriptionUserInfo: String? = null,
    val subscriptionNames: Map<String, String> = emptyMap(),
    val subscriptionInfos: Map<String, String> = emptyMap(),
)

internal class ConfigStore(private val context: Context) {
    private val preferences = AppPreferences(context)
    private val mihomoDirectory = File(context.filesDir, "mihomo")
    private val configsDirectory = File(mihomoDirectory, "configs")
    private val legacyConfigFile = File(mihomoDirectory, "config.yaml")

    init {
        migrateLegacyConfig()
        normalizeLocalProfileNames()
    }

    val configFile: File
        get() {
            val active = activeProfile()
            return if (active == null) {
                File(configsDirectory, "missing.yaml")
            } else {
                profileFile(active.id)
            }
        }

    fun exists(): Boolean = configFile.isFile && configFile.length() > 0

    fun proxyGroupOrder(): List<String> {
        if (!exists()) return emptyList()
        return parseProxyGroupOrder(
            configFile.readText(Charsets.UTF_8).removePrefix("\uFEFF"),
        )
    }

    fun activeProfile(): ConfigProfile? {
        val profiles = readProfiles()
        if (profiles.isEmpty()) return null

        val selected = profiles.firstOrNull { it.id == preferences.activeConfigId }
            ?: profiles.first()
        if (preferences.activeConfigId != selected.id) {
            preferences.activeConfigId = selected.id
            preferences.configFileName = selected.name
        }
        return selected
    }

    fun listMaps(): List<Map<String, Any?>> {
        val activeId = activeProfile()?.id
        return readProfiles().map { profile ->
            mapOf(
                "id" to profile.id,
                "name" to profile.name,
                "type" to profile.type,
                "url" to profile.url,
                "updatedAt" to profile.updatedAt,
                "subscriptionUserInfo" to profile.subscriptionUserInfo,
                "subscriptionNames" to profile.subscriptionNames,
                "subscriptionInfos" to profile.subscriptionInfos,
                "active" to (profile.id == activeId),
                "exists" to profileFile(profile.id).isFile,
            )
        }
    }

    fun import(uris: List<Uri>): List<ConfigProfile> {
        require(uris.isNotEmpty()) { "未选择配置文件" }

        data class PendingConfig(val name: String, val bytes: ByteArray)

        val pending = uris.map { uri ->
            val fileName = displayName(uri)
            val extension = fileName
                .substringAfterLast('.', missingDelimiterValue = "")
                .lowercase()
            require(extension == "yaml" || extension == "yml") {
                "只支持 .yaml 或 .yml 文件：$fileName"
            }

            val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
                readWithLimit(input.readBytes())
            } ?: error("无法读取配置文件：$fileName")
            validateYaml(bytes, "配置文件 $fileName")
            PendingConfig(defaultLocalName(fileName), bytes)
        }

        val profiles = readProfiles()
        val added = pending.map { item ->
            val profile = ConfigProfile(
                id = UUID.randomUUID().toString(),
                name = item.name,
                type = TYPE_LOCAL,
                url = null,
                updatedAt = System.currentTimeMillis(),
            )
            writeAtomically(profileFile(profile.id), item.bytes)
            profiles += profile
            profile
        }

        writeProfiles(profiles)
        if (added.isNotEmpty()) {
            select(added.first().id)
        }
        return added
    }

    fun addSubscription(name: String, rawUrl: String, subscriptionNames: Map<String, String>? = null): ConfigProfile {
        require(name.isNotBlank()) { "订阅名称不能为空" }
        require(rawUrl.isNotBlank()) { "订阅链接不能为空" }

        val download = downloadSubscription(rawUrl)
        val bytes = download.bytes
        val profile = ConfigProfile(
            id = UUID.randomUUID().toString(),
            name = name,
            type = TYPE_SUBSCRIPTION,
            url = SubscriptionConfig.links(rawUrl).joinToString("\n"),
            updatedAt = System.currentTimeMillis(),
            subscriptionUserInfo = download.userInfo,
            subscriptionInfos = download.userInfos,
            subscriptionNames = subscriptionNames.orEmpty().filterKeys { it in SubscriptionConfig.links(rawUrl) }.mapValues { it.value.trim() },
        )
        val profiles = readProfiles()
        profiles += profile
        writeConfigAndProfiles(profile.id, bytes, profiles, download.sources)
        if (preferences.activeConfigId == null) select(profile.id)
        return profile
    }

    fun updateSubscription(
        id: String,
        name: String,
        rawUrl: String,
        subscriptionNames: Map<String, String>? = null,
    ): ConfigProfile {
        require(name.isNotBlank()) { "订阅名称不能为空" }
        require(rawUrl.isNotBlank()) { "订阅链接不能为空" }

        val profiles = readProfiles()
        val index = profiles.indexOfFirst { it.id == id }
        require(index >= 0) { "找不到订阅配置" }
        require(profiles[index].type == TYPE_SUBSCRIPTION) { "本地配置不能修改为订阅" }

        val download = downloadSubscription(rawUrl, profileFile(id).takeIf(File::isFile)?.readText(Charsets.UTF_8))
        val bytes = download.bytes
        val updated = profiles[index].copy(
            name = name,
            url = SubscriptionConfig.links(rawUrl).joinToString("\n"),
            updatedAt = System.currentTimeMillis(),
            subscriptionUserInfo = download.userInfo,
            subscriptionInfos = download.userInfos,
            subscriptionNames = (subscriptionNames ?: profiles[index].subscriptionNames).filterKeys { it in SubscriptionConfig.links(rawUrl) }.mapValues { it.value.trim() },
        )
        profiles[index] = updated
        writeConfigAndProfiles(id, bytes, profiles, download.sources)

        if (preferences.activeConfigId == id) {
            preferences.configFileName = updated.name
            QuickSettingsTileUpdater.request(context)
        }
        return updated
    }

    fun editSubscriptionAirport(id: String, oldUrl: String? = null, name: String? = null, url: String? = null, order: List<String>? = null): ConfigProfile {
        val profiles = readProfiles()
        val index = profiles.indexOfFirst { it.id == id }
        require(index >= 0) { "找不到订阅配置" }
        val profile = profiles[index]
        require(profile.type == TYPE_SUBSCRIPTION) { "这不是订阅配置" }
        val links = SubscriptionConfig.links(profile.url ?: error("订阅链接不存在"))
        val next = links.toMutableList()
        val names = profile.subscriptionNames.toMutableMap()
        val newUrl = url?.let { SubscriptionConfig.links(it).singleOrNull() ?: error("每个机场只能有一个订阅链接") }
        if (order != null) {
            require(order.size == links.size && order.toSet() == links.toSet()) { "机场排序无效" }
            next.clear()
            next.addAll(order)
        } else {
            if (oldUrl != null) require(oldUrl in links) { "找不到机场" }
            require(oldUrl != null || newUrl != null) { "订阅链接不能为空" }
            if (newUrl != null) {
                require(!name.isNullOrBlank()) { "机场名称不能为空" }
                require(newUrl == oldUrl || newUrl !in links) { "订阅链接重复" }
            }
            if (oldUrl == null) next.add(newUrl!!) else {
                val airportIndex = next.indexOf(oldUrl)
                if (newUrl == null) next.removeAt(airportIndex) else next[airportIndex] = newUrl
                names.remove(oldUrl)
            }
            if (newUrl != null) names[newUrl] = name!!.trim()
        }
        require(next.isNotEmpty()) { "删除最后一个机场时请删除配置" }
        val cache = subscriptionCacheFile(id)
        val cachedSources = if (cache.isFile) {
            val json = JSONObject(cache.readText(Charsets.UTF_8))
            json.keys().asSequence().associateWith { json.getString(it) }
        } else emptyMap()
        val download = downloadSubscription(
            next.joinToString("\n"), profileFile(id).takeIf(File::isFile)?.readText(Charsets.UTF_8),
            newUrl, cachedSources, profile.subscriptionInfos, downloadAll = false,
        )
        val updated = profile.copy(url = next.joinToString("\n"), updatedAt = System.currentTimeMillis(),
            subscriptionNames = names, subscriptionUserInfo = download.userInfo, subscriptionInfos = download.userInfos)
        profiles[index] = updated
        writeConfigAndProfiles(id, download.bytes, profiles, download.sources)
        return updated
    }

    fun refreshSubscription(id: String, url: String? = null): ConfigProfile {
        val profiles = readProfiles()
        val index = profiles.indexOfFirst { it.id == id }
        require(index >= 0) { "找不到订阅配置" }
        val profile = profiles[index]
        require(profile.type == TYPE_SUBSCRIPTION) { "这不是订阅配置" }
        val cache = subscriptionCacheFile(id)
        val cachedSources = if (url != null && cache.isFile) {
            val json = JSONObject(cache.readText(Charsets.UTF_8))
            json.keys().asSequence().associateWith { json.getString(it) }
        } else emptyMap()
        val download = downloadSubscription(
            profile.url ?: error("订阅链接不存在"),
            profileFile(id).takeIf(File::isFile)?.readText(Charsets.UTF_8),
            url, cachedSources, profile.subscriptionInfos,
        )
        val updated = profile.copy(updatedAt = System.currentTimeMillis(), subscriptionUserInfo = download.userInfo, subscriptionInfos = download.userInfos)
        profiles[index] = updated
        writeConfigAndProfiles(id, download.bytes, profiles, download.sources)
        return updated
    }

    fun getContent(id: String): String {
        val profile = readProfiles().firstOrNull { it.id == id } ?: error("找不到配置")
        val file = profileFile(profile.id)
        require(file.isFile) { "配置文件不存在" }
        require(file.length() <= MAX_CONFIG_BYTES) { "配置内容超过 8 MB" }
        return file.readText(Charsets.UTF_8).removePrefix("\uFEFF")
    }

    fun saveContent(id: String, content: String): ConfigProfile {
        val profiles = readProfiles()
        val index = profiles.indexOfFirst { it.id == id }
        require(index >= 0) { "找不到配置" }
        val bytes = content.removePrefix("\uFEFF").toByteArray(Charsets.UTF_8)
        validateYaml(bytes, "配置")
        val candidate = File.createTempFile("edit-", ".yaml", configsDirectory)
        try {
            candidate.writeBytes(bytes)
            MihomoProcess.validateConfig(context, candidate)
        } finally {
            candidate.delete()
        }
        val target = profileFile(id)
        if (target.isFile) target.copyTo(File(target.path + ".bak"), overwrite = true)
        val updated = profiles[index].copy(updatedAt = System.currentTimeMillis())
        profiles[index] = updated
        writeConfigAndProfiles(id, bytes, profiles)
        return updated
    }

    fun testSubscriptionUrl(id: String): Map<String, Any?> {
        val profile = readProfiles().firstOrNull { it.id == id } ?: error("找不到订阅配置")
        require(profile.type == TYPE_SUBSCRIPTION) { "这不是订阅配置" }
        val urls = SubscriptionConfig.links(profile.url ?: error("订阅链接不存在"))
        if (urls.size > 1) {
            val startedAt = System.nanoTime()
            val result = runCatching { downloadSubscription(urls.joinToString("\n")) }
            return mapOf(
                "success" to result.isSuccess,
                "responseTimeMs" to ((System.nanoTime() - startedAt) / 1_000_000).toInt(),
                "contentLength" to result.getOrNull()?.bytes?.size,
                "message" to (result.exceptionOrNull()?.message ?: "${urls.size} 个订阅链接有效，节点可合并"),
            )
        }
        val parsed = URL(urls.single())
        require(parsed.protocol == "http" || parsed.protocol == "https") { "订阅链接只支持 HTTP 或 HTTPS" }
        val startedAt = System.nanoTime()
        val connection = parsed.openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        connection.requestMethod = "GET"
        connection.setRequestProperty("User-Agent", "clash.meta")
        connection.setRequestProperty("Accept-Encoding", "gzip")
        try {
            val code = connection.responseCode
            val elapsed = ((System.nanoTime() - startedAt) / 1_000_000).toInt()
            val contentType = connection.contentType
            if (code !in 200..299) return mapOf(
                "success" to false, "responseTimeMs" to elapsed, "statusCode" to code,
                "contentLength" to connection.contentLength, "contentType" to contentType,
                "message" to "HTTP $code",
            )
            val raw = connection.inputStream
            val input = if (connection.contentEncoding?.contains("gzip", true) == true) GZIPInputStream(raw) else raw
            val bytes = input.use(::readStreamWithLimit)
            val validation = runCatching { buildSubscriptionConfig(bytes) }
            return mapOf(
                "success" to validation.isSuccess, "responseTimeMs" to elapsed,
                "statusCode" to code, "contentLength" to bytes.size,
                "contentType" to contentType,
                "message" to (validation.exceptionOrNull()?.message ?: "订阅内容有效"),
            )
        } finally {
            connection.disconnect()
        }
    }

    fun rename(id: String, rawName: String): ConfigProfile {
        val name = rawName.trim()
        require(name.isNotEmpty()) { "配置名称不能为空" }

        val profiles = readProfiles()
        val index = profiles.indexOfFirst { it.id == id }
        require(index >= 0) { "找不到配置" }

        val updated = profiles[index].copy(name = name)
        profiles[index] = updated
        writeProfiles(profiles)

        if (preferences.activeConfigId == id) {
            preferences.configFileName = updated.name
        }
        QuickSettingsTileUpdater.request(context)
        return updated
    }

    fun select(id: String) {
        val profile = readProfiles().firstOrNull { it.id == id }
            ?: error("找不到配置")
        require(profileFile(profile.id).isFile) { "配置文件不存在，请重新导入或更新订阅" }
        check(!ProxyVpnService.running && !ProxyVpnService.starting) { "请先停止代理再修改配置" }
        writeAtomically(File(mihomoDirectory, "runtime.yaml"),
            MihomoProcess.previewConfig(context, profileFile(id)).toByteArray(Charsets.UTF_8))
        preferences.activeConfigId = profile.id
        preferences.configFileName = profile.name
        QuickSettingsTileUpdater.request(context)
    }

    fun delete(id: String) {
        val profiles = readProfiles()
        val index = profiles.indexOfFirst { it.id == id }
        require(index >= 0) { "找不到配置" }

        profileFile(id).delete()
        subscriptionCacheFile(id).delete()
        profiles.removeAt(index)
        writeProfiles(profiles)

        if (preferences.activeConfigId == id) {
            val next = profiles.firstOrNull()
            preferences.activeConfigId = next?.id
            preferences.configFileName = next?.name
        }
        QuickSettingsTileUpdater.request(context)
    }

    private data class SubscriptionDownload(val bytes: ByteArray, val userInfo: String?, val sources: Map<String, String> = emptyMap(), val userInfos: Map<String, String> = emptyMap())

    private fun downloadSubscription(rawUrl: String, previousConfig: String? = null, selectedUrl: String? = null, cachedSources: Map<String, String> = emptyMap(), cachedUserInfos: Map<String, String> = emptyMap(), downloadAll: Boolean = true): SubscriptionDownload {
        val urls = SubscriptionConfig.links(rawUrl)
        require(selectedUrl == null || selectedUrl in urls) { "订阅链接不存在" }
        var totalBytes = 0L
        val sources = urls.mapIndexed { index, url ->
            val source = if ((!downloadAll && selectedUrl == null) || (selectedUrl != null && url != selectedUrl)) {
                val cached = cachedSources[url] ?: error("缺少机场节点缓存，请先更新该机场")
                SubscriptionDownload(cached.toByteArray(Charsets.UTF_8), cachedUserInfos[url])
            } else try {
                downloadSubscriptionSource(url)
            } catch (error: Exception) {
                if (urls.size == 1) throw error
                error("第 ${index + 1} 个订阅下载失败：${error.message ?: "连接失败"}；原配置已保留")
            }
            totalBytes += source.bytes.size
            require(totalBytes <= MAX_CONFIG_BYTES) { "订阅总内容超过 8 MB" }
            source
        }
        val merged = SubscriptionConfig.mergeSources(sources.map { it.bytes.toString(Charsets.UTF_8) })
        return SubscriptionDownload(
            buildSubscriptionConfig(merged.toByteArray(Charsets.UTF_8), previousConfig),
            sources.singleOrNull()?.userInfo,
            urls.zip(sources.map { it.bytes.toString(Charsets.UTF_8) }).toMap(),
            urls.zip(sources).mapNotNull { (url, source) -> source.userInfo?.let { url to it } }.toMap(),
        )
    }

    private fun downloadSubscriptionSource(rawUrl: String): SubscriptionDownload {
        val parsed = URL(rawUrl)
        require(parsed.protocol == "http" || parsed.protocol == "https") {
            "订阅链接只支持 http:// 或 https://"
        }

        val connection = parsed.openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = true
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        connection.requestMethod = "GET"
        connection.setRequestProperty("User-Agent", "clash.meta")
        connection.setRequestProperty(
            "Accept",
            "application/yaml, text/yaml, text/plain, application/octet-stream, */*",
        )
        connection.setRequestProperty("Accept-Encoding", "gzip")

        try {
            val code = connection.responseCode
            require(code in 200..299) { "订阅下载失败：HTTP $code" }

            val contentLength = connection.contentLengthLong
            require(contentLength <= MAX_CONFIG_BYTES || contentLength < 0) {
                "订阅内容超过 8 MB"
            }

            val rawInput = connection.inputStream
            val input = if (
                connection.contentEncoding?.contains("gzip", ignoreCase = true) == true
            ) {
                GZIPInputStream(rawInput)
            } else {
                rawInput
            }

            val bytes = input.use(::readStreamWithLimit)

            return SubscriptionDownload(
                bytes = bytes,
                userInfo = connection.getHeaderField("Subscription-Userinfo"),
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun writeConfigAndProfiles(id: String, bytes: ByteArray, profiles: List<ConfigProfile>, sources: Map<String, String>? = null) {
        check(!ProxyVpnService.running && !ProxyVpnService.starting) { "请先停止代理再修改配置" }
        val target = profileFile(id)
        val oldBytes = target.takeIf(File::isFile)?.readBytes()
        val cache = subscriptionCacheFile(id)
        val oldCache = if (sources != null) cache.takeIf(File::isFile)?.readBytes() else null
        val runtime = File(mihomoDirectory, "runtime.yaml")
        val syncRuntime = preferences.activeConfigId == id
        val oldRuntime = if (syncRuntime) runtime.takeIf(File::isFile)?.readBytes() else null
        writeAtomically(target, bytes)
        try {
            if (syncRuntime) {
                val generated = MihomoProcess.previewConfig(context, target).toByteArray(Charsets.UTF_8)
                writeAtomically(runtime, generated)
            }
            if (sources != null) writeAtomically(cache, JSONObject(sources).toString().toByteArray(Charsets.UTF_8))
            writeProfiles(profiles)
        } catch (error: Throwable) {
            if (sources != null) {
                if (oldCache == null) cache.delete() else writeAtomically(cache, oldCache)
            }
            if (oldBytes == null) target.delete() else writeAtomically(target, oldBytes)
            if (syncRuntime) {
                if (oldRuntime == null) runtime.delete() else writeAtomically(runtime, oldRuntime)
            }
            throw error
        }
    }

    private fun buildSubscriptionConfig(bytes: ByteArray, previousConfig: String? = null): ByteArray {
        validateYaml(bytes, "订阅")
        val template = context.assets.open(DEFAULT_CONFIG_ASSET).use {
            it.readBytes().toString(Charsets.UTF_8)
        }
        val generated = SubscriptionConfig.build(template, bytes.toString(Charsets.UTF_8), previousConfig)
            .toByteArray(Charsets.UTF_8)
        validateYaml(generated, "生成的订阅配置")
        return generated
    }

    private fun validateYaml(bytes: ByteArray, source: String) {
        require(bytes.isNotEmpty()) { "$source 内容为空" }
        require(bytes.size <= MAX_CONFIG_BYTES) { "$source 内容超过 8 MB" }

        val text = bytes.toString(Charsets.UTF_8).removePrefix("\uFEFF").trim()
        require(text.isNotEmpty()) { "$source 内容为空" }
        val start = text.take(1024).lowercase()
        require(!start.startsWith("<!doctype html") && !start.startsWith("<html")) {
            "$source 返回了 HTML 错误页"
        }
        require(!text.startsWith("{") && !text.startsWith("[")) {
            "$source 返回了 JSON 错误页"
        }
        require(MIHOMO_KEY_REGEX.containsMatchIn(text)) {
            "$source 没有返回 mihomo YAML；请确认机场提供 Mclash/Mihomo 订阅"
        }
    }

    private fun readStreamWithLimit(stream: java.io.InputStream): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(16 * 1024)
        var total = 0
        while (true) {
            val count = stream.read(buffer)
            if (count < 0) break
            total += count
            require(total <= MAX_CONFIG_BYTES) { "配置内容超过 8 MB" }
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private fun displayName(uri: Uri): String =
        context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (cursor.moveToFirst() && index >= 0) cursor.getString(index) else null
        } ?: uri.lastPathSegment?.substringAfterLast('/') ?: "config.yaml"

    private fun readWithLimit(bytes: ByteArray): ByteArray {
        require(bytes.size <= MAX_CONFIG_BYTES) { "配置文件超过 8 MB" }
        return bytes
    }

    private fun writeAtomically(target: File, bytes: ByteArray) {
        target.parentFile?.mkdirs()
        val temporary = File(target.parentFile, "${target.name}.tmp")
        val backup = File(target.parentFile, "${target.name}.bak")
        temporary.outputStream().use { output ->
            output.write(bytes)
            output.flush()
            output.fd.sync()
        }
        if (backup.exists()) backup.delete()
        if (target.exists() && !target.renameTo(backup)) {
            temporary.delete()
            error("无法备份旧配置")
        }
        if (!temporary.renameTo(target)) {
            if (backup.exists()) backup.renameTo(target)
            temporary.delete()
            error("无法保存配置")
        }
        backup.delete()
    }

    private fun subscriptionCacheFile(id: String): File = File(configsDirectory, "$id.subscriptions.json")

    private fun profileFile(id: String): File =
        File(configsDirectory, "$id.yaml")

    private fun readProfiles(): MutableList<ConfigProfile> {
        val array = runCatching { JSONArray(preferences.configProfilesJson) }
            .getOrElse { JSONArray() }
        val profiles = mutableListOf<ConfigProfile>()

        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            val id = item.optString("id")
            val name = item.optString("name")
            val type = item.optString("type")
            if (id.isBlank() || name.isBlank()) continue
            if (type != TYPE_LOCAL && type != TYPE_SUBSCRIPTION) continue

            val url = if (item.isNull("url")) {
                null
            } else {
                item.optString("url").takeIf { it.isNotEmpty() }
            }
            profiles += ConfigProfile(
                id = id,
                name = name,
                type = type,
                url = url,
                updatedAt = item.optLong("updatedAt", 0L),
                subscriptionUserInfo = if (item.isNull("subscriptionUserInfo")) null
                    else item.optString("subscriptionUserInfo"),
                subscriptionNames = item.optJSONObject("subscriptionNames")?.let { names ->
                    names.keys().asSequence().associateWith { names.getString(it) }
                }.orEmpty(),
                subscriptionInfos = item.optJSONObject("subscriptionInfos")?.let { infos ->
                    infos.keys().asSequence().associateWith { infos.getString(it) }
                }.orEmpty(),
            )
        }
        return profiles
    }

    private fun writeProfiles(profiles: List<ConfigProfile>) {
        val array = JSONArray()
        profiles.forEach { profile ->
            array.put(
                JSONObject()
                    .put("id", profile.id)
                    .put("name", profile.name)
                    .put("type", profile.type)
                    .put("url", profile.url ?: JSONObject.NULL)
                    .put("updatedAt", profile.updatedAt)
                    .put("subscriptionUserInfo", profile.subscriptionUserInfo ?: JSONObject.NULL)
                    .put("subscriptionNames", JSONObject(profile.subscriptionNames))
                    .put("subscriptionInfos", JSONObject(profile.subscriptionInfos)),
            )
        }
        preferences.configProfilesJson = array.toString()
    }

    private fun defaultLocalName(fileName: String): String {
        val withoutExtension = when {
            fileName.endsWith(".yaml", ignoreCase = true) -> fileName.dropLast(5)
            fileName.endsWith(".yml", ignoreCase = true) -> fileName.dropLast(4)
            else -> fileName
        }.trim()

        return withoutExtension.ifEmpty { "本地配置" }
    }

    private fun normalizeLocalProfileNames() {
        val profiles = readProfiles()
        var changed = false

        for (index in profiles.indices) {
            val profile = profiles[index]
            if (profile.type != TYPE_LOCAL) continue

            val normalized = defaultLocalName(profile.name)
            if (normalized != profile.name) {
                profiles[index] = profile.copy(name = normalized)
                changed = true
            }
        }

        if (!changed) return
        writeProfiles(profiles)

        val active = profiles.firstOrNull { it.id == preferences.activeConfigId }
        if (active != null) {
            preferences.configFileName = active.name
        }
        QuickSettingsTileUpdater.request(context)
    }

    private fun parseProxyGroupOrder(yaml: String): List<String> {
        val names = mutableListOf<String>()
        var inProxyGroups = false
        var baseIndent = -1

        for (line in yaml.lineSequence()) {
            if (line.trim().isEmpty()) continue

            val indent = line.indexOfFirst { !it.isWhitespace() }
                .takeIf { it >= 0 } ?: 0
            val trimmed = line.trim()

            if (!inProxyGroups) {
                if (Regex("""^proxy-groups\s*:""").containsMatchIn(trimmed)) {
                    inProxyGroups = true
                    baseIndent = indent
                }
                continue
            }

            if (indent <= baseIndent && !trimmed.startsWith("-")) break

            val candidate = when {
                trimmed.startsWith("-") -> {
                    val item = trimmed.removePrefix("-").trim()
                    when {
                        item.startsWith("name:") -> item.substringAfter("name:")
                        item.startsWith("{") -> INLINE_NAME_REGEX.find(item)
                            ?.groupValues
                            ?.getOrNull(1)
                        else -> null
                    }
                }
                trimmed.startsWith("name:") -> trimmed.substringAfter("name:")
                else -> null
            }

            cleanYamlValue(candidate)?.let { name ->
                if (name.isNotEmpty()) names += name
            }
        }

        return names.distinct()
    }

    private fun cleanYamlValue(value: String?): String? {
        if (value == null) return null
        return value
            .substringBefore(" #")
            .substringBefore(",")
            .trim()
            .trim('"', '\'')
            .trim()
    }

    private fun migrateLegacyConfig() {
        configsDirectory.mkdirs()
        if (readProfiles().isNotEmpty()) return
        if (!legacyConfigFile.isFile || legacyConfigFile.length() <= 0) return

        val profile = ConfigProfile(
            id = UUID.randomUUID().toString(),
            name = preferences.configFileName ?: "config.yaml",
            type = TYPE_LOCAL,
            url = null,
            updatedAt = legacyConfigFile.lastModified().takeIf { it > 0 }
                ?: System.currentTimeMillis(),
        )
        writeAtomically(profileFile(profile.id), legacyConfigFile.readBytes())
        writeProfiles(listOf(profile))
        preferences.activeConfigId = profile.id
        preferences.configFileName = profile.name
        legacyConfigFile.delete()
    }

    companion object {
        const val TYPE_LOCAL = "local"
        const val TYPE_SUBSCRIPTION = "subscription"
        private const val DEFAULT_CONFIG_ASSET = "default-config.yaml"
        private const val MAX_CONFIG_BYTES = 8 * 1024 * 1024
        private val MIHOMO_KEY_REGEX = Regex(
            "(?m)^\\s*(proxies|proxy-providers|proxy-groups|rules|rule-providers|mixed-port|port|socks-port|mode|dns|tun)\\s*:",
        )
        private val INLINE_NAME_REGEX = Regex("""(?:^|[,{]\s*)name\s*:\s*([^,}]+)""")
    }
}
