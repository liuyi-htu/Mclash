#!/system/bin/sh
MODDIR=${0%/*}
"$MODDIR/bin/mclashctl" stop >/dev/null 2>&1
rm -rf /data/adb/mclash/run /data/adb/mclash/update
# User configuration and logs are intentionally retained in /data/adb/mclash.
