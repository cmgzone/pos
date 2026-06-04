import 'dart:convert';

import '../constants/app_constants.dart';
import 'database_service.dart';
import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_settings_service.dart';

class SupportDiagnosticsService {
  static Future<String> buildReport({
    Map<String, dynamic> sync = const <String, dynamic>{},
  }) async {
    await LicenseService.init();
    await SyncSettingsService.init();
    final counts = await _tableCounts();
    final license = LicenseService.currentSnapshot;
    final payload = <String, dynamic>{
      'app': {
        'name': AppConstants.appName,
        'version': AppConstants.appVersion,
        'apiBaseUrl': AppConstants.apiBaseUrl,
      },
      'shop': {
        'name': ShopSettings.shopName,
        'phone': ShopSettings.shopPhone,
        'email': ShopSettings.shopEmail,
        'currency': ShopSettings.currency,
      },
      'user': {
        'id': SessionService.currentUserId,
        'name': SessionService.currentUserName,
        'email': SessionService.currentUserEmail,
        'role': SessionService.currentUserRole,
      },
      'sync': {
        'configured': SyncSettingsService.isConfigured,
        'autoSyncEnabled': SyncSettingsService.autoSyncEnabled,
        'lastSyncAt': SyncSettingsService.lastSyncAt?.toIso8601String(),
        'cursor': SyncSettingsService.syncCursor,
        'deviceId': SyncSettingsService.deviceId,
        ...sync,
      },
      'license': {
        'status': license.accessStatus.name,
        'label': license.shortLabel,
        'businessId': license.businessId,
        'plan': license.plan,
        'expiresAt': license.expiresAt?.toIso8601String(),
        'graceUntil': license.graceUntil?.toIso8601String(),
        'lastVerifiedAt': license.lastVerifiedAt?.toIso8601String(),
      },
      'database': {'path': DatabaseService.databasePath, 'counts': counts},
      'createdAt': DateTime.now().toIso8601String(),
    };

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(payload);
  }

  static Future<Map<String, int>> _tableCounts() async {
    const tables = [
      'products',
      'product_variants',
      'services',
      'sales',
      'customers',
      'suppliers',
      'purchase_invoices',
      'public_catalog_orders',
      'sync_metadata',
    ];
    final counts = <String, int>{};
    for (final table in tables) {
      try {
        final rows = await DatabaseService.rawQuery(
          'SELECT COUNT(*) AS count FROM $table WHERE deleted_at IS NULL',
        );
        counts[table] = (rows.first['count'] as num? ?? 0).toInt();
      } catch (_) {
        try {
          final rows = await DatabaseService.rawQuery(
            'SELECT COUNT(*) AS count FROM $table',
          );
          counts[table] = (rows.first['count'] as num? ?? 0).toInt();
        } catch (_) {
          counts[table] = -1;
        }
      }
    }
    return counts;
  }
}
