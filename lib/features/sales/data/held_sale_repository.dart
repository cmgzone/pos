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
  }) async {
    final holdId = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    await DatabaseService.db.transaction((txn) async {
      await txn.insert(_heldSalesTable, {
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
        'created_at': now,
        'updated_at': now,
      });

      for (final item in items) {
        await txn.insert(_heldSaleItemsTable, {
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
          'unit': item['unit'] as String? ?? UnitUtils.defaultUnit,
          'stock_unit':
              item['stock_unit'] as String? ??
              item['unit'] as String? ??
              UnitUtils.defaultUnit,
          'created_at': now,
          'updated_at': now,
        });
      }
    });

    await AuditLogService.log(
      action: 'hold',
      entityTable: _heldSalesTable,
      entityId: holdId,
    );
    return holdId;
  }

  static Future<List<Map<String, dynamic>>> getAll() async {
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
        created_at,
        updated_at
      FROM $_heldSalesTable
      WHERE COALESCE(branch_id, ?) = ?
      ORDER BY updated_at DESC, created_at DESC
    ''', _currentBranchArgs);

    return rows.map(_normalizeHoldSummary).toList();
  }

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

          await txn.delete(
            _heldSaleItemsTable,
            where: 'held_sale_id = ?',
            whereArgs: [holdId],
          );
          await txn.delete(
            _heldSalesTable,
            where: 'id = ?',
            whereArgs: [holdId],
          );

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

    for (final item in items) {
      final lineType = item['line_type'] as String? ?? 'product';
      if (lineType == 'service') {
        refreshedItems.add(item);
        continue;
      }

      final productId = item['product_id'] as String? ?? '';
      final product = productId.isEmpty
          ? null
          : (await DatabaseService.rawQuery(
              '''
              SELECT *
              FROM products
              WHERE id = ?
                AND deleted_at IS NULL
                AND COALESCE(branch_id, ?) = ?
              LIMIT 1
              ''',
              [productId, ..._currentBranchArgs],
            )).firstOrNull;
      final variantId = item['variant_id'] as String?;
      final variantName = item['variant_name'] as String?;
      final baseName =
          (product?['name'] as String?) ??
          (item['product_name'] as String?) ??
          'Product';
      final itemName = _variantLabel(baseName, variantName);

      if (product == null) {
        adjustments.add('$itemName is no longer available and was removed.');
        continue;
      }

      final factor = _positiveDouble(item['sale_to_stock_factor'], fallback: 1);
      final variant = (variantId == null || variantId.trim().isEmpty)
          ? null
          : (await DatabaseService.rawQuery(
              '''
              SELECT *
              FROM product_variants
              WHERE id = ?
                AND deleted_at IS NULL
                AND COALESCE(branch_id, ?) = ?
              LIMIT 1
              ''',
              [variantId, ..._currentBranchArgs],
            )).firstOrNull;
      if (variantId != null && variantId.trim().isNotEmpty && variant == null) {
        adjustments.add('$itemName is no longer available and was removed.');
        continue;
      }

      final stockSource = variant ?? product;
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

  static String _variantLabel(String productName, String? variantName) {
    final cleanVariant = variantName?.trim() ?? '';
    if (cleanVariant.isEmpty) {
      return productName;
    }
    return '$productName - $cleanVariant';
  }
}

class _RefreshedHeldItems {
  final List<Map<String, dynamic>> items;
  final List<String> adjustments;

  const _RefreshedHeldItems({required this.items, required this.adjustments});
}
