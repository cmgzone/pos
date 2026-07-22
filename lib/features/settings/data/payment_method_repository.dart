import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';

const _uuid = Uuid();

class PaymentMethodRepository {
  static const _tableName = 'payment_methods';
  static const providerCash = 'cash';
  static const providerKopesha = 'kopesha';
  static const providerMpesa = 'mpesa';
  static const providerCard = 'card';
  static const providerBankTransfer = 'bank_transfer';
  static const providerGiftCard = 'gift_card';
  static const providerOther = 'other';

  static String normalizeProviderKey(String? value) {
    final key = (value ?? '').trim().toLowerCase().replaceAll('-', '_');
    return switch (key) {
      providerCash => providerCash,
      'credit' || providerKopesha => providerKopesha,
      'm_pesa' || 'mpesa' => providerMpesa,
      providerCard => providerCard,
      'bank' || 'transfer' || providerBankTransfer => providerBankTransfer,
      'gift' || 'voucher' || providerGiftCard => providerGiftCard,
      _ => providerOther,
    };
  }

  static String inferProviderKey({
    required String name,
    required bool isCashDrawer,
    required bool isCredit,
    String? providerKey,
  }) {
    final stored = (providerKey ?? '').trim();
    if (stored.isNotEmpty) {
      final normalized = normalizeProviderKey(stored);
      if (normalized != providerOther) return normalized;
    }

    final lowerName = name.trim().toLowerCase();
    if (isCashDrawer || lowerName.contains('cash')) return providerCash;
    if (isCredit || lowerName.contains('kopesha')) return providerKopesha;
    if (lowerName.contains('mpesa') || lowerName.contains('m-pesa')) {
      return providerMpesa;
    }
    if (lowerName.contains('card')) return providerCard;
    if (lowerName.contains('bank') || lowerName.contains('transfer')) {
      return providerBankTransfer;
    }
    return providerOther;
  }

  static String providerKeyFor(Map<String, dynamic>? method) {
    if (method == null) return providerOther;
    return inferProviderKey(
      name: method['name']?.toString() ?? '',
      isCashDrawer: method['is_cash_drawer'] == 1,
      isCredit: method['is_credit'] == 1,
      providerKey: method['provider_key']?.toString(),
    );
  }

  static Future<List<Map<String, dynamic>>> getAll({
    bool activeOnly = false,
  }) async {
    final columns = await DatabaseService.getColumnNames(_tableName);
    final whereParts = <String>['deleted_at IS NULL'];
    final whereArgs = <dynamic>[];

    if (columns.contains('branch_id')) {
      whereParts.add('COALESCE(branch_id, ?) = ?');
      whereArgs
        ..add(DatabaseService.defaultBranchId)
        ..add(DatabaseService.currentBranchId);
    }
    if (activeOnly) whereParts.add('is_active = 1');

    return DatabaseService.queryAll(
      _tableName,
      where: whereParts.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'sort_order ASC, name ASC',
    );
  }

  static Future<String> create({
    required String name,
    required bool isCashDrawer,
    bool isCredit = false,
    String? providerKey,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final normalizedProviderKey = inferProviderKey(
      name: name,
      isCashDrawer: isCashDrawer,
      isCredit: isCredit,
      providerKey: providerKey,
    );

    // Find highest sort order
    final existing = await getAll();
    final sortOrder = existing.length;

    await DatabaseService.insert(_tableName, {
      'id': id,
      'name': name.trim(),
      'provider_key': normalizedProviderKey,
      'is_cash_drawer': isCashDrawer ? 1 : 0,
      'is_credit': isCredit ? 1 : 0,
      'is_active': 1,
      'sort_order': sortOrder,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    return id;
  }

  static Future<void> update(
    String id, {
    required String name,
    required bool isCashDrawer,
    required bool isActive,
    required int sortOrder,
    bool isCredit = false,
    String? providerKey,
  }) async {
    final normalizedProviderKey = inferProviderKey(
      name: name,
      isCashDrawer: isCashDrawer,
      isCredit: isCredit,
      providerKey: providerKey,
    );
    await DatabaseService.update(_tableName, {
      'name': name.trim(),
      'provider_key': normalizedProviderKey,
      'is_cash_drawer': isCashDrawer ? 1 : 0,
      'is_credit': isCredit ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'sort_order': sortOrder,
      'updated_at': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
    }, id);
  }

  static Future<void> delete(String id) async {
    await DatabaseService.delete(_tableName, id);
  }
}
