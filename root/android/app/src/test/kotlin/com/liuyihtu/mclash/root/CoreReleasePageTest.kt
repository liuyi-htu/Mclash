package com.liuyihtu.mclash.root

import org.junit.Assert.*
import org.junit.Test

class CoreReleasePageTest {
    @Test fun acceptsOnlyOfficialStableRedirect() {
        assertEquals("v1.19.32", CoreReleasePage.version("https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.32"))
        for (url in listOf("https://example.com/MetaCubeX/mihomo/releases/tag/v1.19.32",
            "https://github.com/MetaCubeX/mihomo/releases/tag/Prerelease")) {
            assertThrows(IllegalStateException::class.java) { CoreReleasePage.version(url) }
        }
    }

    @Test fun selectsExactArm64DigestRegardlessOfAttributeOrder() {
        val hash = "sha256:" + "a".repeat(64)
        val html = """<clipboard-copy value="$hash" aria-label="Copy to clipboard digest for mihomo-android-arm64-v8-v1.19.32.gz"></clipboard-copy>
            <clipboard-copy value="sha256:${"b".repeat(64)}" aria-label="Copy to clipboard digest for mihomo-linux-arm64-v1.19.32.gz"></clipboard-copy>"""
        assertEquals(hash, CoreReleasePage.digest("v1.19.32", html))
        assertThrows(IllegalArgumentException::class.java) { CoreReleasePage.digest("v1.19.31", html) }
        assertThrows(IllegalArgumentException::class.java) { CoreReleasePage.digest("v1.19.32", html + html) }
    }
}
