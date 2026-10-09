package com.liuyihtu.mclash.root

import org.junit.Assert.*
import org.junit.Test

class RootTrafficStatsTest {
    @Test fun preservesCoreRatesAndLongCounters() {
        val result = RootTrafficStats.decode(mapOf("up" to 12L, "down" to 34L, "upTotal" to 5_000_000_000L, "downTotal" to 6_000_000_000L))
        assertEquals(12L, result["txBytesPerSecond"])
        assertEquals(34L, result["rxBytesPerSecond"])
        assertEquals(5_000_000_000L, result["txBytes"])
        assertEquals(6_000_000_000L, result["rxBytes"])
    }
    @Test fun olderCoreUsesConnectionsTotalsWithoutRecalculatingRates() {
        val result = RootTrafficStats.decode(mapOf("up" to 9L, "down" to 2L), mapOf("uploadTotal" to 800L, "downloadTotal" to 900L))
        assertEquals(800L, result["txBytes"])
        assertEquals(900L, result["rxBytes"])
        assertEquals(9L, result["txBytesPerSecond"])
    }
    @Test fun coreCounterResetIsAccepted() {
        val result = RootTrafficStats.decode(mapOf("upTotal" to 0L, "downTotal" to 0L, "up" to 0L, "down" to 0L))
        assertTrue(result.values.all { it == 0L })
    }
}
