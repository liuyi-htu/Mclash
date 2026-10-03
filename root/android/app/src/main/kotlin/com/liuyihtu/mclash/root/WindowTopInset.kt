package com.liuyihtu.mclash.root

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
    max(0, statusTop - contentScreenTop),
    max(0, max(captionTop, cutoutTop) - contentWindowTop),
)

internal fun Activity.smallWindowTopInset(): Double? {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N || !isInMultiWindowMode) return null
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
    return requiredWindowTopInset(
        statusTop, captionTop, cutoutTop,
        contentPosition[1], contentPosition[1] - decorPosition[1],
    ) / resources.displayMetrics.density.toDouble()
}
