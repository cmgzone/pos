import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/shop_settings.dart';

const _uuid = Uuid();

class LoyaltyRepository {
  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<Map<String, dynamic>?> getRules() async {
    final rows = await DatabaseService.queryAll(
      'loyalty_rules',
      where: 'deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
      whereArgs: _currentBranchArgs,
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>> saveRules({
    required double pointsPerCurrency,
    required double currencyDivisor,
    required int minRedemptionPoints,
    required double pointsToCurrencyFactor,
    required bool isActive,
    String? note,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'configure loyalty rules');

    final existing = await getRules();
    final now = DateTime.now().toIso8601String();
    final payload = {
      'points_per_currency': pointsPerCurrency,
      'currency_divisor': currencyDivisor,
      'min_redemption_points': minRedemptionPoints,
      'points_to_currency_factor': pointsToCurrencyFactor,
      'is_active': isActive ? 1 : 0,
      'note': note?.trim(),
      'updated_at': now,
      'sync_status': 'pending',
    };

    if (existing != null) {
      final id = existing['id'] as String;
      await DatabaseService.update('loyalty_rules', payload, id);
      await AuditLogService.log(
        action: 'update',
        entityTable: 'loyalty_rules',
        entityId: id,
      );
      return Map<String, dynamic>.from({...existing, ...payload});
    }

    final id = _uuid.v4();
    await DatabaseService.insert('loyalty_rules', {
      'id': id,
      ...payload,
      'created_at': now,
    });
    await AuditLogService.log(
      action: 'create',
      entityTable: 'loyalty_rules',
      entityId: id,
    );
    return Map<String, dynamic>.from({'id': id, ...payload});
  }

  static Future<int> getCustomerPoints(String customerId) async {
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT loyalty_points
      FROM customers
      WHERE id = ? AND deleted_at IS NULL
      LIMIT 1
      ''',
      [customerId],
    );
    if (rows.isEmpty) return 0;
    final value = rows.first['loyalty_points'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// Earn points for a completed sale. Returns the points earned (0 if loyalty
  /// is inactive or no customer/amount).
  static Future<int> earnPointsForSale({
    required String customerId,
    required String saleId,
    required double saleTotal,
  }) async {
    final rules = await getRules();
    if (rules == null) return 0;
    final isActive = (rules['is_active'] is int
        ? rules['is_active'] as int
        : int.tryParse(rules['is_active']?.toString() ?? '') ?? 0) != 0;
    if (!isActive) return 0;

    final pointsPerCurrency =
        (rules['points_per_currency'] as num?)?.toDouble() ?? 0;
    final divisor = (rules['currency_divisor'] as num?)?.toDouble() ?? 100;
    if (pointsPerCurrency <= 0 || divisor <= 0) return 0;

    final earned = ((saleTotal / divisor) * pointsPerCurrency).floor();
    if (earned <= 0) return 0;

    final balance = await getCustomerPoints(customerId);
    final newBalance = balance + earned;
    final now = DateTime.now().toIso8601String();
    final ledgerId = _uuid.v4();

    await DatabaseService.insert('loyalty_ledger', {
      'id': ledgerId,
      'customer_id': customerId,
      'sale_id': saleId,
      'type': 'earn',
      'points': earned,
      'balance_after': newBalance,
      'note': 'Points earned from sale',
      'created_at': now,
      'updated_at': now,
    });
    await DatabaseService.update('customers', {
      'loyalty_points': newBalance,
      'sync_status': 'pending',
    }, customerId);
    return earned;
  }

  /// Redeem points as a currency discount. Deducts the points immediately and
  /// records a ledger entry. Returns the discount amount applied (in business
  /// currency) along with the ledger id so the caller can link it to a sale.
  static Future<Map<String, dynamic>> redeemPoints({
    required String customerId,
    required int points,
    String? note,
    String? saleId,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'redeem loyalty points');

    final rules = await getRules();
    if (rules == null) {
      throw Exception('Loyalty is not configured for this branch.');
    }
    final minRedemption = (rules['min_redemption_points'] as num?)?.toInt() ?? 0;
    if (points < minRedemption) {
      throw Exception(
        'A minimum of $minRedemption points is required to redeem.',
      );
    }

    final balance = await getCustomerPoints(customerId);
    if (points > balance) {
      throw Exception('This customer does not have enough loyalty points.');
    }

    final factor =
        (rules['points_to_currency_factor'] as num?)?.toDouble() ?? 1;
    final discount = points * factor;
    final newBalance = balance - points;
    final now = DateTime.now().toIso8601String();
    final ledgerId = _uuid.v4();

    await DatabaseService.insert('loyalty_ledger', {
      'id': ledgerId,
      'customer_id': customerId,
      'sale_id': saleId,
      'type': 'redeem',
      'points': -points,
      'balance_after': newBalance,
      'note': note?.trim().isNotEmpty == true
          ? note!.trim()
          : 'Points redeemed',
      'created_at': now,
      'updated_at': now,
    });
    await DatabaseService.update('customers', {
      'loyalty_points': newBalance,
      'sync_status': 'pending',
    }, customerId);
    await AuditLogService.log(
      action: 'redeem',
      entityTable: 'loyalty_ledger',
      entityId: ledgerId,
    );
    return {'discount': discount, 'ledgerId': ledgerId};
  }

  /// Reverses a previously created redemption when the linked sale is not
  /// completed (cancelled checkout or failed payment). Restores the customer's
  /// point balance and records a `refund` ledger entry. `points` is the
  /// positive redemption amount that was originally deducted.
  static Future<void> refundRedemption({
    required String ledgerId,
    required String customerId,
    required int points,
  }) async {
    if (points <= 0) return;

    final balance = await getCustomerPoints(customerId);
    final restoredBalance = balance + points;
    final now = DateTime.now().toIso8601String();
    final refundId = _uuid.v4();

    await DatabaseService.insert('loyalty_ledger', {
      'id': refundId,
      'customer_id': customerId,
      'sale_id': null,
      'type': 'refund',
      'points': points,
      'balance_after': restoredBalance,
      'note': 'Redemption reversed (sale not completed)',
      'created_at': now,
      'updated_at': now,
    });
    await DatabaseService.update('customers', {
      'loyalty_points': restoredBalance,
      'sync_status': 'pending',
    }, customerId);
    await DatabaseService.update('loyalty_ledger', {
      'note': 'Refunded',
      'updated_at': now,
    }, ledgerId);
    await AuditLogService.log(
      action: 'refund',
      entityTable: 'loyalty_ledger',
      entityId: refundId,
    );
  }

  /// Returns a non-mutating preview of the customer's redemption state for the
  /// current branch rules. Useful for validating input in the checkout dialog.
  static Future<Map<String, dynamic>> getRedemptionPreview(
    String customerId,
  ) async {
    final rules = await getRules();
    final balance = await getCustomerPoints(customerId);
    if (rules == null) {
      return {
        'configured': false,
        'available': balance,
        'minRedemption': 0,
        'factor': 1.0,
        'maxDiscount': 0.0,
      };
    }
    final factor = (rules['points_to_currency_factor'] as num?)?.toDouble() ?? 1;
    final minRedemption = (rules['min_redemption_points'] as num?)?.toInt() ?? 0;
    final redeemable = balance - minRedemption < 0 ? 0 : balance;
    return {
      'configured': true,
      'available': balance,
      'minRedemption': minRedemption,
      'factor': factor,
      'maxDiscount': redeemable * factor,
    };
  }

  /// Links a previously recorded redemption ledger entry to a completed sale.
  static Future<void> linkRedemptionToSale({
    required String ledgerId,
    required String saleId,
  }) async {
    await DatabaseService.update('loyalty_ledger', {
      'sale_id': saleId,
      'updated_at': DateTime.now().toIso8601String(),
    }, ledgerId);
  }

  static Future<List<Map<String, dynamic>>> getLedger(
    String customerId, {
    int limit = 100,
  }) async {
    return DatabaseService.rawQuery(
      '''
      SELECT *
      FROM loyalty_ledger
      WHERE customer_id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY created_at DESC
      LIMIT $limit
      ''',
      [customerId, ..._currentBranchArgs],
    );
  }

  static Future<List<Map<String, dynamic>>> getTopCustomersByPoints({
    int limit = 20,
  }) async {
    return DatabaseService.rawQuery(
      '''
      SELECT id, name, phone, email, loyalty_points
      FROM customers
      WHERE deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
        AND loyalty_points > 0
      ORDER BY loyalty_points DESC, name COLLATE NOCASE ASC
      LIMIT $limit
      ''',
      _currentBranchArgs,
    );
  }

  /// Returns a formatted currency string for a points discount value.
  static String formatPointsDiscount(double amount) {
    return '${ShopSettings.currency}${amount.toStringAsFixed(2)}';
  }
}
