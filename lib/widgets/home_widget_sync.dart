import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Refreshes the two remaining Android home-screen widgets.
class HomeWidgetSync {
  static const MethodChannel _channel = MethodChannel(
    'com.mhasanzare82.daftarcheeshtebahat/widget',
  );

  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod<void>('refreshWidget');
    } on MissingPluginException catch (error) {
      debugPrint('Home widget bridge is unavailable: $error');
    } on PlatformException catch (error, stackTrace) {
      debugPrint(
        'Home widget refresh failed: ${error.code}: ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
