import 'dart:convert';

import '../../../core/data/cloud_spreadsheet_import_planner.dart';
import '../../../core/data/spreadsheet_import_reader.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/openrouter_service.dart';
import '../../../core/services/product_image_upload_service.dart';
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
      'selling price',
      'selling price kes',
      'sale price kes',
      'retail price kes',
      'amount',
    ],
    'cost': [
      'unit_cost',
      'buying_price',
      'purchase_price',
      'buy price',
      'cost price',
      'cost price kes',
      'unit cost kes',
    ],
    'sku': ['product_sku', 'item_sku', 'stock_code', 'code'],
    'barcode': ['product_barcode', 'item_barcode', 'bar_code'],
    'category': ['category_name', 'group', 'department'],
    'stock': [
      'opening_stock',
      'initial_stock',
      'qty',
      'quantity',
      'stock_qty',
      'stock quantity',
      'stock on hand',
      'on hand',
    ],
    'stock_received': [
      'add_stock',
      'stock_in',
      'receive_stock',
      'quantity_received',
      'received_qty',
    ],
    'low_stock': [
      'reorder_level',
      'minimum_stock',
      'min_stock',
      'reorder level',
    ],
    'unit': ['base_unit'],
    'stock_unit': ['stock unit', 'inventory_unit', 'inventory unit'],
    'sale_unit': ['sale unit', 'selling_unit', 'selling unit'],
    'purchase_unit': ['buying_unit'],
    'sale_to_stock_factor': ['stock_factor', 'conversion'],
    'purchase_to_stock_factor': ['purchase_factor'],
    'track_stock': ['tracks_stock', 'stock_tracking'],
    'brand': ['manufacturer'],
    'description': ['details', 'product_details', 'long_description', 'notes'],
    'image_url': ['image', 'photo'],
    'image_urls_json': ['images', 'image_urls', 'gallery', 'photos'],
    'show_online': ['online', 'catalog', 'publish', 'visible_online'],
    'is_featured': ['featured', 'feature', 'top_pick', 'promote'],
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
  static const _descriptionKeys = [
    'description',
    'details',
    'product_details',
    'notes',
  ];
  static const _imageUrlsKeys = [
    'image_urls_json',
    'image_urls',
    'images',
    'gallery',
    'photos',
  ];
  static const _showOnlineKeys = [
    'show_online',
    'online',
    'catalog',
    'publish',
    'visible_online',
  ];
  static const _isFeaturedKeys = [
    'is_featured',
    'featured',
    'feature',
    'top_pick',
    'promote',
  ];
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
      dialogTitle: 'Import Products with Piki AI',
      allowedExtensions: SpreadsheetImportReader.productImportExtensions,
    );
    if (file == null) {
      return null;
    }
    final plan = await buildPlanForPickedFile(file);
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

  static SpreadsheetImportPlan buildPlanFromCloudResult(
    Map<String, dynamic> cloud, {
    String? fileName,
  }) {
    final rows = _rowsFromCloudProductFile(cloud);
    final plan = _buildRawPlan(
      rows,
      fileName: fileName ?? cloud['fileName']?.toString(),
    );
    _validatePlan(plan);
    return plan.copyWith(
      warnings: _dedupe([
        ...plan.warnings,
        'Piki prepared this import in the backend. Review before importing.',
        ..._cloudWarnings(cloud),
      ]),
    );
  }

  static Future<SpreadsheetImportPlan> buildPlanForPickedFile(
    SpreadsheetFileRows file,
  ) async {
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      try {
        return await buildPlanFromCloudFile(file);
      } catch (error) {
        if (!SpreadsheetImportReader.isSpreadsheetExtension(file.extension)) {
          rethrow;
        }
        final fallback = await buildPlanWithCloud(
          file.rows,
          fileName: file.fileName,
        );
        return fallback.copyWith(
          warnings: _dedupe([
            ...fallback.warnings,
            'Piki cloud extraction was unavailable, so Piki used spreadsheet column mapping instead.',
          ]),
        );
      }
    }
    return buildPlanWithCloud(file.rows, fileName: file.fileName);
  }

  static SpreadsheetImportPlan buildPlan(
    List<List<String>> rows, {
    String? fileName,
  }) {
    final plan = _buildRawPlan(rows, fileName: fileName);
    _validatePlan(plan);
    return plan;
  }

  static Future<SpreadsheetImportPlan> buildPlanFromCloudFile(
    SpreadsheetFileRows file,
  ) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Could not read the selected product file.');
    }

    final cloud = await OpenRouterService.extractProductImportRows(
      fileName: file.fileName,
      bytes: bytes,
      mimeType: file.mimeType,
      extension: file.extension,
      sourceText: file.extractedText,
    );
    final rows = _rowsFromCloudProductFile(cloud);
    final plan = _buildRawPlan(rows, fileName: file.fileName);
    _validatePlan(plan);
    return plan.copyWith(
      warnings: _dedupe([
        ...plan.warnings,
        'Piki cloud AI extracted product rows from ${file.fileName}. Review before importing.',
        ..._cloudWarnings(cloud),
      ]),
    );
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
    final imageFields = await _readHostedImageFields(
      row,
      productName: name ?? existing?['name'] as String?,
    );
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
        imageUrl: imageFields.imageUrl,
        description: SpreadsheetImportReader.readText(row, _descriptionKeys),
        imageUrlsJson: imageFields.imageUrlsJson,
        showOnline:
            SpreadsheetImportReader.readBool(row, _showOnlineKeys) ?? true,
        isFeatured:
            SpreadsheetImportReader.readBool(row, _isFeaturedKeys) ?? false,
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
    _putIfPresent(updates, 'image_url', imageFields.imageUrl);
    _putIfPresent(
      updates,
      'description',
      SpreadsheetImportReader.readText(row, _descriptionKeys),
    );
    _putIfPresent(updates, 'image_urls_json', imageFields.imageUrlsJson);
    final showOnline = SpreadsheetImportReader.readBool(row, _showOnlineKeys);
    if (showOnline != null) {
      updates['show_online'] = showOnline ? 1 : 0;
    }
    final isFeatured = SpreadsheetImportReader.readBool(row, _isFeaturedKeys);
    if (isFeatured != null) {
      updates['is_featured'] = isFeatured ? 1 : 0;
    }
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

  static List<List<String>> _rowsFromCloudProductFile(
    Map<String, dynamic> cloud,
  ) {
    var headers =
        (cloud['headers'] as List?)
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList() ??
        <String>[];
    final rows = <List<String>>[];
    final rawRows = cloud['rows'];

    if (rawRows is List) {
      for (final item in rawRows) {
        if (item is List) {
          rows.add(
            item.map((value) => value?.toString().trim() ?? '').toList(),
          );
          continue;
        }
        if (item is Map) {
          final rowMap = Map<String, dynamic>.from(item);
          if (headers.isEmpty) {
            headers = rowMap.keys.map((key) => key.toString()).toList();
          }
          rows.add(
            headers
                .map((header) => rowMap[header]?.toString().trim() ?? '')
                .toList(),
          );
        }
      }
    }

    if (headers.isEmpty || rows.isEmpty) {
      throw Exception('Piki could not find product rows in this file.');
    }
    return [headers, ...rows];
  }

  static List<String> _cloudWarnings(Map<String, dynamic> cloud) {
    final warnings = <String>[];
    final summary = cloud['summary']?.toString().trim();
    if (summary != null && summary.isNotEmpty) {
      warnings.add(summary);
    }
    final rawWarnings = cloud['warnings'];
    if (rawWarnings is List) {
      warnings.addAll(
        rawWarnings
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty),
      );
    }
    if (cloud['sourceTextTruncated'] == true) {
      warnings.add(
        'The file was long, so Piki reviewed the first part of the extracted text.',
      );
    }
    return warnings;
  }

  static Future<_ProductImageFields> _readHostedImageFields(
    Map<String, String> row, {
    String? productName,
  }) async {
    final primary = SpreadsheetImportReader.readText(row, [
      'image_url',
      'image',
    ]);
    final rawUrls = <String>[?primary, ..._readImageUrlList(row)];
    final urls = <String>[];
    for (final rawUrl in rawUrls) {
      final clean = rawUrl.trim();
      if (clean.isEmpty || urls.contains(clean)) {
        continue;
      }
      final hosted = await _resolveImportImageUrl(
        clean,
        productName: productName,
      );
      if (!urls.contains(hosted)) {
        urls.add(hosted);
      }
    }

    return _ProductImageFields(
      imageUrl: urls.isEmpty ? primary : urls.first,
      imageUrlsJson: urls.isEmpty ? null : jsonEncode(urls),
    );
  }

  static Future<String> _resolveImportImageUrl(
    String value, {
    String? productName,
  }) async {
    if (ProductImageUploadService.isRemoteImage(value)) {
      return value;
    }
    return ProductImageUploadService.uploadProductImage(
      imagePath: value,
      productName: productName,
    );
  }

  static List<String> _readImageUrlList(Map<String, String> row) {
    final raw = SpreadsheetImportReader.readText(row, _imageUrlsKeys);
    if (raw == null) {
      return const [];
    }

    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        return parsed
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Fall back to splitting pasted URL lists below.
    }

    return raw
        .split(RegExp(r'[\n,;]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) {
        continue;
      }
      result.add(trimmed);
    }
    return result;
  }
}

class _ProductImageFields {
  final String? imageUrl;
  final String? imageUrlsJson;

  const _ProductImageFields({
    required this.imageUrl,
    required this.imageUrlsJson,
  });
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
