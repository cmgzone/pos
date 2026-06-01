import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'severity': severity,
      'kind': kind,
      'title': title,
      'body': body,
      'action': action,
      'generatedAt': generatedAt?.toIso8601String(),
    };
  }
}

class PikiProactiveService {
  static const _timeout = Duration(seconds: 20);
  static const _cacheKeyPrefix = 'piki_proactive_insights_cache_v1';

  static Future<List<PikiProactiveInsight>> fetchInsights({
    bool forceRefresh = false,
    bool allowNetwork = true,
  }) async {
    final branchId = DatabaseService.currentBranchId;
    final cachedInsights = await _readCachedInsights(branchId);
    if (!allowNetwork) return cachedInsights;

    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) return cachedInsights;

    http.Client? client;

    try {
      final deviceId = await SyncSettingsService.getOrCreateDeviceId();
      final license = await _ensureAccess(backendUrl, deviceId);
      client = http.Client();
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
        return cachedInsights;
      }
      final rawInsights = body['insights'];
      if (rawInsights is! List) return cachedInsights;
      final insights = rawInsights
          .whereType<Map>()
          .map(
            (row) =>
                PikiProactiveInsight.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
      await _cacheInsights(branchId, insights);
      return insights;
    } catch (_) {
      return cachedInsights;
    } finally {
      client?.close();
    }
  }

  static Future<List<PikiProactiveInsight>> _readCachedInsights(
    String branchId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(branchId));
      if (raw == null || raw.trim().isEmpty) {
        return const <PikiProactiveInsight>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <PikiProactiveInsight>[];
      }
      return decoded
          .whereType<Map>()
          .map(
            (row) =>
                PikiProactiveInsight.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
    } catch (_) {
      return const <PikiProactiveInsight>[];
    }
  }

  static Future<void> _cacheInsights(
    String branchId,
    List<PikiProactiveInsight> insights,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey(branchId),
        jsonEncode(insights.map((insight) => insight.toJson()).toList()),
      );
    } catch (_) {
      // Notifications should still work when local preferences are unavailable.
    }
  }

  static String _cacheKey(String branchId) {
    final businessId = SyncSettingsService.localBusinessId;
    return '$_cacheKeyPrefix:${businessId.isEmpty ? 'local' : businessId}:$branchId';
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
