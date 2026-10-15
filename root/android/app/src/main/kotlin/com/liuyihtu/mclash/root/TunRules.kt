package com.liuyihtu.mclash.root

/** Permit only captured sharing flows and their replies through Android's forward filter. */
internal object TunRules {
    const val RETURN_PRIORITY = 8999
    private fun subnet(family: Int) = if (family == 4) "198.18.0.0/30" else "fdfe:dcba:9876::/126"

    // Android does not consult Linux's main table for these root-owned reply sockets.
    // The mixed stack's internal TCP listener must send replies back into the TUN.
    fun checkReturnPriority(ipv6: Boolean): String = buildString {
        for (family in if (ipv6) listOf(4, 6) else listOf(4)) {
            appendLine("[ -z \"${'$'}(ip -$family rule show | awk '${'$'}1 == \"$RETURN_PRIORITY:\" {print}')\" ] || { echo 'TUN 策略路由优先级 $RETURN_PRIORITY 已占用'; exit 1; }")
        }
    }

    fun returnRoute(family: Int): String =
        "ip -$family rule add pref $RETURN_PRIORITY to ${subnet(family)} lookup ${TProxyRules.TABLE}\n"

    fun cleanupReturnRoute(family: Int): String = """
        if [ "${'$'}{own_tun_routes:-0}" = 1 ]; then
            ip -$family rule del pref $RETURN_PRIORITY to ${subnet(family)} lookup ${TProxyRules.TABLE} 2>/dev/null
            remaining_tun_rules=${'$'}(ip -$family rule show) || exit 1
            if echo "${'$'}remaining_tun_rules" | awk '${'$'}1 == "$RETURN_PRIORITY:" && index(${'$'}0, "to ${subnet(family)} ") && /lookup ${TProxyRules.TABLE}/ {found=1} END {exit !found}'; then
                echo 'TUN 内部回包路由仍存在，将重试'; exit 1
            fi
        fi
    """.trimIndent()

    fun install(ipv6: Boolean): String = buildString {
        for (tool in if (ipv6) listOf("iptables", "ip6tables") else listOf("iptables")) {
            appendLine("$tool -w 5 -t filter -N MCLASH_R_TUN")
            appendLine("$tool -w 5 -t filter -A MCLASH_R_TUN -o mclash0 -m mark --mark ${TProxyRules.CAPTURE} -j ACCEPT")
            appendLine("$tool -w 5 -t filter -A MCLASH_R_TUN -i mclash0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT")
            appendLine("$tool -w 5 -t filter -I FORWARD 1 -j MCLASH_R_TUN")
        }
    }

    fun cleanup(): String = buildString {
        for (tool in listOf("iptables", "ip6tables")) {
            appendLine("while $tool -w 5 -t filter -C FORWARD -j MCLASH_R_TUN 2>/dev/null; do")
            appendLine("  $tool -w 5 -t filter -D FORWARD -j MCLASH_R_TUN || break")
            appendLine("done")
            appendLine("$tool -w 5 -t filter -F MCLASH_R_TUN 2>/dev/null")
            appendLine("$tool -w 5 -t filter -X MCLASH_R_TUN 2>/dev/null")
            appendLine("$tool -w 5 -t filter -S MCLASH_R_TUN >/dev/null 2>&1 && { echo 'TUN 转发规则清理失败'; exit 1; }")
        }
        appendLine("true")
    }
}
