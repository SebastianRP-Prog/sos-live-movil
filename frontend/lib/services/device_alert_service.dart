import 'package:flutter/services.dart';

class DeviceAlertService {
  static const MethodChannel _channel = MethodChannel('sos_live/device_alerts');
  static const EventChannel _volumeEvents =
      EventChannel('sos_live/volume_events');

  static Stream<void>? _volumePatternStream;

  static Future<void> initialize() async {
    try {
      await _channel.invokeMethod<void>('initialize');
    } catch (_) {}
  }

  static Future<void> showSosAlert({
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<void>('showSosNotification', {
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  static Stream<void> volumeSosPatternStream() {
    _volumePatternStream ??= _volumeEvents
        .receiveBroadcastStream()
        .where((event) => event == 'sos_volume_pattern')
        .map((_) {});
    return _volumePatternStream!;
  }
}
