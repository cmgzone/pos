import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_settings_service.dart';

class PikiProactiveInsight {
  final String id;
  final String severity;
  final String kind;
  final String title;
  final String body;
  final Map<String, dynamic> action;
  final DateTime? generatedAt;

  const PikiProactiveInsight({
    required this.id,
    required this.severity,
    required this.kind,
    required this.title,
    required this.body,
    required this.action,
    required this.generatedAt,
  });

  factory PikiProactiveInsight.fromJson(Map<String, dynamic> json) {
    return PikiProactiveInsight(
      id: json['id'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      kind: json['kind'] as String? ?? 'general',
      title: json['title'] as String? ?? 'Piki insight',
      body: json['body'] as String? ?? '',
      action: json['action'] is Map
          ? Map<String, dynamic>.from(json['action'] as Map)
          : const <String, dynamic>{},
      generatedAt: DateTime.tryParse(json['generatedAt'] as String? ?? ''),
    );
  }
}

class PikiProactiveService {
  static const _timeout = Duration(seconds: 20);

  static Future<List<PikiProactiveInsight>> fetchInsights({
    bool forceRefresh = false,
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) return const <PikiProactiveInsight>[];

    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final branchId = DatabaseService.currentBranchId;
    final client = http.Client();

    try {
      final response = forceRefresh
          ? await client
                .post(
                  _buildUri(backendUrl, 'ai/proactive-run'),
                  headers: {
                    ..._authHeaders(license),
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'deviceId': deviceId,
                    'branchId': branchId,
                  }),
                )
                .timeout(_timeout)
          : await client
                .get(
                  _buildUri(backendUrl, 'ai/proactive-insights', {
                    'deviceId': deviceId,
                    'branchId': branchId,
                  }),
                  headers: _authHeaders(license),
                )
                .timeout(_timeout);

      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || body['ok'] != true) {
        return const <PikiProactiveInsight>[];
      }
      final rawInsights = body['insights'];
      if (rawInsights is! List) return const <PikiProactiveInsight>[];
      return rawInsights
          .whereType<Map>()
          .map(
            (row) =>
                PikiProactiveInsight.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } catch (_) {
      return const <PikiProactiveInsight>[];
    } finally {
      client.close();
    }
  }

  static Future<bool> syncAlias({
    required String alias,
    required String target,
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) return false;

    try {
      final deviceId = await SyncSettingsService.getOrCreateDeviceId();
      final license = await _ensureAccess(backendUrl, deviceId);
      final client = http.Client();
      try {
        final response = await client
            .post(
              _buildUri(backendUrl, 'ai/learning'),
              headers: {
                ..._authHeaders(license),
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'deviceId': deviceId,
                'branchId': DatabaseService.currentBranchId,
                'kind': 'alias',
                'phrase': alias,
                'target': target,
                'metadata': {'source': 'piki_sell_mode'},
              }),
            )
            .timeout(_timeout);
        if (response.statusCode != 200) return false;
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        return body['ok'] == true;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<LicenseSnapshot> _ensureAccess(
    String backendUrl,
    String deviceId,
  ) async {
    final snapshot = await LicenseService.ensureOnlineLicense(
      backendUrl: backendUrl,
      deviceId: deviceId,
      businessName: ShopSettings.shopName,
      ownerName: SessionService.currentUserName,
      ownerEmail: SessionService.currentUserEmail,
    );
    if (!snapshot.hasBinding || snapshot.accessToken == null) {
      throw Exception('Cloud subscription not activated.');
    }
    return snapshot;
  }

  static Map<String, String> _authHeaders(LicenseSnapshot snapshot) {
    final accessToken = snapshot.accessToken;
    if (accessToken == null || accessToken.trim().isEmpty) {
      return const <String, String>{};
    }
    return {'Authorization': 'Bearer $accessToken'};
  }

  static Uri _buildUri(
    String backendUrl,
    String path, [
    Map<String, String>? queryParameters,
  ]) {
    return Uri.parse(
      '$backendUrl/$path',
    ).replace(queryParameters: queryParameters);
  }
}
