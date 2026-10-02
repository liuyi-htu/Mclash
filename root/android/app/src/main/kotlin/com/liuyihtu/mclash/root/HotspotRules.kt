package com.liuyihtu.mclash.root

/** Only interfaces reported as tethered by Android are intercepted. */
internal object HotspotRules {
    // RootShell bounds captured output. Exclude the large historical event log
    // so the live tether state cannot be truncated from the beginning.
    val SNAPSHOT_COMMAND = """
        set -eu
        dumpsys tethering | sed -n '/Tether state:/,/Hardware offload:/p'
        ip -o -4 addr show | awk '{split(${'$'}4, address, "/"); print "MCLASH_LOCAL_IPV4 " address[1]}'
    """.trimIndent()

    data class Snapshot(val interfaces: Set<String>, val localAddresses: Set<String>)

    fun snapshot(output: String): Snapshot {
        val addresses = output.lineSequence()
            .filter { it.startsWith("MCLASH_LOCAL_IPV4 ") }
            .map { it.removePrefix("MCLASH_LOCAL_IPV4 ").trim() }
            .toSet()
        require(addresses.isNotEmpty() && addresses.all(::validIpv4)) {
            "无法读取本机 IPv4 地址，未安装热点接管规则"
        }
        return Snapshot(interfaces(output), addresses)
    }

    private fun validIpv4(address: String): Boolean {
        val octets = address.split('.')
        return octets.size == 4 && octets.all { octet ->
            octet.isNotEmpty() && octet.all { it in '0'..'9' } &&
                octet.toIntOrNull() in 0..255
        }
    }
    private const val DATA = "MCLASH_R_HOT"
    private const val DNS = "MCLASH_R_HDNS"
    private const val V6 = "MCLASH_R_HV6"
    private val chains = listOf(
        Triple("iptables", "mangle", DATA),
        Triple("iptables", "nat", DNS),
        Triple("ip6tables", "filter", V6),
    )
    private val ifacePattern = Regex("[a-zA-Z0-9_.-]{1,15}")

    fun interfaces(dump: String): Set<String> =
        Regex("(?m)^\\s*([a-zA-Z0-9_.-]{1,15})\\s+-\\s+TetheredState\\s+-")
            .findAll(dump).map { it.groupValues[1] }.filter { it != "lo" }.toSet()

    fun install(): String = buildString {
        for ((tool, table, chain) in chains) {
            val hook = if (tool == "ip6tables") "FORWARD" else "PREROUTING"
            appendLine("$tool -w 5 -t $table -N $chain")
            appendLine("$tool -w 5 -t $table -I $hook 1 -j $chain")
        }
    }

    fun update(interfaces: Set<String>, bypassLan: Boolean, localAddresses: Set<String> = setOf("127.0.0.1")): String {
        require(interfaces.all { it != "lo" && ifacePattern.matches(it) })
        require(localAddresses.all(::validIpv4)) { "本机 IPv4 地址无效" }
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
            for (protocol in listOf("tcp", "udp")) {
                data += "-A $DATA -i $iface -p $protocol -j TPROXY --on-ip 127.0.0.1 --on-port ${RootRuntimeConfig.TPROXY_PORT} --tproxy-mark ${TProxyRules.CAPTURE}"
                // IPv4-only proxy: prevent a hotspot client from bypassing it
                // over IPv6 while allowing router discovery and other ICMPv6.
                ipv6 += "-A $V6 -i $iface -p $protocol -j REJECT"
            }
        }
        return buildString {
            appendLine("set -eu")
            for ((tool, table, rules) in listOf(
                Triple("iptables-restore", "mangle", data),
                Triple("iptables-restore", "nat", dns),
                Triple("ip6tables-restore", "filter", ipv6),
            )) {
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
        for ((tool, table, chain) in chains) {
            val hook = if (tool == "ip6tables") "FORWARD" else "PREROUTING"
            appendLine("while $tool -w 5 -t $table -C $hook -j $chain 2>/dev/null; do")
            appendLine("  $tool -w 5 -t $table -D $hook -j $chain || break")
            appendLine("done")
            appendLine("$tool -w 5 -t $table -F $chain 2>/dev/null")
            appendLine("$tool -w 5 -t $table -X $chain 2>/dev/null")
        }
    }

    fun verifyCleanup(): String = buildString {
        for ((tool, table, chain) in chains) {
            appendLine("$tool -w 5 -t $table -S $chain >/dev/null 2>&1 && failed=1")
        }
    }
}
