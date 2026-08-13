package com.liuyihtu.mclash

import android.app.Activity
import android.content.Intent
import android.os.Bundle

class QuickSettingsPreferencesActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        openMclashHome()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        openMclashHome()
    }

    private fun openMclashHome() {
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        startActivity(mainIntent)
        finish()
        overridePendingTransition(0, 0)
    }
}
