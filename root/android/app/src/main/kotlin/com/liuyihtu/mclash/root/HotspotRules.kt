package com.liuyihtu.mclash.root

import java.net.Inet6Address
import java.net.InetAddress

/** Only interfaces reported as tethered by Android are intercepted. */
internal object HotspotRules {
    // RootShell bounds captured output. Exclude the large historical event log
    // so the live tether state cannot be truncated from the beginning.
    val SNAPSHOT_COMMAND = """
        set -eu
        dumpsys tethering | sed -n '/Tether state:/,/Hardware offload:/p'
        ip -o -4 addr show | awk '{split(${'$'}4, address, "/"); print "MCLASH_LOCAL_IPV4 " address[1]}'
        ip -o -6 addr show | awk '{split(${'$'}4, address, "/"); print "MCLASH_LOCAL_IPV6 " address[1]}'
    """.trimIndent()

    data class Snapshot(val interfaces: Set<String>, val localAddresses: Set<String>, val localIpv6Addresses: Set<String> = emptySet())

    fun snapshot(output: String): Snapshot {
        val addresses = output.lineSequence()
            .filter { it.startsWith("MCLASH_LOCAL_IPV4 ") }
            .map { it.removePrefix("MCLASH_LOCAL_IPV4 ").trim() }
            .toSet()
        require(addresses.isNotEmpty() && addresses.all(::validIpv4)) {
            "无法读取本机 IPv4 地址，未安装热点接管规则"
        }
        val v6 = output.lineSequence().filter { it.startsWith("MCLASH_LOCAL_IPV6 ") }
            .map { it.removePrefix("MCLASH_LOCAL_IPV6 ").trim() }.toSet()
        require(v6.all(::validIpv6)) { "本机 IPv6 地址无效" }
        return Snapshot(interfaces(output), addresses, v6)
    }

    private fun validIpv4(address: String): Boolean {
        val octets = address.split('.')
        return octets.size == 4 && octets.all { octet ->
            octet.isNotEmpty() && octet.all { it in '0'..'9' } &&
                octet.toIntOrNull() in 0..255
        }
    }
    private fun validIpv6(address: String): Boolean =
        address.contains(':') && address.matches(Regex("[0-9a-fA-F:]+")) &&
            runCatching { InetAddress.getByName(address) is Inet6Address }.getOrDefault(false)

    private const val DATA6 = "MCLASH_R_HOT6"
    private const val DNS6 = "MCLASH_R_HDNS6"
    private const val DATA = "MCLASH_R_HOT"
    private const val DNS = "MCLASH_R_HDNS"
    private const val V6 = "MCLASH_R_HV6"
    private val chains = listOf(
        Triple("iptables", "mangle", DATA),
        Triple("iptables", "nat", DNS),
        Triple("ip6tables", "filter", V6),
    )
    private val ipv6Chains = listOf(
        Triple("ip6tables", "mangle", DATA6),
        Triple("ip6tables", "mangle", DNS6),
    )
    private val ifacePattern = Regex("[a-zA-Z0-9_.-]{1,15}")

    fun interfaces(dump: String): Set<String> =
        Regex("(?m)^\\s*([a-zA-Z0-9_.-]{1,15})\\s+-\\s+TetheredState\\s+-")
            .findAll(dump).map { it.groupValues[1] }.filter { it != "lo" }.toSet()

    fun install(ipv6: Boolean = false): String = buildString {
        for ((tool, table, chain) in chains + if (ipv6) ipv6Chains else emptyList()) {
            val hook = if (table == "filter") "FORWARD" else "PREROUTING"
            appendLine("$tool -w 5 -t $table -N $chain")
            appendLine("$tool -w 5 -t $table -I $hook 1 -j $chain")
        }
    }

    fun update(interfaces: Set<String>, bypassLan: Boolean, localAddresses: Set<String> = setOf("127.0.0.1"), ipv6Enabled: Boolean = false, localIpv6Addresses: Set<String> = emptySet()): String {
        require(interfaces.all { it != "lo" && ifacePattern.matches(it) })
        require(localAddresses.all(::validIpv4)) { "本机 IPv4 地址无效" }
        require(localIpv6Addresses.all(::validIpv6)) { "本机 IPv6 地址无效" }
        val data6 = mutableListOf("-F $DATA6")
        val dns6 = mutableListOf("-F $DNS6")
        val data = mutableListOf("-F $DATA")
        val dns = mutableListOf("-F $DNS")
        val ipv6 = mutableListOf("-F $V6")
        for (iface in interfaces.sorted()) {
            // DNS is redirected in nat PREROUTING. DHCP and access to the phone
            // or another local peer must retain Android's normal handling.
            for (protocol in listOf("tcp", "udp")) {
                data += "-A $DATA -i $iface -p $protocol --dport 53 -j RETURN"
                dns += "-A $DNS -i $iface -p $protocol --dport 53 -j REDIRECT --to-ports ${RootRuntimeConfig.DNS_PORT}"
            }
            // Some Android builds omit the addrtype userspace extension.
            // Explicit local addresses preserve access to the phone without it.
            for (address in localAddresses.sorted()) {
                data += "-A $DATA -i $iface -d $address/32 -j RETURN"
            }
            for (subnet in listOf("224.0.0.0/4", "255.255.255.255/32")) {
                data += "-A $DATA -i $iface -d $subnet -j RETURN"
            }
            if (bypassLan) {
                for (subnet in listOf("0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16")) {
                    data += "-A $DATA -i $iface -d $subnet -j RETURN"
                }
            }
            if (ipv6Enabled) {
                for (protocol in listOf("tcp", "udp")) {
                    data6 += "-A $DATA6 -i $iface -p $protocol --dport 53 -j RETURN"
                    dns6 += "-A $DNS6 -i $iface -p $protocol --dport 53 -j TPROXY --on-ip ::1 --on-port ${RootRuntimeConfig.IPV6_DNS_TPROXY_PORT} --tproxy-mark ${TProxyRules.CAPTURE}"
                }
                for (address in localIpv6Addresses.sorted()) {
                    data6 += "-A $DATA6 -i $iface -d $address/128 -j RETURN"
                }
                for (subnet in listOf("::1/128", "fe80::/10", "ff00::/8") + if (bypassLan) listOf("fc00::/7") else emptyList()) {
                    data6 += "-A $DATA6 -i $iface -d $subnet -j RETURN"
                }
                for (port in listOf(546, 547)) {
                    data6 += "-A $DATA6 -i $iface -p udp --dport $port -j RETURN"
                }
                for (protocol in listOf("tcp", "udp")) {
                    data6 += "-A $DATA6 -i $iface -p $protocol -j TPROXY --on-ip ::1 --on-port ${RootRuntimeConfig.TPROXY_PORT} --tproxy-mark ${TProxyRules.CAPTURE}"
                }
            }
            for (protocol in listOf("tcp", "udp")) {
                data += "-A $DATA -i $iface -p $protocol -j TPROXY --on-ip 127.0.0.1 --on-port ${RootRuntimeConfig.TPROXY_PORT} --tproxy-mark ${TProxyRules.CAPTURE}"
                if (!ipv6Enabled) ipv6 += "-A $V6 -i $iface -p $protocol -j REJECT"
            }
        }
        return buildString {
            appendLine("set -eu")
            for ((tool, table, rules) in listOf(
                Triple("iptables-restore", "mangle", data),
                Triple("iptables-restore", "nat", dns),
                Triple("ip6tables-restore", "filter", ipv6),
            ) + if (ipv6Enabled) listOf(
                Triple("ip6tables-restore", "mangle", data6),
                Triple("ip6tables-restore", "mangle", dns6),
            ) else emptyList()) {
                // Commit each table atomically without flushing Android chains.
                appendLine("$tool -w 5 --noflush <<'MCLASH_HOTSPOT'")
                appendLine("*$table")
                rules.forEach(::appendLine)
                appendLine("COMMIT")
                appendLine("MCLASH_HOTSPOT")
            }
        }
    }

    fun cleanup(): String = buildString {
        for ((tool, table, chain) in chains + ipv6Chains) {
            val hook = if (table == "filter") "FORWARD" else "PREROUTING"
            appendLine("while $tool -w 5 -t $table -C $hook -j $chain 2>/dev/null; do")
            appendLine("  $tool -w 5 -t $table -D $hook -j $chain || break")
            appendLine("done")
            appendLine("$tool -w 5 -t $table -F $chain 2>/dev/null")
            appendLine("$tool -w 5 -t $table -X $chain 2>/dev/null")
        }
    }

    fun verifyCleanup(): String = buildString {
        for ((tool, table, chain) in chains + ipv6Chains) {
            appendLine("$tool -w 5 -t $table -S $chain >/dev/null 2>&1 && failed=1")
        }
    }
}
