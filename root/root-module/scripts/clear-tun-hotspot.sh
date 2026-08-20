#!/system/bin/sh
DATA=/data/adb/mclash
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
IP=$(command -v ip)
IPT=$(command -v iptables)
IP6T=$(command -v ip6tables)
LEGACY_STATE=0
[ -r "$CIDR_STATE" ] && [ ! -r "$IFACE_STATE" ] && LEGACY_STATE=1
IPT_WAIT=""
[ -n "$IPT" ] && "$IPT" -w 1 -L >/dev/null 2>&1 && IPT_WAIT="-w 10"
ipt() { "$IPT" $IPT_WAIT "$@"; }
IP6T_WAIT=""
[ -n "$IP6T" ] && "$IP6T" -w 1 -L >/dev/null 2>&1 && IP6T_WAIT="-w 10"
ip6t() { "$IP6T" $IP6T_WAIT "$@"; }

[ -n "$IPT" ] && {
  while ipt -C FORWARD -j "$CHAIN" 2>/dev/null; do ipt -D FORWARD -j "$CHAIN"; done
  ipt -F "$CHAIN" 2>/dev/null
  ipt -X "$CHAIN" 2>/dev/null
}
[ -n "$IP6T" ] && {
  while ip6t -C OUTPUT -j "$IP6_GUARD" 2>/dev/null; do ip6t -D OUTPUT -j "$IP6_GUARD"; done
  while ip6t -C FORWARD -j "$IP6_GUARD" 2>/dev/null; do ip6t -D FORWARD -j "$IP6_GUARD"; done
  ip6t -F "$IP6_GUARD" 2>/dev/null
  ip6t -X "$IP6_GUARD" 2>/dev/null
}
[ -n "$IP" ] && {
  while $IP rule del fwmark "$CORE_MARK" lookup main priority "$CORE_PRIORITY" 2>/dev/null; do :; done
  while $IP -6 rule del fwmark "$CORE_MARK" lookup main priority "$CORE_PRIORITY" 2>/dev/null; do :; done
  while $IP rule del iif "$TUN_DEVICE" lookup main priority "$RETURN_PRIORITY" 2>/dev/null; do :; done
  while $IP -6 rule del iif "$TUN_DEVICE" lookup main priority "$RETURN_PRIORITY" 2>/dev/null; do :; done
  if [ -r "$IFACE_STATE" ]; then
    while IFS= read -r interface; do
      if [ "$interface" = "*" ]; then
        while $IP rule del not iif lo lookup "$TUN_TABLE" priority "$FORWARD_PRIORITY" 2>/dev/null; do :; done
        while $IP -6 rule del not iif lo lookup "$TUN_TABLE" priority "$FORWARD_PRIORITY" 2>/dev/null; do :; done
      else
        while $IP rule del iif "$interface" lookup "$TUN_TABLE" priority "$FORWARD_PRIORITY" 2>/dev/null; do :; done
        while $IP -6 rule del iif "$interface" lookup "$TUN_TABLE" priority "$FORWARD_PRIORITY" 2>/dev/null; do :; done
      fi
    done < "$IFACE_STATE"
  fi
  [ -r "$CIDR_STATE" ] && while IFS= read -r cidr; do
    [ -n "$cidr" ] || continue
    case "$cidr" in
      *:*)
        while $IP -6 rule del to "$cidr" lookup main priority "$BYPASS_PRIORITY" 2>/dev/null; do :; done
        [ "$LEGACY_STATE" = 1 ] && while $IP -6 rule del to "$cidr" lookup main priority 8995 2>/dev/null; do :; done
        ;;
      *)
        while $IP rule del to "$cidr" lookup main priority "$BYPASS_PRIORITY" 2>/dev/null; do :; done
        [ "$LEGACY_STATE" = 1 ] && while $IP rule del to "$cidr" lookup main priority 8995 2>/dev/null; do :; done
        ;;
    esac
  done < "$CIDR_STATE"

  # mihomo owns these fixed indices (configured in runtime.yaml). Some Android
  # kernels leave its auto-route rules behind briefly after SIGTERM, which
  # breaks a following TProxy start. The process is already stopped when this
  # cleanup runs, so remove every rule at the reserved priorities and table.
  priority=23000
  while [ "$priority" -le 23010 ]; do
    while $IP rule del priority "$priority" 2>/dev/null; do :; done
    while $IP -6 rule del priority "$priority" 2>/dev/null; do :; done
    priority=$((priority + 1))
  done
  $IP route flush table "$TUN_TABLE" 2>/dev/null
  $IP -6 route flush table "$TUN_TABLE" 2>/dev/null

  # One-time migration from Mclash versions that used mihomo's default
  # table/rule indices. Only run when the old state-file layout is detected.
  if [ "$LEGACY_STATE" = 1 ]; then
    while $IP rule del iif "$TUN_DEVICE" lookup main priority 8994 2>/dev/null; do :; done
    while $IP rule del not iif lo lookup 2022 priority 8996 2>/dev/null; do :; done
    while $IP -6 rule del iif "$TUN_DEVICE" lookup main priority 8994 2>/dev/null; do :; done
    while $IP -6 rule del not iif lo lookup 2022 priority 8996 2>/dev/null; do :; done
    priority=9000
    while [ "$priority" -le 9010 ]; do
      while $IP rule del priority "$priority" 2>/dev/null; do :; done
      while $IP -6 rule del priority "$priority" 2>/dev/null; do :; done
      priority=$((priority + 1))
    done
    $IP route flush table 2022 2>/dev/null
    $IP -6 route flush table 2022 2>/dev/null
  fi
}
[ -r "$SYSCTL_STATE" ] && {
  while IFS='=' read -r name value; do
    [ -n "$value" ] || continue
    case "$name" in
      ipv4_ip_forward) path=net/ipv4/ip_forward;;
      ipv4_rp_filter_all) path=net/ipv4/conf/all/rp_filter;;
      ipv4_rp_filter_default) path=net/ipv4/conf/default/rp_filter;;
      ipv6_forwarding) path=net/ipv6/conf/all/forwarding;;
      *) continue;;
    esac
    [ -w "/proc/sys/$path" ] && echo "$value" > "/proc/sys/$path"
  done < "$SYSCTL_STATE"
}
rm -f "$CIDR_STATE" "$IFACE_STATE" "$SYSCTL_STATE"
echo "TUN hotspot routing cleared"
