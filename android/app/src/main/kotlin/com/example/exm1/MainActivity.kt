package com.example.exm1

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mhasanzare82.daftarcheeshtebahat/widget"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setWidgetNoteSelection" -> {
                    val ids = call.argument<List<String>>("ids")
                        ?.filter { it.isNotBlank() }
                        ?.distinct()
                        ?: emptyList()
                    val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                    val serializedIds = JSONArray(ids).toString()
                    val saved = prefs.edit()
                        .putString("flutter.notebook_widget_note_ids", serializedIds)
                        .commit()
                    if (!saved) {
                        result.error("WIDGET_SELECTION_SAVE_FAILED", "ذخیره انتخاب‌های ویجت انجام نشد", null)
                    } else {
                        val notes = try {
                            JSONArray(prefs.getString("flutter.notebook_notes", "[]") ?: "[]")
                        } catch (_: Exception) {
                            JSONArray()
                        }
                        val availableIds = (0 until notes.length()).mapNotNull { index ->
                            notes.optJSONObject(index)?.optString("id")?.takeIf { it.isNotBlank() }
                        }.toSet()
                        val matchedCount = ids.count { it in availableIds }

                        // Refresh only after native read-back confirms the selection
                        // has been committed to the same preferences file the widget reads.
                        NotebookWidgetProvider.refreshAll(applicationContext)
                        FeaturedNoteWidgetProvider.refreshAll(
                            applicationContext,
                            resetSelection = true
                        )
                        QuickNoteWidgetProvider.refreshAll(applicationContext)
                        result.success(
                            mapOf(
                                "selectedCount" to ids.size,
                                "matchedCount" to matchedCount
                            )
                        )
                    }
                }
                "refreshWidget" -> {
                    NotebookWidgetProvider.refreshAll(applicationContext)
                    FeaturedNoteWidgetProvider.refreshAll(applicationContext)
                    QuickNoteWidgetProvider.refreshAll(applicationContext)
                    result.success(null)
                }
                "refreshWidgetSelection" -> {
                    NotebookWidgetProvider.refreshAll(applicationContext)
                    FeaturedNoteWidgetProvider.refreshAll(applicationContext, resetSelection = true)
                    QuickNoteWidgetProvider.refreshAll(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
