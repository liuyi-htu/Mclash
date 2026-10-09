package com.liuyihtu.mclash.root

internal object RootHotspotMonitor {
    fun script(bypassLan: Boolean, ipv6: Boolean): String =
        "BYPASS_LAN=${if (bypassLan) 1 else 0}\nIPV6=${if (ipv6) 1 else 0}\n" + """
set -eu
umask 077
# All inputs below are produced by Android, never by a subscription.
dump=${'$'}(dumpsys tethering)
printf '%s\n' "${'$'}dump" | grep -q 'Tether state:' || { echo '无法读取热点状态'; exit 1; }
tether=${'$'}(printf '%s\n' "${'$'}dump" | sed -n '/Tether state:/,/Hardware offload:/p')
ifaces=${'$'}(printf '%s\n' "${'$'}tether" | awk '${'$'}2 == "-" && ${'$'}3 == "TetheredState" && ${'$'}4 == "-" && ${'$'}1 != "lo" && length(${'$'}1) <= 15 && ${'$'}1 ~ /^[a-zA-Z0-9_.-]+${'$'}/ {print ${'$'}1}' | sort -u)
raw4=${'$'}(ip -o -4 addr show)
raw6=${'$'}(ip -o -6 addr show)
addresses4=${'$'}(printf '%s\n' "${'$'}raw4" | awk '{split(${'$'}4, a, "/"); if (a[1] != "") print a[1]}' | sort -u)
addresses6=${'$'}(printf '%s\n' "${'$'}raw6" | awk '{split(${'$'}4, a, "/"); if (a[1] != "") print a[1]}' | sort -u)
[ -n "${'$'}addresses4" ] || { echo '无法读取本机 IPv4 地址'; exit 1; }
snapshot=${'$'}(printf '%s\n' "interfaces=${'$'}ifaces" "ipv4=${'$'}addresses4" "ipv6=${'$'}addresses6")
if [ -f ./hotspot.snapshot ] && [ "${'$'}(cat ./hotspot.snapshot)" = "${'$'}snapshot" ]; then exit 0; fi
{
 echo '*mangle'; echo '-F MCLASH_R_HOT'
 for iface in ${'$'}ifaces; do
  for proto in tcp udp; do echo "-A MCLASH_R_HOT -i ${'$'}iface -p ${'$'}proto --dport 53 -j RETURN"; done
  for addr in ${'$'}addresses4; do echo "-A MCLASH_R_HOT -i ${'$'}iface -d ${'$'}addr/32 -j RETURN"; done
  for addr in 224.0.0.0/4 255.255.255.255/32; do echo "-A MCLASH_R_HOT -i ${'$'}iface -d ${'$'}addr -j RETURN"; done
  if [ "${'$'}BYPASS_LAN" = 1 ]; then
   for addr in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16; do echo "-A MCLASH_R_HOT -i ${'$'}iface -d ${'$'}addr -j RETURN"; done
  fi
  for proto in tcp udp; do echo "-A MCLASH_R_HOT -i ${'$'}iface -p ${'$'}proto -j TPROXY --on-ip 127.0.0.1 --on-port 17894 --tproxy-mark 0x20000000/0x20000000"; done
 done
 echo COMMIT
} > ./hotspot-data4.restore
{
 echo '*nat'; echo '-F MCLASH_R_HDNS'
 for iface in ${'$'}ifaces; do
  for proto in tcp udp; do echo "-A MCLASH_R_HDNS -i ${'$'}iface -p ${'$'}proto --dport 53 -j REDIRECT --to-ports 11053"; done
 done
 echo COMMIT
} > ./hotspot-dns4.restore
{
 echo '*filter'; echo '-F MCLASH_R_HV6'
 if [ "${'$'}IPV6" = 0 ]; then
  for iface in ${'$'}ifaces; do
   for proto in tcp udp; do echo "-A MCLASH_R_HV6 -i ${'$'}iface -p ${'$'}proto -j REJECT"; done
  done
 fi
 echo COMMIT
} > ./hotspot-block6.restore
if [ "${'$'}IPV6" = 1 ]; then
 {
  echo '*mangle'; echo '-F MCLASH_R_HOT6'
  for iface in ${'$'}ifaces; do
   for proto in tcp udp; do echo "-A MCLASH_R_HOT6 -i ${'$'}iface -p ${'$'}proto --dport 53 -j RETURN"; done
   for addr in ${'$'}addresses6; do echo "-A MCLASH_R_HOT6 -i ${'$'}iface -d ${'$'}addr/128 -j RETURN"; done
   for addr in ::1/128 fe80::/10 ff00::/8; do echo "-A MCLASH_R_HOT6 -i ${'$'}iface -d ${'$'}addr -j RETURN"; done
   if [ "${'$'}BYPASS_LAN" = 1 ]; then echo "-A MCLASH_R_HOT6 -i ${'$'}iface -d fc00::/7 -j RETURN"; fi
   for port in 546 547; do echo "-A MCLASH_R_HOT6 -i ${'$'}iface -p udp --dport ${'$'}port -j RETURN"; done
   for proto in tcp udp; do echo "-A MCLASH_R_HOT6 -i ${'$'}iface -p ${'$'}proto -j TPROXY --on-ip ::1 --on-port 17894 --tproxy-mark 0x20000000/0x20000000"; done
  done
  echo COMMIT
 } > ./hotspot-data6.restore
 {
  echo '*mangle'; echo '-F MCLASH_R_HDNS6'
  for iface in ${'$'}ifaces; do
   for proto in tcp udp; do echo "-A MCLASH_R_HDNS6 -i ${'$'}iface -p ${'$'}proto --dport 53 -j TPROXY --on-ip ::1 --on-port 17895 --tproxy-mark 0x20000000/0x20000000"; done
  done
  echo COMMIT
 } > ./hotspot-dns6.restore
fi
iptables-restore -w 5 --noflush < ./hotspot-data4.restore
iptables-restore -w 5 --noflush < ./hotspot-dns4.restore
ip6tables-restore -w 5 --noflush < ./hotspot-block6.restore
if [ "${'$'}IPV6" = 1 ]; then
 ip6tables-restore -w 5 --noflush < ./hotspot-data6.restore
 ip6tables-restore -w 5 --noflush < ./hotspot-dns6.restore
fi
printf '%s\n' "${'$'}snapshot" > ./hotspot.snapshot
printf '%s 热点规则已更新：%s\n' "${'$'}(date '+%Y-%m-%d %H:%M:%S')" "${'$'}{ifaces:-热点关闭}"
        """.trimIndent() + "\n"
}
