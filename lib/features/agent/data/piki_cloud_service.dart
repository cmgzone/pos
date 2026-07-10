import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_settings_service.dart';

class PikiCloudSettings {
  final bool enabled;
  final String notificationEmail;
  final String minimumSeverity;
  final int cooldownMinutes;
  final bool emailConfigured;
  final DateTime? lastDeliveryAt;

  const PikiCloudSettings({
    required this.enabled,
    required this.notificationEmail,
    required this.minimumSeverity,
    required this.cooldownMinutes,
    required this.emailConfigured,
    required this.lastDeliveryAt,
  });

  factory PikiCloudSettings.fromJson(Map<String, dynamic> json) {
    return PikiCloudSettings(
      enabled: json['enabled'] == true,
      notificationEmail: json['notificationEmail'] as String? ?? '',
      minimumSeverity: json['minimumSeverity'] as String? ?? 'high',
      cooldownMinutes: (json['cooldownMinutes'] as num?)?.toInt() ?? 360,
      emailConfigured: json['emailConfigured'] == true,
      lastDeliveryAt: DateTime.tryParse(
        json['lastDeliveryAt'] as String? ?? '',
      ),
    );
  }
}

class PikiCloudService {
  static const _timeout = Duration(seconds: 20);

  static Future<PikiCloudSettings> fetchSettings() async {
    final request = await _requestContext();
    final client = http.Client();
    try {
      final response = await client
          .get(
            _buildUri(request.backendUrl, 'ai/cloud-settings', {
              'deviceId': request.deviceId,
              'branchId': DatabaseService.currentBranchId,
            }),
            headers: _authHeaders(request.license),
          )
          .timeout(_timeout);
      return _decodeSettings(response);
    } finally {
      client.close();
    }
  }

  static Future<PikiCloudSettings> saveSettings({
    required bool enabled,
    required String notificationEmail,
    required String minimumSeverity,
    required int cooldownMinutes,
  }) async {
    final request = await _requestContext();
    final client = http.Client();
    try {
      final response = await client
          .put(
            _buildUri(request.backendUrl, 'ai/cloud-settings'),
            headers: {
              ..._authHeaders(request.license),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'deviceId': request.deviceId,
              'branchId': DatabaseService.currentBranchId,
              'enabled': enabled,
              'notificationEmail': notificationEmail.trim(),
              'minimumSeverity': minimumSeverity,
              'cooldownMinutes': cooldownMinutes,
            }),
          )
          .timeout(_timeout);
      return _decodeSettings(response);
    } finally {
      client.close();
    }
  }

  static Future<_PikiCloudRequestContext> _requestContext() async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured.');
    }
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await LicenseService.ensureOnlineLicense(
      backendUrl: backendUrl,
      deviceId: deviceId,
      businessName: ShopSettings.shopName,
      ownerName: SessionService.currentUserName,
      ownerEmail: SessionService.currentUserEmail,
    );
    if (!license.hasBinding || license.accessToken == null) {
      throw Exception('Cloud subscription is not activated.');
    }
    return _PikiCloudRequestContext(
      backendUrl: backendUrl,
      deviceId: deviceId,
      license: license,
    );
  }

  static PikiCloudSettings _decodeSettings(http.Response response) {
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map || response.statusCode != 200 || body['ok'] != true) {
      final message = body is Map ? body['error']?.toString() : null;
      throw Exception(message ?? 'Could not update Piki Cloud settings.');
    }
    final settings = body['settings'];
    if (settings is! Map) {
      throw Exception('Piki Cloud returned invalid settings.');
    }
    return PikiCloudSettings.fromJson(Map<String, dynamic>.from(settings));
  }

  static Map<String, String> _authHeaders(LicenseSnapshot snapshot) {
    final token = snapshot.accessToken;
    return token == null || token.trim().isEmpty
        ? const <String, String>{}
        : {'Authorization': 'Bearer $token'};
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

class _PikiCloudRequestContext {
  final String backendUrl;
  final String deviceId;
  final LicenseSnapshot license;

  const _PikiCloudRequestContext({
    required this.backendUrl,
    required this.deviceId,
    required this.license,
  });
}
