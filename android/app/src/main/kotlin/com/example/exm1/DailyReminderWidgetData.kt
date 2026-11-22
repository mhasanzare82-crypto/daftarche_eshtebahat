package com.example.exm1

import org.json.JSONArray

data class DailyReminderNote(
    val id: String,
    val title: String,
    val body: String
)

/**
 * Pure data transformation for the daily reminder widget.
 * Flutter sends complete note snapshots; this class owns validation and text extraction.
 */
object DailyReminderWidgetData {
    private const val QUILL_MARKER = "__quill_note_v1__"
    private const val LEGACY_MARKER = "__rich_note_v1__"
    private val entrySeparator = Regex("(?m)^[ \\t]*(?:-{20}|-{79})[ \\t]*$")

    fun parse(payload: String): List<DailyReminderNote> {
        return try {
            val array = JSONArray(payload)
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val id = item.optString("id").trim()
                    if (id.isEmpty()) continue
                    add(
                        DailyReminderNote(
                            id = id,
                            title = item.optString("title").ifBlank { "بدون عنوان" },
                            body = item.optString("body")
                        )
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    fun displayText(rawBody: String): String {
        val text = plainText(rawBody)
        val entry = text.split(entrySeparator)
            .map { it.trim() }
            .firstOrNull { it.isNotEmpty() }
            ?: text.trim()
        return entry.replace(Regex("\\s+"), " ").trim()
    }

    private fun plainText(body: String): String {
        return try {
            when {
                body.startsWith(QUILL_MARKER) -> {
                    val operations = JSONArray(body.removePrefix(QUILL_MARKER))
                    buildString {
                        for (index in 0 until operations.length()) {
                            val insert = operations.optJSONObject(index)?.opt("insert")
                            if (insert is String) append(insert)
                        }
                    }
                }

                body.startsWith(LEGACY_MARKER) || body.trimStart().startsWith("[") -> {
                    val json = if (body.startsWith(LEGACY_MARKER)) {
                        body.removePrefix(LEGACY_MARKER)
                    } else {
                        body
                    }
                    val blocks = JSONArray(json)
                    buildString {
                        for (index in 0 until blocks.length()) {
                            val block = blocks.optJSONObject(index) ?: continue
                            if (block.optString("type") == "text") {
                                append(block.optString("text")).append(' ')
                            }
                        }
                    }
                }

                else -> body
            }
        } catch (_: Exception) {
            "متن این یادداشت قابل نمایش نیست."
        }
    }
}
