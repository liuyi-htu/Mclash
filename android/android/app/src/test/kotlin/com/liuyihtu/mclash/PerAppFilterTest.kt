package com.liuyihtu.mclash

import org.junit.Assert.*
import org.junit.Test

class PerAppFilterTest {
    private val own = "com.liuyihtu.mclash"

    private fun apply(only: Boolean, selected: Set<String>, installed: Set<String>): Pair<List<String>, List<String>> {
        val allowed = mutableListOf<String>()
        val disallowed = mutableListOf<String>()
        PerAppFilter.apply(only, selected, own,
            isInstalled = { it in installed },
            allow = { allowed += it; true },
            disallow = { if (it in installed) { disallowed += it; true } else false })
        return allowed to disallowed
    }

    @Test fun onlySelectedIncludesInstalledPackagesWithoutSelf() {
        assertEquals(listOf("a", "b") to emptyList<String>(),
            apply(true, setOf("b", own, "a"), setOf("a", "b", own)))
    }

    @Test fun partiallyUninstalledAllowListKeepsOnlyInstalledPackages() {
        assertEquals(listOf("b"), apply(true, setOf("a", "b"), setOf("b")).first)
    }

    @Test fun emptyAllowListFailsClosed() { assertThrows(IllegalArgumentException::class.java) { apply(true, emptySet(), setOf(own)) } }
    @Test fun fullyUninstalledAllowListFailsClosed() { assertThrows(IllegalArgumentException::class.java) { apply(true, setOf("gone"), setOf(own)) } }
    @Test fun selfOnlyFailsClosed() { assertThrows(IllegalArgumentException::class.java) { apply(true, setOf(own), setOf(own)) } }
    @Test fun selfPlusUninstalledFailsClosed() { assertThrows(IllegalArgumentException::class.java) { apply(true, setOf(own, "gone"), setOf(own)) } }

    @Test fun reinstalledPackageIsReconsideredOnNextStart() {
        assertThrows(IllegalArgumentException::class.java) { apply(true, setOf("a"), emptySet()) }
        assertEquals(listOf("a"), apply(true, setOf("a"), setOf("a")).first)
    }

    @Test fun excludeSelectedAlwaysExcludesSelfAndSkipsUninstalled() {
        assertEquals(emptyList<String>() to listOf(own, "a"),
            apply(false, setOf("a", "gone", own), setOf("a", own)))
        assertEquals(listOf(own), apply(false, emptySet(), setOf(own)).second)
    }

    @Test fun selfExclusionFailureMustNotPermitRoutingLoop() {
        assertThrows(IllegalStateException::class.java) { apply(false, setOf("a"), setOf("a")) }
    }

    @Test fun unexpectedBuilderFailurePropagates() {
        assertThrows(SecurityException::class.java) {
            PerAppFilter.apply(true, setOf("a"), own, { true }, { throw SecurityException("denied") }, { true })
        }
    }
    @Test fun builderAcceptingUnknownNamesStillCannotStartWithUninstalledSelection() {
        var builderCalls = 0
        assertThrows(IllegalArgumentException::class.java) {
            PerAppFilter.apply(true, setOf("gone"), own,
                isInstalled = { false },
                allow = { builderCalls++; true },
                disallow = { true })
        }
        assertEquals(0, builderCalls)
    }

    @Test fun packageRemovedBetweenLookupAndBuilderAdditionStillFailsClosed() {
        assertThrows(IllegalArgumentException::class.java) {
            PerAppFilter.apply(true, setOf("removed"), own,
                isInstalled = { true },
                allow = { false },
                disallow = { true })
        }
    }

}
