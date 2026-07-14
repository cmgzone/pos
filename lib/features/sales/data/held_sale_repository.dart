import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

class HeldSaleRepository {
  static const _heldSalesTable = 'held_sales';
  static const _heldSaleItemsTable = 'held_sale_items';

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<String> createHold({
    required String name,
    required double subtotal,
    required double tax,
    required double discount,
    required double total,
    required String userId,
    required String cashierName,
    required List<Map<String, dynamic>> items,
    String source = 'pos',
    String? sourceRef,
    String? id,
    Transaction? txn,
  }) async {
    final holdId = id ?? _uuid.v4();
    final now = DateTime.now().toIso8601String();

    Future<void> exec(Transaction t) async {
      await t.insert(_heldSalesTable, {
        'id': holdId,
        'branch_id': DatabaseService.currentBranchId,
        'name': name,
        'subtotal': subtotal,
        'tax': tax,
        'discount': discount,
        'total': total,
        'item_count': items.length,
        'user_id': userId,
        'cashier_name': cashierName,
        'source': source,
        'source_ref': sourceRef,
        'created_at': now,
        'updated_at': now,
      });

      for (final item in items) {
        await t.insert(_heldSaleItemsTable, {
          'id': _uuid.v4(),
          'held_sale_id': holdId,
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'quantity': _asDouble(item['quantity']),
          'unit_price': _asDouble(item['unit_price']),
          'cost': _asDouble(item['cost']),
          'max_stock': _asDouble(item['max_stock']),
          'stock_on_hand': _asDouble(item['stock_on_hand']),
          'sale_to_stock_factor': _positiveDouble(
            item['sale_to_stock_factor'],
            fallback: 1,
          ),
          'line_type': item['line_type'] as String? ?? 'product',
          'service_order_id': item['service_order_id'],
          'service_id': item['service_id'],
          'variant_id': item['variant_id'],
          'variant_name': item['variant_name'],
          'variant_color_id': item['variant_color_id'],
          'variant_color_name': item['variant_color_name'],
          'serial_numbers_json': item['serial_numbers_json'],
          'unit': item['unit'] as String? ?? UnitUtils.defaultUnit,
          'stock_unit':
              item['stock_unit'] as String? ??
              item['unit'] as String? ??
              UnitUtils.defaultUnit,
          'created_at': now,
          'updated_at': now,
        });
      }
    }

    if (txn != null) {
      await exec(txn);
    } else {
      await DatabaseService.db.transaction(exec);
    }

    await AuditLogService.log(
      action: 'hold',
      entityTable: _heldSalesTable,
      entityId: holdId,
      executor: txn,
    );
    return holdId;
  }

  /// Ids of restaurant bills already prepared for a given table order.
  /// Used to make bill preparation idempotent so repeated taps never duplicate bills.
  static Future<List<String>> existingRestaurantHoldIds(
    String sourceRef,
  ) async {
    if (sourceRef.isEmpty) return const [];
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT id FROM $_heldSalesTable
      WHERE source = ? AND source_ref = ?
      ORDER BY created_at ASC, id ASC
      ''',
      ['restaurant', sourceRef],
    );
    return rows
        .map((row) => (row['id'] as String? ?? '').trim())
        .where((id) => id.isNotEmpty)
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getAll({String? source}) async {
    final args = <dynamic>[..._currentBranchArgs];
    final sourceClause = source == null
        ? " AND (source = 'pos' OR source IS NULL)"
        : ' AND source = ?';
    if (source != null) {
      args.add(source);
    }
    final rows = await DatabaseService.rawQuery('''
      SELECT
        id,
        name,
        subtotal,
        tax,
        discount,
        total,
        item_count,
        user_id,
        cashier_name,
        source,
        source_ref,
        created_at,
        updated_at
      FROM $_heldSalesTable
      WHERE COALESCE(branch_id, ?) = ?
        $sourceClause
      ORDER BY updated_at DESC, created_at DESC
    ''', args);

    return rows.map(_normalizeHoldSummary).toList();
  }

  /// Bills created by the restaurant module and waiting for payment.
  static Future<List<Map<String, dynamic>>> getRestaurantBills() =>
      getAll(source: 'restaurant');

  static Future<Map<String, dynamic>?> takeHold(String holdId) async {
    final heldSale = await DatabaseService.db
        .transaction<Map<String, dynamic>?>((txn) async {
          final holdRows = await txn.query(
            _heldSalesTable,
            where: 'id = ? AND COALESCE(branch_id, ?) = ?',
            whereArgs: [holdId, ..._currentBranchArgs],
            limit: 1,
          );
          if (holdRows.isEmpty) {
            return null;
          }

          final itemRows = await txn.query(
            _heldSaleItemsTable,
            where: 'held_sale_id = ?',
            whereArgs: [holdId],
            orderBy: 'created_at ASC, id ASC',
          );

          // Read only. The hold is consumed (deleted) by the caller only after
          // the items have been restored to the cart, so a refresh or UI
          // failure can never destroy the bill.
          return {
            ...Map<String, dynamic>.from(holdRows.first),
            'items': itemRows
                .map((row) => Map<String, dynamic>.from(row))
                .toList(),
          };
        });

    if (heldSale == null) {
      return null;
    }

    await AuditLogService.log(
      action: 'take',
      entityTable: _heldSalesTable,
      entityId: holdId,
      branchId: heldSale['branch_id'] as String?,
    );

    final refreshed = await _refreshHeldItems(
      List<Map<String, dynamic>>.from(heldSale['items'] as List<dynamic>),
    );

    return {
      ..._normalizeHoldSummary(heldSale),
      'items': refreshed.items,
      'adjustments': refreshed.adjustments,
    };
  }

  static Future<void> deleteHold(String holdId) async {
    await DatabaseService.db.transaction((txn) async {
      final holdRows = await txn.query(
        _heldSalesTable,
        columns: const ['id'],
        where: 'id = ? AND COALESCE(branch_id, ?) = ?',
        whereArgs: [holdId, ..._currentBranchArgs],
        limit: 1,
      );
      if (holdRows.isEmpty) {
        return;
      }
      await txn.delete(
        _heldSaleItemsTable,
        where: 'held_sale_id = ?',
        whereArgs: [holdId],
      );
      await txn.delete(_heldSalesTable, where: 'id = ?', whereArgs: [holdId]);
    });
    await AuditLogService.log(
      action: 'delete',
      entityTable: _heldSalesTable,
      entityId: holdId,
    );
  }

  static Future<_RefreshedHeldItems> _refreshHeldItems(
    List<Map<String, dynamic>> items,
  ) async {
    final refreshedItems = <Map<String, dynamic>>[];
    final adjustments = <String>[];

    final productIds = items
        .where(
          (item) => (item['line_type'] as String? ?? 'product') != 'service',
        )
        .map((item) => item['product_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final variantIds = items
        .where(
          (item) => (item['line_type'] as String? ?? 'product') != 'service',
        )
        .map((item) => item['variant_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final variantColorIds = items
        .where(
          (item) => (item['line_type'] as String? ?? 'product') != 'service',
        )
        .map((item) => item['variant_color_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final List<Map<String, dynamic>> productsList;
    if (productIds.isNotEmpty) {
      final placeholders = List.filled(productIds.length, '?').join(',');
      productsList = await DatabaseService.rawQuery(
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
      productsList = [];
    }
    final productsMap = {for (final p in productsList) p['id'] as String: p};

    final List<Map<String, dynamic>> variantsList;
    if (variantIds.isNotEmpty) {
      final placeholders = List.filled(variantIds.length, '?').join(',');
      variantsList = await DatabaseService.rawQuery(
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
      variantsList = [];
    }
    final variantsMap = {for (final v in variantsList) v['id'] as String: v};

    final List<Map<String, dynamic>> colorsList;
    if (variantColorIds.isNotEmpty) {
      final placeholders = List.filled(variantColorIds.length, '?').join(',');
      colorsList = await DatabaseService.rawQuery(
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
      colorsList = [];
    }
    final colorsMap = {
      for (final color in colorsList) color['id'] as String: color,
    };

    for (final item in items) {
      final lineType = item['line_type'] as String? ?? 'product';
      if (lineType == 'service') {
        refreshedItems.add(item);
        continue;
      }

      final productId = item['product_id'] as String? ?? '';
      final product = productId.isEmpty ? null : productsMap[productId];
      final variantId = item['variant_id'] as String?;
      final variantName = item['variant_name'] as String?;
      final variantColorId = item['variant_color_id'] as String?;
      final variantColorName = item['variant_color_name'] as String?;
      final baseName =
          (product?['name'] as String?) ??
          (item['product_name'] as String?) ??
          'Product';
      final itemName = _variantLabel(
        baseName,
        variantName,
        colorName: variantColorName,
      );

      if (product == null) {
        adjustments.add('$itemName is no longer available and was removed.');
        continue;
      }

      final factor = _positiveDouble(item['sale_to_stock_factor'], fallback: 1);
      final variant = (variantId == null || variantId.trim().isEmpty)
          ? null
          : variantsMap[variantId];
      if (variantId != null && variantId.trim().isNotEmpty && variant == null) {
        adjustments.add('$itemName is no longer available and was removed.');
        continue;
      }

      final color = (variantColorId == null || variantColorId.trim().isEmpty)
          ? null
          : colorsMap[variantColorId];
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

      // Services and restaurant dishes commonly do not track inventory.
      // They must survive hold/bill restoration even when their stock is zero.
      if (!UnitUtils.tracksStock(product)) {
        refreshedItems.add({
          ...item,
          'product_name': baseName,
          'variant_name': (variant?['name'] as String?) ?? variantName,
          'variant_color_id': color?['id'] as String? ?? variantColorId,
          'variant_color_name': (color?['name'] as String?) ?? variantColorName,
          'cost': _asDouble((variant ?? product)['cost']) * factor,
          'max_stock': 999999.0,
          'stock_on_hand': 999999.0,
        });
        continue;
      }

      final stockSource = color ?? variant ?? product;
      final currentStockOnHand = _asDouble(stockSource['stock']);
      final maxStock = factor <= 0
          ? currentStockOnHand
          : _roundQuantity(currentStockOnHand / factor);

      if (maxStock <= 0.001) {
        adjustments.add('$itemName is out of stock and was removed.');
        continue;
      }

      final requestedQuantity = _asDouble(item['quantity']);
      final restoredQuantity = requestedQuantity > maxStock
          ? maxStock
          : requestedQuantity;

      if (requestedQuantity - restoredQuantity > 0.001) {
        final unit = item['unit'] as String? ?? UnitUtils.defaultUnit;
        adjustments.add(
          '$itemName was reduced to ${UnitUtils.formatWithUnit(restoredQuantity, unit)}.',
        );
      }

      refreshedItems.add({
        ...item,
        'product_name': baseName,
        'variant_name': (variant?['name'] as String?) ?? variantName,
        'variant_color_id': color?['id'] as String? ?? variantColorId,
        'variant_color_name': (color?['name'] as String?) ?? variantColorName,
        'quantity': restoredQuantity,
        'cost': _asDouble((variant ?? product)['cost']) * factor,
        'max_stock': maxStock,
        'stock_on_hand': currentStockOnHand,
      });
    }

    return _RefreshedHeldItems(items: refreshedItems, adjustments: adjustments);
  }

  static Map<String, dynamic> _normalizeHoldSummary(Map<String, dynamic> row) {
    return {
      'id': row['id'] as String? ?? '',
      'name': row['name'] as String? ?? 'Held Sale',
      'subtotal': _asDouble(row['subtotal']),
      'tax': _asDouble(row['tax']),
      'discount': _asDouble(row['discount']),
      'total': _asDouble(row['total']),
      'item_count': _asInt(row['item_count']),
      'user_id': row['user_id'] as String?,
      'cashier_name': row['cashier_name'] as String?,
      'source': row['source'] as String? ?? 'pos',
      'source_ref': row['source_ref'] as String?,
      'created_at': row['created_at'] as String? ?? '',
      'updated_at': row['updated_at'] as String? ?? '',
    };
  }

  static double _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static double _positiveDouble(Object? value, {required double fallback}) {
    final parsed = _asDouble(value);
    return parsed > 0 ? parsed : fallback;
  }

  static int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _roundQuantity(double value) {
    return double.parse(value.toStringAsFixed(3));
  }

  static String _variantLabel(
    String productName,
    String? variantName, {
    String? colorName,
  }) {
    final cleanVariant = variantName?.trim() ?? '';
    final cleanColor = colorName?.trim() ?? '';
    return [
      productName,
      if (cleanVariant.isNotEmpty) cleanVariant,
      if (cleanColor.isNotEmpty) cleanColor,
    ].join(' - ');
  }
}

class _RefreshedHeldItems {
  final List<Map<String, dynamic>> items;
  final List<String> adjustments;

  const _RefreshedHeldItems({required this.items, required this.adjustments});
}
