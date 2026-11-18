package com.example.exm1

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONArray

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
        private const val WIDGET_NOTE_IDS_KEY = "flutter.notebook_widget_note_ids"
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
            val allNotes = (0 until notes.length()).mapNotNull { notes.optJSONObject(it) }
            val selectedIds = try {
                val raw = appPrefs.getString(WIDGET_NOTE_IDS_KEY, "[]") ?: "[]"
                val ids = JSONArray(raw)
                (0 until ids.length()).map { ids.optString(it) }
            } catch (_: Exception) { emptyList() }
            // Keep the widget useful if the saved selection is empty or stale.
            // Prefer explicitly selected notes, but fall back to the notebook notes
            // instead of leaving the daily reminder widget blank.
            val selectedNotes = selectedIds.mapNotNull { id ->
                allNotes.firstOrNull { it.optString("id") == id }
            }
            val available = selectedNotes.ifEmpty { allNotes }
            val widgetPrefs = context.getSharedPreferences(WIDGET_PREFS, Context.MODE_PRIVATE)
            val key = "featured_note_$widgetId"
            val previousId = widgetPrefs.getString(key, null)
            val previous = available.firstOrNull { it.optString("id") == previousId }
            val selected = when {
                available.isEmpty() -> null
                chooseNext -> {
                    val currentIndex = available.indexOfFirst { it.optString("id") == previousId }
                    available[(currentIndex + 1).mod(available.size)]
                }
                previous != null -> previous
                else -> available.first()
            }
            widgetPrefs.edit().putString(key, selected?.optString("id")).apply()

            val views = RemoteViews(context.packageName, R.layout.featured_note_widget)
            val widgetBackground = appPrefs.getInt(
                "flutter.featured_note_widget_background_color",
                android.graphics.Color.rgb(36, 42, 50)
            )
            val widgetText = appPrefs.getInt(
                "flutter.featured_note_widget_text_color",
                android.graphics.Color.rgb(196, 204, 214)
            )
            val widgetHeading = appPrefs.getInt(
                "flutter.featured_note_widget_heading_color",
                android.graphics.Color.rgb(191, 199, 210)
            )
            views.setInt(R.id.featured_note_root, "setBackgroundColor", widgetBackground)
            views.setTextColor(R.id.featured_note_body, widgetText)
            views.setTextColor(R.id.featured_note_next, widgetHeading)
            views.setTextColor(R.id.featured_note_heading, widgetText)
            // Keep the content area visible in launcher RemoteViews layouts.
            views.setViewVisibility(R.id.featured_note_body, android.view.View.VISIBLE)

            if (selected == null) {
                views.setViewVisibility(R.id.featured_note_title, android.view.View.GONE)
                views.setTextViewText(R.id.featured_note_body, "از گزینه‌های هر یادداشت، «افزودن به ویجت» را بزن.")
                views.setViewVisibility(R.id.featured_note_hint, android.view.View.VISIBLE)
                views.setTextViewText(R.id.featured_note_hint, "نوشته‌ای برای ویجت انتخاب نشده")
            } else {
                val title = selected.optString("title").ifBlank { "بدون عنوان" }
                val fullBody = plainText(selected.optString("body"))
                // Every note can contain multiple entries separated by the
                // standard 20-hyphen or 79-hyphen divider.
                val displayBody = pickRandomEntry(fullBody)
                val body = displayBody.replace(Regex("\\s+"), " ").trim()
                val snippet = body.take(180).let { if (body.length > 180) "$it…" else it }
                    .ifBlank { "این یادداشت متنی ندارد." }

                // The title view starts as GONE in XML; explicitly reveal it and show
                // the selected note's real title rather than the widget's generic label.
                views.setViewVisibility(R.id.featured_note_title, android.view.View.VISIBLE)
                views.setTextViewText(R.id.featured_note_title, title)
                views.setTextViewText(R.id.featured_note_body, snippet)
                views.setViewVisibility(R.id.featured_note_hint, android.view.View.GONE)
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

        /**
         * Treat both the 20-hyphen separator and the 79-hyphen Quick Note
         * separator as entry boundaries. Any standalone separator line with
         * at least 20 hyphens is recognized.
         */
        private fun pickRandomEntry(body: String): String {
            val separatorRegex = Regex("(?m)^\\s*-{20,}\\s*$")
            val entries = body.split(separatorRegex)
                .map { it.trim() }
                .filter { it.isNotBlank() }
            return entries.randomOrNull() ?: body.trim()
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
                // Never expose serialized rich-text JSON as if it were note text.
                "متن قالب‌بندی‌شده این یادداشت قابل خواندن نیست."
            }
        }
    }
}
