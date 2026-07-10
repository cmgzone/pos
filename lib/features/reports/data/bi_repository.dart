import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/sync_settings_service.dart';

class BiDashboardData {
  final Map<String, dynamic> clv;
  final Map<String, dynamic> forecast;
  final Map<String, dynamic> cohorts;
  final Map<String, dynamic> turnover;

  const BiDashboardData({
    required this.clv,
    required this.forecast,
    required this.cohorts,
    required this.turnover,
  });
}

/// Cloud-backed advanced analytics. The local reporting screens remain
/// available offline; these calculations intentionally use the complete,
/// business-scoped cloud history.
class BiRepository {
  static const _timeout = Duration(seconds: 20);

  static Future<BiDashboardData?> loadDashboard() async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) return null;

    await LicenseService.init();
    final token = LicenseService.currentSnapshot.accessToken?.trim();
    if (token == null || token.isEmpty) return null;
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final branchId = DatabaseService.currentBranchId;

    final results = await Future.wait([
      _get('customer-lifetime-value', token, deviceId, branchId),
      _get('sales-forecast', token, deviceId, branchId),
      _get('customer-cohorts', token, deviceId, branchId),
      _get('employee-turnover', token, deviceId, branchId),
    ]);
    if (results.any((result) => result == null)) return null;

    return BiDashboardData(
      clv: results[0]!,
      forecast: results[1]!,
      cohorts: results[2]!,
      turnover: results[3]!,
    );
  }

  static Future<Map<String, dynamic>?> _get(
    String endpoint,
    String token,
    String deviceId,
    String branchId,
  ) async {
    final uri = Uri.parse('${SyncSettingsService.backendUrl}/bi/$endpoint')
        .replace(
          queryParameters: {
            'deviceId': deviceId,
            'branchId': branchId,
          },
        );
    final client = http.Client();
    try {
      final response = await client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['ok'] != true) return null;
      return Map<String, dynamic>.from(body);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
