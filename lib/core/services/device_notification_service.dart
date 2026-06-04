import 'dart:io';

import 'package:flutter/services.dart';

class DeviceNotificationService {
  static const MethodChannel _channel = MethodChannel(
    'piki_pos/device_notifications',
  );

  static Future<bool> requestPermissionIfNeeded() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> showImportant({
    required String id,
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('showNotification', {
            'id': id,
            'title': title,
            'body': body,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
