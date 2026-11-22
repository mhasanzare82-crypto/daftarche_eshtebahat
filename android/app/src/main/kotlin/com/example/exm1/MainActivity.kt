package com.example.exm1

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val DAILY_REMINDER_CHANNEL =
            "com.mhasanzare82.daftarcheeshtebahat/daily_reminder_widget"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DAILY_REMINDER_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncDailyReminder" -> {
                    val payload = call.argument<String>("payload")
                    if (payload == null) {
                        result.error(
                            "INVALID_DAILY_REMINDER_PAYLOAD",
                            "محتوای ویجت ارسال نشده است",
                            null
                        )
                    } else {
                        try {
                            val selectedCount = DailyReminderWidgetProvider.syncData(
                                applicationContext,
                                payload
                            )
                            NotebookWidgetProvider.refreshAll(applicationContext)
                            QuickNoteWidgetProvider.refreshAll(applicationContext)
                            result.success(
                                mapOf(
                                    "selectedCount" to selectedCount,
                                    "updated" to true
                                )
                            )
                        } catch (error: Exception) {
                            result.error(
                                "DAILY_REMINDER_SYNC_FAILED",
                                error.message ?: "همگام‌سازی ویجت انجام نشد",
                                null
                            )
                        }
                    }
                }

                "refreshWidgets" -> {
                    DailyReminderWidgetProvider.refreshAll(applicationContext)
                    NotebookWidgetProvider.refreshAll(applicationContext)
                    QuickNoteWidgetProvider.refreshAll(applicationContext)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }
}
