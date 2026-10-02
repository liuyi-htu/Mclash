package com.liuyihtu.mclash.root

import java.nio.file.Files
import java.io.File
import org.junit.Assert.*
import org.junit.Test

class BundledDashboardTest {
    @Test fun interruptedInstallRetriesAndRevisionUpdateReplacesAssets() {
        val home = Files.createTempDirectory("dashboard-test").toFile()
        val manifest = """{"revision":"one","files":["index.html","_nuxt/app.js"]}"""
        try {
            try {
                BundledDashboard.install(home, manifest) { path ->
                    if (path.endsWith("app.js")) error("interrupted")
                    "old".toByteArray()
                }
                fail("install should fail")
            } catch (_: IllegalStateException) { }
            assertFalse(File(home, "dashboard/bundle.json").exists())
            BundledDashboard.install(home, manifest) { "restored".toByteArray() }
            assertEquals("restored", File(home, "dashboard/_nuxt/app.js").readText())
            BundledDashboard.install(home, manifest) { error("must reuse installed resources") }
            BundledDashboard.install(home, manifest.replace("one", "two")) { "updated".toByteArray() }
            assertEquals("updated", File(home, "dashboard/index.html").readText())
        } finally { home.deleteRecursively() }
    }

    @Test fun resourceCannotEscapeDashboardDirectory() {
        val home = Files.createTempDirectory("dashboard-test").toFile()
        try {
            try {
                BundledDashboard.install(home, """{"files":["../outside"]}""") { byteArrayOf(1) }
                fail("invalid path accepted")
            } catch (_: IllegalArgumentException) { }
            assertFalse(File(home, "outside").exists())
        } finally { home.deleteRecursively() }
    }
}
