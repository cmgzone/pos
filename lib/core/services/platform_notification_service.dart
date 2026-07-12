import 'dart:convert';

import 'package:http/http.dart' as http;

import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_settings_service.dart';

class PlatformNotification {
  final String id;
  final String title;
  final String message;
  final String severity;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  const PlatformNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    this.createdAt,
    this.expiresAt,
  });

  factory PlatformNotification.fromJson(Map<String, dynamic> json) {
    return PlatformNotification(
      id: json['id']?.toString().trim() ?? '',
      title: json['title']?.toString().trim() ?? '',
      message: json['message']?.toString().trim() ?? '',
      severity: json['severity']?.toString().trim().toLowerCase() ?? 'info',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
    );
  }
}

class PlatformNotificationService {
  static const _timeout = Duration(seconds: 20);

  static Future<List<PlatformNotification>> fetchNotifications() async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) return const <PlatformNotification>[];

    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await LicenseService.ensureOnlineLicense(
      backendUrl: backendUrl,
      deviceId: deviceId,
      businessName: ShopSettings.shopName,
      ownerName: SessionService.currentUserName,
      ownerEmail: SessionService.currentUserEmail,
    );
    final token = license.accessToken?.trim() ?? '';
    if (!license.hasBinding || token.isEmpty) {
      return const <PlatformNotification>[];
    }

    final params = <String, String>{'deviceId': deviceId};
    final userId = SessionService.currentUserId.trim();
    if (userId.isNotEmpty) params['userId'] = userId;
    final uri = Uri.parse(
      '$backendUrl/notifications',
    ).replace(queryParameters: params);
    final client = http.Client();
    try {
      final response = await client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(_timeout);
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 ||
          decoded is! Map ||
          decoded['ok'] != true) {
        return const <PlatformNotification>[];
      }
      final rows = decoded['data'];
      if (rows is! List) return const <PlatformNotification>[];
      return rows
          .whereType<Map>()
          .map(
            (row) =>
                PlatformNotification.fromJson(Map<String, dynamic>.from(row)),
          )
          .where(
            (item) =>
                item.id.isNotEmpty &&
                item.title.isNotEmpty &&
                item.message.isNotEmpty,
          )
          .toList(growable: false);
    } catch (_) {
      // Platform announcements must never block the POS user flow.
      return const <PlatformNotification>[];
    } finally {
      client.close();
    }
  }
}
