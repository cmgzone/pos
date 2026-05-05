import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';

const _uuid = Uuid();

class ProductVariantRepository {
  static const _table = 'product_variants';

  /// All variants for a product (non-deleted, sorted)
  static Future<List<Map<String, dynamic>>> getForProduct(
    String productId,
  ) async {
    return DatabaseService.queryAll(
      _table,
      where: 'product_id = ? AND deleted_at IS NULL',
      whereArgs: [productId],
      orderBy: 'sort_order ASC, name ASC',
    );
  }

  static Future<Map<String, dynamic>?> getById(String id) async {
    return DatabaseService.queryById(_table, id);
  }

  /// Look up a variant by barcode; also joins parent product fields needed by
  /// the POS cart.
  static Future<Map<String, dynamic>?> getByBarcode(String barcode) async {
    final results = await DatabaseService.rawQuery(
      '''
      SELECT
        pv.*,
        p.name  AS parent_product_name,
        p.unit, p.stock_unit, p.sale_unit,
        p.sale_to_stock_factor,
        p.image_url, p.category_id, p.track_stock, p.has_variants
      FROM $_table pv
      JOIN products p ON p.id = pv.product_id
      WHERE pv.barcode = ? AND pv.deleted_at IS NULL
      LIMIT 1
      ''',
      [barcode],
    );
    return results.isNotEmpty ? results.first : null;
  }

  static Future<String> create({
    required String productId,
    required String name,
    required double price,
    double? cost,
    String? sku,
    String? barcode,
    double stock = 0,
    double lowStock = 0,
    int sortOrder = 0,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'create product variants');
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.insert(_table, {
      'id': id,
      'product_id': productId,
      'name': name,
      'price': price,
      'cost': cost,
      'sku': sku,
      'barcode': barcode,
      'stock': stock,
      'low_stock': lowStock,
      'sort_order': sortOrder,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    return id;
  }

  static Future<void> update(String id, Map<String, dynamic> data) async {
    await LicenseService.ensureWriteAccess(action: 'update product variants');
    await DatabaseService.update(_table, data, id);
  }

  static Future<void> delete(String id) async {
    await LicenseService.ensureWriteAccess(action: 'delete product variants');
    await DatabaseService.delete(_table, id);
  }

  /// Toggle has_variants on the parent product. When disabling, does NOT
  /// delete existing variants so they can be re-enabled without data loss.
  static Future<void> setProductHasVariants(
    String productId,
    bool hasVariants,
  ) async {
    await DatabaseService.update('products', {
      'has_variants': hasVariants ? 1 : 0,
    }, productId);
  }

  /// Recompute the aggregate stock on the parent product from all variant
  /// stocks. Call after any direct variant-stock change outside a sale.
  static Future<void> syncAggregateStock(String productId) async {
    await DatabaseService.rawQuery(
      '''
      UPDATE products
      SET stock = (
        SELECT COALESCE(SUM(stock), 0)
        FROM product_variants
        WHERE product_id = ? AND deleted_at IS NULL
      ),
      updated_at = ?,
      sync_status = 'pending'
      WHERE id = ?
      ''',
      [productId, DateTime.now().toIso8601String(), productId],
    );
  }
}
