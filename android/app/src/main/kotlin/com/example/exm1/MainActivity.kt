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
                "refreshWidget" -> {
                    NotebookWidgetProvider.refreshAll(applicationContext)
                    FeaturedNoteWidgetProvider.refreshAll(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
