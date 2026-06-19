import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';

import '../../../core/data/cloud_spreadsheet_import_planner.dart';
import '../../../core/data/spreadsheet_import_reader.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/unit_utils.dart';
import '../../customers/data/customer_repository.dart';
import 'sale_repository.dart';

class SaleImportResult {
  final int imported;
  final int skipped;
  final int productLines;
  final int serviceLines;
  final int summaryOnly;
  final List<String> errors;
  final String? fileName;

  const SaleImportResult({
    required this.imported,
    required this.skipped,
    this.productLines = 0,
    this.serviceLines = 0,
    this.summaryOnly = 0,
    required this.errors,
    this.fileName,
  });

  bool get hasErrors => errors.isNotEmpty;
}

enum _ImportedSaleKind { summary, product, service }

class _ImportedSaleLine {
  final _ImportedSaleKind kind;
  final List<Map<String, dynamic>> items;
  final String? label;

  const _ImportedSaleLine({
    required this.kind,
    required this.items,
    this.label,
  });
}

class _ImportedSaleRowResult {
  final _ImportedSaleKind kind;

  const _ImportedSaleRowResult(this.kind);
}

class _ProductMatch {
  final Map<String, dynamic> product;
  final Map<String, dynamic>? variant;

  const _ProductMatch({required this.product, this.variant});

  String get productId => product['id'] as String;
  String? get variantId => variant?['id'] as String?;

  String get label {
    final productName = product['name'] as String? ?? 'Product';
    final variantName = variant?['name'] as String?;
    if (variantName == null || variantName.trim().isEmpty) {
      return productName;
    }
    return '$productName - $variantName';
  }

  double get price {
    return (variant?['price'] as num? ?? product['price'] as num? ?? 0)
        .toDouble();
  }

  double get cost {
    return (variant?['cost'] as num? ?? product['cost'] as num? ?? 0)
        .toDouble();
  }
}

class SaleImportService {
  static const columnAliases = {
    'date': ['sale_date', 'created_at', 'sold_at', 'transaction_date'],
    'total': ['total_amount', 'amount', 'sale_total', 'paid', 'value'],
    'payment_type': ['payment', 'method', 'payment_method'],
    'tax': ['vat', 'tax_amount'],
    'discount': ['discount_amount'],
    'customer_name': ['customer', 'client', 'client_name'],
    'phone': ['customer_phone', 'mobile', 'phone_number'],
    'due_date': ['credit_due_date', 'kopesha_due_date'],
    'reference': ['receipt', 'receipt_no', 'invoice', 'invoice_no'],
    'note': ['notes', 'description', 'remarks'],
    'line_type': ['type', 'item_type'],
    'product_id': ['product id'],
    'variant_id': ['variant id'],
    'sku': ['product_sku', 'item_sku', 'variant_sku', 'stock_code', 'code'],
    'barcode': ['product_barcode', 'item_barcode', 'variant_barcode'],
    'product': ['product_name', 'item', 'item_name', 'prdct'],
    'service_id': ['service id'],
    'service': ['service_name'],
    'quantity': ['qty', 'units', 'sold_quantity'],
    'unit_price': ['price', 'rate', 'selling_price'],
    'unit_cost': ['cost'],
    'unit': ['sale_unit'],
  };
  static const supportedExtensions = ['xlsx', 'csv'];
  static const _totalKeys = ['total', 'total_amount', 'amount', 'sale_total'];
  static const _productIdKeys = ['product_id'];
  static const _variantIdKeys = ['variant_id'];
  static const _skuKeys = ['sku', 'product_sku', 'item_sku', 'variant_sku'];
  static const _barcodeKeys = [
    'barcode',
    'product_barcode',
    'item_barcode',
    'variant_barcode',
  ];
  static const _productNameKeys = [
    'product',
    'product_name',
    'item',
    'item_name',
  ];
  static const _serviceIdKeys = ['service_id'];
  static const _serviceNameKeys = ['service', 'service_name'];
  static const _quantityKeys = ['quantity', 'qty', 'units', 'sold_quantity'];
  static const _unitPriceKeys = ['unit_price', 'price', 'rate'];
  static const _itemLookupKeys = [
    ..._productIdKeys,
    ..._variantIdKeys,
    ..._skuKeys,
    ..._barcodeKeys,
    ..._productNameKeys,
    ..._serviceIdKeys,
    ..._serviceNameKeys,
  ];

  static Future<SaleImportResult?> pickAndImportSales({
    Future<bool> Function(SpreadsheetImportPlan plan)? confirmPlan,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Sales from Excel or CSV',
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      return null;
    }

    final file = picked.files.single;
    final extension = _extensionFor(file.name, file.path);
    final bytes = file.bytes ?? await _readFileBytes(file.path);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Could not read the selected file.');
    }

    final rows = switch (extension) {
      'csv' => _readCsvRows(bytes),
      'xlsx' => _readExcelRows(bytes),
      _ => throw Exception('Choose an .xlsx or .csv file.'),
    };

    final plan = await buildPlanWithCloud(rows, fileName: file.name);
    if (confirmPlan != null && !await confirmPlan(plan)) {
      return null;
    }
    return importPlan(plan);
  }

  static Future<SaleImportResult> importRows(
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
      importType: 'sales',
      importLabel: 'sales',
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
      requiredAny: const ['total', 'sku', 'barcode', 'product', 'service'],
      importLabel: 'sales',
    );
  }

  static void _validatePlan(SpreadsheetImportPlan plan) {
    final hasTotalColumn = SpreadsheetImportReader.hasAnyHeader(
      plan.headers,
      _totalKeys,
    );
    final hasItemColumn = SpreadsheetImportReader.hasAnyHeader(
      plan.headers,
      _itemLookupKeys,
    );
    if (!hasTotalColumn && !hasItemColumn) {
      throw Exception(
        'Only one sale format is required: a total column for summary sales, or product/service columns such as sku, barcode, product_name, or service_name.',
      );
    }
  }

  static Future<SaleImportResult> importPlan(SpreadsheetImportPlan plan) async {
    final headers = plan.headers;
    var imported = 0;
    var skipped = 0;
    var productLines = 0;
    var serviceLines = 0;
    var summaryOnly = 0;
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
        final row = _rowMap(headers, sourceRow);
        final result = await _importSaleRow(row, rowNumber: index + 1);
        switch (result.kind) {
          case _ImportedSaleKind.product:
            productLines += 1;
          case _ImportedSaleKind.service:
            serviceLines += 1;
          case _ImportedSaleKind.summary:
            summaryOnly += 1;
        }
        imported += 1;
      } catch (error) {
        skipped += 1;
        if (errors.length < 8) {
          errors.add(
            'Row ${index + 1}: ${error.toString().replaceFirst('Exception: ', '')}',
          );
        }
      }
    }

    return SaleImportResult(
      imported: imported,
      skipped: skipped,
      productLines: productLines,
      serviceLines: serviceLines,
      summaryOnly: summaryOnly,
      errors: errors,
      fileName: plan.fileName,
    );
  }

  static Future<_ImportedSaleRowResult> _importSaleRow(
    Map<String, String> row, {
    required int rowNumber,
  }) async {
    final discount = _readMoney(row, ['discount']) ?? 0;
    final tax = _readMoney(row, ['tax', 'vat']) ?? 0;
    if (discount < 0 || tax < 0) {
      throw Exception('Tax and discount cannot be negative.');
    }

    final rawTotal = _readMoney(row, _totalKeys);
    final lineSubtotalHint = rawTotal == null
        ? null
        : rawTotal - tax + discount;
    final importedLine = await _buildImportedLine(
      row,
      lineSubtotalHint: lineSubtotalHint != null && lineSubtotalHint > 0
          ? lineSubtotalHint
          : null,
    );
    final items = importedLine?.items ?? const <Map<String, dynamic>>[];
    final computedTotal = items.isEmpty
        ? null
        : _roundMoney(_lineSubtotal(items) + tax - discount);
    final total = rawTotal ?? computedTotal;
    if (total == null || total <= 0) {
      throw Exception(
        'Total must be greater than zero, or provide item quantity and price.',
      );
    }

    final paymentType = _normalizePaymentType(
      _readText(row, ['payment_type', 'payment', 'method']) ?? 'cash',
    );
    final saleDate =
        _readDate(row, ['date', 'sale_date', 'created_at', 'sold_at']) ??
        DateTime.now();
    final customerName = _readText(row, [
      'customer_name',
      'customer',
      'client',
    ]);
    final customerPhone = _readText(row, ['phone', 'customer_phone']);
    final dueDate = _readDate(row, ['due_date', 'credit_due_date']);
    final reference = _readText(row, [
      'reference',
      'receipt',
      'receipt_no',
      'invoice',
    ]);
    final note = _readText(row, ['note', 'notes', 'description']);
    final paymentMetadata = <String, dynamic>{
      'source': 'sales_import',
      'row_number': rowNumber,
    };
    if (importedLine?.label != null) {
      paymentMetadata['imported_item'] = importedLine!.label;
      paymentMetadata['imported_line_type'] = importedLine.kind.name;
    }
    if (note != null) {
      paymentMetadata['note'] = note;
    }

    String? customerId;
    String? cleanCustomerName;
    String? dueDateIso;
    if (paymentType.toLowerCase() == 'kopesha') {
      if (customerName == null || customerName.isEmpty) {
        throw Exception('Kopesha rows need customer_name.');
      }
      if (dueDate == null) {
        throw Exception('Kopesha rows need due_date.');
      }
      customerId = await _findOrCreateCustomer(
        customerName,
        phone: customerPhone,
      );
      cleanCustomerName = customerName;
      dueDateIso = dueDate.toIso8601String();
    }

    await SaleRepository.createSale(
      totalAmount: total,
      tax: tax,
      discount: discount,
      paymentType: paymentType,
      isCashDrawer: _isCashDrawerPayment(paymentType),
      userId: SessionService.currentUserId.trim().isNotEmpty
          ? SessionService.currentUserId
          : 'admin',
      customerId: customerId,
      customerName: cleanCustomerName,
      dueDate: dueDateIso,
      items: items,
      amountTendered: total,
      changeGiven: 0,
      paymentReference: reference,
      paymentStatus: 'imported',
      paymentMetadata: paymentMetadata,
      createdAt: saleDate,
    );

    return _ImportedSaleRowResult(
      importedLine?.kind ?? _ImportedSaleKind.summary,
    );
  }

  static Future<_ImportedSaleLine?> _buildImportedLine(
    Map<String, String> row, {
    double? lineSubtotalHint,
  }) async {
    final requestedKind = _requestedLineKind(row);
    if (requestedKind == _ImportedSaleKind.service ||
        _hasServiceLookup(row) && !_hasProductLookup(row)) {
      return _buildServiceLine(row, lineSubtotalHint: lineSubtotalHint);
    }

    if (requestedKind == _ImportedSaleKind.product || _hasProductLookup(row)) {
      return _buildProductLine(row, lineSubtotalHint: lineSubtotalHint);
    }

    if (requestedKind == _ImportedSaleKind.service) {
      throw Exception('Service rows need service_name or service_id.');
    }
    if (requestedKind == _ImportedSaleKind.product) {
      throw Exception(
        'Product rows need product_id, variant_id, sku, barcode, or product_name.',
      );
    }
    return null;
  }

  static Future<_ImportedSaleLine> _buildProductLine(
    Map<String, String> row, {
    double? lineSubtotalHint,
  }) async {
    final match = await _findProductMatch(row);
    if (match == null) {
      final lookup = _describeLookup(row, [
        ..._productIdKeys,
        ..._variantIdKeys,
        ..._skuKeys,
        ..._barcodeKeys,
        ..._productNameKeys,
      ]);
      throw Exception(
        lookup == null
            ? 'Product rows need product_id, variant_id, sku, barcode, or product_name.'
            : 'No product found for "$lookup".',
      );
    }

    if (match.variant == null && _asBool(match.product['has_variants'])) {
      throw Exception(
        'Product "${match.label}" has variants. Use variant_id, variant SKU, barcode, or variant name.',
      );
    }

    final quantity = _readPositiveNumber(row, _quantityKeys) ?? 1.0;
    final unitPrice =
        _readMoney(row, _unitPriceKeys) ??
        (lineSubtotalHint != null ? lineSubtotalHint / quantity : match.price);
    if (unitPrice <= 0) {
      throw Exception(
        'Product rows need unit_price, total, or a product price.',
      );
    }

    final saleToStockFactor =
        _readPositiveNumber(row, ['sale_to_stock_factor', 'stock_factor']) ??
        UnitUtils.saleToStockFactor(match.product);
    final rawUnitCost = _readMoney(row, ['unit_cost', 'cost']);
    final unitCost = rawUnitCost ?? (match.cost * saleToStockFactor);
    final unit = UnitUtils.normalize(
      _readText(row, ['unit', 'sale_unit']) ??
          UnitUtils.saleUnitForProduct(match.product),
    );

    return _ImportedSaleLine(
      kind: _ImportedSaleKind.product,
      label: match.label,
      items: [
        {
          'line_type': 'product',
          'product_id': match.productId,
          'variant_id': match.variantId,
          'product_name': match.label,
          'quantity': quantity,
          'unit_price': _roundMoney(unitPrice),
          'unit_cost': _roundMoney(unitCost),
          'unit': unit,
          'sale_to_stock_factor': saleToStockFactor,
          'stock_unit': UnitUtils.stockUnitForProduct(match.product),
          'track_stock': match.product['track_stock'] ?? 1,
        },
      ],
    );
  }

  static Future<_ImportedSaleLine> _buildServiceLine(
    Map<String, String> row, {
    double? lineSubtotalHint,
  }) async {
    final serviceId = _readText(row, _serviceIdKeys);
    final serviceName =
        _readText(row, _serviceNameKeys) ??
        (_requestedLineKind(row) == _ImportedSaleKind.service
            ? _readText(row, [..._productNameKeys, 'name'])
            : null);
    if (serviceId == null && serviceName == null) {
      throw Exception('Service rows need service_name or service_id.');
    }

    final service = serviceId != null
        ? await _findServiceById(serviceId)
        : await _findServiceByName(serviceName!);
    if (serviceId != null && service == null) {
      throw Exception('No service found for service_id "$serviceId".');
    }

    final label = service?['name'] as String? ?? serviceName ?? 'Service';
    final quantity = _readPositiveNumber(row, _quantityKeys) ?? 1.0;
    final unitPrice =
        _readMoney(row, _unitPriceKeys) ??
        (lineSubtotalHint != null
            ? lineSubtotalHint / quantity
            : (service?['base_price'] as num? ?? 0).toDouble());
    if (unitPrice <= 0) {
      throw Exception(
        'Service rows need unit_price, total, or a service price.',
      );
    }

    return _ImportedSaleLine(
      kind: _ImportedSaleKind.service,
      label: label,
      items: [
        {
          'line_type': 'service',
          'service_order_id': null,
          'service_id': service?['id'],
          'product_name': label,
          'quantity': quantity,
          'unit_price': _roundMoney(unitPrice),
        },
      ],
    );
  }

  static double _lineSubtotal(List<Map<String, dynamic>> items) {
    return items.fold<double>(0, (sum, item) {
      final quantity = (item['quantity'] as num? ?? 0).toDouble();
      final unitPrice = (item['unit_price'] as num? ?? 0).toDouble();
      return sum + quantity * unitPrice;
    });
  }

  static Future<_ProductMatch?> _findProductMatch(
    Map<String, String> row,
  ) async {
    final variantId = _readText(row, _variantIdKeys);
    if (variantId != null) {
      final match = await _findVariantById(variantId);
      if (match != null) return match;
      throw Exception('No product variant found for variant_id "$variantId".');
    }

    final productId = _readText(row, _productIdKeys);
    if (productId != null) {
      final match = await _findProductById(productId);
      if (match != null) return match;
      throw Exception('No product found for product_id "$productId".');
    }

    final barcode = _readText(row, _barcodeKeys);
    if (barcode != null) {
      return await _findVariantByExact('barcode', barcode) ??
          await _findProductByExact('barcode', barcode);
    }

    final sku = _readText(row, _skuKeys);
    if (sku != null) {
      return await _findVariantByExact('sku', sku) ??
          await _findProductByExact('sku', sku) ??
          await _findVariantByLike('sku', sku) ??
          await _findProductByLike('sku', sku);
    }

    final productName = _readText(row, _productNameKeys);
    if (productName != null) {
      return _findProductOrVariantByName(productName);
    }

    return null;
  }

  static Future<_ProductMatch?> _findVariantById(String id) async {
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT
        p.*,
        pv.id AS matched_variant_id,
        pv.name AS matched_variant_name,
        pv.sku AS matched_variant_sku,
        pv.barcode AS matched_variant_barcode,
        pv.price AS matched_variant_price,
        pv.cost AS matched_variant_cost,
        pv.stock AS matched_variant_stock,
        pv.low_stock AS matched_variant_low_stock
      FROM product_variants pv
      JOIN products p ON p.id = pv.product_id
      WHERE pv.id = ?
        AND pv.deleted_at IS NULL
        AND p.deleted_at IS NULL
        AND COALESCE(pv.branch_id, ?) = ?
        AND COALESCE(p.branch_id, ?) = ?
      LIMIT 1
      ''',
      [
        id,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
      ],
    );
    return rows.isEmpty ? null : _productMatchFromVariantRow(rows.first);
  }

  static Future<_ProductMatch?> _findProductById(String id) async {
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM products
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [id, DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
    );
    return rows.isEmpty ? null : _ProductMatch(product: rows.first);
  }

  static Future<_ProductMatch?> _findVariantByExact(
    String column,
    String value,
  ) async {
    final safeColumn = _safeProductCodeColumn(column);
    final query = value.trim().toLowerCase();
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT
        p.*,
        pv.id AS matched_variant_id,
        pv.name AS matched_variant_name,
        pv.sku AS matched_variant_sku,
        pv.barcode AS matched_variant_barcode,
        pv.price AS matched_variant_price,
        pv.cost AS matched_variant_cost,
        pv.stock AS matched_variant_stock,
        pv.low_stock AS matched_variant_low_stock
      FROM product_variants pv
      JOIN products p ON p.id = pv.product_id
      WHERE LOWER(COALESCE(pv.$safeColumn, '')) = ?
        AND pv.deleted_at IS NULL
        AND p.deleted_at IS NULL
        AND COALESCE(pv.branch_id, ?) = ?
        AND COALESCE(p.branch_id, ?) = ?
      LIMIT 1
      ''',
      [
        query,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
      ],
    );
    return rows.isEmpty ? null : _productMatchFromVariantRow(rows.first);
  }

  static Future<_ProductMatch?> _findProductByExact(
    String column,
    String value,
  ) async {
    final safeColumn = _safeProductCodeColumn(column);
    final query = value.trim().toLowerCase();
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM products
      WHERE LOWER(COALESCE($safeColumn, '')) = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [query, DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
    );
    return rows.isEmpty ? null : _ProductMatch(product: rows.first);
  }

  static Future<_ProductMatch?> _findVariantByLike(
    String column,
    String value,
  ) async {
    final safeColumn = _safeProductCodeColumn(column);
    final pattern = '%${value.trim().toLowerCase()}%';
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT
        p.*,
        pv.id AS matched_variant_id,
        pv.name AS matched_variant_name,
        pv.sku AS matched_variant_sku,
        pv.barcode AS matched_variant_barcode,
        pv.price AS matched_variant_price,
        pv.cost AS matched_variant_cost,
        pv.stock AS matched_variant_stock,
        pv.low_stock AS matched_variant_low_stock
      FROM product_variants pv
      JOIN products p ON p.id = pv.product_id
      WHERE LOWER(COALESCE(pv.$safeColumn, '')) LIKE ?
        AND pv.deleted_at IS NULL
        AND p.deleted_at IS NULL
        AND COALESCE(pv.branch_id, ?) = ?
        AND COALESCE(p.branch_id, ?) = ?
      ORDER BY LENGTH(COALESCE(pv.$safeColumn, '')) ASC
      LIMIT 1
      ''',
      [
        pattern,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
      ],
    );
    return rows.isEmpty ? null : _productMatchFromVariantRow(rows.first);
  }

  static Future<_ProductMatch?> _findProductByLike(
    String column,
    String value,
  ) async {
    final safeColumn = _safeProductCodeColumn(column);
    final pattern = '%${value.trim().toLowerCase()}%';
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM products
      WHERE LOWER(COALESCE($safeColumn, '')) LIKE ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY LENGTH(COALESCE($safeColumn, '')) ASC
      LIMIT 1
      ''',
      [
        pattern,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
      ],
    );
    return rows.isEmpty ? null : _ProductMatch(product: rows.first);
  }

  static Future<_ProductMatch?> _findProductOrVariantByName(
    String value,
  ) async {
    final query = value.trim().toLowerCase();
    final pattern = '%$query%';
    final variantRows = await DatabaseService.rawQuery(
      '''
      SELECT
        p.*,
        pv.id AS matched_variant_id,
        pv.name AS matched_variant_name,
        pv.sku AS matched_variant_sku,
        pv.barcode AS matched_variant_barcode,
        pv.price AS matched_variant_price,
        pv.cost AS matched_variant_cost,
        pv.stock AS matched_variant_stock,
        pv.low_stock AS matched_variant_low_stock
      FROM products p
      JOIN product_variants pv
        ON pv.product_id = p.id
       AND pv.deleted_at IS NULL
       AND COALESCE(pv.branch_id, ?) = ?
      WHERE p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND (
          LOWER(p.name || ' ' || pv.name) = ?
          OR LOWER(pv.name) = ?
          OR LOWER(COALESCE(pv.sku, '')) = ?
          OR LOWER(COALESCE(pv.barcode, '')) = ?
          OR LOWER(p.name || ' ' || pv.name) LIKE ?
          OR LOWER(pv.name) LIKE ?
        )
      ORDER BY
        CASE
          WHEN LOWER(p.name || ' ' || pv.name) = ? THEN 0
          WHEN LOWER(pv.name) = ? THEN 1
          ELSE 2
        END,
        LENGTH(p.name || pv.name) ASC
      LIMIT 1
      ''',
      [
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        query,
        query,
        query,
        query,
        pattern,
        pattern,
        query,
        query,
      ],
    );
    if (variantRows.isNotEmpty) {
      return _productMatchFromVariantRow(variantRows.first);
    }

    final productRows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM products
      WHERE deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
        AND (
          LOWER(name) = ?
          OR LOWER(COALESCE(sku, '')) = ?
          OR LOWER(COALESCE(barcode, '')) = ?
          OR LOWER(name) LIKE ?
        )
      ORDER BY
        CASE WHEN LOWER(name) = ? THEN 0 ELSE 1 END,
        LENGTH(name) ASC
      LIMIT 1
      ''',
      [
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        query,
        query,
        query,
        pattern,
        query,
      ],
    );
    return productRows.isEmpty
        ? null
        : _ProductMatch(product: productRows.first);
  }

  static _ProductMatch _productMatchFromVariantRow(Map<String, dynamic> row) {
    return _ProductMatch(
      product: row,
      variant: {
        'id': row['matched_variant_id'],
        'product_id': row['id'],
        'branch_id': row['branch_id'],
        'name': row['matched_variant_name'],
        'sku': row['matched_variant_sku'],
        'barcode': row['matched_variant_barcode'],
        'price': row['matched_variant_price'],
        'cost': row['matched_variant_cost'],
        'stock': row['matched_variant_stock'],
        'low_stock': row['matched_variant_low_stock'],
      },
    );
  }

  static Future<Map<String, dynamic>?> _findServiceById(String id) async {
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM services
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [id, DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>?> _findServiceByName(String name) async {
    final query = name.trim().toLowerCase();
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM services
      WHERE deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
        AND (LOWER(name) = ? OR LOWER(name) LIKE ? OR LOWER(category) LIKE ?)
      ORDER BY
        CASE WHEN LOWER(name) = ? THEN 0 ELSE 1 END,
        is_active DESC,
        LENGTH(name) ASC
      LIMIT 1
      ''',
      [
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        query,
        '%$query%',
        '%$query%',
        query,
      ],
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<String> _findOrCreateCustomer(
    String name, {
    String? phone,
  }) async {
    final matches = await CustomerRepository.search(name);
    final normalizedName = name.trim().toLowerCase();
    for (final customer in matches) {
      final existingName = (customer['name'] as String? ?? '')
          .trim()
          .toLowerCase();
      if (existingName == normalizedName) {
        return customer['id'] as String;
      }
    }
    return CustomerRepository.create(name: name, phone: phone);
  }

  static List<List<String>> _readExcelRows(Uint8List bytes) {
    final book = xl.Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) {
      return const [];
    }
    final sheet = book.tables.values.firstWhere(
      (table) =>
          table.rows.any((row) => row.any((cell) => cell?.value != null)),
      orElse: () => book.tables.values.first,
    );
    return sheet.rows
        .map(
          (row) =>
              row.map((cell) => cell?.value?.toString().trim() ?? '').toList(),
        )
        .toList();
  }

  static List<List<String>> _readCsvRows(Uint8List bytes) {
    var content = utf8.decode(bytes, allowMalformed: true);
    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }
    final separator = _detectCsvSeparator(content);
    final rows = <List<String>>[];
    var row = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var index = 0; index < content.length; index += 1) {
      final char = content[index];
      final next = index + 1 < content.length ? content[index + 1] : '';

      if (char == '"') {
        if (inQuotes && next == '"') {
          buffer.write('"');
          index += 1;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (char == separator && !inQuotes) {
        row.add(buffer.toString().trim());
        buffer.clear();
        continue;
      }

      if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && next == '\n') {
          index += 1;
        }
        row.add(buffer.toString().trim());
        buffer.clear();
        rows.add(row);
        row = <String>[];
        continue;
      }

      buffer.write(char);
    }

    if (buffer.isNotEmpty || row.isNotEmpty) {
      row.add(buffer.toString().trim());
      rows.add(row);
    }
    return rows;
  }

  static String _detectCsvSeparator(String content) {
    final firstLine = content
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return ',';
    final commas = _countUnquoted(firstLine, ',');
    final semicolons = _countUnquoted(firstLine, ';');
    return semicolons > commas ? ';' : ',';
  }

  static int _countUnquoted(String line, String separator) {
    var count = 0;
    var inQuotes = false;
    for (var i = 0; i < line.length; i += 1) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          i += 1;
          continue;
        }
        inQuotes = !inQuotes;
      } else if (char == separator && !inQuotes) {
        count += 1;
      }
    }
    return count;
  }

  static Map<String, String> _rowMap(List<String> headers, List<String> row) {
    final values = <String, String>{};
    for (var index = 0; index < headers.length; index += 1) {
      final header = headers[index];
      if (header.isEmpty) continue;
      values[header] = index < row.length ? row[index].trim() : '';
    }
    return values;
  }

  static _ImportedSaleKind? _requestedLineKind(Map<String, String> row) {
    final value = _readText(row, ['line_type', 'type', 'item_type']);
    if (value == null) {
      return null;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('service')) {
      return _ImportedSaleKind.service;
    }
    if (normalized.contains('product') ||
        normalized.contains('inventory') ||
        normalized.contains('stock')) {
      return _ImportedSaleKind.product;
    }
    return null;
  }

  static bool _hasProductLookup(Map<String, String> row) {
    return _readText(row, [
          ..._productIdKeys,
          ..._variantIdKeys,
          ..._skuKeys,
          ..._barcodeKeys,
          ..._productNameKeys,
        ]) !=
        null;
  }

  static bool _hasServiceLookup(Map<String, String> row) {
    return _readText(row, [..._serviceIdKeys, ..._serviceNameKeys]) != null;
  }

  static String? _readText(Map<String, String> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static double? _readMoney(Map<String, String> row, List<String> keys) {
    final raw = _readText(row, keys);
    if (raw == null) return null;
    final normalized = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (normalized.isEmpty || normalized == '-' || normalized == '.') {
      return null;
    }
    return double.tryParse(normalized);
  }

  static double? _readPositiveNumber(
    Map<String, String> row,
    List<String> keys,
  ) {
    final value = _readMoney(row, keys);
    if (value == null) {
      return null;
    }
    if (value <= 0) {
      throw Exception('${keys.first} must be greater than zero.');
    }
    return value;
  }

  static DateTime? _readDate(Map<String, String> row, List<String> keys) {
    final raw = _readText(row, keys);
    if (raw == null) return null;
    return _parseDate(raw);
  }

  static DateTime? _parseDate(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final iso = DateTime.tryParse(trimmed);
    if (iso != null) return iso;

    final parts = trimmed.split(RegExp(r'[\/\-.]'));
    if (parts.length >= 3) {
      final first = int.tryParse(parts[0]);
      final second = int.tryParse(parts[1]);
      final third = int.tryParse(parts[2].split(RegExp(r'\s+')).first);
      if (first != null && second != null && third != null) {
        if (parts[0].length == 4) {
          return _safeDate(first, second, third);
        }
        if (first > 12) {
          return _safeDate(third, second, first);
        }
        if (second > 12) {
          return _safeDate(third, first, second);
        }
        // Ambiguous: prefer DD/MM/YYYY for the app's primary East-African market.
        return _safeDate(third, second, first);
      }
    }

    final excelSerial = double.tryParse(trimmed);
    if (excelSerial != null && excelSerial > 59) {
      return DateTime(1899, 12, 30).add(Duration(days: excelSerial.floor()));
    }
    return null;
  }

  static DateTime? _safeDate(int year, int month, int day) {
    if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    return DateTime(year, month, day);
  }

  static String? _describeLookup(Map<String, String> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static String _safeProductCodeColumn(String column) {
    return switch (column) {
      'sku' => 'sku',
      'barcode' => 'barcode',
      _ => throw ArgumentError('Unsupported product lookup column: $column'),
    };
  }

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized != '0' &&
          normalized != 'false' &&
          normalized != 'no' &&
          normalized != 'off';
    }
    return false;
  }

  static double _roundMoney(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  static String _normalizePaymentType(String value) {
    final normalized = value.trim();
    final key = normalized.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (key == 'credit' || key == 'kopesha' || key == 'debt') {
      return 'Kopesha';
    }
    if (key == 'mpesa' || key == 'm pesa' || key == 'mobilemoney') {
      return 'M-Pesa';
    }
    if (key == 'cash') {
      return 'Cash';
    }
    return normalized.isEmpty ? 'Cash' : normalized;
  }

  static bool _isCashDrawerPayment(String paymentType) {
    return paymentType.trim().toLowerCase() == 'cash';
  }

  static String _extensionFor(String name, String? path) {
    final source = path?.trim().isNotEmpty == true ? path! : name;
    final index = source.lastIndexOf('.');
    if (index < 0 || index == source.length - 1) {
      return '';
    }
    return source.substring(index + 1).toLowerCase();
  }

  static Future<Uint8List?> _readFileBytes(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return null;
    }
    return File(path).readAsBytes();
  }
}
