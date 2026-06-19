import '../../../core/data/cloud_spreadsheet_import_planner.dart';
import '../../../core/data/spreadsheet_import_reader.dart';
import '../../../core/services/database_service.dart';
import '../../../core/utils/expiry_utils.dart';
import '../../../core/utils/unit_utils.dart';
import 'category_repository.dart';
import 'product_repository.dart';

class ProductImportResult {
  final int created;
  final int updated;
  final int stockBatches;
  final int skipped;
  final List<String> errors;
  final String? fileName;

  const ProductImportResult({
    required this.created,
    required this.updated,
    required this.stockBatches,
    required this.skipped,
    required this.errors,
    this.fileName,
  });

  int get imported => created + updated;
}

class ProductImportService {
  static const columnAliases = {
    'product_id': ['id', 'product id'],
    'name': [
      'product',
      'product_name',
      'item',
      'item_name',
      'item description',
      'description',
      'prdct',
      'prod name',
      'productname',
    ],
    'price': [
      'selling_price',
      'sale_price',
      'retail_price',
      'sell price',
      'amount',
    ],
    'cost': ['unit_cost', 'buying_price', 'purchase_price', 'buy price'],
    'sku': ['product_sku', 'item_sku', 'stock_code', 'code'],
    'barcode': ['product_barcode', 'item_barcode', 'bar_code'],
    'category': ['category_name', 'group', 'department'],
    'stock': ['opening_stock', 'initial_stock', 'qty', 'quantity'],
    'stock_received': [
      'add_stock',
      'stock_in',
      'receive_stock',
      'quantity_received',
      'received_qty',
    ],
    'low_stock': ['reorder_level', 'minimum_stock', 'min_stock'],
    'unit': ['base_unit'],
    'stock_unit': ['stock unit', 'inventory_unit', 'inventory unit'],
    'sale_unit': ['sale unit', 'selling_unit', 'selling unit'],
    'purchase_unit': ['buying_unit'],
    'sale_to_stock_factor': ['stock_factor', 'conversion'],
    'purchase_to_stock_factor': ['purchase_factor'],
    'track_stock': ['tracks_stock', 'stock_tracking'],
    'brand': ['manufacturer'],
    'image_url': ['image', 'photo'],
    'expiry_date': ['expires_on', 'expiry'],
    'batch_number': ['batch'],
  };
  static const _nameKeys = ['name', 'product_name', 'item', 'item_name'];
  static const _priceKeys = ['price', 'selling_price', 'sale_price'];
  static const _costKeys = ['cost', 'unit_cost', 'buying_price'];
  static const _skuKeys = ['sku', 'product_sku', 'item_sku'];
  static const _barcodeKeys = ['barcode', 'product_barcode', 'item_barcode'];
  static const _categoryKeys = ['category', 'category_name'];
  static const _stockKeys = ['stock', 'opening_stock', 'initial_stock'];
  static const _stockAddKeys = [
    'stock_received',
    'add_stock',
    'stock_in',
    'receive_stock',
    'quantity_received',
  ];

  static Future<ProductImportResult?> pickAndImportProducts({
    Future<bool> Function(SpreadsheetImportPlan plan)? confirmPlan,
  }) async {
    final file = await SpreadsheetImportReader.pickRows(
      dialogTitle: 'Import Products from Excel or CSV',
    );
    if (file == null) {
      return null;
    }
    final plan = await buildPlanWithCloud(file.rows, fileName: file.fileName);
    if (confirmPlan != null && !await confirmPlan(plan)) {
      return null;
    }
    return importPlan(plan);
  }

  static Future<ProductImportResult> importRows(
    List<List<String>> rows, {
    String? fileName,
  }) async {
    return importPlan(buildPlan(rows, fileName: fileName));
  }

  static SpreadsheetImportPlan buildPlan(
    List<List<String>> rows, {
    String? fileName,
  }) {
    final plan = _buildRawPlan(rows, fileName: fileName);
    _validatePlan(plan);
    return plan;
  }

  static Future<SpreadsheetImportPlan> buildPlanWithCloud(
    List<List<String>> rows, {
    String? fileName,
  }) async {
    final plan = await CloudSpreadsheetImportPlanner.buildPlan(
      rows: rows,
      fileName: fileName,
      importType: 'products',
      importLabel: 'products',
      columnAliases: columnAliases,
      localPlanBuilder: () => _buildRawPlan(rows, fileName: fileName),
    );
    _validatePlan(plan);
    return plan;
  }

  static SpreadsheetImportPlan _buildRawPlan(
    List<List<String>> rows, {
    String? fileName,
  }) {
    return SpreadsheetImportReader.buildPlan(
      rows: rows,
      fileName: fileName,
      columnAliases: columnAliases,
      requiredAny: const ['name', 'sku', 'barcode', 'product_id'],
      importLabel: 'products',
    );
  }

  static void _validatePlan(SpreadsheetImportPlan plan) {
    if (!SpreadsheetImportReader.hasAnyHeader(plan.headers, [
      ..._nameKeys,
      ..._skuKeys,
      ..._barcodeKeys,
      'product_id',
    ])) {
      throw Exception(
        'Only one product identifier column is required: name for new products, or sku, barcode, or product_id for updates.',
      );
    }
  }

  static Future<ProductImportResult> importPlan(
    SpreadsheetImportPlan plan,
  ) async {
    final headers = plan.headers;
    final categoryCache = await _categoryCache();
    var created = 0;
    var updated = 0;
    var stockBatches = 0;
    var skipped = 0;
    final errors = <String>[];

    for (
      var index = plan.headerIndex + 1;
      index < plan.rows.length;
      index += 1
    ) {
      final sourceRow = plan.rows[index];
      if (sourceRow.every((cell) => cell.trim().isEmpty)) {
        continue;
      }

      try {
        final row = SpreadsheetImportReader.rowMap(headers, sourceRow);
        final result = await _importProductRow(row, categoryCache);
        if (result.created) {
          created += 1;
        } else if (result.updated) {
          updated += 1;
        }
        if (result.stockBatchAdded) {
          stockBatches += 1;
        }
      } catch (error) {
        skipped += 1;
        if (errors.length < 8) {
          errors.add(
            'Row ${index + 1}: ${error.toString().replaceFirst('Exception: ', '')}',
          );
        }
      }
    }

    return ProductImportResult(
      created: created,
      updated: updated,
      stockBatches: stockBatches,
      skipped: skipped,
      errors: errors,
      fileName: plan.fileName,
    );
  }

  static Future<_ProductRowImportResult> _importProductRow(
    Map<String, String> row,
    Map<String, String> categoryCache,
  ) async {
    final existing = await _findExistingProduct(row);
    final name = SpreadsheetImportReader.readText(row, _nameKeys);
    if (existing == null && (name == null || name.trim().isEmpty)) {
      throw Exception('Product name is required for new products.');
    }

    final categoryId = await _resolveCategoryId(row, categoryCache);
    if (existing == null) {
      await ProductRepository.create(
        name: name!,
        price: SpreadsheetImportReader.readMoney(row, _priceKeys) ?? 0,
        cost: SpreadsheetImportReader.readMoney(row, _costKeys),
        brand: SpreadsheetImportReader.readText(row, ['brand']),
        sku: SpreadsheetImportReader.readText(row, _skuKeys),
        barcode: SpreadsheetImportReader.readText(row, _barcodeKeys),
        stock: SpreadsheetImportReader.readMoney(row, _stockKeys) ?? 0,
        lowStock:
            SpreadsheetImportReader.readMoney(row, [
              'low_stock',
              'reorder_level',
            ]) ??
            5,
        unit: UnitUtils.normalize(
          SpreadsheetImportReader.readText(row, ['unit']) ?? 'pcs',
        ),
        stockUnit: UnitUtils.normalize(
          SpreadsheetImportReader.readText(row, ['stock_unit']),
        ),
        saleUnit: UnitUtils.normalize(
          SpreadsheetImportReader.readText(row, ['sale_unit']),
        ),
        saleToStockFactor:
            _positiveNumber(row, ['sale_to_stock_factor', 'stock_factor']) ?? 1,
        purchaseUnit: UnitUtils.normalize(
          SpreadsheetImportReader.readText(row, ['purchase_unit']),
        ),
        purchaseToStockFactor:
            _positiveNumber(row, ['purchase_to_stock_factor']) ?? 1,
        imageUrl: SpreadsheetImportReader.readText(row, ['image_url', 'image']),
        categoryId: categoryId,
        initialExpiryDate: ExpiryUtils.toStorageString(
          SpreadsheetImportReader.readDate(row, ['expiry_date', 'expires_on']),
        ),
        initialBatchNumber: SpreadsheetImportReader.readText(row, [
          'batch_number',
          'batch',
        ]),
        trackStock:
            SpreadsheetImportReader.readBool(row, [
              'track_stock',
              'tracks_stock',
            ]) ??
            true,
      );
      return const _ProductRowImportResult(created: true);
    }

    final updates = <String, dynamic>{};
    _putIfPresent(updates, 'name', name);
    _putIfPresent(
      updates,
      'price',
      SpreadsheetImportReader.readMoney(row, _priceKeys),
    );
    _putIfPresent(
      updates,
      'cost',
      SpreadsheetImportReader.readMoney(row, _costKeys),
    );
    _putIfPresent(
      updates,
      'brand',
      SpreadsheetImportReader.readText(row, ['brand']),
    );
    _putIfPresent(
      updates,
      'sku',
      SpreadsheetImportReader.readText(row, _skuKeys),
    );
    _putIfPresent(
      updates,
      'barcode',
      SpreadsheetImportReader.readText(row, _barcodeKeys),
    );
    _putIfPresent(
      updates,
      'low_stock',
      SpreadsheetImportReader.readMoney(row, ['low_stock', 'reorder_level']),
    );
    _putIfPresent(
      updates,
      'image_url',
      SpreadsheetImportReader.readText(row, ['image_url', 'image']),
    );
    if (categoryId != null) {
      updates['category_id'] = categoryId;
    }
    _putIfPresent(updates, 'unit', _normalizedUnitIfPresent(row, ['unit']));
    _putIfPresent(
      updates,
      'stock_unit',
      _normalizedUnitIfPresent(row, ['stock_unit']),
    );
    _putIfPresent(
      updates,
      'sale_unit',
      _normalizedUnitIfPresent(row, ['sale_unit']),
    );
    _putIfPresent(
      updates,
      'purchase_unit',
      _normalizedUnitIfPresent(row, ['purchase_unit']),
    );
    _putIfPresent(
      updates,
      'sale_to_stock_factor',
      _positiveNumber(row, ['sale_to_stock_factor', 'stock_factor']),
    );
    _putIfPresent(
      updates,
      'purchase_to_stock_factor',
      _positiveNumber(row, ['purchase_to_stock_factor']),
    );
    final trackStock = SpreadsheetImportReader.readBool(row, [
      'track_stock',
      'tracks_stock',
    ]);
    if (trackStock != null) {
      updates['track_stock'] = trackStock ? 1 : 0;
    }

    if (updates.isNotEmpty) {
      await ProductRepository.update(existing['id'] as String, updates);
    }

    var stockBatchAdded = false;
    final stockToAdd = SpreadsheetImportReader.readMoney(row, [
      ..._stockAddKeys,
      ..._stockKeys,
    ]);
    if (stockToAdd != null && stockToAdd > 0) {
      await ProductRepository.addStockBatch(
        productId: existing['id'] as String,
        quantity: stockToAdd,
        unitCost:
            SpreadsheetImportReader.readMoney(row, _costKeys) ??
            (existing['cost'] as num? ?? 0).toDouble(),
        product: {...existing, ...updates},
        sourceUnit: SpreadsheetImportReader.readText(row, [
          'source_unit',
          'purchase_unit',
          'unit',
        ]),
        expiryDate: ExpiryUtils.toStorageString(
          SpreadsheetImportReader.readDate(row, ['expiry_date', 'expires_on']),
        ),
        batchNumber: SpreadsheetImportReader.readText(row, [
          'batch_number',
          'batch',
        ]),
      );
      stockBatchAdded = true;
    }

    return _ProductRowImportResult(
      updated: true,
      stockBatchAdded: stockBatchAdded,
    );
  }

  static Future<Map<String, dynamic>?> _findExistingProduct(
    Map<String, String> row,
  ) async {
    final productId = SpreadsheetImportReader.readText(row, ['product_id']);
    if (productId != null) {
      return ProductRepository.getById(productId);
    }

    final barcode = SpreadsheetImportReader.readText(row, _barcodeKeys);
    if (barcode != null) {
      final product = await ProductRepository.getByBarcode(barcode);
      if (product != null) return product;
    }

    final sku = SpreadsheetImportReader.readText(row, _skuKeys);
    if (sku != null) {
      final rows = await DatabaseService.rawQuery(
        '''
        SELECT *
        FROM products
        WHERE LOWER(COALESCE(sku, '')) = ?
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        LIMIT 1
        ''',
        [
          sku.trim().toLowerCase(),
          DatabaseService.defaultBranchId,
          DatabaseService.currentBranchId,
        ],
      );
      if (rows.isNotEmpty) return rows.first;
    }

    final name = SpreadsheetImportReader.readText(row, _nameKeys);
    if (name != null) {
      final rows = await DatabaseService.rawQuery(
        '''
        SELECT *
        FROM products
        WHERE LOWER(TRIM(name)) = ?
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        LIMIT 1
        ''',
        [
          name.trim().toLowerCase(),
          DatabaseService.defaultBranchId,
          DatabaseService.currentBranchId,
        ],
      );
      if (rows.isNotEmpty) return rows.first;
    }
    return null;
  }

  static Future<Map<String, String>> _categoryCache() async {
    final categories = await CategoryRepository.getAll();
    return {
      for (final category in categories)
        if (category['id'] != null)
          (category['name'] as String? ?? '').trim().toLowerCase():
              category['id'] as String,
    };
  }

  static Future<String?> _resolveCategoryId(
    Map<String, String> row,
    Map<String, String> categoryCache,
  ) async {
    final categoryName = SpreadsheetImportReader.readText(row, _categoryKeys);
    if (categoryName == null) {
      return null;
    }
    final key = categoryName.trim().toLowerCase();
    final existingId = categoryCache[key];
    if (existingId != null) {
      return existingId;
    }
    final id = await CategoryRepository.create(name: categoryName);
    categoryCache[key] = id;
    return id;
  }

  static String? _normalizedUnitIfPresent(
    Map<String, String> row,
    List<String> keys,
  ) {
    final raw = SpreadsheetImportReader.readText(row, keys);
    return raw == null ? null : UnitUtils.normalize(raw);
  }

  static double? _positiveNumber(Map<String, String> row, List<String> keys) {
    final value = SpreadsheetImportReader.readMoney(row, keys);
    if (value == null || value <= 0) {
      return null;
    }
    return value;
  }

  static void _putIfPresent(
    Map<String, dynamic> updates,
    String key,
    Object? value,
  ) {
    if (value != null) {
      updates[key] = value;
    }
  }
}

class _ProductRowImportResult {
  final bool created;
  final bool updated;
  final bool stockBatchAdded;

  const _ProductRowImportResult({
    this.created = false,
    this.updated = false,
    this.stockBatchAdded = false,
  });
}
