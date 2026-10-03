package com.liuyihtu.mclash

import android.app.Activity
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import io.flutter.embedding.android.FlutterView
import kotlin.math.max

internal fun requiredWindowTopInset(
    statusTop: Int, captionTop: Int, cutoutTop: Int,
    contentScreenTop: Int, contentWindowTop: Int,
): Int = max(
    max(0, max(statusTop, cutoutTop) - contentScreenTop),
    max(0, captionTop - contentWindowTop),
)

internal fun isCompactAppWindow(
    multiWindow: Boolean, captionTop: Int,
    windowWidth: Int, windowHeight: Int,
    maximumWidth: Int, maximumHeight: Int,
): Boolean = multiWindow || captionTop > 0 || (
    windowWidth > 0 && windowHeight > 0 && maximumWidth > 0 && maximumHeight > 0 &&
        (windowWidth < maximumWidth - 1 || windowHeight < maximumHeight - 1)
    )

internal fun isFloatingAppWindow(
    captionTop: Int, windowWidth: Int, windowHeight: Int,
    maximumWidth: Int, maximumHeight: Int,
): Boolean = captionTop > 0 || (
    windowWidth > 0 && windowHeight > 0 && maximumWidth > 0 && maximumHeight > 0 &&
        windowWidth < maximumWidth - 1 && windowHeight < maximumHeight - 1
    )

internal fun Activity.smallWindowTopInset(): Double? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return null
    fun findFlutter(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findFlutter(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }
    val decor = window.decorView
    val content = findFlutter(decor) ?: return null
    val insets = decor.rootWindowInsets ?: return null
    val decorPosition = IntArray(2)
    val contentPosition = IntArray(2)
    decor.getLocationOnScreen(decorPosition)
    content.getLocationOnScreen(contentPosition)
    val statusTop: Int
    val captionTop: Int
    val cutoutTop: Int
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        statusTop = insets.getInsets(WindowInsets.Type.statusBars()).top
        captionTop = insets.getInsets(WindowInsets.Type.captionBar()).top
        cutoutTop = insets.getInsets(WindowInsets.Type.displayCutout()).top
    } else {
        @Suppress("DEPRECATION")
        val legacyTop = insets.systemWindowInsetTop
        statusTop = legacyTop
        captionTop = 0
        cutoutTop = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            insets.displayCutout?.safeInsetTop ?: 0
        } else 0
    }
    val compactWindow = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val bounds = windowManager.currentWindowMetrics.bounds
        val maximumBounds = windowManager.maximumWindowMetrics.bounds
        if (isFloatingAppWindow(
                captionTop, bounds.width(), bounds.height(),
                maximumBounds.width(), maximumBounds.height(),
            )) return 0.0
        isCompactAppWindow(
            isInMultiWindowMode, captionTop,
            bounds.width(), bounds.height(), maximumBounds.width(), maximumBounds.height(),
        )
    } else {
        // Older Android versions have no window metrics. Width is unaffected by
        // IME resize, so it can detect a floating window without treating the
        // fullscreen keyboard as a window-mode change.
        val displaySize = android.graphics.Point()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealSize(displaySize)
        @Suppress("DEPRECATION")
        val bottomInset = insets.systemWindowInsetBottom
        if (isFloatingAppWindow(
                captionTop, decor.width, decor.height + max(statusTop, cutoutTop) + bottomInset,
                displaySize.x, displaySize.y,
            )) return 0.0
        isCompactAppWindow(
            isInMultiWindowMode, captionTop,
            decor.width, displaySize.y, displaySize.x, displaySize.y,
        )
    }
    if (!compactWindow) return null
    // Window bounds locate the content on the display even when an OEM
    // reports view coordinates relative to the floating window.
    val contentWindowTop = contentPosition[1] - decorPosition[1]
    val contentScreenTop = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        windowManager.currentWindowMetrics.bounds.top + contentWindowTop
    } else contentPosition[1]
    return requiredWindowTopInset(
        statusTop, captionTop, cutoutTop,
        contentScreenTop, contentWindowTop,
    ) / resources.displayMetrics.density.toDouble()
}
