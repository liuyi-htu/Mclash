package com.liuyihtu.mclash

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.service.quicksettings.TileService

internal object QuickSettingsTileUpdater {
    fun request(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return

        runCatching {
            TileService.requestListeningState(
                context.applicationContext,
                ComponentName(context, MclashTileService::class.java),
            )
        }
    }
}
