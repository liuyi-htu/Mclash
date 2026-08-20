#!/system/bin/sh
DATA=/data/adb/mclash
ENV="$DATA/config/root.env"
CIDRS="$DATA/config/bypass-cidrs.txt"
CIDR_STATE="$DATA/run/tun-hotspot-cidrs.txt"
IFACE_STATE="$DATA/run/tun-hotspot-interfaces.txt"
SYSCTL_STATE="$DATA/run/tun-hotspot-sysctl.txt"
TUN_DEVICE=mclash0
TUN_TABLE=2233
CORE_MARK=0x2334
CORE_PRIORITY=22993
RETURN_PRIORITY=22994
BYPASS_PRIORITY=22995
FORWARD_PRIORITY=22996
CHAIN=MCLASH_TUN_FORWARD
IP6_GUARD=MCLASH_TUN_IPV6_GUARD
[ -r "$ENV" ] && . "$ENV"
IPV6=${IPV6:-0}
IP=$(command -v ip) || { echo "ip not found" >&2; exit 1; }
IPT=$(command -v iptables) || { echo "iptables not found" >&2; exit 1; }
IP6T=$(command -v ip6tables)
IPT_WAIT=""
"$IPT" -w 1 -L >/dev/null 2>&1 && IPT_WAIT="-w 10"
ipt() { "$IPT" $IPT_WAIT "$@"; }
IP6T_WAIT=""
[ -n "$IP6T" ] && "$IP6T" -w 1 -L >/dev/null 2>&1 && IP6T_WAIT="-w 10"
ip6t() { "$IP6T" $IP6T_WAIT "$@"; }

"${0%/*}/clear-tun-hotspot.sh"
$IP link show dev "$TUN_DEVICE" >/dev/null 2>&1 || {
  echo "TUN device $TUN_DEVICE is not ready" >&2
  exit 1
}

read_sysctl() { cat "/proc/sys/$1" 2>/dev/null; }
write_sysctl() { [ -w "/proc/sys/$1" ] && echo "$2" > "/proc/sys/$1"; }
{
  echo "ipv4_ip_forward=$(read_sysctl net/ipv4/ip_forward)"
  echo "ipv4_rp_filter_all=$(read_sysctl net/ipv4/conf/all/rp_filter)"
  echo "ipv4_rp_filter_default=$(read_sysctl net/ipv4/conf/default/rp_filter)"
  echo "ipv6_forwarding=$(read_sysctl net/ipv6/conf/all/forwarding)"
} > "$SYSCTL_STATE"
write_sysctl net/ipv4/ip_forward 1
write_sysctl net/ipv4/conf/all/rp_filter 2
write_sysctl net/ipv4/conf/default/rp_filter 2
[ "$IPV6" = 1 ] && write_sysctl net/ipv6/conf/all/forwarding 1

# Packets written back by mihomo must leave through Android's normal routing
# table. All other non-local input is forwarded traffic from hotspot, USB or
# Bluetooth tethering and must enter mihomo's TUN table.
$IP rule add fwmark "$CORE_MARK" lookup main priority "$CORE_PRIORITY" || exit 1
$IP -6 rule add fwmark "$CORE_MARK" lookup main priority "$CORE_PRIORITY" || exit 1
$IP rule add iif "$TUN_DEVICE" lookup main priority "$RETURN_PRIORITY" || exit 1
: > "$CIDR_STATE"
[ -r "$CIDRS" ] && while IFS= read -r cidr; do
  [ -n "$cidr" ] || continue
  case "$cidr" in
    *:*)
      [ "$IPV6" = 1 ] || continue
      $IP -6 rule add to "$cidr" lookup main priority "$BYPASS_PRIORITY" || exit 1
      ;;
    *)
      $IP rule add to "$cidr" lookup main priority "$BYPASS_PRIORITY" || exit 1
      ;;
  esac
  echo "$cidr" >> "$CIDR_STATE"
done < "$CIDRS"

# Android tethering interface names vary by vendor. Route known Wi-Fi AP, USB
# and Bluetooth tethering interfaces explicitly. If a ROM uses an unknown name,
# retain the generic forwarding rule as a compatibility fallback.
: > "$IFACE_STATE"
for path in /sys/class/net/*; do
  [ -e "$path" ] || continue
  interface=${path##*/}
  case "$interface" in
    ap*|wlan*|swlan*|rndis*|usb*|bnep*|bt-pan*)
      [ "$interface" = "$TUN_DEVICE" ] && continue
      $IP rule add iif "$interface" lookup "$TUN_TABLE" priority "$FORWARD_PRIORITY" || continue
      echo "$interface" >> "$IFACE_STATE"
      ;;
  esac
done
# Hotspot interfaces may be created after the proxy starts. Keep a final
# forwarding fallback so those future interfaces work without a resident
# watcher; the explicit entries above make diagnostics device-specific.
$IP rule add not iif lo lookup "$TUN_TABLE" priority "$FORWARD_PRIORITY" || exit 1
echo "*" >> "$IFACE_STATE"

if [ "$IPV6" = 1 ]; then
  $IP -6 rule add iif "$TUN_DEVICE" lookup main priority "$RETURN_PRIORITY" || exit 1
  while IFS= read -r interface; do
    if [ "$interface" = "*" ]; then
      $IP -6 rule add not iif lo lookup "$TUN_TABLE" priority "$FORWARD_PRIORITY" || exit 1
    else
      $IP -6 rule add iif "$interface" lookup "$TUN_TABLE" priority "$FORWARD_PRIORITY" || exit 1
    fi
  done < "$IFACE_STATE"
fi

# Android vendors commonly place a DROP rule in FORWARD which only permits the
# physical upstream. Insert our jump first so forwarding to and from TUN works.
ipt -N "$CHAIN" || exit 1
ipt -A "$CHAIN" -i "$TUN_DEVICE" -j ACCEPT || exit 1
ipt -A "$CHAIN" -o "$TUN_DEVICE" -j ACCEPT || exit 1
ipt -I FORWARD 1 -j "$CHAIN" || exit 1

if [ "$IPV6" != 1 ]; then
  [ -n "$IP6T" ] || { echo "ip6tables is required to prevent IPv6 leaks while IPv6 proxy is disabled" >&2; exit 1; }
  ip6t -N "$IP6_GUARD" || exit 1
  ip6t -A "$IP6_GUARD" -m mark --mark "$CORE_MARK" -j RETURN || exit 1
  ip6t -A "$IP6_GUARD" -d ::1/128 -j RETURN || exit 1
  ip6t -A "$IP6_GUARD" -d fe80::/10 -j RETURN || exit 1
  ip6t -A "$IP6_GUARD" -d ff00::/8 -j RETURN || exit 1
  ip6t -A "$IP6_GUARD" -j REJECT || exit 1
  ip6t -I OUTPUT 1 -j "$IP6_GUARD" || exit 1
  ip6t -I FORWARD 1 -j "$IP6_GUARD" || exit 1
fi
echo "TUN hotspot routing applied for: $(tr '\n' ' ' < "$IFACE_STATE")"
