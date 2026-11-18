package com.example.exm1

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.inputmethod.InputMethodManager
import android.content.Context
import android.graphics.Color
import android.text.InputType
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class QuickNoteActivity : Activity() {
    private lateinit var editor: EditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(22), dp(20), dp(18))
            setBackgroundColor(Color.rgb(248, 249, 251))
            layoutDirection = android.view.View.LAYOUT_DIRECTION_RTL
        }
        root.addView(TextView(this).apply {
            text = "یادداشت سریع"
            textSize = 21f
            setTextColor(Color.rgb(35, 43, 52))
            gravity = Gravity.RIGHT
        }, LinearLayout.LayoutParams(-1, -2))

        editor = EditText(this).apply {
            hint = "یادداشتت رو اینجا بنویس..."
            textSize = 17f
            gravity = Gravity.TOP or Gravity.RIGHT
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_MULTI_LINE or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            minLines = 7
            setPadding(dp(14), dp(14), dp(14), dp(14))
            setTextColor(Color.rgb(35, 43, 52))
            setHintTextColor(Color.GRAY)
            setBackgroundColor(Color.WHITE)
        }
        root.addView(editor, LinearLayout.LayoutParams(-1, 0, 1f).apply {
            topMargin = dp(18)
            bottomMargin = dp(16)
        })

        val buttons = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        buttons.addView(Button(this).apply {
            text = "ذخیره یادداشت"
            isAllCaps = false
            setOnClickListener {
                isEnabled = false
                saveNote { isEnabled = true }
            }
        }, LinearLayout.LayoutParams(0, dp(52), 1f))
        buttons.addView(Button(this).apply {
            text = "انصراف"
            setOnClickListener { finish() }
        }, LinearLayout.LayoutParams(dp(104), dp(52)).apply { marginStart = dp(10) })
        root.addView(buttons)
        setContentView(root)
        editor.requestFocus()
        editor.post {
            (getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                .showSoftInput(editor, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun saveNote(onFinished: () -> Unit) {
        val body = editor.text.toString().trim()
        if (body.isEmpty()) {
            Toast.makeText(this, "اول متن یادداشت رو بنویس", Toast.LENGTH_SHORT).show()
            return
        }
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val key = "flutter.notebook_notes"
            val stored = prefs.getString(key, null)
            // Never replace a damaged/unexpected notebook value with an empty
            // array: that would silently erase every existing note.
            val notes = if (stored.isNullOrBlank()) JSONArray() else JSONArray(stored)
            val now = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = TimeZone.getTimeZone("UTC")
            }.format(Date())

            // Keep every Quick Note widget entry in one persistent note in the app's notebook.
            val widgetNoteId = "quick_note_widget_entries"
            var widgetNote: JSONObject? = null
            for (index in 0 until notes.length()) {
                val candidate = notes.optJSONObject(index) ?: continue
                if (candidate.optString("id") == widgetNoteId) {
                    widgetNote = candidate
                    break
                }
            }

            if (widgetNote != null) {
                val previousBody = widgetNote.optString("body")
                val separator = "\n-------------------------------------------------------------------------------\n"
                widgetNote.put("body", if (previousBody.isBlank()) body else "$previousBody$separator$body")
                widgetNote.put("updated", now)
            } else {
                val note = JSONObject().apply {
                    put("id", widgetNoteId)
                    put("title", "یادداشت‌های ویجت")
                    put("body", body)
                    put("updated", now)
                    put("images", JSONArray())
                    put("themeColor", -1184275)
                    put("themeTextColor", -14474461)
                    put("themeFontFamily", "sans-serif")
                    put("folderId", JSONObject.NULL)
                    put("audios", JSONArray())
                }
                notes.put(note)
            }

            if (!prefs.edit().putString(key, notes.toString()).commit()) {
                throw IllegalStateException("ذخیره انجام نشد")
            }
            // Persistence is the success criterion. A launcher/widget refresh
            // failure must not be reported as a failed save after commit().
            listOf<() -> Unit>(
                { NotebookWidgetProvider.refreshAll(this) },
                { FeaturedNoteWidgetProvider.refreshAll(this) },
                { QuickNoteWidgetProvider.refreshAll(this) }
            ).forEach { refresh ->
                try { refresh() } catch (_: Exception) { /* Saved data remains safe. */ }
            }
            Toast.makeText(this, "یادداشت با موفقیت ذخیره شد", Toast.LENGTH_SHORT).show()
            editor.setText("")
            finish()
        } catch (error: Exception) {
            val detail = error.message?.takeIf { it.isNotBlank() } ?: "خطای ناشناخته"
            Toast.makeText(this, "ذخیره یادداشت انجام نشد: $detail", Toast.LENGTH_LONG).show()
            onFinished()
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
