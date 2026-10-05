package com.liuyihtu.mclash.root

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

internal object LauncherIconPalette {
    val colors = linkedMapOf(
        "Blue" to 0xFF315F95.toInt(),
        "Purple" to 0xFF7356A6.toInt(),
        "Green" to 0xFF26745A.toInt(),
        "Orange" to 0xFFA75B29.toInt(),
        "Pink" to 0xFFAD476B.toInt(),
        "Cyan" to 0xFF357C85.toInt(),
        "Gray" to 0xFF675F71.toInt(),
    )

    fun select(color: Int): String = colors.minBy { (_, candidate) ->
        listOf(16, 8, 0).sumOf { shift ->
            val difference = ((color ushr shift) and 255) - ((candidate ushr shift) and 255)
            difference * difference
        }
    }.key
}

internal object LauncherThemeIcon {
    fun apply(context: Context, color: Int) {
        val pm = context.packageManager
        val chosen = LauncherIconPalette.select(color)
        val changes = LauncherIconPalette.colors.keys.mapNotNull { name ->
            val component = ComponentName(context, "${context.packageName}.ThemeLauncher$name")
            val enabled = name == chosen
            val current = pm.getComponentEnabledSetting(component)
            val isEnabled = current == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (current == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && name == "Blue")
            if (isEnabled == enabled) null else component to enabled
        }
        if (changes.isEmpty()) return
        if (Build.VERSION.SDK_INT >= 33) {
            pm.setComponentEnabledSettings(changes.map { (component, enabled) ->
                PackageManager.ComponentEnabledSetting(component,
                    if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP)
            })
        } else {
            // Enable the replacement before hiding the old entry. The service stays alive.
            changes.sortedByDescending { it.second }.forEach { (component, enabled) ->
                pm.setComponentEnabledSetting(component,
                    if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP)
            }
        }
    }
}
