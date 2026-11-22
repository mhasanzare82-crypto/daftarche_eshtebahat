import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Requests a native Android home-screen widget refresh after notebook data changes.
class HomeWidgetSync {
  static const MethodChannel _channel = MethodChannel('com.mhasanzare82.daftarcheeshtebahat/widget');

  static Future<void> refresh({bool selectionChanged = false}) async {
    try {
      await _channel.invokeMethod<void>(
        selectionChanged ? 'refreshWidgetSelection' : 'refreshWidget',
      );
    } on MissingPluginException catch (error) {
      // The widget bridge is Android-specific; other platforms safely ignore it.
      debugPrint('Home widget bridge is unavailable: $error');
    } on PlatformException catch (error, stackTrace) {
      // Keep notebook persistence successful, but make refresh failures diagnosable.
      debugPrint('Home widget refresh failed (selectionChanged=$selectionChanged): ${error.code}: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
