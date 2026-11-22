package com.example.exm1

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews

class DailyReminderWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_NEXT) {
            refreshAll(context, advance = true)
        }
    }

    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        widgetIds: IntArray
    ) {
        widgetIds.forEach { render(context, manager, it, advance = false) }
    }

    companion object {
        private const val ACTION_NEXT =
            "com.example.exm1.action.NEXT_DAILY_REMINDER"
        private const val DATA_PREFS = "daily_reminder_widget_data"
        private const val DATA_KEY = "selected_notes_json"
        private const val STATE_PREFS = "daily_reminder_widget_state"
        private const val CURRENT_NOTE_PREFIX = "current_note_"
        private const val FLUTTER_PREFS = "FlutterSharedPreferences"

        /**
         * Replaces the complete widget data snapshot in one synchronous commit.
         * The widget does not read Flutter's internal preference keys.
         */
        fun syncData(context: Context, payload: String): Int {
            val notes = DailyReminderWidgetData.parse(payload)
            val normalizedPayload = org.json.JSONArray().apply {
                notes.forEach { note ->
                    put(org.json.JSONObject().apply {
                        put("id", note.id)
                        put("title", note.title)
                        put("body", note.body)
                    })
                }
            }.toString()

            val saved = context.getSharedPreferences(
                DATA_PREFS,
                Context.MODE_PRIVATE
            ).edit()
                .putString(DATA_KEY, normalizedPayload)
                .commit()

            check(saved) { "ذخیره اطلاعات ویجت انجام نشد" }

            // A new selection starts from the first selected note.
            context.getSharedPreferences(
                STATE_PREFS,
                Context.MODE_PRIVATE
            ).edit().clear().commit()

            refreshAll(context)
            return notes.size
        }

        fun refreshAll(context: Context, advance: Boolean = false) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(
                context,
                DailyReminderWidgetProvider::class.java
            )
            manager.getAppWidgetIds(component).forEach { widgetId ->
                render(context, manager, widgetId, advance)
            }
        }

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
            advance: Boolean
        ) {
            val dataPrefs = context.getSharedPreferences(
                DATA_PREFS,
                Context.MODE_PRIVATE
            )
            val notes = DailyReminderWidgetData.parse(
                dataPrefs.getString(DATA_KEY, "[]") ?: "[]"
            )

            val statePrefs = context.getSharedPreferences(
                STATE_PREFS,
                Context.MODE_PRIVATE
            )
            val currentKey = CURRENT_NOTE_PREFIX + widgetId
            val previousId = statePrefs.getString(currentKey, null)
            val previousIndex = notes.indexOfFirst { it.id == previousId }
            val selected = when {
                notes.isEmpty() -> null
                advance -> notes[(previousIndex + 1).mod(notes.size)]
                previousIndex >= 0 -> notes[previousIndex]
                else -> notes.first()
            }
            statePrefs.edit().putString(currentKey, selected?.id).apply()

            val views = RemoteViews(
                context.packageName,
                R.layout.daily_reminder_widget
            )

            val flutterPrefs = context.getSharedPreferences(
                FLUTTER_PREFS,
                Context.MODE_PRIVATE
            )
            val background = flutterPrefs.getInt(
                "flutter.featured_note_widget_background_color",
                Color.rgb(36, 42, 50)
            )
            val textColor = flutterPrefs.getInt(
                "flutter.featured_note_widget_text_color",
                Color.rgb(196, 204, 214)
            )
            val headingColor = flutterPrefs.getInt(
                "flutter.featured_note_widget_heading_color",
                Color.rgb(191, 199, 210)
            )

            views.setInt(
                R.id.daily_reminder_root,
                "setBackgroundColor",
                background
            )
            views.setTextColor(R.id.daily_reminder_heading, headingColor)
            views.setTextColor(R.id.daily_reminder_title, textColor)
            views.setTextColor(R.id.daily_reminder_body, textColor)
            views.setTextColor(R.id.daily_reminder_next, headingColor)

            if (selected == null) {
                views.setViewVisibility(R.id.daily_reminder_title, View.GONE)
                views.setTextViewText(
                    R.id.daily_reminder_body,
                    "از منوی یادداشت، «افزودن به ویجت» را انتخاب کن."
                )
                views.setViewVisibility(R.id.daily_reminder_next, View.GONE)
            } else {
                views.setViewVisibility(R.id.daily_reminder_title, View.VISIBLE)
                views.setViewVisibility(R.id.daily_reminder_next, View.VISIBLE)
                views.setTextViewText(R.id.daily_reminder_title, selected.title)
                val text = DailyReminderWidgetData.displayText(selected.body)
                val visibleText = when {
                    text.isBlank() -> "این یادداشت متنی ندارد."
                    text.length > 260 -> text.take(260).trimEnd() + "…"
                    else -> text
                }
                views.setTextViewText(R.id.daily_reminder_body, visibleText)
            }

            val openApp = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            openApp.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
            val openPending = PendingIntent.getActivity(
                context,
                widgetId,
                openApp,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.daily_reminder_root, openPending)

            val nextIntent = Intent(
                context,
                DailyReminderWidgetProvider::class.java
            ).apply {
                action = ACTION_NEXT
            }
            val nextPending = PendingIntent.getBroadcast(
                context,
                widgetId + 20000,
                nextIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.daily_reminder_next, nextPending)
            manager.updateAppWidget(widgetId, views)
        }
    }
}
