package com.liuyihtu.mclash.root

/** Scripts use private chains and masked high bits, never flush Android/netd tables. */
internal object TProxyRules {
    const val TABLE = 20230
    const val PRIORITY = 9000
    const val CAPTURE = "0x20000000/0x20000000"
    private const val BYPASS = "0x40000000/0x40000000"
    private const val OUT = "MCLASH_R_OUT"
    private const val PRE = "MCLASH_R_PRE"
    private const val DNS = "MCLASH_R_DNS"
    private const val V6 = "MCLASH_R_V6"

    fun install(appUid: Int, onlySelected: Boolean, selectedUids: Set<Int>, bypassLan: Boolean): String {
        require(appUid > 0)
        require(selectedUids.all { it > 0 && it != appUid })
        require(!onlySelected || selectedUids.isNotEmpty()) { "请至少选择一个已安装的应用" }
        val filter = buildString {
            if (onlySelected) {
                selectedUids.sorted().forEach { uid -> appendLine("UID_MATCH $uid") }
            } else {
                selectedUids.sorted().forEach { uid -> appendLine("UID_SKIP $uid") }
            }
        }
        return buildString {
            appendLine("set -eu")
            // Refuse collisions rather than replacing a route owned by another application.
            appendLine("[ -z \"${'$'}(ip -4 rule show | awk '${'$'}1 == \"$PRIORITY:\" {print}')\" ] || { echo '策略路由优先级 $PRIORITY 已占用'; exit 1; }")
            appendLine("[ -z \"${'$'}(ip -4 route show table $TABLE 2>/dev/null)\" ] || { echo '路由表 $TABLE 已占用'; exit 1; }")
            appendLine("iptables -w 5 -t mangle -N $OUT")
            appendLine("iptables -w 5 -t mangle -N $PRE")
            appendLine("iptables -w 5 -t nat -N $DNS")
            appendLine("ip6tables -w 5 -t filter -N $V6")
            // Android enables tcp_fwmark_accept: transparent listener replies can
            // inherit CAPTURE from the SYN. Clear only our bit before bypassing
            // OUTPUT, otherwise the reply is intercepted again in PREROUTING.
            for (match in listOf(
                "-m mark --mark $BYPASS",
                "-m owner --uid-owner 0",
                "-m owner --uid-owner $appUid",
            )) {
                appendLine("iptables -w 5 -t mangle -A $OUT $match -j MARK --set-xmark 0x0/0x20000000")
            }
            // Root data traffic is direct, including transparent reply sockets.
            // A socket routing mark alone does not cover every listener response.
            for ((tool, table, chain) in listOf(
                Triple("iptables", "mangle", OUT), Triple("iptables", "nat", DNS),
                Triple("ip6tables", "filter", V6),
            )) {
                appendLine("$tool -w 5 -t $table -A $chain -m mark --mark $BYPASS -j RETURN")
                // Android's resolver can send DNS as UID 0. Its queries must
                // reach our DNS listener; the core's BYPASS mark prevents loops.
                if (chain != DNS) {
                    appendLine("$tool -w 5 -t $table -A $chain -m owner --uid-owner 0 -j RETURN")
                }
                appendLine("$tool -w 5 -t $table -A $chain -m owner --uid-owner $appUid -j RETURN")
            }
            appendLine("iptables -w 5 -t mangle -A $OUT -d 127.0.0.0/8 -j RETURN")
            appendLine("iptables -w 5 -t mangle -A $OUT -d 224.0.0.0/4 -j RETURN")
            appendLine("iptables -w 5 -t mangle -A $OUT -d 255.255.255.255/32 -j RETURN")
            // DNS stays unmarked so nat OUTPUT can redirect it before policy routing.
            for (protocol in listOf("tcp", "udp")) {
                appendLine("iptables -w 5 -t mangle -A $OUT -p $protocol --dport 53 -j RETURN")
                // System DNS commonly belongs to netd, not the calling application's UID.
                appendLine("iptables -w 5 -t nat -A $DNS -p $protocol --dport 53 -j REDIRECT --to-ports ${RootRuntimeConfig.DNS_PORT}")
            }
            if (bypassLan) {
                for (subnet in listOf("0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16")) {
                    appendLine("iptables -w 5 -t mangle -A $OUT -d $subnet -j RETURN")
                }
            }
            for (protocol in listOf("tcp", "udp")) {
                appendLine("ip6tables -w 5 -t filter -A $V6 -p $protocol --dport 53 -j REJECT")
            }
            appendLine("ip6tables -w 5 -t filter -A $V6 -d ::1/128 -j RETURN")
            appendLine("ip6tables -w 5 -t filter -A $V6 -d ff00::/8 -j RETURN")
            if (bypassLan) for (subnet in listOf("fe80::/10", "fc00::/7")) {
                appendLine("ip6tables -w 5 -t filter -A $V6 -d $subnet -j RETURN")
            }
            filter.lineSequence().filter { it.isNotBlank() }.forEach { line ->
                val uid = line.substringAfter(' ')
                if (line.startsWith("UID_SKIP")) {
                    appendLine("iptables -w 5 -t mangle -A $OUT -m owner --uid-owner $uid -j RETURN")
                    appendLine("ip6tables -w 5 -t filter -A $V6 -m owner --uid-owner $uid -j RETURN")
                } else {
                    appendCapture(uid)
                }
            }
            if (!onlySelected) appendCapture(null)
            for (protocol in listOf("tcp", "udp")) {
                appendLine("iptables -w 5 -t mangle -A $PRE -p $protocol -j TPROXY --on-ip 127.0.0.1 --on-port ${RootRuntimeConfig.TPROXY_PORT} --tproxy-mark $CAPTURE")
            }
            appendLine("ip -4 route add local 0.0.0.0/0 dev lo table $TABLE")
            appendLine("ip -4 rule add pref $PRIORITY fwmark $CAPTURE lookup $TABLE")
            append(HotspotRules.install())
            // Only install hooks after every chain and route is ready.
            appendLine("iptables -w 5 -t mangle -I PREROUTING 1 -i lo -m mark --mark $CAPTURE -j $PRE")
            appendLine("iptables -w 5 -t nat -I OUTPUT 1 -j $DNS")
            appendLine("ip6tables -w 5 -t filter -I OUTPUT 1 -j $V6")
            appendLine("iptables -w 5 -t mangle -A OUTPUT -j $OUT")
        }
    }

    private fun StringBuilder.appendCapture(uid: String?) {
        val owner = uid?.let { " -m owner --uid-owner $it" }.orEmpty()
        for (protocol in listOf("tcp", "udp")) {
            appendLine("iptables -w 5 -t mangle -A $OUT -p $protocol$owner -j MARK --set-xmark $CAPTURE")
            appendLine("ip6tables -w 5 -t filter -A $V6 -p $protocol$owner -j REJECT")
        }
    }

    /** Rollback works for a partially installed transaction as well as a normal stop. */
    fun cleanup(): String = """
        set +e
        ${HotspotRules.cleanup()}
        own_routes=0
        iptables -w 5 -t mangle -S $OUT >/dev/null 2>&1 && own_routes=1
        while iptables -w 5 -t mangle -C OUTPUT -j $OUT 2>/dev/null; do
            iptables -w 5 -t mangle -D OUTPUT -j $OUT || break
        done
        while iptables -w 5 -t mangle -C PREROUTING -i lo -m mark --mark $CAPTURE -j $PRE 2>/dev/null; do
            iptables -w 5 -t mangle -D PREROUTING -i lo -m mark --mark $CAPTURE -j $PRE || break
        done
        while iptables -w 5 -t nat -C OUTPUT -j $DNS 2>/dev/null; do
            iptables -w 5 -t nat -D OUTPUT -j $DNS || break
        done
        while ip6tables -w 5 -t filter -C OUTPUT -j $V6 2>/dev/null; do
            ip6tables -w 5 -t filter -D OUTPUT -j $V6 || break
        done
        iptables -w 5 -t mangle -F $PRE 2>/dev/null
        iptables -w 5 -t mangle -X $PRE 2>/dev/null
        iptables -w 5 -t nat -F $DNS 2>/dev/null
        iptables -w 5 -t nat -X $DNS 2>/dev/null
        ip6tables -w 5 -t filter -F $V6 2>/dev/null
        ip6tables -w 5 -t filter -X $V6 2>/dev/null
        if [ "${'$'}own_routes" = 1 ]; then
            ip -4 rule del pref $PRIORITY fwmark $CAPTURE lookup $TABLE 2>/dev/null
            ip -4 route del local 0.0.0.0/0 dev lo table $TABLE 2>/dev/null
            remaining_rules=${'$'}(ip -4 rule show) || { echo '无法核验策略路由清理结果'; exit 1; }
            if echo "${'$'}remaining_rules" | awk '${'$'}1 == "$PRIORITY:" && /fwmark 0x20000000\/0x20000000/ && /lookup $TABLE/ {found=1} END {exit !found}'; then
                echo 'Mclash Root 策略路由仍存在，将重试'; exit 1
            fi
            if ip -4 route show table $TABLE 2>/dev/null | awk '${'$'}1 == "local" && (${'$'}2 == "default" || ${'$'}2 == "0.0.0.0/0") && ${'$'}3 == "dev" && ${'$'}4 == "lo" {found=1} END {exit !found}'; then
                echo 'Mclash Root 本地路由仍存在，将重试'; exit 1
            fi
        fi
        # Keep OUT until route removal is verified, so a retry retains ownership.
        iptables -w 5 -t mangle -F $OUT 2>/dev/null
        iptables -w 5 -t mangle -X $OUT 2>/dev/null
        failed=0
        ${HotspotRules.verifyCleanup()}
        iptables -w 5 -t mangle -S OUTPUT >/dev/null 2>&1 || failed=1
        iptables -w 5 -t nat -S OUTPUT >/dev/null 2>&1 || failed=1
        ip6tables -w 5 -t filter -S OUTPUT >/dev/null 2>&1 || failed=1
        iptables -w 5 -t mangle -S $OUT >/dev/null 2>&1 && failed=1
        iptables -w 5 -t mangle -S $PRE >/dev/null 2>&1 && failed=1
        iptables -w 5 -t nat -S $DNS >/dev/null 2>&1 && failed=1
        ip6tables -w 5 -t filter -S $V6 >/dev/null 2>&1 && failed=1
        [ "${'$'}failed" = 0 ] || { echo 'Mclash Root 规则清理失败，将重试'; exit 1; }
    """.trimIndent()
}
