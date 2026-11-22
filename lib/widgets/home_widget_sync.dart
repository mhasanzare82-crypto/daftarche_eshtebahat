import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The single Flutter-to-Android boundary for all home-screen widgets.
class HomeWidgetSync {
  static const MethodChannel _channel = MethodChannel(
    'com.mhasanzare82.daftarcheeshtebahat/daily_reminder_widget',
  );

  /// Sends complete selected-note snapshots. Android never has to decode
  /// Flutter's private SharedPreferences representation or guess its keys.
  static Future<void> syncDailyReminder(
    List<Map<String, dynamic>> selectedNotes,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'syncDailyReminder',
        <String, Object>{
          'payload': jsonEncode(selectedNotes),
        },
      );
      debugPrint('Daily reminder widget synchronized: $result');
    } on MissingPluginException catch (error) {
      debugPrint('Daily reminder widget bridge is unavailable: $error');
      rethrow;
    } on PlatformException catch (error, stackTrace) {
      debugPrint(
        'Daily reminder widget synchronization failed: '
        '${error.code}: ${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Refreshes widgets after visual settings or other shared data changes.
  static Future<void> refresh() async {
    try {
      await _channel.invokeMethod<void>('refreshWidgets');
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
