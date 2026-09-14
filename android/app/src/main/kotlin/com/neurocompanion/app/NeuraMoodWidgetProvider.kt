// UNVERIFIED: authored without an Android build/emulator available in the
// drafting environment. Review and test on a device before shipping.
//
// Renders the bounded, display-only data HomeWidgetBridge (Dart side)
// already computed and saved -- this class makes no decisions of its own.
package com.neurocompanion.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class NeuraMoodWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = buildViews(context, widgetData)
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun buildViews(context: Context, widgetData: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.neura_mood_widget)

        val pendingIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        views.setOnClickPendingIntent(R.id.neura_widget_container, pendingIntent)

        val safeMode = widgetData.getString("neura_widget_safe_mode", "0") == "1"
        views.setViewVisibility(
            R.id.neura_widget_safe_mode_line,
            if (safeMode) View.VISIBLE else View.GONE
        )

        val moodValue = widgetData.getString("neura_widget_mood_value", "") ?: ""
        val moodAge = widgetData.getString("neura_widget_mood_age", "") ?: ""
        views.setTextViewText(
            R.id.neura_widget_mood_line,
            if (moodValue.isEmpty()) {
                "No check-in yet"
            } else {
                "Last check-in: $moodValue/10 ($moodAge)"
            }
        )

        val nudgeTitle = widgetData.getString("neura_widget_nudge_title", "") ?: ""
        views.setViewVisibility(
            R.id.neura_widget_nudge_line,
            if (nudgeTitle.isEmpty() || safeMode) View.GONE else View.VISIBLE
        )
        if (nudgeTitle.isNotEmpty()) {
            views.setTextViewText(R.id.neura_widget_nudge_line, nudgeTitle)
        }

        return views
    }
}
