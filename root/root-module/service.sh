#!/system/bin/sh
DATA=/data/adb/mclash
LOG="$DATA/logs/module.log"
ENV="$DATA/config/root.env"
mkdir -p "$DATA/logs" "$DATA/run"
echo "$(date '+%F %T') service.sh started" >> "$LOG"
[ -r "$ENV" ] || { echo "$(date '+%F %T') root.env missing; auto-start skipped" >> "$LOG"; exit 0; }
. "$ENV"
[ "${AUTO_START:-0}" = "1" ] || { echo "$(date '+%F %T') auto-start disabled" >> "$LOG"; exit 0; }
i=0
while [ "$i" -lt 60 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 2
  i=$((i + 1))
done
"${0%/*}/bin/mclashctl" start >> "$LOG" 2>&1 || echo "$(date '+%F %T') auto-start failed" >> "$LOG"
