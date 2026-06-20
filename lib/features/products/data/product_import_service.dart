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
import 'product_variant_repository.dart';

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
    'variant_id': ['variant id', 'product variant id', 'option id'],
    'parent_product_id': [
      'parent id',
      'parent_product',
      'base_product_id',
      'main_product_id',
    ],
    'parent_product_name': [
      'parent product',
      'parent product name',
      'base_product',
      'base product',
      'main product',
      'product family',
    ],
    'variant_name': [
      'variant',
      'variation',
      'variety',
      'option',
      'option name',
      'size',
      'colour',
      'color',
      'flavour',
      'flavor',
      'pack size',
      'pack_size',
    ],
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
  static const _productIdKeys = ['product_id'];
  static const _variantIdKeys = ['variant_id'];
  static const _parentProductIdKeys = ['parent_product_id'];
  static const _parentProductNameKeys = ['parent_product_name'];
  static const _variantNameKeys = ['variant_name'];
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
      requiredAny: const [
        'name',
        'sku',
        'barcode',
        'product_id',
        'variant_id',
        'parent_product_id',
        'parent_product_name',
        'variant_name',
      ],
      importLabel: 'products',
    );
  }

  static void _validatePlan(SpreadsheetImportPlan plan) {
    if (!SpreadsheetImportReader.hasAnyHeader(plan.headers, [
      ..._nameKeys,
      ..._skuKeys,
      ..._barcodeKeys,
      'product_id',
      'variant_id',
      'parent_product_id',
      'parent_product_name',
      'variant_name',
    ])) {
      throw Exception(
        'Only one product identifier column is required: name for new products, sku/barcode/product_id for updates, or parent_product_name plus variant_name for variants.',
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
    if (_hasVariantIntent(row)) {
      final parent = await _resolveParentProductForVariant(row, categoryCache);
      final variantName = SpreadsheetImportReader.readText(
        row,
        _variantNameKeys,
      );
      final existingVariant = await _findExistingVariant(
        row,
        parentId: parent?['id'] as String?,
        variantName: variantName,
      );
      final resolvedParent =
          parent ?? await _parentProductForVariant(existingVariant);
      if (resolvedParent == null) {
        throw Exception(
          'Parent product is required before importing this variant.',
        );
      }
      return _importVariantRow(
        row,
        resolvedParent,
        variantName: variantName,
        existingVariant: existingVariant,
      );
    }

    final existingVariant = await _findExistingVariant(row);
    if (existingVariant != null) {
      final parent = await _parentProductForVariant(existingVariant);
      if (parent == null) {
        throw Exception('Parent product was not found for this variant.');
      }
      return _importVariantRow(
        row,
        parent,
        variantName: existingVariant['name'] as String?,
        existingVariant: existingVariant,
      );
    }

    final inferredVariant = await _inferVariantFromProductName(row);
    if (inferredVariant != null) {
      return _importVariantRow(
        row,
        inferredVariant.parent,
        variantName: inferredVariant.variantName,
      );
    }

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

  static bool _hasVariantIntent(Map<String, String> row) {
    return SpreadsheetImportReader.readText(row, _variantIdKeys) != null ||
        SpreadsheetImportReader.readText(row, _variantNameKeys) != null ||
        SpreadsheetImportReader.readText(row, _parentProductIdKeys) != null ||
        SpreadsheetImportReader.readText(row, _parentProductNameKeys) != null;
  }

  static Future<_ProductRowImportResult> _importVariantRow(
    Map<String, String> row,
    Map<String, dynamic> parent, {
    String? variantName,
    Map<String, dynamic>? existingVariant,
  }) async {
    final parentId = parent['id'] as String?;
    if (parentId == null || parentId.trim().isEmpty) {
      throw Exception('Parent product is missing for this variant.');
    }

    final cleanVariantName =
        _cleanText(variantName) ??
        _cleanText(existingVariant?['name']) ??
        _cleanText(SpreadsheetImportReader.readText(row, _nameKeys));
    if (cleanVariantName == null) {
      throw Exception('Variant name is required.');
    }

    final existing =
        existingVariant ??
        await _findExistingVariant(
          row,
          parentId: parentId,
          variantName: cleanVariantName,
        );
    final stockReceived = SpreadsheetImportReader.readMoney(row, _stockAddKeys);
    final stockValue = SpreadsheetImportReader.readMoney(row, _stockKeys);
    final lowStock = SpreadsheetImportReader.readMoney(row, [
      'low_stock',
      'reorder_level',
    ]);

    if (existing == null) {
      await ProductVariantRepository.create(
        productId: parentId,
        name: cleanVariantName,
        price:
            SpreadsheetImportReader.readMoney(row, _priceKeys) ??
            _numberOr(parent['price'], 0),
        cost: SpreadsheetImportReader.readMoney(row, _costKeys),
        sku: SpreadsheetImportReader.readText(row, _skuKeys),
        barcode: SpreadsheetImportReader.readText(row, _barcodeKeys),
        stock: stockReceived ?? stockValue ?? 0,
        lowStock: lowStock ?? _numberOr(parent['low_stock'], 0),
      );
      await ProductVariantRepository.setProductHasVariants(parentId, true);
      await ProductVariantRepository.syncAggregateStock(parentId);
      return const _ProductRowImportResult(created: true);
    }

    final updates = <String, dynamic>{'name': cleanVariantName};
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
      'sku',
      SpreadsheetImportReader.readText(row, _skuKeys),
    );
    _putIfPresent(
      updates,
      'barcode',
      SpreadsheetImportReader.readText(row, _barcodeKeys),
    );
    _putIfPresent(updates, 'low_stock', lowStock);
    if (stockReceived != null && stockReceived > 0) {
      updates['stock'] = _numberOr(existing['stock'], 0) + stockReceived;
    } else if (stockValue != null) {
      updates['stock'] = stockValue;
    }

    if (updates.isNotEmpty) {
      await ProductVariantRepository.update(existing['id'] as String, updates);
    }
    await ProductVariantRepository.setProductHasVariants(parentId, true);
    await ProductVariantRepository.syncAggregateStock(parentId);
    return const _ProductRowImportResult(updated: true);
  }

  static Future<Map<String, dynamic>?> _resolveParentProductForVariant(
    Map<String, String> row,
    Map<String, String> categoryCache,
  ) async {
    final variantId = SpreadsheetImportReader.readText(row, _variantIdKeys);
    if (variantId != null) {
      final variant = await _findVariantById(variantId);
      final parent = await _parentProductForVariant(variant);
      if (parent != null) return parent;
    }

    final parentId =
        SpreadsheetImportReader.readText(row, _parentProductIdKeys) ??
        SpreadsheetImportReader.readText(row, _productIdKeys);
    if (parentId != null) {
      final parent = await ProductRepository.getById(parentId);
      if (parent != null) return parent;
    }

    final explicitParentName = SpreadsheetImportReader.readText(
      row,
      _parentProductNameKeys,
    );
    if (explicitParentName != null) {
      return await _findProductByExactName(explicitParentName) ??
          await _createParentProductForVariant(
            row,
            categoryCache,
            explicitParentName,
          );
    }

    final variantName = SpreadsheetImportReader.readText(row, _variantNameKeys);
    final productName = SpreadsheetImportReader.readText(row, _nameKeys);
    if (variantName != null &&
        productName != null &&
        _normalizeName(productName) != _normalizeName(variantName)) {
      final parentName =
          _parentNameWithoutVariantSuffix(productName, variantName) ??
          productName;
      return await _findProductByExactName(parentName) ??
          await _createParentProductForVariant(row, categoryCache, parentName);
    }

    return null;
  }

  static Future<Map<String, dynamic>> _createParentProductForVariant(
    Map<String, String> row,
    Map<String, String> categoryCache,
    String parentName,
  ) async {
    final categoryId = await _resolveCategoryId(row, categoryCache);
    final imageFields = await _readHostedImageFields(
      row,
      productName: parentName,
    );
    final productId = await ProductRepository.create(
      name: parentName,
      price: SpreadsheetImportReader.readMoney(row, _priceKeys) ?? 0,
      cost: SpreadsheetImportReader.readMoney(row, _costKeys),
      brand: SpreadsheetImportReader.readText(row, ['brand']),
      stock: 0,
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
      trackStock:
          SpreadsheetImportReader.readBool(row, [
            'track_stock',
            'tracks_stock',
          ]) ??
          true,
      hasVariants: true,
    );
    final product = await ProductRepository.getById(productId);
    if (product == null) {
      throw Exception('Could not create parent product for variant.');
    }
    return product;
  }

  static Future<Map<String, dynamic>?> _parentProductForVariant(
    Map<String, dynamic>? variant,
  ) async {
    final productId = variant?['product_id'] as String?;
    if (productId == null || productId.trim().isEmpty) {
      return null;
    }
    return ProductRepository.getById(productId);
  }

  static Future<Map<String, dynamic>?> _findExistingVariant(
    Map<String, String> row, {
    String? parentId,
    String? variantName,
  }) async {
    final variantId = SpreadsheetImportReader.readText(row, _variantIdKeys);
    if (variantId != null) {
      final variant = await _findVariantById(variantId);
      if (_variantMatchesParent(variant, parentId)) return variant;
    }

    final barcode = SpreadsheetImportReader.readText(row, _barcodeKeys);
    if (barcode != null) {
      final variant = await ProductVariantRepository.getByBarcode(barcode);
      if (_variantMatchesParent(variant, parentId)) return variant;
    }

    final sku = SpreadsheetImportReader.readText(row, _skuKeys);
    if (sku != null) {
      final variant = await _findVariantByField(
        field: 'sku',
        value: sku,
        parentId: parentId,
      );
      if (variant != null) return variant;
    }

    final cleanVariantName =
        _cleanText(variantName) ??
        SpreadsheetImportReader.readText(row, _variantNameKeys);
    if (parentId != null && cleanVariantName != null) {
      return _findVariantByField(
        field: 'name',
        value: cleanVariantName,
        parentId: parentId,
      );
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _findVariantById(String id) async {
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT pv.*, p.name AS parent_product_name
      FROM product_variants pv
      JOIN products p ON p.id = pv.product_id
      WHERE pv.id = ?
        AND pv.deleted_at IS NULL
        AND p.deleted_at IS NULL
        AND COALESCE(pv.branch_id, ?) = ?
      LIMIT 1
      ''',
      [id, DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>?> _findVariantByField({
    required String field,
    required String value,
    String? parentId,
  }) async {
    if (!const ['name', 'sku'].contains(field)) {
      return null;
    }
    final args = <Object?>[
      value.trim().toLowerCase(),
      DatabaseService.defaultBranchId,
      DatabaseService.currentBranchId,
    ];
    final parentClause = parentId == null ? '' : 'AND pv.product_id = ?';
    if (parentId != null) {
      args.add(parentId);
    }
    final rows = await DatabaseService.rawQuery('''
      SELECT pv.*, p.name AS parent_product_name
      FROM product_variants pv
      JOIN products p ON p.id = pv.product_id
      WHERE LOWER(TRIM(COALESCE(pv.$field, ''))) = ?
        AND pv.deleted_at IS NULL
        AND p.deleted_at IS NULL
        AND COALESCE(pv.branch_id, ?) = ?
        $parentClause
      LIMIT 1
      ''', args);
    return rows.isEmpty ? null : rows.first;
  }

  static bool _variantMatchesParent(
    Map<String, dynamic>? variant,
    String? parentId,
  ) {
    if (variant == null) return false;
    return parentId == null || variant['product_id'] == parentId;
  }

  static Future<Map<String, dynamic>?> _findProductByExactName(
    String name,
  ) async {
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
    return rows.isEmpty ? null : rows.first;
  }

  static Future<_InferredProductVariant?> _inferVariantFromProductName(
    Map<String, String> row,
  ) async {
    final productName = SpreadsheetImportReader.readText(row, _nameKeys);
    if (productName == null) return null;

    final parents = await DatabaseService.rawQuery(
      '''
      SELECT p.*, COALESCE(vc.active_variant_count, 0) AS active_variant_count
      FROM products p
      LEFT JOIN (
        SELECT product_id, COUNT(*) AS active_variant_count
        FROM product_variants
        WHERE deleted_at IS NULL
        GROUP BY product_id
      ) vc ON vc.product_id = p.id
      WHERE p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
      ORDER BY LENGTH(TRIM(p.name)) DESC
      ''',
      [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
    );

    for (final parent in parents) {
      final parentName = _cleanText(parent['name']);
      if (parentName == null) continue;
      final variantName = _variantNameFromImportedProductName(
        productName,
        parentName,
        parent,
      );
      if (variantName != null) {
        return _InferredProductVariant(
          parent: parent,
          variantName: variantName,
        );
      }
    }
    return null;
  }

  static String? _variantNameFromImportedProductName(
    String productName,
    String parentName,
    Map<String, dynamic> parent,
  ) {
    final cleanProduct = productName.trim();
    final cleanParent = parentName.trim();
    if (cleanProduct.length <= cleanParent.length) return null;
    if (!cleanProduct.toLowerCase().startsWith(cleanParent.toLowerCase())) {
      return null;
    }
    final boundary = cleanProduct.substring(
      cleanParent.length,
      cleanParent.length + 1,
    );
    if (RegExp(r'[A-Za-z0-9]').hasMatch(boundary)) {
      return null;
    }
    final remainder = _trimVariantSeparators(
      cleanProduct.substring(cleanParent.length),
    );
    if (remainder.isEmpty) return null;

    final hasVariants =
        _numberOr(parent['has_variants'], 0) > 0 ||
        _numberOr(parent['active_variant_count'], 0) > 0;
    if (hasVariants || _looksLikeVariantName(remainder)) {
      return remainder;
    }
    return null;
  }

  static String _trimVariantSeparators(String value) {
    return value
        .replaceFirst(RegExp(r'^[\s\-_/|:()]+'), '')
        .replaceFirst(RegExp(r'[\s\-_/|:()]+$'), '')
        .trim();
  }

  static String? _parentNameWithoutVariantSuffix(
    String productName,
    String variantName,
  ) {
    final cleanProduct = productName.trim();
    final cleanVariant = variantName.trim();
    if (cleanProduct.length <= cleanVariant.length) return null;
    if (!cleanProduct.toLowerCase().endsWith(cleanVariant.toLowerCase())) {
      return null;
    }
    final parent = _trimVariantSeparators(
      cleanProduct.substring(0, cleanProduct.length - cleanVariant.length),
    );
    return parent.isEmpty ? null : parent;
  }

  static bool _looksLikeVariantName(String value) {
    final lower = value.toLowerCase();
    return RegExp(
          r'\b\d+(\.\d+)?\s*(ml|l|lt|ltr|litre|liter|g|kg|mg|oz|lb|pc|pcs|piece|pieces|pack|pkt|box|ct|cm|mm|m)\b',
        ).hasMatch(lower) ||
        RegExp(r'^\d+\s*x\s*\d+').hasMatch(lower) ||
        RegExp(r'\b(xs|s|m|l|xl|xxl|small|medium|large)\b').hasMatch(lower) ||
        RegExp(
          r'\b(red|blue|green|black|white|yellow|pink|purple|brown|orange|grey|gray|gold|silver|clear)\b',
        ).hasMatch(lower) ||
        RegExp(
          r'\b(vanilla|chocolate|strawberry|mint|lemon|mango|banana|plain|original|classic|spicy|hot|mild)\b',
        ).hasMatch(lower) ||
        RegExp(
          r'\b(size|color|colour|flavor|flavour|pack|bottle|carton|crate|tin|can|refill|sachet|roll|rolls)\b',
        ).hasMatch(lower);
  }

  static String _normalizeName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? _cleanText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double _numberOr(Object? value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
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

class _InferredProductVariant {
  final Map<String, dynamic> parent;
  final String variantName;

  const _InferredProductVariant({
    required this.parent,
    required this.variantName,
  });
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
