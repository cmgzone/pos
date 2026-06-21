import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

enum QuotationStatus {
  draft,
  sent,
  accepted,
  converted,
  expired,
  cancelled;

  static QuotationStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'sent':
        return QuotationStatus.sent;
      case 'accepted':
        return QuotationStatus.accepted;
      case 'converted':
        return QuotationStatus.converted;
      case 'expired':
        return QuotationStatus.expired;
      case 'cancelled':
        return QuotationStatus.cancelled;
      default:
        return QuotationStatus.draft;
    }
  }

  String get label => name;
}

class QuotationRepository {
  static const _quotationsTable = 'quotations';
  static const _itemsTable = 'quotation_items';
  static const _sequencesTable = 'quotation_sequences';

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static double _asDouble(Object? value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _roundMoney(double value) =>
      double.parse(value.toStringAsFixed(2));

  static double _roundQuantity(double value) =>
      double.parse(value.toStringAsFixed(3));

  /// Allocates a branch-aware quotation number using a per-branch sequence
  /// row. Must be called inside a transaction. The unique index on
  /// (branch_id, quotation_no) guarantees correctness even if the sequence
  /// ever drifts.
  static Future<String> _nextQuotationNo(dynamic txn) async {
    await txn.rawInsert(
      'INSERT OR IGNORE INTO $_sequencesTable (branch_id, next_number) VALUES (?, 1)',
      [DatabaseService.currentBranchId],
    );
    await txn.rawUpdate(
      'UPDATE $_sequencesTable SET next_number = next_number + 1 WHERE branch_id = ?',
      [DatabaseService.currentBranchId],
    );
    final rows = await txn.rawQuery(
      'SELECT next_number FROM $_sequencesTable WHERE branch_id = ?',
      [DatabaseService.currentBranchId],
    );
    final next = (rows.first['next_number'] as num? ?? 1).toInt();
    return 'QUO-${next.toString().padLeft(6, '0')}';
  }

  /// Create a quotation. Does NOT deduct stock and does NOT record revenue.
  static Future<String> createQuotation({
    required String customerId,
    required String customerName,
    required double subtotal,
    required double discountTotal,
    required double taxTotal,
    required double total,
    required String userId,
    required List<Map<String, dynamic>> items,
    String? expiryDate,
    String? notes,
    String status = 'draft',
  }) async {
    final quotationId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final cleanStatus = status.trim().isEmpty ? 'draft' : status.trim();

    await DatabaseService.db.transaction((txn) async {
      final quotationNo = await _nextQuotationNo(txn);
      await txn.insert(_quotationsTable, {
        'id': quotationId,
        'branch_id': DatabaseService.currentBranchId,
        'quotation_no': quotationNo,
        'customer_id': customerId.isEmpty ? null : customerId,
        'customer_name': customerName.isEmpty ? null : customerName,
        'subtotal': _roundMoney(subtotal),
        'discount_total': _roundMoney(discountTotal),
        'tax_total': _roundMoney(taxTotal),
        'total': _roundMoney(total),
        'expiry_date': expiryDate,
        'notes': notes,
        'status': cleanStatus,
        'created_by': userId,
        'converted_sale_id': null,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      for (final item in items) {
        final qty = _asDouble(item['quantity'], fallback: 0);
        final unitPrice = _asDouble(item['unit_price'], fallback: 0);
        final lineTotal = _roundMoney(qty * unitPrice);
        await txn.insert(_itemsTable, {
          'id': _uuid.v4(),
          'branch_id': DatabaseService.currentBranchId,
          'quotation_id': quotationId,
          'product_id': item['product_id'] as String?,
          'variant_id': item['variant_id'] as String?,
          'variant_color_id': item['variant_color_id'] as String?,
          'variant_color_name': item['variant_color_name'] as String?,
          'product_name': item['product_name'] as String? ?? 'Product',
          'quantity': qty,
          'unit': item['unit'] as String? ?? 'pcs',
          'unit_price': unitPrice,
          'discount': _asDouble(item['discount']),
          'tax': _asDouble(item['tax']),
          'line_total': lineTotal,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });
      }
    });

    DatabaseService.notifyLocalChange();
    await AuditLogService.log(
      action: 'create',
      entityTable: _quotationsTable,
      entityId: quotationId,
    );
    return quotationId;
  }

  static Future<List<Map<String, dynamic>>> getAll({
    String? status,
    String? customerId,
  }) async {
    final clauses = <String>[
      'COALESCE(q.branch_id, ?) = ?',
      'q.deleted_at IS NULL',
    ];
    final args = <dynamic>[..._currentBranchArgs];
    if (status != null && status.isNotEmpty) {
      clauses.add('q.status = ?');
      args.add(status);
    }
    if (customerId != null && customerId.isNotEmpty) {
      clauses.add('q.customer_id = ?');
      args.add(customerId);
    }
    return DatabaseService.rawQuery('''
      SELECT
        q.id,
        q.quotation_no,
        q.customer_id,
        q.customer_name,
        q.subtotal,
        q.discount_total,
        q.tax_total,
        q.total,
        q.expiry_date,
        q.notes,
        q.status,
        q.created_by,
        q.converted_sale_id,
        q.created_at,
        q.updated_at,
        (SELECT COUNT(*) FROM $_itemsTable qi
           WHERE qi.quotation_id = q.id AND qi.deleted_at IS NULL) AS item_count
      FROM $_quotationsTable q
      WHERE ${clauses.join(' AND ')}
      ORDER BY q.created_at DESC
    ''', args);
  }

  static Future<Map<String, dynamic>?> getWithItems(String quotationId) async {
    final headers = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM $_quotationsTable
      WHERE id = ? AND COALESCE(branch_id, ?) = ? AND deleted_at IS NULL
      ''',
      [quotationId, ..._currentBranchArgs],
    );
    if (headers.isEmpty) return null;
    final header = Map<String, dynamic>.from(headers.first);
    final items = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM $_itemsTable
      WHERE quotation_id = ? AND deleted_at IS NULL
      ORDER BY created_at ASC, id ASC
      ''',
      [quotationId],
    );
    return {...header, 'items': items};
  }

  static Future<void> updateStatus(String quotationId, String status) async {
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.transaction((txn) async {
      await txn.update(
        _quotationsTable,
        {'status': status, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [quotationId],
      );
    });
    DatabaseService.notifyLocalChange();
    await AuditLogService.log(
      action: 'status:$status',
      entityTable: _quotationsTable,
      entityId: quotationId,
    );
  }

  /// Mark a quotation as converted and link it to the completed sale. Only
  /// call this after the sale has been paid and stock deducted.
  static Future<void> markConverted(
    String quotationId, {
    required String saleId,
  }) async {
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.transaction((txn) async {
      await txn.update(
        _quotationsTable,
        {
          'status': 'converted',
          'converted_sale_id': saleId,
          'updated_at': now,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [quotationId],
      );
    });
    DatabaseService.notifyLocalChange();
    await AuditLogService.log(
      action: 'convert',
      entityTable: _quotationsTable,
      entityId: quotationId,
    );
  }

  static Future<void> delete(String quotationId) async {
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.transaction((txn) async {
      await txn.update(
        _quotationsTable,
        {
          'deleted_at': now,
          'status': 'cancelled',
          'updated_at': now,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [quotationId],
      );
      await txn.update(
        _itemsTable,
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'quotation_id = ? AND deleted_at IS NULL',
        whereArgs: [quotationId],
      );
    });
    DatabaseService.notifyLocalChange();
    await AuditLogService.log(
      action: 'delete',
      entityTable: _quotationsTable,
      entityId: quotationId,
    );
  }

  /// Loads a quotation and re-validates its line items against current stock.
  /// Returns the refreshed items plus a list of human-readable adjustment
  /// messages (out of stock, quantity reduced, product removed). Use this
  /// before converting a quotation to a sale so the cashier is warned and the
  /// cart is not over-allocated.
  static Future<QuotationLoadResult> loadForConvert(String quotationId) async {
    final quotation = await getWithItems(quotationId);
    if (quotation == null) {
      return const QuotationLoadResult(items: [], adjustments: []);
    }
    final rawItems = List<Map<String, dynamic>>.from(
      quotation['items'] as List<dynamic>? ?? const <dynamic>[],
    );

    final productIds = rawItems
        .map((item) => item['product_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final variantIds = rawItems
        .map((item) => item['variant_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final variantColorIds = rawItems
        .map((item) => item['variant_color_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final List<Map<String, dynamic>> products;
    if (productIds.isNotEmpty) {
      final placeholders = List.filled(productIds.length, '?').join(',');
      products = await DatabaseService.rawQuery(
        '''
        SELECT *
        FROM products
        WHERE id IN ($placeholders)
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        ''',
        [...productIds, ..._currentBranchArgs],
      );
    } else {
      products = [];
    }
    final productsMap = {for (final p in products) p['id'] as String: p};

    final List<Map<String, dynamic>> variants;
    if (variantIds.isNotEmpty) {
      final placeholders = List.filled(variantIds.length, '?').join(',');
      variants = await DatabaseService.rawQuery(
        '''
        SELECT *
        FROM product_variants
        WHERE id IN ($placeholders)
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        ''',
        [...variantIds, ..._currentBranchArgs],
      );
    } else {
      variants = [];
    }
    final variantsMap = {for (final v in variants) v['id'] as String: v};

    final List<Map<String, dynamic>> variantColors;
    if (variantColorIds.isNotEmpty) {
      final placeholders = List.filled(variantColorIds.length, '?').join(',');
      variantColors = await DatabaseService.rawQuery(
        '''
        SELECT *
        FROM product_variant_colors
        WHERE id IN ($placeholders)
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        ''',
        [...variantColorIds, ..._currentBranchArgs],
      );
    } else {
      variantColors = [];
    }
    final variantColorsMap = {
      for (final color in variantColors) color['id'] as String: color,
    };

    final refreshed = <Map<String, dynamic>>[];
    final adjustments = <String>[];

    for (final item in rawItems) {
      final productId = item['product_id'] as String? ?? '';
      final variantId = item['variant_id'] as String?;
      final variantName = item['variant_name'] as String?;
      final variantColorId = item['variant_color_id'] as String?;
      final variantColorName = item['variant_color_name'] as String?;
      final product = productId.isEmpty ? null : productsMap[productId];
      final variant = (variantId == null || variantId.trim().isEmpty)
          ? null
          : variantsMap[variantId];
      final color = (variantColorId == null || variantColorId.trim().isEmpty)
          ? null
          : variantColorsMap[variantColorId];
      final baseName = (product?['name'] as String?) ?? 'Product';
      final itemName = _variantLabel(
        baseName,
        variantName,
        colorName: variantColorName,
      );

      if (product == null) {
        adjustments.add('$itemName is no longer available and was removed.');
        continue;
      }
      if (variantId != null && variantId.trim().isNotEmpty && variant == null) {
        adjustments.add('$itemName is no longer available and was removed.');
        continue;
      }
      if (variantColorId != null &&
          variantColorId.trim().isNotEmpty &&
          color == null) {
        adjustments.add('$itemName is no longer available and was removed.');
        continue;
      }
      if (color != null &&
          (color['variant_id'] != variantId ||
              color['product_id'] != productId)) {
        adjustments.add('$itemName is no longer available and was removed.');
        continue;
      }

      final tracksStock = UnitUtils.tracksStock(product);
      final factor = UnitUtils.saleToStockFactor(product);
      final stockSource = color ?? variant ?? product;
      final currentStock = _asDouble(stockSource['stock']);
      final maxSaleQty = !tracksStock
          ? 999999.0
          : (factor <= 0
                ? currentStock
                : _roundQuantity(currentStock / factor));

      if (tracksStock && maxSaleQty <= 0.001) {
        adjustments.add('$itemName is out of stock and was removed.');
        continue;
      }

      final requested = _asDouble(item['quantity']);
      final restored = (!tracksStock || requested <= maxSaleQty)
          ? requested
          : maxSaleQty;
      if (requested - restored > 0.001) {
        final unit = item['unit'] as String? ?? UnitUtils.defaultUnit;
        adjustments.add(
          '$itemName was reduced to ${UnitUtils.formatWithUnit(restored, unit)}.',
        );
      }

      refreshed.add({
        ...item,
        'product_name': baseName,
        'variant_name': (variant?['name'] as String?) ?? variantName,
        'variant_color_id': color?['id'] as String? ?? variantColorId,
        'variant_color_name': (color?['name'] as String?) ?? variantColorName,
        'quantity': restored,
        'max_stock': maxSaleQty,
        'stock_on_hand': currentStock,
        'sale_to_stock_factor': factor,
        'stock_unit': UnitUtils.stockUnitForProduct(product),
        'unit':
            item['unit'] as String? ?? UnitUtils.saleUnitForProduct(product),
        'track_stock': tracksStock ? 1 : 0,
        'cost': _asDouble((variant ?? product)['cost']) * factor,
      });
    }

    return QuotationLoadResult(items: refreshed, adjustments: adjustments);
  }

  static String _variantLabel(
    String productName,
    String? variantName, {
    String? colorName,
  }) {
    final parts = <String>[productName];
    final cleanVariant = variantName?.trim() ?? '';
    if (cleanVariant.isNotEmpty) {
      parts.add(cleanVariant);
    }
    final cleanColor = colorName?.trim() ?? '';
    if (cleanColor.isNotEmpty) {
      parts.add(cleanColor);
    }
    return parts.join(' - ');
  }
}

class QuotationLoadResult {
  final List<Map<String, dynamic>> items;
  final List<String> adjustments;

  const QuotationLoadResult({required this.items, required this.adjustments});
}
