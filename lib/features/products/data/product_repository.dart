import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/utils/expiry_utils.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

enum ProductTypeFilter { all, variantsOnly, simpleOnly }

class ProductRepository {
  static const _table = 'products';

  static String _typeFilterClause(String alias, ProductTypeFilter typeFilter) {
    return switch (typeFilter) {
      ProductTypeFilter.all => '',
      ProductTypeFilter.variantsOnly => ' AND $alias.has_variants = 1',
      ProductTypeFilter.simpleOnly => ' AND $alias.has_variants = 0',
    };
  }

  /// Get all products, optionally filtered by category
  static Future<List<Map<String, dynamic>>> getAll({
    String? categoryId,
    ProductTypeFilter typeFilter = ProductTypeFilter.all,
  }) async {
    final args = <dynamic>[];
    final categoryClause = categoryId != null ? ' AND p.category_id = ?' : '';
    if (categoryId != null) {
      args.add(categoryId);
    }

    return DatabaseService.rawQuery('''
      SELECT
        p.*,
        (
          SELECT COUNT(*)
          FROM product_variants pv
          WHERE pv.product_id = p.id AND pv.deleted_at IS NULL
        ) AS active_variant_count
      FROM $_table p
      WHERE p.deleted_at IS NULL
        $categoryClause
        ${_typeFilterClause('p', typeFilter)}
      ORDER BY p.name ASC
      ''', args);
  }

  /// Search products and surface matching variant summaries for management.
  static Future<List<Map<String, dynamic>>> search(
    String query, {
    String? categoryId,
    ProductTypeFilter typeFilter = ProductTypeFilter.all,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getAll(categoryId: categoryId, typeFilter: typeFilter);
    }

    final like = '%$trimmed%';
    // args order: matched_variant_count(3) + matched_variant_names(3)
    //             + WHERE name/brand/barcode/sku (4) + variant EXISTS (3)
    //             + ORDER BY name/brand/barcode/sku (4) + categoryId appended last
    final args = <dynamic>[
      like, like, like, // matched_variant_count: pv name/barcode/sku
      like, like, like, // matched_variant_names: pv name/barcode/sku
      like, like, like, like, // WHERE: p.name/brand/barcode/sku
      like, like, like, // WHERE EXISTS: pv name/barcode/sku
    ];
    final categoryClause = categoryId != null ? ' AND p.category_id = ?' : '';
    if (categoryId != null) {
      args.add(categoryId);
    }
    args.addAll([like, like, like, like]); // ORDER BY: name/brand/barcode/sku

    return DatabaseService.rawQuery('''
      SELECT
        p.*,
        (
          SELECT COUNT(*)
          FROM product_variants pv
          WHERE pv.product_id = p.id AND pv.deleted_at IS NULL
        ) AS active_variant_count,
        (
          SELECT COUNT(*)
          FROM product_variants pv
          WHERE pv.product_id = p.id
            AND pv.deleted_at IS NULL
            AND (pv.name LIKE ? OR pv.barcode LIKE ? OR pv.sku LIKE ?)
        ) AS matched_variant_count,
        (
          SELECT GROUP_CONCAT(pv.name, ' | ')
          FROM product_variants pv
          WHERE pv.product_id = p.id
            AND pv.deleted_at IS NULL
            AND (pv.name LIKE ? OR pv.barcode LIKE ? OR pv.sku LIKE ?)
          ORDER BY pv.sort_order ASC, pv.name ASC
        ) AS matched_variant_names
      FROM $_table p
      WHERE p.deleted_at IS NULL
        $categoryClause
        ${_typeFilterClause('p', typeFilter)}
        AND (
          p.name LIKE ? OR p.brand LIKE ? OR p.barcode LIKE ? OR p.sku LIKE ?
          OR EXISTS (
            SELECT 1
            FROM product_variants pv
            WHERE pv.product_id = p.id
              AND pv.deleted_at IS NULL
              AND (pv.name LIKE ? OR pv.barcode LIKE ? OR pv.sku LIKE ?)
          )
        )
      ORDER BY
        CASE
          WHEN p.name LIKE ? OR p.brand LIKE ? OR p.barcode LIKE ? OR p.sku LIKE ? THEN 0
          ELSE 1
        END,
        p.name ASC
      ''', args);
  }

  /// Search results for POS. Variant hits are returned as direct sellable rows.
  static Future<List<Map<String, dynamic>>> searchForPos(
    String query, {
    String? categoryId,
    ProductTypeFilter typeFilter = ProductTypeFilter.all,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getAll(categoryId: categoryId, typeFilter: typeFilter);
    }

    final like = '%$trimmed%';
    final productArgs = <dynamic>[];
    final productCategoryClause = categoryId != null
        ? ' AND p.category_id = ?'
        : '';
    if (categoryId != null) {
      productArgs.add(categoryId);
    }
    productArgs.addAll([like, like, like]);

    final variantArgs = <dynamic>[];
    final variantCategoryClause = categoryId != null
        ? ' AND p.category_id = ?'
        : '';
    if (categoryId != null) {
      variantArgs.add(categoryId);
    }
    variantArgs.addAll([like, like, like]);

    return DatabaseService.rawQuery(
      '''
      SELECT *
      FROM (
        SELECT
          p.*,
          (
            SELECT COUNT(*)
            FROM product_variants pv
            WHERE pv.product_id = p.id AND pv.deleted_at IS NULL
          ) AS active_variant_count,
          NULL AS matched_variant_id,
          NULL AS matched_variant_name,
          NULL AS matched_variant_sku,
          NULL AS matched_variant_barcode,
          NULL AS matched_variant_price,
          NULL AS matched_variant_stock,
          NULL AS matched_variant_low_stock,
          'product' AS result_type
        FROM $_table p
        WHERE p.deleted_at IS NULL
          $productCategoryClause
          ${_typeFilterClause('p', typeFilter)}
          AND (p.name LIKE ? OR p.barcode LIKE ? OR p.sku LIKE ?)

        UNION ALL

        SELECT
          p.*,
          (
            SELECT COUNT(*)
            FROM product_variants pv2
            WHERE pv2.product_id = p.id AND pv2.deleted_at IS NULL
          ) AS active_variant_count,
          pv.id AS matched_variant_id,
          pv.name AS matched_variant_name,
          pv.sku AS matched_variant_sku,
          pv.barcode AS matched_variant_barcode,
          pv.price AS matched_variant_price,
          pv.stock AS matched_variant_stock,
          pv.low_stock AS matched_variant_low_stock,
          'variant' AS result_type
        FROM $_table p
        JOIN product_variants pv
          ON pv.product_id = p.id
         AND pv.deleted_at IS NULL
        WHERE p.deleted_at IS NULL
          $variantCategoryClause
          ${_typeFilterClause('p', typeFilter)}
          AND (pv.name LIKE ? OR pv.barcode LIKE ? OR pv.sku LIKE ?)
      ) results
      ORDER BY
        CASE WHEN result_type = 'variant' THEN 0 ELSE 1 END,
        name ASC,
        matched_variant_name ASC
      ''',
      [...productArgs, ...variantArgs],
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
      where: 'barcode = ? AND deleted_at IS NULL',
      whereArgs: [barcode],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Create a new product
  static Future<String> create({
    required String name,
    required double price,
    double? cost,
    String? brand,
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
    String? initialExpiryDate,
    bool trackStock = true,
    bool hasVariants = false,
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
      'brand': brand,
      'category_id': categoryId,
      'track_stock': trackStock ? 1 : 0,
      'has_variants': hasVariants ? 1 : 0,
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
        'expiry_date': ExpiryUtils.toStorageString(
          ExpiryUtils.parse(initialExpiryDate),
        ),
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

  static Future<List<Map<String, dynamic>>> getExpiryAlerts({
    int alertBeforeDays = ExpiryUtils.defaultAlertDays,
    int? limit,
  }) async {
    final limitClause = limit == null ? '' : 'LIMIT $limit';
    return DatabaseService.rawQuery('''
      SELECT
        sb.*,
        p.name AS product_name,
        p.stock_unit,
        p.sale_unit,
        p.image_url,
        CAST(julianday(date(sb.expiry_date)) - julianday(date('now')) AS INTEGER) AS days_to_expiry
      FROM stock_batches sb
      JOIN products p ON p.id = sb.product_id
      WHERE sb.quantity_remaining > 0
        AND sb.deleted_at IS NULL
        AND sb.expiry_date IS NOT NULL
        AND TRIM(sb.expiry_date) <> ''
        AND date(sb.expiry_date) <= date('now', '+$alertBeforeDays days')
      ORDER BY date(sb.expiry_date) ASC, sb.received_at ASC
      $limitClause
    ''');
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
    String? expiryDate,
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
      'expiry_date': ExpiryUtils.toStorageString(ExpiryUtils.parse(expiryDate)),
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
