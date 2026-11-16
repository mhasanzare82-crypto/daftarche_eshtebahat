package com.example.exm1

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject

class FeaturedNoteWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_NEXT_NOTE) {
            refreshAll(context, chooseNext = true)
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { updateOne(context, manager, it, chooseNext = false) }
    }

    companion object {
        private const val PREFS_FILE = "FlutterSharedPreferences"
        private const val NOTES_KEY = "flutter.notebook_notes"
        private const val WIDGET_PREFS = "featured_note_widget"
        private const val ACTION_NEXT_NOTE = "com.example.exm1.ACTION_NEXT_FEATURED_NOTE"

        fun refreshAll(context: Context, chooseNext: Boolean = false) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, FeaturedNoteWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { id ->
                updateOne(context, manager, id, chooseNext)
            }
        }

        private fun updateOne(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
            chooseNext: Boolean
        ) {
            val appPrefs = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            val notes = try {
                JSONArray(appPrefs.getString(NOTES_KEY, "[]") ?: "[]")
            } catch (_: Exception) {
                JSONArray()
            }
            val available = (0 until notes.length()).mapNotNull { notes.optJSONObject(it) }
            val widgetPrefs = context.getSharedPreferences(WIDGET_PREFS, Context.MODE_PRIVATE)
            val key = "featured_note_$widgetId"
            val previousId = widgetPrefs.getString(key, null)
            val previous = available.firstOrNull { it.optString("id") == previousId }
            val selected = when {
                available.isEmpty() -> null
                chooseNext -> {
                    val candidates = available.filter { it.optString("id") != previousId }
                    (candidates.ifEmpty { available }).random()
                }
                previous != null -> previous
                else -> available.random()
            }
            widgetPrefs.edit().putString(key, selected?.optString("id")).apply()

            val views = RemoteViews(context.packageName, R.layout.featured_note_widget)
            if (selected == null) {
                views.setTextViewText(R.id.featured_note_title, "هنوز یادداشتی نداری")
                views.setTextViewText(R.id.featured_note_body, "برای ساخت اولین یادداشت، دفترچه را باز کن.")
                views.setTextViewText(R.id.featured_note_hint, "دفترچه اشتباهات")
            } else {
                val title = selected.optString("title").ifBlank { "بدون عنوان" }
                val body = plainText(selected.optString("body"))
                    .replace(Regex("\\s+"), " ").trim()
                val snippet = body.take(112).let { if (body.length > 112) "$it…" else it }
                    .ifBlank { "این یادداشت متنی ندارد." }
                views.setTextViewText(R.id.featured_note_title, title)
                views.setTextViewText(R.id.featured_note_body, snippet)
                views.setTextViewText(R.id.featured_note_hint, "یک یادداشت برای مرور")
            }

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val openPending = PendingIntent.getActivity(
                context, widgetId, launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.featured_note_root, openPending)

            val nextIntent = Intent(context, FeaturedNoteWidgetProvider::class.java).apply {
                action = ACTION_NEXT_NOTE
            }
            val nextPending = PendingIntent.getBroadcast(
                context, widgetId + 10000, nextIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.featured_note_next, nextPending)
            manager.updateAppWidget(widgetId, views)
        }

        private fun plainText(body: String): String {
            val quillMarker = "__quill_note_v1__"
            val legacyMarker = "__rich_note_v1__"
            return try {
                when {
                    body.startsWith(quillMarker) -> {
                        val ops = JSONArray(body.removePrefix(quillMarker))
                        buildString {
                            for (i in 0 until ops.length()) {
                                val insert = ops.optJSONObject(i)?.opt("insert")
                                if (insert is String) append(insert)
                            }
                        }
                    }
                    body.startsWith(legacyMarker) || body.trimStart().startsWith("[") -> {
                        val raw = body.removePrefix(legacyMarker).let {
                            if (it == body) body else it
                        }
                        val blocks = JSONArray(raw)
                        buildString {
                            for (i in 0 until blocks.length()) {
                                val block = blocks.optJSONObject(i) ?: continue
                                if (block.optString("type") == "text") append(block.optString("text")).append(' ')
                            }
                        }
                    }
                    else -> body
                }
            } catch (_: Exception) {
                body.removePrefix(quillMarker).removePrefix(legacyMarker)
            }
        }
    }
}
