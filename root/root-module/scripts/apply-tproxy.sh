#!/system/bin/sh
DATA=/data/adb/mclash
ENV="$DATA/config/root.env"
CIDRS="$DATA/config/bypass-cidrs.txt"
UIDS="$DATA/config/app-uids.txt"
MARK=0x2333
TABLE=233
CHAIN=MCLASH_TPROXY
OUT=MCLASH_OUTPUT
[ -r "$ENV" ] && . "$ENV"
APP_UID=${APP_UID:-0}
APP_FILTER_MODE=${APP_FILTER_MODE:-exclude}
IPT=$(command -v iptables) || { echo "iptables not found" >&2; exit 1; }
IP=$(command -v ip) || { echo "ip not found" >&2; exit 1; }

"${0%/*}/clear-tproxy.sh"
$IP rule add fwmark "$MARK" lookup "$TABLE" priority 10000 || exit 1
$IP route add local 0.0.0.0/0 dev lo table "$TABLE" || exit 1
$IPT -t mangle -N "$CHAIN" || exit 1
$IPT -t mangle -N "$OUT" || exit 1
$IPT -t mangle -A "$CHAIN" -d 127.0.0.0/8 -j RETURN
[ -r "$CIDRS" ] && while IFS= read -r cidr; do
  [ -n "$cidr" ] || continue
  echo "$cidr" | grep -q ':' && continue
  $IPT -t mangle -A "$CHAIN" -d "$cidr" -j RETURN || exit 1
done < "$CIDRS"
$IPT -t mangle -A "$CHAIN" -p tcp -j TPROXY --on-ip 127.0.0.1 --on-port 7894 --tproxy-mark "$MARK" || exit 1
$IPT -t mangle -A "$CHAIN" -p udp -j TPROXY --on-ip 127.0.0.1 --on-port 7894 --tproxy-mark "$MARK" || exit 1
$IPT -t mangle -A "$OUT" -m owner --uid-owner 0 -j RETURN
$IPT -t mangle -A "$OUT" -m owner --uid-owner "$APP_UID" -j RETURN
[ -r "$CIDRS" ] && while IFS= read -r cidr; do
  [ -n "$cidr" ] || continue
  echo "$cidr" | grep -q ':' && continue
  $IPT -t mangle -A "$OUT" -d "$cidr" -j RETURN || exit 1
done < "$CIDRS"
if [ "$APP_FILTER_MODE" = include ]; then
  [ -r "$UIDS" ] && while IFS= read -r uid; do
    case "$uid" in ''|*[!0-9]*) continue;; esac
    $IPT -t mangle -A "$OUT" -m owner --uid-owner "$uid" -p tcp -j MARK --set-mark "$MARK"
    $IPT -t mangle -A "$OUT" -m owner --uid-owner "$uid" -p udp -j MARK --set-mark "$MARK"
  done < "$UIDS"
else
  [ -r "$UIDS" ] && while IFS= read -r uid; do
    case "$uid" in ''|*[!0-9]*) continue;; esac
    $IPT -t mangle -A "$OUT" -m owner --uid-owner "$uid" -j RETURN
  done < "$UIDS"
  $IPT -t mangle -A "$OUT" -p tcp -j MARK --set-mark "$MARK"
  $IPT -t mangle -A "$OUT" -p udp -j MARK --set-mark "$MARK"
fi
$IPT -t mangle -A PREROUTING -j "$CHAIN" || exit 1
$IPT -t mangle -A OUTPUT -j "$OUT" || exit 1
echo "TProxy rules applied"
