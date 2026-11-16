package com.neurocompanion.app

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Static policy only: launching this exported page cannot read health data. */
class NeuraHealthPrivacyActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val column = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 40, 32, 32)
        }
        column.addView(TextView(this).apply {
            textSize = 18f
            text = getString(R.string.neura_health_privacy_statement)
        })
        column.addView(Button(this).apply { text = getString(R.string.neura_health_privacy_close); setOnClickListener { finish() } })
        setContentView(ScrollView(this).apply { addView(column) })
    }
}
