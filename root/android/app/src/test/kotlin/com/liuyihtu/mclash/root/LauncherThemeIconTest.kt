package com.liuyihtu.mclash.root

import org.junit.Assert.assertEquals
import org.junit.Test

class LauncherThemeIconTest {
    @Test fun everyPresetSelectsItsOwnLauncherAndIgnoresAlpha() {
        LauncherIconPalette.colors.forEach { (name, color) ->
            assertEquals(name, LauncherIconPalette.select(color))
            assertEquals(name, LauncherIconPalette.select(color and 0x00FFFFFF))
        }
    }
    @Test fun customShadesSelectTheClosestAvailableColor() {
        assertEquals("Blue", LauncherIconPalette.select(0xFF325F96.toInt()))
        assertEquals("Green", LauncherIconPalette.select(0xFF27755B.toInt()))
    }
}
