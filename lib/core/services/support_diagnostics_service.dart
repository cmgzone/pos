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
    final tableDiagnostics = await _tableDiagnostics();
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
      'database': {
        'path': DatabaseService.databasePath,
        'tables': tableDiagnostics.tables,
        'counts': tableDiagnostics.counts,
        'countErrors': tableDiagnostics.countErrors,
      },
      'createdAt': DateTime.now().toIso8601String(),
    };

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(payload);
  }

  static Future<_TableDiagnostics> _tableDiagnostics() async {
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
    final tableRows = await DatabaseService.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
      ORDER BY name ASC
    ''');
    final existingTables = tableRows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final existingTableSet = existingTables.toSet();
    final counts = <String, int>{};
    final countErrors = <String, String>{};
    for (final table in tables) {
      if (!existingTableSet.contains(table)) {
        counts[table] = -1;
        countErrors[table] = 'Table does not exist in the local SQLite schema.';
        continue;
      }
      try {
        final columnRows = await DatabaseService.rawQuery(
          "PRAGMA table_info('$table')",
        );
        final columnNames = columnRows
            .map((row) => row['name']?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toSet();
        final countSql = columnNames.contains('deleted_at')
            ? 'SELECT COUNT(*) AS count FROM $table WHERE deleted_at IS NULL'
            : 'SELECT COUNT(*) AS count FROM $table';
        final rows = await DatabaseService.rawQuery(countSql);
        counts[table] = (rows.first['count'] as num? ?? 0).toInt();
      } catch (error) {
        counts[table] = -1;
        countErrors[table] = error.toString();
      }
    }
    return _TableDiagnostics(
      tables: existingTables,
      counts: counts,
      countErrors: countErrors,
    );
  }
}

class _TableDiagnostics {
  final List<String> tables;
  final Map<String, int> counts;
  final Map<String, String> countErrors;

  const _TableDiagnostics({
    required this.tables,
    required this.counts,
    required this.countErrors,
  });
}
