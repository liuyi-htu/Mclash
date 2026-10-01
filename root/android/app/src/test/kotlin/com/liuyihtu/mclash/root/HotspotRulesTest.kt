package com.liuyihtu.mclash.root

import org.junit.Assert.*
import org.junit.Test

class HotspotRulesTest {
    @Test fun detectsOnlyActiveTetheredInterfaces() {
        val dump = """
              Tether state:
                wlan0 - AvailableState - lastError = 0
                wlan2 - TetheredState - lastError = 0
                rndis0 - TetheredState - lastError = 0
                Current upstream interface(s): [rmnet_data4]
              Log:
                previously wlan1 - TetheredState - lastError = 0
        """.trimIndent()
        assertEquals(setOf("wlan2", "rndis0"), HotspotRules.interfaces(dump))
    }

    @Test fun capturesHotspotTcpUdpAndDnsWithoutCapturingUpstreamOrLocalServices() {
        val script = HotspotRules.update(setOf("wlan2"), true)
        assertFalse(script.contains("rmnet"))
        assertTrue(script.contains("--noflush"))
        assertTrue(script.contains("-i wlan2 -m addrtype --dst-type LOCAL -j RETURN"))
        assertTrue(script.contains("-i wlan2 -d 255.255.255.255/32 -j RETURN"))
        for (protocol in listOf("tcp", "udp")) {
            assertTrue(script.contains("-i wlan2 -p $protocol -j TPROXY"))
            assertTrue(script.contains("-i wlan2 -p $protocol --dport 53 -j REDIRECT --to-ports 11053"))
            assertTrue(script.contains("-A MCLASH_R_HV6 -i wlan2 -p $protocol -j REJECT"))
        }
    }

    @Test fun closingHotspotRemovesInterfaceRulesButRetainsOwnEmptyChains() {
        val script = HotspotRules.update(emptySet(), true)
        assertFalse(script.contains("-A "))
        assertTrue(script.contains("-F MCLASH_R_HOT"))
        assertTrue(script.contains("-F MCLASH_R_HDNS"))
        assertTrue(script.contains("-F MCLASH_R_HV6"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsUntrustedInterfaceNames() {
        HotspotRules.update(setOf("wlan2;id"), true)
    }
}
