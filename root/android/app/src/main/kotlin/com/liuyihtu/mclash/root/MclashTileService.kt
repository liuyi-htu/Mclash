package com.liuyihtu.mclash.root

import android.graphics.drawable.Icon
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.view.Gravity
import android.widget.Toast

class MclashTileService : TileService() {
    override fun onTileAdded() {
        super.onTileAdded()
        updateTileState()
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
        Thread({
            runCatching { MihomoProcess.attach(this) }
            android.os.Handler(android.os.Looper.getMainLooper()).post { updateTileState() }
        }, "root-tile-probe").start()
    }

    override fun onClick() {
        super.onClick()

        val action = Runnable {
            if (ProxyTProxyService.tileStopPending) return@Runnable
            try {
                ProxyTProxyService.toggle(this)
            } catch (error: Throwable) {
                Toast.makeText(this, error.message ?: "无法切换 Root 代理", Toast.LENGTH_SHORT)
                    .apply { setGravity(Gravity.TOP or Gravity.CENTER_HORIZONTAL, 0, 96) }
                    .show()
            }
            updateTileState()
        }

        if (isLocked) {
            unlockAndRun(action)
        } else {
            action.run()
        }
    }

    private fun updateTileState() {
        ProxyTProxyService.restore(this)
        val tile = qsTile ?: return
        val store = ConfigStore(this)
        val profile = store.activeProfile()
        val hasConfig = profile != null && store.exists()
        val stopping = ProxyTProxyService.tileStopPending
        val active = !stopping && ProxyTProxyService.tileActive(this)
        val label = profile?.name
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?.take(MAX_TILE_LABEL_LENGTH)
            ?: "Mclash"

        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_clash)
        tile.label = label
        tile.contentDescription = when {
            stopping -> "$label，正在停止"
            ProxyTProxyService.lastError?.startsWith("停止清理失败：") == true -> "$label，停止失败"
            !hasConfig && !active -> "$label，未配置"
            ProxyTProxyService.starting -> "$label，正在启动"
            active -> "$label，已启动"
            else -> "$label，已停止"
        }
        tile.state = when {
            stopping -> Tile.STATE_INACTIVE
            !hasConfig && !active -> Tile.STATE_UNAVAILABLE
            active -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        tile.updateTile()
    }

    companion object {
        private const val MAX_TILE_LABEL_LENGTH = 18
    }
}
