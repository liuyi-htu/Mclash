package com.liuyihtu.mclash.root

import android.content.Context
import java.io.File
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.constructor.SafeConstructor

/** Install the pinned offline dashboard before starting the local controller. */
internal object BundledDashboard {
    fun install(context: Context, home: File) {
        val manifest = context.assets.open("dashboard/bundle.json").bufferedReader().use { it.readText() }
        install(home, manifest) { path -> context.assets.open("dashboard/$path").use { it.readBytes() } }
    }

    internal fun install(home: File, manifest: String, load: (String) -> ByteArray) {
        val directory = File(home, "dashboard").apply { mkdirs() }
        val marker = File(directory, "bundle.json")
        if (marker.isFile && marker.readText() == manifest && File(directory, "index.html").isFile) return
        val document = Yaml(SafeConstructor(LoaderOptions())).load<Map<String, Any>>(manifest)
        val files = document["files"] as List<*>
        for (entry in files) {
            val path = entry as String
            val target = File(directory, path)
            require(target.canonicalPath.startsWith(directory.canonicalPath + File.separator)) {
                "本地面板资源路径无效"
            }
            target.parentFile!!.mkdirs()
            val temporary = File(target.parentFile, ".${target.name}.tmp")
            temporary.writeBytes(load(path))
            if (!temporary.renameTo(target)) {
                temporary.copyTo(target, overwrite = true)
                temporary.delete()
            }
        }
        // Remove obsolete resources only after the new bundle is installed.
        val previous = runCatching {
            Yaml(SafeConstructor(LoaderOptions())).load<Map<String, Any>>(marker.readText())["files"] as List<*>
        }.getOrDefault(emptyList<Any>())
        for (entry in previous) {
            if (entry !is String || entry in files) continue
            val obsolete = File(directory, entry)
            if (obsolete.canonicalPath.startsWith(directory.canonicalPath + File.separator)) obsolete.delete()
        }
        // Write the revision last so an interrupted install is retried.
        marker.writeText(manifest)
    }
}
