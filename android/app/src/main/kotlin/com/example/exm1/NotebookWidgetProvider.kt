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

class NotebookWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        appWidgetIds.forEach { id -> updateOne(context, appWidgetManager, id) }
    }

    companion object {
        private const val PREFS_FILE = "FlutterSharedPreferences"
        private const val NOTES_KEY = "flutter.notebook_notes"
        private const val FOLDERS_KEY = "flutter.notebook_folders"
        private const val PINNED_KEY = "flutter.notebook_pinned_note_ids"

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, NotebookWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            ids.forEach { id -> updateOne(context, manager, id) }
        }

        private fun updateOne(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val prefs = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            val notes = parseArray(prefs.getString(NOTES_KEY, "[]"))
            val folders = parseArray(prefs.getString(FOLDERS_KEY, "[]"))
            val pinned = parseStringArray(prefs.getString(PINNED_KEY, "[]")).toSet()

            val sorted = (0 until notes.length()).mapNotNull { index ->
                notes.optJSONObject(index)
            }.sortedWith(
                compareByDescending<JSONObject> { pinned.contains(it.optString("id")) }
                    .thenByDescending { it.optString("updated") }
            )

            val views = RemoteViews(context.packageName, R.layout.notebook_widget)
            views.setTextViewText(R.id.widget_note_count, "یادداشت‌ها: ${notes.length()}")
            views.setTextViewText(R.id.widget_folder_count, "پوشه‌ها: ${folders.length()}")

            setNote(views, 1, sorted.getOrNull(0), pinned)
            setNote(views, 2, sorted.getOrNull(1), pinned)
            setNote(views, 3, sorted.getOrNull(2), pinned)

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pending = PendingIntent.getActivity(
                context,
                widgetId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            manager.updateAppWidget(widgetId, views)
        }

        private fun setNote(
            views: RemoteViews,
            index: Int,
            note: JSONObject?,
            pinned: Set<String>
        ) {
            val titleId = when (index) {
                1 -> R.id.widget_note_1_title
                2 -> R.id.widget_note_2_title
                else -> R.id.widget_note_3_title
            }
            val bodyId = when (index) {
                1 -> R.id.widget_note_1_body
                2 -> R.id.widget_note_2_body
                else -> R.id.widget_note_3_body
            }
            val metaId = when (index) {
                1 -> R.id.widget_note_1_meta
                2 -> R.id.widget_note_2_meta
                else -> R.id.widget_note_3_meta
            }
            val rowId = when (index) {
                1 -> R.id.widget_note_1_row
                2 -> R.id.widget_note_2_row
                else -> R.id.widget_note_3_row
            }

            if (note == null) {
                views.setViewVisibility(rowId, android.view.View.GONE)
                return
            }

            val id = note.optString("id")
            val title = note.optString("title").ifBlank { "یادداشت بدون عنوان" }
            val body = plainText(note.optString("body"))
            val snippet = body.replace(Regex("\\s+"), " ").trim().let {
                if (it.length > 78) it.take(78) + "…" else it
            }.ifBlank { "بدون متن" }
            val date = note.optString("updated").take(10)

            views.setViewVisibility(rowId, android.view.View.VISIBLE)
            views.setTextViewText(titleId, if (pinned.contains(id)) "📌 $title" else title)
            views.setTextViewText(bodyId, snippet)
            views.setTextViewText(metaId, date)
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
                    body.startsWith(legacyMarker) -> {
                        val blocks = JSONArray(body.removePrefix(legacyMarker))
                        buildString {
                            for (i in 0 until blocks.length()) {
                                val block = blocks.optJSONObject(i) ?: continue
                                if (block.optString("type") == "text") append(block.optString("text")).append(' ')
                            }
                        }
                    }
                    body.trimStart().startsWith("[") -> {
                        val blocks = JSONArray(body)
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

        private fun parseArray(raw: String?): JSONArray =
            try { JSONArray(raw ?: "[]") } catch (_: Exception) { JSONArray() }

        private fun parseStringArray(raw: String?): List<String> {
            val array = parseArray(raw)
            return (0 until array.length()).mapNotNull { array.optString(it).takeIf(String::isNotBlank) }
        }
    }
}
