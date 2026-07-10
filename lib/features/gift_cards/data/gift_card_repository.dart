import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/shop_settings.dart';

const _uuid = Uuid();

class GiftCardRepository {
  static const _transactionsTable = 'gift_card_transactions';

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static bool _isExpired(String? rawExpiresAt) {
    if (rawExpiresAt == null || rawExpiresAt.trim().isEmpty) {
      return false;
    }
    final expiry = DateTime.tryParse(rawExpiresAt);
    if (expiry == null) {
      return false;
    }
    final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return expiryDay.isBefore(today);
  }

  static Future<List<Map<String, dynamic>>> getAll({
    String? codeQuery,
    bool activeOnly = false,
    String? customerId,
  }) async {
    final where = <String>['deleted_at IS NULL', 'COALESCE(branch_id, ?) = ?'];
    final args = <dynamic>[..._currentBranchArgs];
    if (codeQuery != null && codeQuery.trim().isNotEmpty) {
      where.add('code LIKE ?');
      args.add('%${codeQuery.trim()}%');
    }
    if (activeOnly) {
      where.add('is_active = 1');
    }
    if (customerId != null && customerId.isNotEmpty) {
      where.add('customer_id = ?');
      args.add(customerId);
    }
    return DatabaseService.queryAll(
      'gift_cards',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC',
    );
  }

  static Future<Map<String, dynamic>?> getById(String id) async {
    final rows = await DatabaseService.queryAll(
      'gift_cards',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>?> getByCode(String code) async {
    final clean = code.trim();
    if (clean.isEmpty) return null;
    final rows = await DatabaseService.queryAll(
      'gift_cards',
      where: 'code = ? AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
      whereArgs: [clean, ..._currentBranchArgs],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, dynamic>>> getTransactions(
    String giftCardId,
  ) async {
    return DatabaseService.queryAll(
      _transactionsTable,
      where:
          'gift_card_id = ? AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
      whereArgs: [giftCardId, ..._currentBranchArgs],
      orderBy: 'created_at DESC, updated_at DESC',
    );
  }

  static Future<void> _recordTransaction({
    required String giftCardId,
    required String type,
    required double amount,
    required double balanceAfter,
    String? saleId,
    String? note,
  }) async {
    final now = DateTime.now().toIso8601String();
    await DatabaseService.insert(_transactionsTable, {
      'id': _uuid.v4(),
      'branch_id': DatabaseService.currentBranchId,
      'gift_card_id': giftCardId,
      'sale_id': saleId?.trim().isEmpty == true ? null : saleId?.trim(),
      'type': type,
      'amount': amount,
      'balance_after': balanceAfter,
      'note': note?.trim().isEmpty == true ? null : note?.trim(),
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
  }

  static Future<void> linkLatestRedemptionToSale({
    required String giftCardId,
    required String saleId,
  }) async {
    final rows = await DatabaseService.queryAll(
      _transactionsTable,
      where:
          "gift_card_id = ? AND type = ? AND sale_id IS NULL AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?",
      whereArgs: [giftCardId, 'redeem', ..._currentBranchArgs],
      orderBy: 'created_at DESC, updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return;
    await DatabaseService.update(_transactionsTable, {
      'sale_id': saleId,
      'updated_at': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
    }, rows.first['id'] as String);
  }

  static Future<Map<String, dynamic>> create({
    required String code,
    required double initialBalance,
    String? customerId,
    String? currency,
    bool isActive = true,
    String? expiresAt,
    String? note,
    String? saleId,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'create gift card');

    final cleanCode = code.trim();
    if (cleanCode.isEmpty) {
      throw Exception('A gift card code is required.');
    }
    if (initialBalance < 0) {
      throw Exception('Initial balance must be zero or greater.');
    }
    final existing = await getByCode(cleanCode);
    if (existing != null) {
      throw Exception('A gift card with this code already exists.');
    }

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final payload = {
      'id': id,
      'branch_id': DatabaseService.currentBranchId,
      'code': cleanCode,
      'customer_id': customerId?.trim().isEmpty == true
          ? null
          : customerId?.trim(),
      'initial_balance': initialBalance,
      'balance': initialBalance,
      'currency': currency?.trim().isEmpty == true ? null : currency?.trim(),
      'is_active': isActive ? 1 : 0,
      'expires_at': expiresAt?.trim().isEmpty == true
          ? null
          : expiresAt?.trim(),
      'note': note?.trim().isEmpty == true ? null : note?.trim(),
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    };
    await DatabaseService.insert('gift_cards', payload);
    await _recordTransaction(
      giftCardId: id,
      type: 'issue',
      amount: initialBalance,
      balanceAfter: initialBalance,
      saleId: saleId,
      note: note,
    );
    await AuditLogService.log(
      action: 'create',
      entityTable: 'gift_cards',
      entityId: id,
    );
    return Map<String, dynamic>.from(payload);
  }

  static Future<Map<String, dynamic>> topUp({
    required String id,
    required double amount,
    String? note,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'top up gift card');

    if (amount <= 0) {
      throw Exception('Top-up amount must be greater than zero.');
    }
    final card = await getById(id);
    if (card == null) {
      throw Exception('Gift card not found.');
    }
    final now = DateTime.now().toIso8601String();
    final newBalance = (card['balance'] as num? ?? 0) + amount;
    final updated = <String, dynamic>{
      'balance': newBalance,
      'initial_balance': (card['initial_balance'] as num? ?? 0) + amount,
      'updated_at': now,
      'sync_status': 'pending',
    };
    if (note != null) {
      updated['note'] = note.trim().isEmpty ? null : note.trim();
    }
    await DatabaseService.update('gift_cards', updated, id);
    await _recordTransaction(
      giftCardId: id,
      type: 'top_up',
      amount: amount,
      balanceAfter: newBalance,
      note: note,
    );
    await AuditLogService.log(
      action: 'update',
      entityTable: 'gift_cards',
      entityId: id,
    );
    final refreshed = await getById(id);
    return refreshed ?? {...card, ...updated};
  }

  static Future<Map<String, dynamic>> updateStatus({
    required String id,
    bool? isActive,
    String? expiresAt,
    String? customerId,
    String? note,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'update gift card');

    final card = await getById(id);
    if (card == null) {
      throw Exception('Gift card not found.');
    }
    final now = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'updated_at': now,
      'sync_status': 'pending',
    };
    if (isActive != null) payload['is_active'] = isActive ? 1 : 0;
    if (expiresAt != null) {
      payload['expires_at'] = expiresAt.trim().isEmpty
          ? null
          : expiresAt.trim();
    }
    if (customerId != null) {
      payload['customer_id'] = customerId.trim().isEmpty
          ? null
          : customerId.trim();
    }
    if (note != null) {
      payload['note'] = note.trim().isEmpty ? null : note.trim();
    }
    await DatabaseService.update('gift_cards', payload, id);
    await AuditLogService.log(
      action: 'update',
      entityTable: 'gift_cards',
      entityId: id,
    );
    final refreshed = await getById(id);
    return refreshed ?? {...card, ...payload};
  }

  /// Redeems `amount` from the gift card, reducing its balance. Returns the
  /// updated card. Throws if the card is inactive, expired, or has insufficient
  /// balance. The caller is responsible for linking the redemption to a sale.
  static Future<Map<String, dynamic>> redeem({
    required String id,
    required double amount,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'redeem gift card');

    if (amount <= 0) {
      throw Exception('Redemption amount must be greater than zero.');
    }
    final card = await getById(id);
    if (card == null) {
      throw Exception('Gift card not found.');
    }
    final isActive =
        (card['is_active'] is int
            ? card['is_active'] as int
            : int.tryParse(card['is_active']?.toString() ?? '') ?? 0) !=
        0;
    if (!isActive) {
      throw Exception('This gift card is not active.');
    }
    if (_isExpired(card['expires_at']?.toString())) {
      throw Exception('This gift card has expired.');
    }
    final balance = (card['balance'] as num? ?? 0).toDouble();
    if (amount > balance) {
      throw Exception('The gift card balance is insufficient.');
    }
    final newBalance = balance - amount;
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update('gift_cards', {
      'balance': newBalance,
      'updated_at': now,
      'sync_status': 'pending',
    }, id);
    await _recordTransaction(
      giftCardId: id,
      type: 'redeem',
      amount: -amount,
      balanceAfter: newBalance,
    );
    await AuditLogService.log(
      action: 'update',
      entityTable: 'gift_cards',
      entityId: id,
    );
    final refreshed = await getById(id);
    return refreshed ?? {...card, 'balance': newBalance};
  }

  /// Restores `amount` to a gift card balance. Used to reverse a redemption
  /// when the linked sale is not completed (cancelled checkout or failed
  /// payment). `amount` is the positive amount that was originally deducted.
  static Future<void> refundRedemption({
    required String id,
    required double amount,
  }) async {
    if (amount <= 0) return;

    final card = await getById(id);
    if (card == null) return;
    final now = DateTime.now().toIso8601String();
    final balance = (card['balance'] as num? ?? 0).toDouble();
    final newBalance = balance + amount;
    await DatabaseService.update('gift_cards', {
      'balance': newBalance,
      'updated_at': now,
      'sync_status': 'pending',
    }, id);
    await _recordTransaction(
      giftCardId: id,
      type: 'refund',
      amount: amount,
      balanceAfter: newBalance,
      note: 'Reversed pending redemption',
    );
    await AuditLogService.log(
      action: 'update',
      entityTable: 'gift_cards',
      entityId: id,
    );
  }

  static Future<void> delete(String id) async {
    await LicenseService.ensureWriteAccess(action: 'delete gift card');

    final now = DateTime.now().toIso8601String();
    await DatabaseService.update('gift_cards', {
      'deleted_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    }, id);
    await AuditLogService.log(
      action: 'delete',
      entityTable: 'gift_cards',
      entityId: id,
    );
  }

  static String formatBalance(double amount) {
    return '${ShopSettings.currency}${amount.toStringAsFixed(2)}';
  }
}
