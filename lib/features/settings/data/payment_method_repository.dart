import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';

const _uuid = Uuid();

class PaymentMethodRepository {
  static const _tableName = 'payment_methods';

  static Future<List<Map<String, dynamic>>> getAll({
    bool activeOnly = false,
  }) async {
    final where = activeOnly ? 'is_active = 1' : null;
    return DatabaseService.queryAll(
      _tableName,
      where: where,
      orderBy: 'sort_order ASC, name ASC',
    );
  }

  static Future<String> create({
    required String name,
    required bool isCashDrawer,
    bool isCredit = false,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    // Find highest sort order
    final existing = await getAll();
    final sortOrder = existing.length;

    await DatabaseService.insert(_tableName, {
      'id': id,
      'name': name.trim(),
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
  }) async {
    await DatabaseService.update(_tableName, {
      'name': name.trim(),
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
