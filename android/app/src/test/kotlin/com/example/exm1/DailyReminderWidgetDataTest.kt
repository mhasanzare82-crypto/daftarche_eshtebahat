package com.example.exm1

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DailyReminderWidgetDataTest {
    @Test
    fun parsesOnlyValidSelectedNotes() {
        val payload = JSONArray()
            .put(JSONObject().put("id", "note-1").put("title", "عنوان").put("body", "متن"))
            .put(JSONObject().put("title", "بدون شناسه").put("body", "نباید نمایش داده شود"))
            .toString()

        val notes = DailyReminderWidgetData.parse(payload)

        assertEquals(1, notes.size)
        assertEquals("note-1", notes.single().id)
        assertEquals("عنوان", notes.single().title)
        assertEquals("متن", notes.single().body)
    }

    @Test
    fun extractsTextBeforeExactTwentyDashSeparator() {
        val text = DailyReminderWidgetData.displayText(
            "یادآوری اول\n--------------------\nیادآوری دوم"
        )

        assertEquals("یادآوری اول", text)
    }

    @Test
    fun extractsTextBeforeExactSeventyNineDashSeparator() {
        val separator = "-".repeat(79)
        val text = DailyReminderWidgetData.displayText(
            "یادآوری سریع\n$separator\nیادآوری بعدی"
        )

        assertEquals("یادآوری سریع", text)
    }

    @Test
    fun doesNotTreatOtherDashLengthsAsEntrySeparators() {
        val text = DailyReminderWidgetData.displayText(
            "بخش اول\n---------------------\nبخش دوم"
        )

        assertTrue(text.contains("بخش اول"))
        assertTrue(text.contains("بخش دوم"))
    }

    @Test
    fun extractsPlainTextFromQuillDelta() {
        val delta = JSONArray()
            .put(JSONObject().put("insert", "متن کویل"))
            .put(JSONObject().put("insert", "\n"))
            .toString()

        val text = DailyReminderWidgetData.displayText(
            "__quill_note_v1__$delta"
        )

        assertEquals("متن کویل", text)
    }

    @Test
    fun invalidPayloadProducesEmptySelection() {
        assertTrue(DailyReminderWidgetData.parse("not-json").isEmpty())
    }
}
