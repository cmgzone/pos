import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/shop_settings.dart';

const _uuid = Uuid();

class GiftCardRepository {
  static List<dynamic> get _currentBranchArgs => [
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
      ];

  static Future<List<Map<String, dynamic>>> getAll({
    String? codeQuery,
    bool activeOnly = false,
    String? customerId,
  }) async {
    final where = <String>[
      'deleted_at IS NULL',
      'COALESCE(branch_id, ?) = ?',
    ];
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
      where:
          'code = ? AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
      whereArgs: [clean, ..._currentBranchArgs],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>> create({
    required String code,
    required double initialBalance,
    String? customerId,
    String? currency,
    bool isActive = true,
    String? expiresAt,
    String? note,
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
      'customer_id': customerId?.trim().isEmpty == true ? null : customerId?.trim(),
      'initial_balance': initialBalance,
      'balance': initialBalance,
      'currency': currency?.trim().isEmpty == true ? null : currency?.trim(),
      'is_active': isActive ? 1 : 0,
      'expires_at': expiresAt?.trim().isEmpty == true ? null : expiresAt?.trim(),
      'note': note?.trim().isEmpty == true ? null : note?.trim(),
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    };
    await DatabaseService.insert('gift_cards', payload);
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
    final updated = <String, dynamic>{
      'balance': (card['balance'] as num? ?? 0) + amount,
      'initial_balance': (card['initial_balance'] as num? ?? 0) + amount,
      'updated_at': now,
      'sync_status': 'pending',
    };
    if (note != null) {
      updated['note'] = note.trim().isEmpty ? null : note.trim();
    }
    await DatabaseService.update('gift_cards', updated, id);
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
      payload['expires_at'] =
          expiresAt.trim().isEmpty ? null : expiresAt.trim();
    }
    if (customerId != null) {
      payload['customer_id'] =
          customerId.trim().isEmpty ? null : customerId.trim();
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
    final isActive = (card['is_active'] is int
            ? card['is_active'] as int
            : int.tryParse(card['is_active']?.toString() ?? '') ?? 0) !=
        0;
    if (!isActive) {
      throw Exception('This gift card is not active.');
    }
    final expiresAt = card['expires_at']?.toString();
    if (expiresAt != null && expiresAt.isNotEmpty) {
      final expiry = DateTime.tryParse(expiresAt);
      if (expiry != null && expiry.isBefore(DateTime.now())) {
        throw Exception('This gift card has expired.');
      }
    }
    final balance = (card['balance'] as num? ?? 0).toDouble();
    if (amount > balance) {
      throw Exception('The gift card balance is insufficient.');
    }
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update('gift_cards', {
      'balance': balance - amount,
      'updated_at': now,
      'sync_status': 'pending',
    }, id);
    await AuditLogService.log(
      action: 'update',
      entityTable: 'gift_cards',
      entityId: id,
    );
    final refreshed = await getById(id);
    return refreshed ?? {...card, 'balance': balance - amount};
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
    await DatabaseService.update('gift_cards', {
      'balance': balance + amount,
      'updated_at': now,
      'sync_status': 'pending',
    }, id);
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
