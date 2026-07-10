import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';

const _uuid = Uuid();

class ExchangeRateRepository {
  static const table = 'exchange_rates';

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<Map<String, dynamic>?> getActive() async {
    final rows = await DatabaseService.rawQuery('''
      SELECT *
      FROM $table
      WHERE deleted_at IS NULL
        AND is_active = 1
        AND COALESCE(branch_id, ?) = ?
      ORDER BY updated_at DESC
      LIMIT 1
      ''', _currentBranchArgs);
    return rows.isEmpty ? null : rows.first;
  }

  static Future<String> saveActive({
    required String quoteCurrency,
    required double rate,
    required bool enabled,
  }) async {
    await _ensureWriteAccess();
    if (enabled && rate <= 0) {
      throw Exception('Exchange rate must be greater than zero.');
    }
    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    await DatabaseService.db.transaction((txn) async {
      await txn.rawUpdate(
        '''
        UPDATE $table
        SET is_active = 0,
            updated_at = ?,
            sync_status = 'pending'
        WHERE deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        ''',
        [now, ..._currentBranchArgs],
      );
      await txn.insert(table, {
        'id': id,
        'branch_id': DatabaseService.currentBranchId,
        'base_currency': ShopSettings.currency,
        'quote_currency': ShopSettings.normalizeCurrency(quoteCurrency),
        'rate': rate,
        'is_active': enabled ? 1 : 0,
        'updated_by': SessionService.currentUserId,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
    });
    await ShopSettings.setSecondaryCurrency(quoteCurrency);
    await ShopSettings.setSecondaryCurrencyRate(enabled ? rate : 0);
    await ShopSettings.setDualCurrencyEnabled(enabled);
    await AuditLogService.log(action: 'save', entityTable: table, entityId: id);
    return id;
  }

  static double convert(double amount) {
    final rate = ShopSettings.secondaryCurrencyRate;
    if (!ShopSettings.dualCurrencyEnabled || rate <= 0) {
      return 0;
    }
    return amount * rate;
  }

  static String formatConverted(double amount) {
    final converted = convert(amount);
    if (converted <= 0) return '';
    final symbol = ShopSettings.secondaryCurrency;
    final separator = ShopSettings.currencySymbolUsesSpace(symbol) ? ' ' : '';
    return '$symbol$separator${converted.toStringAsFixed(2)}';
  }

  static Future<void> _ensureWriteAccess() async {
    if (!SessionService.canAccessFeature(
      UserAccessProfile.featureMultiCurrency,
    )) {
      throw Exception('Your account cannot manage multi-currency settings.');
    }
    await LicenseService.ensureWriteAccess(action: 'manage exchange rates');
    await LicenseService.ensureFeatureAccess(
      featureKey: UserAccessProfile.featureMultiCurrency,
      action: 'multi-currency',
    );
  }
}
