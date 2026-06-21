import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';

const _uuid = Uuid();

class ProductVariantColorRepository {
  static const table = 'product_variant_colors';

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<List<Map<String, dynamic>>> getForVariant(
    String variantId,
  ) async {
    return DatabaseService.queryAll(
      table,
      where:
          'variant_id = ? AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
      whereArgs: [variantId, ..._currentBranchArgs],
      orderBy: 'sort_order ASC, name ASC',
    );
  }

  static Future<List<Map<String, dynamic>>> getForProduct(
    String productId,
  ) async {
    return DatabaseService.queryAll(
      table,
      where:
          'product_id = ? AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
      whereArgs: [productId, ..._currentBranchArgs],
      orderBy: 'variant_id ASC, sort_order ASC, name ASC',
    );
  }

  static Future<Map<String, dynamic>?> getById(String id) async {
    final rows = await DatabaseService.queryAll(
      table,
      where: 'id = ? AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
      whereArgs: [id, ..._currentBranchArgs],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<String> create({
    required String productId,
    required String variantId,
    required String name,
    String? hexColor,
    double stock = 0,
    int sortOrder = 0,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'create variant colors');
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.insert(table, {
      'id': id,
      'branch_id': DatabaseService.currentBranchId,
      'product_id': productId,
      'variant_id': variantId,
      'name': name,
      'hex_color': _normalizeHexColor(hexColor),
      'stock': stock,
      'sort_order': sortOrder,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    await AuditLogService.log(
      action: 'create',
      entityTable: table,
      entityId: id,
    );
    return id;
  }

  static Future<void> update(String id, Map<String, dynamic> data) async {
    await LicenseService.ensureWriteAccess(action: 'update variant colors');
    final payload = Map<String, dynamic>.from(data);
    if (payload.containsKey('hex_color')) {
      payload['hex_color'] = _normalizeHexColor(payload['hex_color']);
    }
    await DatabaseService.update(table, payload, id);
  }

  static Future<void> delete(String id) async {
    await LicenseService.ensureWriteAccess(action: 'delete variant colors');
    await DatabaseService.delete(table, id);
    await AuditLogService.log(
      action: 'delete',
      entityTable: table,
      entityId: id,
    );
  }

  static Future<void> decrementStock({
    required String id,
    required double quantity,
  }) async {
    await DatabaseService.rawQuery(
      '''
      UPDATE $table
      SET stock = stock - ?,
          updated_at = ?,
          sync_status = 'pending'
      WHERE id = ?
      ''',
      [quantity, DateTime.now().toIso8601String(), id],
    );
  }

  static String? _normalizeHexColor(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    final withHash = raw.startsWith('#') ? raw : '#$raw';
    final normalized = withHash.toUpperCase();
    return RegExp(r'^#[0-9A-F]{6}$').hasMatch(normalized) ? normalized : null;
  }
}
