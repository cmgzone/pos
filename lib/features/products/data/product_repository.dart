import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

class ProductRepository {
  static const _table = 'products';

  /// Get all products, optionally filtered by category
  static Future<List<Map<String, dynamic>>> getAll({String? categoryId}) async {
    return DatabaseService.queryAll(
      _table,
      where: categoryId != null ? 'category_id = ?' : null,
      whereArgs: categoryId != null ? [categoryId] : null,
      orderBy: 'name ASC',
    );
  }

  /// Search products by name or barcode
  static Future<List<Map<String, dynamic>>> search(String query) async {
    return DatabaseService.rawQuery(
      'SELECT * FROM $_table WHERE name LIKE ? OR barcode LIKE ? OR sku LIKE ? ORDER BY name ASC',
      ['%$query%', '%$query%', '%$query%'],
    );
  }

  /// Get a single product by ID
  static Future<Map<String, dynamic>?> getById(String id) async {
    return DatabaseService.queryById(_table, id);
  }

  /// Get a product by barcode
  static Future<Map<String, dynamic>?> getByBarcode(String barcode) async {
    final results = await DatabaseService.queryAll(
      _table,
      where: 'barcode = ?',
      whereArgs: [barcode],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Create a new product
  static Future<String> create({
    required String name,
    required double price,
    double? cost,
    String? sku,
    String? barcode,
    double stock = 0,
    double lowStock = 5,
    String unit = 'pcs',
    String? stockUnit,
    String? saleUnit,
    double saleToStockFactor = 1,
    String? purchaseUnit,
    double purchaseToStockFactor = 1,
    String? imageUrl,
    String? categoryId,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'create products');
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final normalizedUnit = UnitUtils.normalize(unit);
    final normalizedStockUnit = UnitUtils.normalize(
      stockUnit ?? normalizedUnit,
    );
    final normalizedSaleUnit = UnitUtils.normalize(saleUnit ?? normalizedUnit);
    final normalizedPurchaseUnit = UnitUtils.normalize(
      purchaseUnit ?? normalizedUnit,
    );

    final batch = DatabaseService.db.batch();

    batch.insert(_table, {
      'id': id,
      'name': name,
      'price': price,
      'cost': cost,
      'sku': sku,
      'barcode': barcode,
      'stock': stock,
      'low_stock': lowStock,
      'unit': normalizedUnit,
      'stock_unit': normalizedStockUnit,
      'sale_unit': normalizedSaleUnit,
      'sale_to_stock_factor': saleToStockFactor > 0 ? saleToStockFactor : 1.0,
      'purchase_unit': normalizedPurchaseUnit,
      'purchase_to_stock_factor': purchaseToStockFactor > 0
          ? purchaseToStockFactor
          : 1.0,
      'image_url': imageUrl,
      'category_id': categoryId,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    if (stock > 0) {
      batch.insert('stock_batches', {
        'id': _uuid.v4(),
        'product_id': id,
        'quantity_received': stock,
        'quantity_remaining': stock,
        'unit_cost': cost ?? 0.0,
        'received_at': now,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
    }

    await batch.commit(noResult: true);
    return id;
  }

  /// Update a product
  static Future<void> update(String id, Map<String, dynamic> data) async {
    await LicenseService.ensureWriteAccess(action: 'update products');
    await DatabaseService.update(_table, data, id);
  }

  /// Delete a product
  static Future<void> delete(String id) async {
    await LicenseService.ensureWriteAccess(action: 'delete products');
    await DatabaseService.delete(_table, id);
  }

  /// Get low-stock products
  static Future<List<Map<String, dynamic>>> getLowStock() async {
    return DatabaseService.rawQuery(
      'SELECT * FROM $_table WHERE stock <= low_stock ORDER BY stock ASC',
    );
  }

  /// Update stock after a sale (Legacy - will be replaced)
  static Future<void> decrementStock(String id, double quantity) async {
    await DatabaseService.rawQuery(
      'UPDATE $_table SET stock = stock - ?, updated_at = ?, sync_status = ? WHERE id = ?',
      [quantity, DateTime.now().toIso8601String(), 'pending', id],
    );
  }

  /// Add a new stock batch and update aggregate total stock natively
  static Future<void> addStockBatch({
    required String productId,
    required double quantity,
    required double unitCost,
    Map<String, dynamic>? product,
    String? sourceUnit,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'receive stock');
    final batch = DatabaseService.db.batch();
    final now = DateTime.now().toIso8601String();
    final productData =
        product ?? await DatabaseService.queryById(_table, productId);
    if (productData == null) {
      throw Exception('Product not found');
    }

    final normalizedSourceUnit = UnitUtils.normalize(
      sourceUnit ?? UnitUtils.purchaseUnitForProduct(productData),
    );
    final stockUnit = UnitUtils.stockUnitForProduct(productData);
    final convertedQuantity =
        UnitUtils.convertQuantity(quantity, normalizedSourceUnit, stockUnit) ??
        quantity;
    final convertedUnitCost = convertedQuantity > 0
        ? ((quantity * unitCost) / convertedQuantity)
        : unitCost;

    // Add batch
    batch.insert('stock_batches', {
      'id': _uuid.v4(),
      'product_id': productId,
      'quantity_received': convertedQuantity,
      'quantity_remaining': convertedQuantity,
      'unit_cost': convertedUnitCost,
      'received_at': now,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    // Bump aggregate product stock
    batch.rawUpdate(
      'UPDATE $_table SET stock = stock + ?, cost = ?, updated_at = ?, sync_status = ? WHERE id = ?',
      [convertedQuantity, convertedUnitCost, now, 'pending', productId],
    );

    await batch.commit(noResult: true);
  }
}
