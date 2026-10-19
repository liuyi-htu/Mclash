package com.liuyihtu.mclash.root

internal object RootHotspotMonitor {
    fun script(bypassLan: Boolean, ipv6: Boolean, tun: Boolean = false): String =
        "BYPASS_LAN=${if (bypassLan) 1 else 0}\nIPV6=${if (ipv6) 1 else 0}\n" + """
set -eu
umask 077
${HotspotOffload.functions()}
[ ! -f ./log-maintenance.sh ] || /system/bin/sh ./log-maintenance.sh || true
# Only explicitly selected Android tethering interfaces may be intercepted.
policy=${'$'}(cat ./sharing.policy 2>/dev/null || printf '0\n')
enabled=${'$'}(printf '%s\n' "${'$'}policy" | head -n 1)
ifaces=''
selected=${'$'}(printf '%s\n' "${'$'}policy" | sed '1d')
if [ "${'$'}enabled" = 1 ] && [ -n "${'$'}selected" ]; then
 # Stream the dump: historical logs can exceed Android's per-argument limit.
 tether=${'$'}(dumpsys tethering | sed -n '/Tether state:/,/Hardware offload:/p')
 printf '%s\n' "${'$'}tether" | grep -q 'Tether state:' || { echo '无法读取热点状态'; exit 1; }
 available=${'$'}(printf '%s\n' "${'$'}tether" | awk '${'$'}2 == "-" && ${'$'}3 == "TetheredState" && ${'$'}4 == "-" && ${'$'}1 != "lo" && length(${'$'}1) <= 15 && ${'$'}1 ~ /^[a-zA-Z0-9_.-]+${'$'}/ {print ${'$'}1}' | sort -u)
 ifaces=${'$'}(printf '%s\n' "${'$'}available" | while IFS= read -r iface; do
  [ -n "${'$'}iface" ] || continue
  printf '%s\n' "${'$'}selected" | grep -F -x -- "${'$'}iface" >/dev/null && printf '%s\n' "${'$'}iface" || true
 done)
fi
addresses4=''
addresses6=''
if [ -n "${'$'}ifaces" ]; then
raw4=${'$'}(ip -o -4 addr show)
raw6=''
if [ "${'$'}IPV6" = 1 ]; then raw6=${'$'}(ip -o -6 addr show); fi
addresses4=${'$'}(printf '%s\n' "${'$'}raw4" | awk '{split(${'$'}4, a, "/"); if (a[1] != "") print a[1]}' | sort -u)
addresses6=${'$'}(printf '%s\n' "${'$'}raw6" | awk '{split(${'$'}4, a, "/"); if (a[1] != "") print a[1]}' | sort -u)
[ -n "${'$'}addresses4" ] || { echo '无法读取本机 IPv4 地址'; exit 1; }
fi
snapshot=${'$'}(printf '%s\n' "policy=${'$'}policy" "interfaces=${'$'}ifaces" "ipv4=${'$'}addresses4" "ipv6=${'$'}addresses6")
# Recheck even when addresses are unchanged: Android can attach its fast path later.
offload_update
acknowledge() {
 if ! cmp -s ./sharing.policy ./sharing.applied; then
  printf '%s\n' "${'$'}policy" > ./sharing.applied.tmp
  mv -f ./sharing.applied.tmp ./sharing.applied
 fi
}
if [ -f ./hotspot.snapshot ] && [ "${'$'}(cat ./hotspot.snapshot)" = "${'$'}snapshot" ]; then acknowledge; exit 0; fi
force=0
[ -f ./hotspot.snapshot ] || force=1
{
 echo '*mangle'; echo '-F MCLASH_R_HOT'
 for iface in ${'$'}ifaces; do
  for proto in tcp udp; do echo "-A MCLASH_R_HOT -i ${'$'}iface -p ${'$'}proto --dport 53 -j RETURN"; done
  for addr in ${'$'}addresses4; do echo "-A MCLASH_R_HOT -i ${'$'}iface -d ${'$'}addr/32 -j RETURN"; done
  for addr in 224.0.0.0/4 255.255.255.255/32; do echo "-A MCLASH_R_HOT -i ${'$'}iface -d ${'$'}addr -j RETURN"; done
  if [ "${'$'}BYPASS_LAN" = 1 ]; then
   for addr in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16; do echo "-A MCLASH_R_HOT -i ${'$'}iface -d ${'$'}addr -j RETURN"; done
  fi
  for proto in tcp udp; do echo "-A MCLASH_R_HOT -i ${'$'}iface -p ${'$'}proto ${if (tun) "-j MARK --set-xmark 0x20000000/0x20000000" else "-j TPROXY --on-ip 127.0.0.1 --on-port 17894 --tproxy-mark 0x20000000/0x20000000"}"; done
 done
 echo COMMIT
} > ./hotspot-data4.restore.next
{
 echo '*nat'; echo '-F MCLASH_R_HDNS'
 for iface in ${'$'}ifaces; do
  for proto in tcp udp; do echo "-A MCLASH_R_HDNS -i ${'$'}iface -p ${'$'}proto --dport 53 -j REDIRECT --to-ports 11053"; done
 done
 echo COMMIT
} > ./hotspot-dns4.restore.next
{
 echo '*filter'; echo '-F MCLASH_R_HV6'
 if [ "${'$'}IPV6" = 0 ]; then
  for iface in ${'$'}ifaces; do
   for proto in tcp udp; do echo "-A MCLASH_R_HV6 -i ${'$'}iface -p ${'$'}proto -j REJECT"; done
  done
 fi
 echo COMMIT
} > ./hotspot-block6.restore.next
if [ "${'$'}IPV6" = 1 ]; then
 {
  echo '*mangle'; echo '-F MCLASH_R_HOT6'
  for iface in ${'$'}ifaces; do
   for proto in tcp udp; do echo "-A MCLASH_R_HOT6 -i ${'$'}iface -p ${'$'}proto --dport 53 -j RETURN"; done
   for addr in ${'$'}addresses6; do echo "-A MCLASH_R_HOT6 -i ${'$'}iface -d ${'$'}addr/128 -j RETURN"; done
   for addr in ::1/128 fe80::/10 ff00::/8; do echo "-A MCLASH_R_HOT6 -i ${'$'}iface -d ${'$'}addr -j RETURN"; done
   if [ "${'$'}BYPASS_LAN" = 1 ]; then echo "-A MCLASH_R_HOT6 -i ${'$'}iface -d fc00::/7 -j RETURN"; fi
   for port in 546 547; do echo "-A MCLASH_R_HOT6 -i ${'$'}iface -p udp --dport ${'$'}port -j RETURN"; done
   for proto in tcp udp; do echo "-A MCLASH_R_HOT6 -i ${'$'}iface -p ${'$'}proto ${if (tun) "-j MARK --set-xmark 0x20000000/0x20000000" else "-j TPROXY --on-ip ::1 --on-port 17894 --tproxy-mark 0x20000000/0x20000000"}"; done
  done
  echo COMMIT
 } > ./hotspot-data6.restore.next
 {
  echo '*mangle'; echo '-F MCLASH_R_HDNS6'
  for iface in ${'$'}ifaces; do
   for proto in tcp udp; do echo "-A MCLASH_R_HDNS6 -i ${'$'}iface -p ${'$'}proto --dport 53 ${if (tun) "-j MARK --set-xmark 0x20000000/0x20000000" else "-j TPROXY --on-ip ::1 --on-port 17895 --tproxy-mark 0x20000000/0x20000000"}"; done
  done
  echo COMMIT
 } > ./hotspot-dns6.restore.next
fi
apply_batch() {
 tool=${'$'}1; file=${'$'}2
 if [ "${'$'}force" = 1 ] || ! cmp -s "${'$'}file.next" "${'$'}file"; then
  "${'$'}tool" -w 5 --noflush < "${'$'}file.next"
  mv -f "${'$'}file.next" "${'$'}file"
 else
  rm -f "${'$'}file.next"
 fi
}
apply_batch iptables-restore ./hotspot-data4.restore
apply_batch iptables-restore ./hotspot-dns4.restore
apply_batch ip6tables-restore ./hotspot-block6.restore
if [ "${'$'}IPV6" = 1 ]; then
 apply_batch ip6tables-restore ./hotspot-data6.restore
 apply_batch ip6tables-restore ./hotspot-dns6.restore
fi
printf '%s\n' "${'$'}snapshot" > ./hotspot.snapshot.tmp
mv -f ./hotspot.snapshot.tmp ./hotspot.snapshot
acknowledge
printf '%s 热点规则已更新：%s\n' "${'$'}(date '+%Y-%m-%d %H:%M:%S')" "${'$'}{ifaces:-热点关闭}"
        """.trimIndent() + "\n"
}
