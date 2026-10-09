package com.liuyihtu.mclash.root

import org.junit.Assert.*
import org.junit.Test

class HotspotRulesTest {
    @Test fun ipv6HotspotCapturesDataAndDnsWhilePreservingLocalServices() {
        val script = HotspotRules.update(setOf("wlan2"), false, ipv6Enabled = true,
            localIpv6Addresses = setOf("2001:db8::1"))
        assertTrue(script.contains("-A MCLASH_R_HOT6 -i wlan2 -d 2001:db8::1/128 -j RETURN"))
        assertTrue(script.contains("-A MCLASH_R_HDNS6 -i wlan2 -p udp --dport 53 -j TPROXY --on-ip ::1 --on-port 17895"))
        assertTrue(script.contains("-A MCLASH_R_HOT6 -i wlan2 -p udp -j TPROXY --on-ip ::1"))
        assertTrue(script.contains("-d fe80::/10 -j RETURN"))
        assertTrue(script.contains("--dport 547 -j RETURN"))
        assertFalse(script.contains("-d fc00::/7 -j RETURN"))
        assertFalse(script.contains("-j REJECT"))
        val snapshot = HotspotRules.snapshot("wlan2 - TetheredState -\nMCLASH_LOCAL_IPV4 127.0.0.1\nMCLASH_LOCAL_IPV6 2001:db8::1")
        assertEquals(setOf("2001:db8::1"), snapshot.localIpv6Addresses)
    }

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
        val script = HotspotRules.update(setOf("wlan2"), true, setOf("127.0.0.1", "192.168.241.201"))
        assertFalse(script.contains("rmnet"))
        assertTrue(script.contains("--noflush"))
        assertFalse(script.contains("addrtype"))
        assertTrue(script.contains("-i wlan2 -d 192.168.241.201/32 -j RETURN"))
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
    @Test fun snapshotTracksLocalAddressesAlongsideTetherState() {
        val output = """
            Tether state:
              wlan0 - AvailableState - lastError = 0
              wlan2 - TetheredState - lastError = 0
            MCLASH_LOCAL_IPV4 127.0.0.1
            MCLASH_LOCAL_IPV4 100.84.162.133
            MCLASH_LOCAL_IPV4 192.168.241.201
        """.trimIndent()
        val state = HotspotRules.snapshot(output)
        assertEquals(setOf("wlan2"), state.interfaces)
        assertEquals(setOf("127.0.0.1", "100.84.162.133", "192.168.241.201"), state.localAddresses)
        assertNotEquals(state, HotspotRules.snapshot(output.replace("192.168.241.201", "192.168.100.1")))
    }

    @Test fun localPhoneServicesRemainReachableWhenLanBypassIsDisabled() {
        val script = HotspotRules.update(setOf("wlan2"), false, setOf("192.168.241.201", "100.84.162.133"))
        assertFalse(script.contains("addrtype"))
        assertFalse(script.contains("-d 192.168.0.0/16"))
        assertTrue(script.contains("-i wlan2 -d 192.168.241.201/32 -j RETURN"))
        assertTrue(script.contains("-i wlan2 -d 100.84.162.133/32 -j RETURN"))
        assertTrue(script.indexOf("--dport 53 -j RETURN") < script.indexOf("-d 192.168.241.201/32"))
        assertTrue(script.indexOf("-d 192.168.241.201/32") < script.indexOf("-j TPROXY"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun snapshotWithoutLocalAddressesFailsClosed() {
        HotspotRules.snapshot("wlan2 - TetheredState - lastError = 0")
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsInvalidLocalAddresses() {
        HotspotRules.update(setOf("wlan2"), false, setOf("192.168.0.1;id"))
    }

}
