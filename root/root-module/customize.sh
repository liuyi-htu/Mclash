#!/system/bin/sh
SKIPUNZIP=0
ui_print "- Installing Mclash Root Runtime"
mkdir -p /data/adb/mclash/bin /data/adb/mclash/config /data/adb/mclash/logs /data/adb/mclash/run
chmod 0700 /data/adb/mclash /data/adb/mclash/bin /data/adb/mclash/config /data/adb/mclash/run
chmod 0755 "$MODPATH/service.sh" "$MODPATH/uninstall.sh" "$MODPATH/bin/mclashctl"
chmod 0755 "$MODPATH/scripts/apply-tproxy.sh" "$MODPATH/scripts/clear-tproxy.sh"
touch /data/adb/mclash/logs/module.log /data/adb/mclash/logs/mihomo.log /data/adb/mclash/logs/update.log
chmod 0600 /data/adb/mclash/logs/*.log
