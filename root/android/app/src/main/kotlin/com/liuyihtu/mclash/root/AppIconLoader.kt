package com.liuyihtu.mclash.root

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import java.io.ByteArrayOutputStream

/** Rasterize both ordinary and adaptive application icons away from the UI thread. */
internal object AppIconLoader {
    fun load(context: Context, packageName: String): ByteArray? = runCatching {
        val drawable = context.packageManager.getApplicationIcon(packageName)
        val bitmap = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888)
        val bounds = Rect(drawable.bounds)
        try {
            drawable.setBounds(0, 0, bitmap.width, bitmap.height)
            drawable.draw(Canvas(bitmap))
            ByteArrayOutputStream().use { output ->
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
                output.toByteArray()
            }
        } finally {
            drawable.bounds = bounds
            bitmap.recycle()
        }
    }.getOrNull()
}
