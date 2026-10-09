package com.liuyihtu.mclash.root

/** IPv6 uses the same UID policy and private routing mark as IPv4. */
internal object Ipv6TProxyRules {
    private const val OUT = "MCLASH_R_OUT6"
    private const val PRE = "MCLASH_R_PRE6"
    private const val DNS = "MCLASH_R_DNS6"
    private const val BYPASS = "0x40000000/0x40000000"

    fun install(appUid: Int, onlySelected: Boolean, selectedUids: Set<Int>, bypassLan: Boolean): String = buildString {
        val capture = TProxyRules.CAPTURE
        val table = TProxyRules.TABLE
        val priority = TProxyRules.PRIORITY
        appendLine("ip6tables -w 5 -t mangle -S >/dev/null || { echo '设备不支持 IPv6 mangle 表'; exit 1; }")
        appendLine("[ -z \"${'$'}(ip -6 rule show | awk '${'$'}1 == \"$priority:\" {print}')\" ] || { echo 'IPv6 策略路由优先级 $priority 已占用'; exit 1; }")
        appendLine("[ -z \"${'$'}(ip -6 route show table $table 2>/dev/null)\" ] || { echo 'IPv6 路由表 $table 已占用'; exit 1; }")
        appendLine("ip6tables -w 5 -t mangle -N $OUT")
        appendLine("ip6tables -w 5 -t mangle -N $PRE")
        appendLine("ip6tables -w 5 -t mangle -N $DNS")
        for (match in listOf("-m mark --mark $BYPASS", "-m owner --uid-owner $appUid")) {
            appendLine("ip6tables -w 5 -t mangle -A $OUT $match -j MARK --set-xmark 0x0/0x20000000")
            appendLine("ip6tables -w 5 -t mangle -A $OUT $match -j RETURN")
        }
        for (match in listOf("-m mark --mark $BYPASS", "-m owner --uid-owner $appUid")) {
            appendLine("ip6tables -w 5 -t mangle -A $DNS $match -j RETURN")
        }
        // Capture netd DNS before UID 0 bypass, without requiring IPv6 NAT.
        appendLine("ip6tables -w 5 -t mangle -A $OUT -j $DNS")
        for (protocol in listOf("tcp", "udp")) {
            appendLine("ip6tables -w 5 -t mangle -A $OUT -p $protocol --dport 53 -j RETURN")
            appendLine("ip6tables -w 5 -t mangle -A $DNS -p $protocol --dport 53 -j MARK --set-xmark $capture")
        }
        appendLine("ip6tables -w 5 -t mangle -A $OUT -m owner --uid-owner 0 -j MARK --set-xmark 0x0/0x20000000")
        appendLine("ip6tables -w 5 -t mangle -A $OUT -m owner --uid-owner 0 -j RETURN")
        // Link-local, multicast, DHCPv6 and neighbor discovery remain with Android.
        for (subnet in listOf("::1/128", "fe80::/10", "ff00::/8") + if (bypassLan) listOf("fc00::/7") else emptyList()) {
            appendLine("ip6tables -w 5 -t mangle -A $OUT -d $subnet -j RETURN")
        }
        if (!onlySelected) for (uid in selectedUids.sorted()) {
            appendLine("ip6tables -w 5 -t mangle -A $OUT -m owner --uid-owner $uid -j RETURN")
        }
        val owners = if (onlySelected) selectedUids.sorted().map { " -m owner --uid-owner $it" } else listOf("")
        for (owner in owners) for (protocol in listOf("tcp", "udp")) {
            appendLine("ip6tables -w 5 -t mangle -A $OUT -p $protocol$owner -j MARK --set-xmark $capture")
        }
        for (protocol in listOf("tcp", "udp")) {
            appendLine("ip6tables -w 5 -t mangle -A $PRE -p $protocol --dport 53 -j TPROXY --on-ip ::1 --on-port ${RootRuntimeConfig.IPV6_DNS_TPROXY_PORT} --tproxy-mark $capture")
            appendLine("ip6tables -w 5 -t mangle -A $PRE -p $protocol -j TPROXY --on-ip ::1 --on-port ${RootRuntimeConfig.TPROXY_PORT} --tproxy-mark $capture")
        }
        appendLine("ip -6 route add local ::/0 dev lo table $table")
        appendLine("ip -6 rule add pref $priority fwmark $capture lookup $table")
        appendLine("ip6tables -w 5 -t mangle -I PREROUTING 1 -i lo -m mark --mark $capture -j $PRE")
        appendLine("ip6tables -w 5 -t mangle -A OUTPUT -j $OUT")
    }

    fun cleanup(): String = """
        own_v6_routes=0
        ip6tables -w 5 -t mangle -S $OUT >/dev/null 2>&1 && own_v6_routes=1
        while ip6tables -w 5 -t mangle -C OUTPUT -j $OUT 2>/dev/null; do
            ip6tables -w 5 -t mangle -D OUTPUT -j $OUT || break
        done
        while ip6tables -w 5 -t mangle -C PREROUTING -i lo -m mark --mark ${TProxyRules.CAPTURE} -j $PRE 2>/dev/null; do
            ip6tables -w 5 -t mangle -D PREROUTING -i lo -m mark --mark ${TProxyRules.CAPTURE} -j $PRE || break
        done
        ip6tables -w 5 -t mangle -F $PRE 2>/dev/null
        ip6tables -w 5 -t mangle -X $PRE 2>/dev/null
        ip6tables -w 5 -t mangle -F $OUT 2>/dev/null
        ip6tables -w 5 -t mangle -F $DNS 2>/dev/null
        ip6tables -w 5 -t mangle -X $DNS 2>/dev/null
        if [ "${'$'}own_v6_routes" = 1 ]; then
            ip -6 rule del pref ${TProxyRules.PRIORITY} fwmark ${TProxyRules.CAPTURE} lookup ${TProxyRules.TABLE} 2>/dev/null
            ip -6 route del local ::/0 dev lo table ${TProxyRules.TABLE} 2>/dev/null
            remaining_v6_rules=${'$'}(ip -6 rule show) || { echo '无法核验 IPv6 策略路由清理结果'; exit 1; }
            if echo "${'$'}remaining_v6_rules" | awk '${'$'}1 == "${TProxyRules.PRIORITY}:" && /fwmark 0x20000000\/0x20000000/ && /lookup ${TProxyRules.TABLE}/ {found=1} END {exit !found}'; then
                echo 'Mclash IPv6 策略路由仍存在，将重试'; exit 1
            fi
            remaining_v6_routes=${'$'}(ip -6 route show table ${TProxyRules.TABLE}) || { echo '无法核验 IPv6 路由清理结果'; exit 1; }
            if echo "${'$'}remaining_v6_routes" | awk '${'$'}1 == "local" && (${'$'}2 == "default" || ${'$'}2 == "::/0") && ${'$'}3 == "dev" && ${'$'}4 == "lo" {found=1} END {exit !found}'; then
                echo 'Mclash IPv6 本地路由仍存在，将重试'; exit 1
            fi
            ip6tables -w 5 -t mangle -S OUTPUT >/dev/null 2>&1 || exit 1
        fi
        # Preserve ownership until route removal is verified, including on retries.
        ip6tables -w 5 -t mangle -F $OUT 2>/dev/null
        ip6tables -w 5 -t mangle -X $OUT 2>/dev/null
        ip6tables -w 5 -t mangle -S $OUT >/dev/null 2>&1 && { echo 'IPv6 OUTPUT 清理失败'; exit 1; }
        ip6tables -w 5 -t mangle -S $PRE >/dev/null 2>&1 && { echo 'IPv6 TProxy 清理失败'; exit 1; }
        ip6tables -w 5 -t mangle -S $DNS >/dev/null 2>&1 && { echo 'IPv6 DNS 清理失败'; exit 1; }
        true
    """.trimIndent()
}
