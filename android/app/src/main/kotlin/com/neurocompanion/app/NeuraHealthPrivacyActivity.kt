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
            text = "Neura — connected health data\n\n" +
                "Neura can read the heart rate, steps and sleep sessions you select from this Android user's Health Connect data. " +
                "A foreground Read action is required each time. Permission approval alone does not read anything.\n\n" +
                "Readings stay in this screen's memory and clear when you leave, background, stop, or enter Safe Mode or recovery. " +
                "Neura does not write or delete Health Connect records, read in the background, send them to a model or clinic, or save them to a journal.\n\n" +
                "Copying selected readings requires a separate review. Copied text is outside Neura and may be synced by your clipboard. " +
                "Use Health Connect's permission controls to revoke Neura's access. Clearing this view does not delete source records or revoke Android grants.\n\n" +
                "Source apps and wearables have their own sync policies. Synced readings can be delayed, incomplete or inaccurate. " +
                "This feature does not diagnose a condition or monitor emergencies."
        })
        column.addView(Button(this).apply { text = "Close"; setOnClickListener { finish() } })
        setContentView(ScrollView(this).apply { addView(column) })
    }
}
