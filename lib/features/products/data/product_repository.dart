import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/expiry_utils.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

enum ProductTypeFilter { all, variantsOnly, simpleOnly }

class ProductRepository {
  static const _table = 'products';

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<void> _ensureProductWriteAccess(String action) async {
    if (!SessionService.canAccessFeature(UserAccessProfile.featureProducts)) {
      throw Exception('Your account cannot $action');
    }
    await LicenseService.ensureWriteAccess(action: action);
    await LicenseService.ensureFeatureAccess(
      featureKey: 'products',
      action: action,
    );
  }

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
    bool restaurantMenuOnly = false,
    bool excludeRestaurantMenu = false,
  }) async {
    final args = <dynamic>[..._currentBranchArgs];
    final categoryClause = categoryId != null ? ' AND p.category_id = ?' : '';
    if (categoryId != null) {
      args.add(categoryId);
    }
    final menuClause = restaurantMenuOnly
        ? ' AND COALESCE(p.is_restaurant_menu, 0) = 1'
        : excludeRestaurantMenu
        ? ' AND COALESCE(p.is_restaurant_menu, 0) = 0'
        : '';

    return DatabaseService.rawQuery('''
      SELECT
        p.*,
        COALESCE(vc.active_variant_count, 0) AS active_variant_count
      FROM $_table p
      LEFT JOIN (
        SELECT product_id, COUNT(*) AS active_variant_count
        FROM product_variants
        WHERE deleted_at IS NULL
        GROUP BY product_id
      ) vc ON vc.product_id = p.id
      WHERE p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        $categoryClause
        $menuClause
        ${_typeFilterClause('p', typeFilter)}
      ORDER BY p.name ASC
      ''', args);
  }

  static Future<bool> hasRetailProducts() async {
    final rows = await DatabaseService.rawQuery('''
      SELECT 1
      FROM $_table p
      WHERE p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND COALESCE(p.is_restaurant_menu, 0) = 0
      LIMIT 1
      ''', _currentBranchArgs);
    return rows.isNotEmpty;
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
    final projectionArgs = <dynamic>[
      like, like, like, // matched_variant_count: pv name/barcode/sku
      like, like, like, // matched_variant_names: pv name/barcode/sku
    ];
    final filterArgs = <dynamic>[
      ..._currentBranchArgs,
      like, like, like, like, // WHERE: p.name/brand/barcode/sku
      like, like, like, // WHERE EXISTS: pv name/barcode/sku
    ];
    final args = <dynamic>[...projectionArgs, ...filterArgs];
    final categoryClause = categoryId != null ? ' AND p.category_id = ?' : '';
    if (categoryId != null) {
      args.insert(
        projectionArgs.length + _currentBranchArgs.length,
        categoryId,
      );
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
        AND COALESCE(p.branch_id, ?) = ?
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
      return getAll(
        categoryId: categoryId,
        typeFilter: typeFilter,
        excludeRestaurantMenu: true,
      );
    }

    final like = '%$trimmed%';
    final productArgs = <dynamic>[..._currentBranchArgs];
    final productCategoryClause = categoryId != null
        ? ' AND p.category_id = ?'
        : '';
    if (categoryId != null) {
      productArgs.add(categoryId);
    }
    productArgs.addAll([like, like, like]);

    final variantArgs = <dynamic>[..._currentBranchArgs];
    final variantCategoryClause = categoryId != null
        ? ' AND p.category_id = ?'
        : '';
    if (categoryId != null) {
      variantArgs.add(categoryId);
    }
    variantArgs.addAll([like, like, like]);

    final serialArgs = <dynamic>[..._currentBranchArgs, ..._currentBranchArgs];
    final serialCategoryClause = categoryId != null
        ? ' AND p.category_id = ?'
        : '';
    if (categoryId != null) {
      serialArgs.add(categoryId);
    }
    serialArgs.add(like);

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
          NULL AS matched_variant_cost,
          NULL AS matched_variant_stock,
          NULL AS matched_variant_low_stock,
          NULL AS matched_serial_number,
          'product' AS result_type
        FROM $_table p
        WHERE p.deleted_at IS NULL
          AND COALESCE(p.branch_id, ?) = ?
          AND COALESCE(p.is_restaurant_menu, 0) = 0
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
          pv.cost AS matched_variant_cost,
          pv.stock AS matched_variant_stock,
          pv.low_stock AS matched_variant_low_stock,
          NULL AS matched_serial_number,
          'variant' AS result_type
        FROM $_table p
        JOIN product_variants pv
          ON pv.product_id = p.id
         AND pv.deleted_at IS NULL
        WHERE p.deleted_at IS NULL
          AND COALESCE(p.branch_id, ?) = ?
          AND COALESCE(p.is_restaurant_menu, 0) = 0
          $variantCategoryClause
          ${_typeFilterClause('p', typeFilter)}
          AND (pv.name LIKE ? OR pv.barcode LIKE ? OR pv.sku LIKE ?)

        UNION ALL

        SELECT
          p.*,
          (
            SELECT COUNT(*)
            FROM product_variants pv2
            WHERE pv2.product_id = p.id AND pv2.deleted_at IS NULL
          ) AS active_variant_count,
          ps.variant_id AS matched_variant_id,
          pv.name AS matched_variant_name,
          pv.sku AS matched_variant_sku,
          pv.barcode AS matched_variant_barcode,
          pv.price AS matched_variant_price,
          pv.cost AS matched_variant_cost,
          pv.stock AS matched_variant_stock,
          pv.low_stock AS matched_variant_low_stock,
          ps.serial_number AS matched_serial_number,
          'serial' AS result_type
        FROM product_serials ps
        JOIN $_table p
          ON p.id = ps.product_id
         AND p.deleted_at IS NULL
        LEFT JOIN product_variants pv
          ON pv.id = ps.variant_id
         AND pv.deleted_at IS NULL
        WHERE ps.deleted_at IS NULL
          AND ps.status = 'available'
          AND COALESCE(ps.branch_id, ?) = ?
          AND COALESCE(p.branch_id, ?) = ?
          AND COALESCE(p.is_restaurant_menu, 0) = 0
          $serialCategoryClause
          ${_typeFilterClause('p', typeFilter)}
          AND ps.serial_number LIKE ?
      ) results
      ORDER BY
        CASE result_type
          WHEN 'serial' THEN 0
          WHEN 'variant' THEN 1
          ELSE 2
        END,
        name ASC,
        matched_variant_name ASC
      ''',
      [...productArgs, ...variantArgs, ...serialArgs],
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
      where:
          'barcode = ? AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
      whereArgs: [barcode, ..._currentBranchArgs],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Look up a scan value in a single roundtrip: serial first, then variant,
  /// then simple product.
  /// Returns a unified row with `result_type` of `serial`, `variant`, or
  /// `product`.
  static Future<Map<String, dynamic>?> lookupBarcode(String barcode) async {
    final results = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM (
        SELECT
        'serial' AS result_type,
        ps.variant_id AS variant_id,
        p.id AS id,
        p.name AS name,
        p.price AS price,
        p.cost AS cost,
        p.stock AS stock,
        p.low_stock AS low_stock,
        p.unit AS unit,
        p.stock_unit AS stock_unit,
        p.sale_unit AS sale_unit,
        p.sale_to_stock_factor AS sale_to_stock_factor,
        p.purchase_unit AS purchase_unit,
        p.purchase_to_stock_factor AS purchase_to_stock_factor,
        p.sku AS sku,
        p.barcode AS barcode,
        p.image_url AS image_url,
        p.brand AS brand,
        p.category_id AS category_id,
        p.track_stock AS track_stock,
        p.has_variants AS has_variants,
        pv.name AS variant_name,
        pv.sku AS variant_sku,
        pv.barcode AS variant_barcode,
        pv.price AS variant_price,
        pv.cost AS variant_cost,
        pv.stock AS variant_stock,
        pv.low_stock AS variant_low_stock,
        ps.serial_number AS serial_number
      FROM product_serials ps
      JOIN products p ON p.id = ps.product_id
      LEFT JOIN product_variants pv
        ON pv.id = ps.variant_id
       AND pv.deleted_at IS NULL
      WHERE LOWER(ps.serial_number) = LOWER(?)
        AND ps.status = 'available'
        AND ps.deleted_at IS NULL
        AND COALESCE(ps.branch_id, ?) = ?
        AND p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND COALESCE(p.is_restaurant_menu, 0) = 0

      UNION ALL

      SELECT
        'variant' AS result_type,
        pv.id AS variant_id,
        p.id AS id,
        p.name AS name,
        p.price AS price,
        p.cost AS cost,
        p.stock AS stock,
        p.low_stock AS low_stock,
        p.unit AS unit,
        p.stock_unit AS stock_unit,
        p.sale_unit AS sale_unit,
        p.sale_to_stock_factor AS sale_to_stock_factor,
        p.purchase_unit AS purchase_unit,
        p.purchase_to_stock_factor AS purchase_to_stock_factor,
        p.sku AS sku,
        p.barcode AS barcode,
        p.image_url AS image_url,
        p.brand AS brand,
        p.category_id AS category_id,
        p.track_stock AS track_stock,
        p.has_variants AS has_variants,
        pv.name AS variant_name,
        pv.sku AS variant_sku,
        pv.barcode AS variant_barcode,
        pv.price AS variant_price,
        pv.cost AS variant_cost,
        pv.stock AS variant_stock,
        pv.low_stock AS variant_low_stock,
        NULL AS serial_number
      FROM product_variants pv
      JOIN products p ON p.id = pv.product_id
      WHERE pv.barcode = ?
        AND pv.deleted_at IS NULL
        AND COALESCE(pv.branch_id, ?) = ?
        AND p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND COALESCE(p.is_restaurant_menu, 0) = 0

      UNION ALL

      SELECT
        'product' AS result_type,
        NULL AS variant_id,
        p.id AS id,
        p.name AS name,
        p.price AS price,
        p.cost AS cost,
        p.stock AS stock,
        p.low_stock AS low_stock,
        p.unit AS unit,
        p.stock_unit AS stock_unit,
        p.sale_unit AS sale_unit,
        p.sale_to_stock_factor AS sale_to_stock_factor,
        p.purchase_unit AS purchase_unit,
        p.purchase_to_stock_factor AS purchase_to_stock_factor,
        p.sku AS sku,
        p.barcode AS barcode,
        p.image_url AS image_url,
        p.brand AS brand,
        p.category_id AS category_id,
        p.track_stock AS track_stock,
        p.has_variants AS has_variants,
        NULL AS variant_name,
        NULL AS variant_sku,
        NULL AS variant_barcode,
        NULL AS variant_price,
        NULL AS variant_cost,
        NULL AS variant_stock,
        NULL AS variant_low_stock,
        NULL AS serial_number
      FROM products p
      WHERE p.barcode = ?
        AND p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND COALESCE(p.is_restaurant_menu, 0) = 0
      ) results
      ORDER BY CASE result_type
        WHEN 'serial' THEN 0
        WHEN 'variant' THEN 1
        ELSE 2
      END
      LIMIT 1
      ''',
      [
        barcode,
        ..._currentBranchArgs,
        ..._currentBranchArgs,
        barcode,
        ..._currentBranchArgs,
        ..._currentBranchArgs,
        barcode,
        ..._currentBranchArgs,
      ],
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
    String? description,
    String? imageUrlsJson,
    bool showOnline = true,
    bool isFeatured = false,
    bool restaurantMenu = false,
    String? categoryId,
    String? initialExpiryDate,
    String? initialBatchNumber,
    bool trackStock = true,
    bool hasVariants = false,
  }) async {
    await _ensureProductWriteAccess('create products');
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
      'branch_id': DatabaseService.currentBranchId,
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
      'description': description,
      'image_urls_json': imageUrlsJson,
      'show_online': showOnline ? 1 : 0,
      'is_featured': isFeatured ? 1 : 0,
      'is_restaurant_menu': restaurantMenu ? 1 : 0,
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
        'branch_id': DatabaseService.currentBranchId,
        'batch_number': initialBatchNumber?.trim(),
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
    // Product creation is a multi-row batch (product plus optional opening
    // stock batch), so it bypasses DatabaseService.insert's change signal.
    // Notify once after the batch commits so auto-sync starts immediately.
    DatabaseService.notifyLocalChange();
    await AuditLogService.log(
      action: 'create',
      entityTable: _table,
      entityId: id,
    );
    return id;
  }

  /// Update a product
  static Future<void> update(String id, Map<String, dynamic> data) async {
    await _ensureProductWriteAccess('update products');
    await DatabaseService.update(_table, data, id);
  }

  /// Delete a product
  static Future<void> delete(String id) async {
    await _ensureProductWriteAccess('delete products');
    await DatabaseService.delete(_table, id);
  }

  /// Get low-stock products
  static Future<List<Map<String, dynamic>>> getLowStock() async {
    return DatabaseService.rawQuery('''
      SELECT *
      FROM $_table
      WHERE stock <= low_stock
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY stock ASC
      ''', _currentBranchArgs);
  }

  static Future<List<Map<String, dynamic>>> getReorderSuggestions({
    int lookbackDays = 30,
    int defaultLeadTimeDays = 7,
    int limit = 10,
  }) async {
    final safeLookbackDays = lookbackDays.clamp(7, 365);
    final safeDefaultLeadTimeDays = defaultLeadTimeDays.clamp(1, 90);
    final safeLimit = limit.clamp(1, 50);
    final salesWindow = '-$safeLookbackDays days';

    final candidates = await DatabaseService.rawQuery(
      '''
      WITH sales_base AS (
        SELECT
          si.product_id,
          si.variant_id,
          si.variant_color_id,
          COALESCE(SUM(CASE WHEN si.quantity > 0 THEN si.quantity ELSE 0 END), 0) AS sold_qty,
          COUNT(DISTINCT s.id) AS sale_count,
          MAX(s.created_at) AS last_sold_at
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        WHERE si.deleted_at IS NULL
          AND s.deleted_at IS NULL
          AND s.refund_sale_id IS NULL
          AND datetime(s.created_at) >= datetime('now', ?)
          AND COALESCE(s.branch_id, ?) = ?
        GROUP BY si.product_id, si.variant_id, si.variant_color_id
      )
      SELECT
        'product' AS item_type,
        p.id AS product_id,
        NULL AS variant_id,
        NULL AS variant_color_id,
        p.name AS item_name,
        p.name AS product_name,
        p.sku,
        p.barcode,
        p.stock AS stock,
        p.low_stock AS low_stock,
        p.stock_unit,
        p.cost AS unit_cost,
        COALESCE(s.sold_qty, 0) AS sold_qty,
        COALESCE(s.sale_count, 0) AS sale_count,
        s.last_sold_at
      FROM $_table p
      LEFT JOIN sales_base s
        ON s.product_id = p.id
       AND s.variant_id IS NULL
       AND s.variant_color_id IS NULL
      WHERE p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND COALESCE(p.track_stock, 1) <> 0
        AND COALESCE(p.has_variants, 0) = 0
      UNION ALL
      SELECT
        CASE WHEN pvc.id IS NULL THEN 'variant' ELSE 'color' END AS item_type,
        p.id AS product_id,
        pv.id AS variant_id,
        pvc.id AS variant_color_id,
        p.name || ' - ' || pv.name ||
          CASE WHEN pvc.id IS NULL THEN '' ELSE ' - ' || pvc.name END AS item_name,
        p.name AS product_name,
        COALESCE(NULLIF(pv.sku, ''), p.sku) AS sku,
        COALESCE(NULLIF(pv.barcode, ''), p.barcode) AS barcode,
        COALESCE(pvc.stock, pv.stock, 0) AS stock,
        COALESCE(NULLIF(pv.low_stock, 0), p.low_stock, 0) AS low_stock,
        p.stock_unit,
        COALESCE(pv.cost, p.cost, 0) AS unit_cost,
        COALESCE(s.sold_qty, 0) AS sold_qty,
        COALESCE(s.sale_count, 0) AS sale_count,
        s.last_sold_at
      FROM product_variants pv
      JOIN $_table p ON p.id = pv.product_id
      LEFT JOIN product_variant_colors pvc
        ON pvc.variant_id = pv.id
       AND pvc.deleted_at IS NULL
       AND COALESCE(pvc.branch_id, ?) = ?
      LEFT JOIN sales_base s
        ON s.product_id = p.id
       AND s.variant_id = pv.id
       AND (
          (pvc.id IS NULL AND s.variant_color_id IS NULL)
          OR s.variant_color_id = pvc.id
       )
      WHERE p.deleted_at IS NULL
        AND pv.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND COALESCE(pv.branch_id, ?) = ?
        AND COALESCE(p.track_stock, 1) <> 0
        AND COALESCE(p.has_variants, 0) <> 0
        AND (
          pvc.id IS NOT NULL
          OR NOT EXISTS (
            SELECT 1
            FROM product_variant_colors c
            WHERE c.variant_id = pv.id
              AND c.deleted_at IS NULL
              AND COALESCE(c.branch_id, ?) = ?
          )
        )
    ''',
      [
        salesWindow,
        ..._currentBranchArgs,
        ..._currentBranchArgs,
        ..._currentBranchArgs,
        ..._currentBranchArgs,
        ..._currentBranchArgs,
        ..._currentBranchArgs,
      ],
    );

    final receiptRows = await DatabaseService.rawQuery('''
      SELECT product_id, received_at
      FROM stock_batches
      WHERE deleted_at IS NULL
        AND received_at IS NOT NULL
        AND TRIM(received_at) <> ''
        AND COALESCE(branch_id, ?) = ?
      ORDER BY product_id ASC, datetime(received_at) ASC
    ''', _currentBranchArgs);
    final leadTimeByProduct = _estimateLeadTimes(
      receiptRows,
      safeDefaultLeadTimeDays.toDouble(),
    );

    final suggestions = <Map<String, dynamic>>[];
    for (final candidate in candidates) {
      final productId = candidate['product_id']?.toString();
      final stock = (candidate['stock'] as num? ?? 0).toDouble();
      final lowStock = (candidate['low_stock'] as num? ?? 0).toDouble();
      final soldQty = (candidate['sold_qty'] as num? ?? 0).toDouble();
      final dailyVelocity = soldQty / safeLookbackDays;
      final leadTimeDays =
          leadTimeByProduct[productId] ?? safeDefaultLeadTimeDays.toDouble();
      final daysOfCover = dailyVelocity > 0 ? stock / dailyVelocity : null;
      final triggerWindowDays = leadTimeDays + 2;
      final needsReorder =
          stock <= lowStock ||
          (dailyVelocity > 0 &&
              (daysOfCover ?? double.infinity) <= triggerWindowDays);
      if (!needsReorder) {
        continue;
      }

      final targetStock = dailyVelocity > 0
          ? [
              lowStock * 2,
              dailyVelocity * (leadTimeDays + 7),
              lowStock + (dailyVelocity * 7),
            ].reduce((a, b) => a > b ? a : b)
          : lowStock * 2;
      final suggestedQty = targetStock - stock;
      if (suggestedQty <= 0.001) {
        continue;
      }

      suggestions.add({
        ...candidate,
        'daily_velocity': double.parse(dailyVelocity.toStringAsFixed(2)),
        'lead_time_days': double.parse(leadTimeDays.toStringAsFixed(1)),
        'days_of_cover': daysOfCover == null
            ? null
            : double.parse(daysOfCover.toStringAsFixed(1)),
        'target_stock': double.parse(targetStock.toStringAsFixed(2)),
        'suggested_qty': double.parse(suggestedQty.toStringAsFixed(2)),
        'urgency': stock <= 0
            ? 'out'
            : stock <= lowStock
            ? 'low'
            : 'soon',
      });
    }

    suggestions.sort((a, b) {
      final priorityA = _reorderPriority(a);
      final priorityB = _reorderPriority(b);
      if (priorityA != priorityB) {
        return priorityA.compareTo(priorityB);
      }
      final coverA = (a['days_of_cover'] as num?)?.toDouble() ?? 999999;
      final coverB = (b['days_of_cover'] as num?)?.toDouble() ?? 999999;
      final coverCompare = coverA.compareTo(coverB);
      if (coverCompare != 0) {
        return coverCompare;
      }
      final qtyA = (a['suggested_qty'] as num? ?? 0).toDouble();
      final qtyB = (b['suggested_qty'] as num? ?? 0).toDouble();
      return qtyB.compareTo(qtyA);
    });

    return suggestions.take(safeLimit).toList(growable: false);
  }

  static Map<String, double> _estimateLeadTimes(
    List<Map<String, dynamic>> receiptRows,
    double fallbackDays,
  ) {
    final receiptDates = <String, List<DateTime>>{};
    for (final row in receiptRows) {
      final productId = row['product_id']?.toString();
      final receivedAt = DateTime.tryParse(
        row['received_at']?.toString() ?? '',
      );
      if (productId == null || productId.isEmpty || receivedAt == null) {
        continue;
      }
      receiptDates.putIfAbsent(productId, () => <DateTime>[]).add(receivedAt);
    }

    final leadTimes = <String, double>{};
    receiptDates.forEach((productId, dates) {
      if (dates.length < 2) {
        return;
      }
      dates.sort();
      final gaps = <int>[];
      for (var i = 1; i < dates.length; i++) {
        final gap = dates[i].difference(dates[i - 1]).inDays.abs();
        if (gap > 0) {
          gaps.add(gap);
        }
      }
      if (gaps.isEmpty) {
        return;
      }
      final average = gaps.reduce((a, b) => a + b) / gaps.length;
      leadTimes[productId] = average.clamp(3, 45).toDouble();
    });
    return leadTimes;
  }

  static int _reorderPriority(Map<String, dynamic> row) {
    return switch (row['urgency']?.toString()) {
      'out' => 0,
      'low' => 1,
      _ => 2,
    };
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
        AND COALESCE(sb.branch_id, ?) = ?
        AND sb.expiry_date IS NOT NULL
        AND TRIM(sb.expiry_date) <> ''
        AND date(sb.expiry_date) <= date('now', '+$alertBeforeDays days')
      ORDER BY date(sb.expiry_date) ASC, sb.received_at ASC
      $limitClause
    ''', _currentBranchArgs);
  }

  static Future<List<Map<String, dynamic>>> getStockList({
    String? search,
    String? categoryId,
  }) async {
    final args = <dynamic>[..._currentBranchArgs];
    final clauses = <String>[
      'p.deleted_at IS NULL',
      'p.track_stock = 1',
      'COALESCE(p.branch_id, ?) = ?',
    ];

    if (categoryId != null) {
      clauses.add('p.category_id = ?');
      args.add(categoryId);
    }

    final trimmedSearch = search?.trim() ?? '';
    if (trimmedSearch.isNotEmpty) {
      final like = '%$trimmedSearch%';
      clauses.add(
        '(p.name LIKE ? OR p.sku LIKE ? OR p.barcode LIKE ? OR sb.batch_number LIKE ?)',
      );
      args.addAll([like, like, like, like]);
    }

    return DatabaseService.rawQuery('''
      SELECT
        p.id AS product_id,
        p.name AS product_name,
        p.sku,
        p.barcode,
        p.category_id,
        p.stock AS product_stock,
        p.low_stock,
        p.stock_unit,
        p.sale_unit,
        p.cost AS product_cost,
        sb.id AS batch_id,
        sb.batch_number,
        sb.quantity_received,
        sb.quantity_remaining,
        sb.unit_cost,
        sb.expiry_date,
        sb.received_at,
        pi.supplier_name,
        pi.invoice_number,
        CAST(julianday(date(sb.expiry_date)) - julianday(date('now')) AS INTEGER) AS days_to_expiry
      FROM $_table p
      LEFT JOIN stock_batches sb
        ON sb.product_id = p.id
       AND sb.deleted_at IS NULL
       AND sb.quantity_remaining > 0
      LEFT JOIN purchase_invoices pi ON pi.id = sb.purchase_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY
        CASE WHEN sb.id IS NULL THEN 1 ELSE 0 END,
        CASE WHEN sb.expiry_date IS NULL OR TRIM(sb.expiry_date) = '' THEN 1 ELSE 0 END,
        date(sb.expiry_date) ASC,
        p.name ASC,
        sb.received_at DESC
      ''', args);
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
    String? batchNumber,
  }) async {
    await _ensureProductWriteAccess('receive stock');
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
      'branch_id': DatabaseService.currentBranchId,
      'batch_number': batchNumber?.trim(),
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
