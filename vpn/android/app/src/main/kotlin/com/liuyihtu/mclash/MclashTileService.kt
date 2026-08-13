package com.liuyihtu.mclash

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.view.Gravity
import android.widget.Toast

class MclashTileService : TileService() {
    private val handler = Handler(Looper.getMainLooper())

    override fun onTileAdded() {
        super.onTileAdded()
        updateTileState()
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()

        val action = Runnable {
            val store = ConfigStore(this)
            if (!store.exists()) {
                Toast.makeText(
                    this,
                    "请先在 Mclash 中添加配置",
                    Toast.LENGTH_SHORT,
                ).apply {
                    setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL, 0, 96)
                }.show()
                openMainActivity(requestStart = false)
                updateTileState()
                return@Runnable
            }

            if (ProxyVpnService.running || ProxyVpnService.starting) {
                ProxyVpnService.stop(this)
                updateTileState()
                handler.postDelayed(::updateTileState, 700)
                return@Runnable
            }

            if (VpnService.prepare(this) == null) {
                ProxyVpnService.start(this)
                updateTileState()
                handler.postDelayed(::updateTileState, 700)
            } else {
                Toast.makeText(
                    this,
                    "请完成一次 VPN 授权",
                    Toast.LENGTH_SHORT,
                ).apply {
                    setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL, 0, 96)
                }.show()
                openMainActivity(requestStart = true)
            }
        }

        if (isLocked) {
            unlockAndRun(action)
        } else {
            action.run()
        }
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        val store = ConfigStore(this)
        val profile = store.activeProfile()
        val hasConfig = profile != null && store.exists()
        val active = ProxyVpnService.running || ProxyVpnService.starting
        val label = profile?.name
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.take(MAX_TILE_LABEL_LENGTH)
            ?: "Mclash"

        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_clash)
        tile.label = label
        tile.contentDescription = when {
            !hasConfig -> "$label，未配置"
            ProxyVpnService.starting -> "$label，正在启动"
            active -> "$label，已启动"
            else -> "$label，已停止"
        }
        tile.state = when {
            !hasConfig -> Tile.STATE_UNAVAILABLE
            active -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        tile.updateTile()
    }

    private fun openMainActivity(requestStart: Boolean) {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
            ?.apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                putExtra(MainActivity.EXTRA_START_FROM_TILE, requestStart)
            }
            ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                8112,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    companion object {
        private const val MAX_TILE_LABEL_LENGTH = 18
    }
}
