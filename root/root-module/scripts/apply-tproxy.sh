#!/system/bin/sh
DATA=/data/adb/mclash
ENV="$DATA/config/root.env"
CIDRS="$DATA/config/bypass-cidrs.txt"
UIDS="$DATA/config/app-uids.txt"
MARK=0x2333
CORE_MARK=0x2334
TABLE=233
RULE_PRIORITY=8000
CHAIN=MCLASH_TPROXY
OUT=MCLASH_OUTPUT
DIVERT=MCLASH_DIVERT
IP6_GUARD=MCLASH_IPV6_GUARD
[ -r "$ENV" ] && . "$ENV"
APP_FILTER_MODE=${APP_FILTER_MODE:-exclude}
IPT=$(command -v iptables) || { echo "iptables not found" >&2; exit 1; }
IP=$(command -v ip) || { echo "ip not found" >&2; exit 1; }
IP6T=$(command -v ip6tables) || { echo "ip6tables is required to prevent IPv6 leaks in TProxy mode" >&2; exit 1; }
IPT_WAIT=""
"$IPT" -w 1 -L >/dev/null 2>&1 && IPT_WAIT="-w 10"
ipt() { "$IPT" $IPT_WAIT "$@"; }
IP6T_WAIT=""
"$IP6T" -w 1 -L >/dev/null 2>&1 && IP6T_WAIT="-w 10"
ip6t() { "$IP6T" $IP6T_WAIT "$@"; }

"${0%/*}/clear-tproxy.sh"

# Probe the actual userspace/kernel combination. Reading CONFIG_* alone is not
# sufficient on Android because extension revisions can still be incompatible.
PROBE=MCLASH_TPROXY_PROBE
ipt -t mangle -N "$PROBE" || exit 1
if ! ipt -t mangle -A "$PROBE" -p tcp -j TPROXY --on-port 7894 --tproxy-mark "$MARK"; then
  ipt -t mangle -F "$PROBE" 2>/dev/null
  ipt -t mangle -X "$PROBE" 2>/dev/null
  echo "kernel/iptables does not support the required TPROXY target" >&2
  exit 1
fi
ipt -t mangle -F "$PROBE" || exit 1
ipt -t mangle -X "$PROBE" || exit 1

$IP rule add fwmark "$MARK" lookup "$TABLE" priority "$RULE_PRIORITY" || exit 1
$IP route add local 0.0.0.0/0 dev lo table "$TABLE" || exit 1
ipt -t mangle -N "$CHAIN" || exit 1
# Do not intercept connections addressed to the phone itself. Do not use the
# addrtype match here: many Android kernels omit xt_addrtype. Enumerating local
# addresses provides the same protection without an optional kernel module.
ipt -t mangle -A "$CHAIN" -d 0.0.0.0/8 -j RETURN || exit 1
ipt -t mangle -A "$CHAIN" -d 127.0.0.0/8 -j RETURN || exit 1
ipt -t mangle -A "$CHAIN" -d 169.254.0.0/16 -j RETURN || exit 1
ipt -t mangle -A "$CHAIN" -d 224.0.0.0/4 -j RETURN || exit 1
ipt -t mangle -A "$CHAIN" -d 240.0.0.0/4 -j RETURN || exit 1
$IP -4 addr show 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    *" inet "*)
      address=${line#* inet }
      address=${address%%/*}
      address=${address%% *}
      [ -n "$address" ] || continue
      ipt -t mangle -A "$CHAIN" -d "$address/32" -j RETURN || exit 1
      ;;
  esac
done || exit 1
[ -r "$CIDRS" ] && while IFS= read -r cidr; do
  [ -n "$cidr" ] || continue
  echo "$cidr" | grep -q ':' && continue
  # LAN access may bypass the proxy, but DNS must not leak just because the
  # resolver happens to use a private address.
  ipt -t mangle -A "$CHAIN" -d "$cidr" -p tcp ! --dport 53 -j RETURN || exit 1
  ipt -t mangle -A "$CHAIN" -d "$cidr" -p udp ! --dport 53 -j RETURN || exit 1
done < "$CIDRS"
ipt -t mangle -A "$CHAIN" -p tcp -j TPROXY --on-port 7894 --tproxy-mark "$MARK" || exit 1
ipt -t mangle -A "$CHAIN" -p udp -j TPROXY --on-port 7894 --tproxy-mark "$MARK" || exit 1
ipt -t mangle -A PREROUTING -j "$CHAIN" || exit 1

# DIVERT established transparent TCP sockets when xt_socket is available. It
# is an optional optimization and must never prevent startup on trimmed kernels.
if ipt -t mangle -N "$DIVERT" 2>/dev/null; then
  if ! ipt -t mangle -A "$DIVERT" -j MARK --set-mark "$MARK" ||
     ! ipt -t mangle -A "$DIVERT" -j ACCEPT ||
     ! ipt -t mangle -I PREROUTING 1 -p tcp -m socket -j "$DIVERT" 2>/dev/null; then
    ipt -t mangle -F "$DIVERT" 2>/dev/null
    ipt -t mangle -X "$DIVERT" 2>/dev/null
    echo "xt_socket unavailable; continuing without DIVERT optimization"
  fi
fi

ipt -t mangle -N "$OUT" || exit 1
ipt -t mangle -A "$OUT" -m mark --mark "$CORE_MARK" -j RETURN || exit 1
ipt -t mangle -A "$OUT" -d 0.0.0.0/8 -j RETURN || exit 1
ipt -t mangle -A "$OUT" -d 127.0.0.0/8 -j RETURN || exit 1
ipt -t mangle -A "$OUT" -d 169.254.0.0/16 -j RETURN || exit 1
ipt -t mangle -A "$OUT" -d 224.0.0.0/4 -j RETURN || exit 1
ipt -t mangle -A "$OUT" -d 240.0.0.0/4 -j RETURN || exit 1
[ -r "$CIDRS" ] && while IFS= read -r cidr; do
  [ -n "$cidr" ] || continue
  echo "$cidr" | grep -q ':' && continue
  ipt -t mangle -A "$OUT" -d "$cidr" -p tcp ! --dport 53 -j RETURN || exit 1
  ipt -t mangle -A "$OUT" -d "$cidr" -p udp ! --dport 53 -j RETURN || exit 1
done < "$CIDRS"
if [ "$APP_FILTER_MODE" = include ]; then
  [ -r "$UIDS" ] && while IFS= read -r uid; do
    case "$uid" in ''|*[!0-9]*) continue;; esac
    ipt -t mangle -A "$OUT" -m owner --uid-owner "$uid" -p tcp -j MARK --set-mark "$MARK" || exit 1
    ipt -t mangle -A "$OUT" -m owner --uid-owner "$uid" -p udp -j MARK --set-mark "$MARK" || exit 1
  done < "$UIDS"
else
  [ -r "$UIDS" ] && while IFS= read -r uid; do
    case "$uid" in ''|*[!0-9]*) continue;; esac
    ipt -t mangle -A "$OUT" -m owner --uid-owner "$uid" -j RETURN || exit 1
  done < "$UIDS"
  ipt -t mangle -A "$OUT" -p tcp -j MARK --set-mark "$MARK" || exit 1
  ipt -t mangle -A "$OUT" -p udp -j MARK --set-mark "$MARK" || exit 1
fi
ipt -t mangle -A OUTPUT -j "$OUT" || exit 1

# Mihomo TProxy is IPv4-only in this app. Fail closed for public IPv6 instead
# of silently allowing it to bypass the proxy. Link-local/multicast traffic is
# retained so Android network discovery and interface management keep working.
ip6t -N "$IP6_GUARD" || exit 1
ip6t -A "$IP6_GUARD" -m mark --mark "$CORE_MARK" -j RETURN || exit 1
ip6t -A "$IP6_GUARD" -d ::1/128 -j RETURN || exit 1
ip6t -A "$IP6_GUARD" -d fe80::/10 -j RETURN || exit 1
ip6t -A "$IP6_GUARD" -d ff00::/8 -j RETURN || exit 1
ip6t -A "$IP6_GUARD" -j REJECT || exit 1
ip6t -I OUTPUT 1 -j "$IP6_GUARD" || exit 1
ip6t -I FORWARD 1 -j "$IP6_GUARD" || exit 1
echo "TProxy rules applied"
