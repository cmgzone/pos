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
    String? imageUrl,
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
      'image_url': _normalizeText(imageUrl),
      'stock': stock,
      'sort_order': sortOrder,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    await syncVariantStock(productId: productId, variantId: variantId);
    await AuditLogService.log(
      action: 'create',
      entityTable: table,
      entityId: id,
    );
    return id;
  }

  static Future<void> update(String id, Map<String, dynamic> data) async {
    await LicenseService.ensureWriteAccess(action: 'update variant colors');
    final existing = await getById(id);
    final payload = Map<String, dynamic>.from(data);
    if (payload.containsKey('hex_color')) {
      payload['hex_color'] = _normalizeHexColor(payload['hex_color']);
    }
    if (payload.containsKey('image_url')) {
      payload['image_url'] = _normalizeText(payload['image_url']);
    }
    await DatabaseService.update(table, payload, id);
    if (existing != null) {
      await syncVariantStock(
        productId: existing['product_id'] as String,
        variantId: existing['variant_id'] as String,
      );
    }
  }

  static Future<void> delete(String id) async {
    await LicenseService.ensureWriteAccess(action: 'delete variant colors');
    final existing = await getById(id);
    await DatabaseService.delete(table, id);
    if (existing != null) {
      await syncVariantStock(
        productId: existing['product_id'] as String,
        variantId: existing['variant_id'] as String,
      );
    }
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

  static Future<void> syncVariantStock({
    required String productId,
    required String variantId,
  }) async {
    final now = DateTime.now().toIso8601String();
    await DatabaseService.rawQuery(
      '''
      UPDATE product_variants
      SET stock = (
        SELECT COALESCE(SUM(stock), 0)
        FROM $table
        WHERE variant_id = ?
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
      ),
      updated_at = ?,
      sync_status = 'pending'
      WHERE id = ?
        AND COALESCE(branch_id, ?) = ?
      ''',
      [variantId, ..._currentBranchArgs, now, variantId, ..._currentBranchArgs],
    );
    await DatabaseService.rawQuery(
      '''
      UPDATE products
      SET stock = (
        SELECT COALESCE(SUM(stock), 0)
        FROM product_variants
        WHERE product_id = ?
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
      ),
      updated_at = ?,
      sync_status = 'pending'
      WHERE id = ?
        AND COALESCE(branch_id, ?) = ?
      ''',
      [productId, ..._currentBranchArgs, now, productId, ..._currentBranchArgs],
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

  static String? _normalizeText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
