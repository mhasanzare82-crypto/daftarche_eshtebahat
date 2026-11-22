import 'package:flutter/services.dart';

/// Requests a native Android home-screen widget refresh after notebook data changes.
class HomeWidgetSync {
  static const MethodChannel _channel = MethodChannel('com.mhasanzare82.daftarcheeshtebahat/widget');

  static Future<void> refresh({bool selectionChanged = false}) async {
    try {
      await _channel.invokeMethod<void>(
        selectionChanged ? 'refreshWidgetSelection' : 'refreshWidget',
      );
    } on MissingPluginException {
      // The widget bridge is Android-specific; other platforms safely ignore it.
    } on PlatformException {
      // A widget refresh must never interrupt saving a note.
    }
  }
}
