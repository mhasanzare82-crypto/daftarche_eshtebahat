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
import java.util.UUID

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
            setOnClickListener { saveNote() }
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

    private fun saveNote() {
        val body = editor.text.toString().trim()
        if (body.isEmpty()) {
            Toast.makeText(this, "اول متن یادداشت رو بنویس", Toast.LENGTH_SHORT).show()
            return
        }
        try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val key = "flutter.notebook_notes"
            val notes = try { JSONArray(prefs.getString(key, "[]") ?: "[]") } catch (_: Exception) { JSONArray() }
            val now = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
                timeZone = java.util.TimeZone.getTimeZone("UTC")
            }.format(Date())
            val title = body.lineSequence().first().take(48).ifBlank { "یادداشت سریع" }
            val note = JSONObject().apply {
                put("id", UUID.randomUUID().toString())
                put("title", title)
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
            if (!prefs.edit().putString(key, notes.toString()).commit()) {
                throw IllegalStateException("ذخیره انجام نشد")
            }
            NotebookWidgetProvider.refreshAll(this)
            FeaturedNoteWidgetProvider.refreshAll(this)
            QuickNoteWidgetProvider.refreshAll(this)
            Toast.makeText(this, "یادداشت در دفترچه ذخیره شد", Toast.LENGTH_SHORT).show()
            editor.setText("")
            finish()
        } catch (error: Exception) {
            Toast.makeText(this, "ذخیره یادداشت ناموفق بود", Toast.LENGTH_LONG).show()
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()
}
