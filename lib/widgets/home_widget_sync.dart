import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Requests a native Android home-screen widget refresh after notebook data changes.
class HomeWidgetSync {
  static const MethodChannel _channel = MethodChannel('com.mhasanzare82.daftarcheeshtebahat/widget');

  /// Persists the exact selected IDs natively before refreshing the daily widget.
  /// This avoids relying on two independent preference writers observing the
  /// same selection at precisely the same time.
  static Future<void> saveWidgetSelection(List<String> ids) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'setWidgetNoteSelection',
        <String, Object>{'ids': ids},
      );
      debugPrint('Daily widget selection sync: $result');
    } on MissingPluginException catch (error) {
      debugPrint('Daily widget selection bridge is unavailable: $error');
      rethrow;
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Daily widget selection sync failed: ${error.code}: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

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
