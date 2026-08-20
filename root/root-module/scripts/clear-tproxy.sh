#!/system/bin/sh
IPT=$(command -v iptables)
IP=$(command -v ip)
CHAIN=MCLASH_TPROXY
OUT=MCLASH_OUTPUT
DIVERT=MCLASH_DIVERT
PROBE=MCLASH_TPROXY_PROBE
IP6_GUARD=MCLASH_IPV6_GUARD
IP6T=$(command -v ip6tables)
IPT_WAIT=""
[ -n "$IPT" ] && "$IPT" -w 1 -L >/dev/null 2>&1 && IPT_WAIT="-w 10"
ipt() { "$IPT" $IPT_WAIT "$@"; }
IP6T_WAIT=""
[ -n "$IP6T" ] && "$IP6T" -w 1 -L >/dev/null 2>&1 && IP6T_WAIT="-w 10"
ip6t() { "$IP6T" $IP6T_WAIT "$@"; }
[ -n "$IPT" ] && {
  while ipt -t mangle -C PREROUTING -j "$CHAIN" 2>/dev/null; do ipt -t mangle -D PREROUTING -j "$CHAIN"; done
  while ipt -t mangle -C PREROUTING -p tcp -m socket -j "$DIVERT" 2>/dev/null; do ipt -t mangle -D PREROUTING -p tcp -m socket -j "$DIVERT"; done
  while ipt -t mangle -C OUTPUT -j "$OUT" 2>/dev/null; do ipt -t mangle -D OUTPUT -j "$OUT"; done
  for chain in "$CHAIN" "$OUT" "$DIVERT" "$PROBE"; do
    ipt -t mangle -F "$chain" 2>/dev/null
    ipt -t mangle -X "$chain" 2>/dev/null
  done
}
[ -n "$IP6T" ] && {
  while ip6t -C OUTPUT -j "$IP6_GUARD" 2>/dev/null; do ip6t -D OUTPUT -j "$IP6_GUARD"; done
  while ip6t -C FORWARD -j "$IP6_GUARD" 2>/dev/null; do ip6t -D FORWARD -j "$IP6_GUARD"; done
  ip6t -F "$IP6_GUARD" 2>/dev/null
  ip6t -X "$IP6_GUARD" 2>/dev/null
}
[ -n "$IP" ] && {
  while $IP rule del fwmark 0x2333 lookup 233 priority 8000 2>/dev/null; do :; done
  # Remove rules left by versions before hotspot forwarding support.
  while $IP rule del fwmark 0x2333 lookup 233 priority 10000 2>/dev/null; do :; done
  $IP route flush table 233 2>/dev/null
}
echo "TProxy rules cleared"
