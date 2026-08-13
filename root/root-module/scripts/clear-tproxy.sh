#!/system/bin/sh
IPT=$(command -v iptables)
IP=$(command -v ip)
CHAIN=MCLASH_TPROXY
OUT=MCLASH_OUTPUT
[ -n "$IPT" ] && {
  while $IPT -t mangle -C PREROUTING -j "$CHAIN" 2>/dev/null; do $IPT -t mangle -D PREROUTING -j "$CHAIN"; done
  while $IPT -t mangle -C OUTPUT -j "$OUT" 2>/dev/null; do $IPT -t mangle -D OUTPUT -j "$OUT"; done
  $IPT -t mangle -F "$CHAIN" 2>/dev/null
  $IPT -t mangle -X "$CHAIN" 2>/dev/null
  $IPT -t mangle -F "$OUT" 2>/dev/null
  $IPT -t mangle -X "$OUT" 2>/dev/null
}
[ -n "$IP" ] && {
  while $IP rule del fwmark 0x2333 lookup 233 priority 10000 2>/dev/null; do :; done
  $IP route flush table 233 2>/dev/null
}
echo "TProxy rules cleared"
