package com.liuyihtu.mclash.root

/** Keep selected tethering packets in netfilter instead of Android's tc redirect fast path. */
internal object HotspotOffload {
    fun functions(): String = """
offload_owned() {
 printf '%s\n' "${'$'}listing" | grep 'filter protocol all pref 1 bpf' |
  grep 'handle 0x4d43 ' | grep 'direct-action' | grep -F "bytecode '1,6 0 0 0'" >/dev/null
}
offload_foreign() {
 # TC_ACT_OK terminates classification. Refuse other classifiers/actions rather
 # than accidentally bypassing an administrator's filter further down the chain.
 printf '%s\n' "${'$'}listing" | sed -E \
  -e '/^filter protocol (ip|ipv6) pref [0-9]+ bpf( chain 0)?[[:space:]]*${'$'}/d' \
  -e '/^filter protocol all pref 1 bpf( chain 0)?[[:space:]]*${'$'}/d' \
  -e '/^filter .*prog_offload_schedcls_tether_upstream[46]_(ether|rawip)(:|[[:space:]])/d' \
  -e "/^filter protocol all pref 1 bpf .*handle 0x4d43 .*direct-action.*bytecode '1,6 0 0 0'/d" |
  grep '[^[:space:]]' >/dev/null
}
offload_remove() {
 iface=${'$'}1; index=${'$'}2
 case "${'$'}iface" in ''|*[!a-zA-Z0-9_.-]*) return 1;; esac
 case "${'$'}index" in ''|*[!0-9]*) return 1;; esac
 [ -r /sys/class/net/"${'$'}iface"/ifindex ] || return 0
 [ "${'$'}(cat /sys/class/net/"${'$'}iface"/ifindex)" = "${'$'}index" ] || return 0
 listing=${'$'}(tc filter show dev "${'$'}iface" ingress) || return 1
 offload_owned || return 0
 tc filter del dev "${'$'}iface" ingress protocol all pref 1 handle 19779 bpf || return 1
 listing=${'$'}(tc filter show dev "${'$'}iface" ingress) || return 1
 ! offload_owned
}
offload_cleanup() {
 [ -f ./offload.owned ] || return 0
 command -v tc >/dev/null || return 1
 while read -r iface index; do
  offload_remove "${'$'}iface" "${'$'}index" || return 1
 done < ./offload.owned
 rm -f ./offload.owned
}
offload_update() {
 # The journal is written before installation, so interrupted setup is recoverable.
 if [ -f ./offload.owned ]; then
  kept=${'$'}(while read -r iface index; do
   if printf '%s\n' "${'$'}ifaces" | grep -Fx "${'$'}iface" >/dev/null &&
      [ -r /sys/class/net/"${'$'}iface"/ifindex ] &&
      [ "${'$'}(cat /sys/class/net/"${'$'}iface"/ifindex)" = "${'$'}index" ]; then
    printf '%s %s\n' "${'$'}iface" "${'$'}index"
   else
    offload_remove "${'$'}iface" "${'$'}index" || exit 1
   fi
  done < ./offload.owned) || return 1
  if [ "${'$'}kept" != "${'$'}(cat ./offload.owned)" ]; then
   printf '%s\n' "${'$'}kept" | sed '/^${'$'}/d' > ./offload.next
   mv ./offload.next ./offload.owned
  fi
 fi
 [ -n "${'$'}ifaces" ] || { rm -f ./offload.owned; return 0; }
 command -v tc >/dev/null || { echo '共享代理需要系统 tc 工具'; return 1; }
 for iface in ${'$'}ifaces; do
  listing=${'$'}(tc filter show dev "${'$'}iface" ingress) || return 1
  if offload_owned || printf '%s\n' "${'$'}listing" | grep -E 'prog_offload_schedcls_tether_upstream[46]_' >/dev/null; then
   if offload_foreign; then
    if offload_owned; then
     index=${'$'}(cat /sys/class/net/"${'$'}iface"/ifindex) || return 1
     grep -Fx "${'$'}iface ${'$'}index" ./offload.owned >/dev/null 2>&1 || return 1
     offload_remove "${'$'}iface" "${'$'}index" || return 1
    fi
    echo '共享接口存在其他流量过滤器，拒绝绕过'; return 1
   fi
  fi
  if offload_owned; then
   index=${'$'}(cat /sys/class/net/"${'$'}iface"/ifindex) || return 1
   grep -Fx "${'$'}iface ${'$'}index" ./offload.owned >/dev/null 2>&1 || { echo '共享过滤器身份冲突'; return 1; }
   continue
  fi
  # Never remove, replace or reorder a system/foreign filter. Only known Android
  # tethering acceleration needs interception; older systems retain their path.
  printf '%s\n' "${'$'}listing" | grep -E 'prog_offload_schedcls_tether_upstream[46]_' >/dev/null || continue
  index=${'$'}(cat /sys/class/net/"${'$'}iface"/ifindex) || return 1
  if printf '%s\n' "${'$'}listing" | grep -q 'pref 1 '; then echo '共享过滤器优先级 1 已占用'; return 1; fi
  if ! grep -Fx "${'$'}iface ${'$'}index" ./offload.owned >/dev/null 2>&1; then
   { [ ! -f ./offload.owned ] || cat ./offload.owned; printf '%s %s\n' "${'$'}iface" "${'$'}index"; } > ./offload.next
   mv ./offload.next ./offload.owned
  fi
  # One classic BPF RET TC_ACT_OK instruction: proceed through the normal stack.
  # This leaves Android's own BPF programs attached and needs no userspace worker.
  tc filter add dev "${'$'}iface" ingress protocol all pref 1 handle 19779 bpf bytecode '1,6 0 0 0,' direct-action || return 1
  listing=${'$'}(tc filter show dev "${'$'}iface" ingress) || return 1
  offload_owned || return 1
 done
 return 0
}
""".trimIndent() + "\n"
}
