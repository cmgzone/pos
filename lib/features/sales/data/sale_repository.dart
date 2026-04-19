import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

class SaleRepository {
  static const _salesTable = 'sales';
  static const _itemsTable = 'sale_items';

  static double _money(num? value) => (value ?? 0).toDouble();

  static double _roundMoney(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  /// Create a complete sale with items (transactional)
  static Future<String> createSale({
    required double totalAmount,
    required double tax,
    required double discount,
    required String paymentType,
    required String userId,
    required List<Map<String, dynamic>> items,
    double? amountTendered,
    double? changeGiven,
    String? customerId,
    String? customerName,
    String? dueDate,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'complete sales');
    if (paymentType == 'kopesha' &&
        (customerId == null || customerName == null)) {
      throw Exception('Kopesha sales require a customer');
    }
    if (paymentType == 'kopesha' && (dueDate == null || dueDate.isEmpty)) {
      throw Exception('Kopesha sales require a due date');
    }

    final saleId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final amountPaid = paymentType == 'kopesha' ? 0.0 : totalAmount;
    final balanceDue = paymentType == 'kopesha' ? totalAmount : 0.0;
    final normalizedAmountTendered = paymentType == 'cash'
        ? _roundMoney(amountTendered ?? totalAmount)
        : 0.0;
    final normalizedChangeGiven = paymentType == 'cash'
        ? _roundMoney(changeGiven ?? (normalizedAmountTendered - totalAmount))
        : 0.0;

    if (paymentType == 'cash' &&
        normalizedAmountTendered + 0.001 < totalAmount) {
      throw Exception('Cash received must be at least the sale total');
    }

    // Fetch stock batches dynamically
    final requiredBatches = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final pid = item['product_id'] as String;
      final product = await DatabaseService.queryById('products', pid);
      if (product == null) {
        throw Exception('Product not found');
      }
      final batches = await DatabaseService.rawQuery(
        '''
        SELECT * FROM stock_batches 
        WHERE product_id = ? AND quantity_remaining > 0 
        ORDER BY received_at ASC
      ''',
        [pid],
      );

      final mutableBatches = List<Map<String, dynamic>>.from(batches);
      final batchStock = mutableBatches.fold<double>(
        0.0,
        (sum, batch) =>
            sum + ((batch['quantity_remaining'] as num? ?? 0).toDouble()),
      );
      final aggregateStock = (product['stock'] as num? ?? 0).toDouble();
      final unbatchedStock = aggregateStock - batchStock;
      if (unbatchedStock > 0.001) {
        final costPerStockUnit =
            ((product['cost'] as num? ?? 0).toDouble()) /
            UnitUtils.saleToStockFactor(product);
        mutableBatches.add({
          'id': 'aggregate_fallback_$pid',
          'quantity_remaining': unbatchedStock,
          'unit_cost': costPerStockUnit.isFinite ? costPerStockUnit : 0.0,
          'is_fallback': 1,
        });
      }

      requiredBatches[pid] = mutableBatches;
    }

    final batch = DatabaseService.db.batch();

    batch.insert(_salesTable, {
      'id': saleId,
      'total_amount': totalAmount,
      'tax': tax,
      'discount': discount,
      'payment_type': paymentType,
      'user_id': userId,
      'customer_id': customerId,
      'customer_name': customerName,
      'due_date': dueDate,
      'amount_paid': amountPaid,
      'amount_tendered': normalizedAmountTendered,
      'change_given': normalizedChangeGiven < 0 ? 0.0 : normalizedChangeGiven,
      'balance_due': balanceDue,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    if (customerId != null && balanceDue > 0) {
      batch.rawUpdate(
        'UPDATE customers SET balance = balance + ?, updated_at = ?, sync_status = ? WHERE id = ?',
        [balanceDue, now, 'pending', customerId],
      );
    }

    for (final item in items) {
      final pid = item['product_id'] as String;
      final qty = (item['quantity'] as num).toDouble();
      final unit = item['unit'] as String? ?? 'pcs';
      final saleToStockFactor = (item['sale_to_stock_factor'] as num? ?? 1)
          .toDouble();
      final stockQty = qty * saleToStockFactor;
      double remainingToFulfill = stockQty;
      double totalCostAccumulated = 0;

      final batches = requiredBatches[pid] ?? [];

      for (final b in batches) {
        if (remainingToFulfill <= 0) break;

        final availableInBatch = (b['quantity_remaining'] as num).toDouble();
        final bId = b['id'] as String;
        final bCost = (b['unit_cost'] as num).toDouble();
        final isFallback = (b['is_fallback'] as num? ?? 0) == 1;

        if (availableInBatch <= remainingToFulfill) {
          // Exhaust the batch completely
          totalCostAccumulated += availableInBatch * bCost;
          remainingToFulfill -= availableInBatch;
          if (!isFallback) {
            batch.rawUpdate(
              'UPDATE stock_batches SET quantity_remaining = 0, finished_at = ?, updated_at = ?, sync_status = ? WHERE id = ?',
              [now, now, 'pending', bId],
            );
          }
        } else {
          // Take partial from batch
          totalCostAccumulated += remainingToFulfill * bCost;
          if (!isFallback) {
            batch.rawUpdate(
              'UPDATE stock_batches SET quantity_remaining = quantity_remaining - ?, updated_at = ?, sync_status = ? WHERE id = ?',
              [remainingToFulfill, now, 'pending', bId],
            );
          }
          remainingToFulfill = 0;
        }
      }

      if (remainingToFulfill > 0.001) {
        throw Exception('Not enough stock remaining for this sale');
      }

      final avgUnitCost = qty > 0 ? (totalCostAccumulated / qty) : 0.0;

      batch.insert(_itemsTable, {
        'id': _uuid.v4(),
        'quantity': qty,
        'unit_price': item['unit_price'],
        'unit_cost': avgUnitCost,
        'unit': unit,
        'sale_id': saleId,
        'product_id': pid,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      // Decrement aggregate global stock
      batch.rawUpdate(
        'UPDATE products SET stock = stock - ?, updated_at = ?, sync_status = ? WHERE id = ?',
        [stockQty, now, 'pending', pid],
      );
    }

    await batch.commit(noResult: true);
    return saleId;
  }

  /// Get all sales, optionally filtered by date range
  static Future<List<Map<String, dynamic>>> getAll({
    String? startDate,
    String? endDate,
    String? cashierId,
  }) async {
    final clauses = <String>[];
    final whereArgs = <dynamic>[];
    final normalizedCashierId = cashierId?.trim();

    if (startDate != null) {
      clauses.add('s.created_at >= ?');
      whereArgs.add(startDate);
    }
    if (endDate != null) {
      clauses.add('s.created_at <= ?');
      whereArgs.add(endDate);
    }
    if (normalizedCashierId != null && normalizedCashierId.isNotEmpty) {
      clauses.add('s.user_id = ?');
      whereArgs.add(normalizedCashierId);
    }
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';

    return DatabaseService.rawQuery('''
      SELECT
        s.*,
        COALESCE(
          NULLIF(TRIM(u.name), ''),
          CASE
            WHEN s.user_id = 'admin' THEN 'Admin'
            WHEN COALESCE(s.user_id, '') = '' THEN 'Unknown Cashier'
            ELSE s.user_id
          END
        ) as cashier_name,
        COALESCE(u.role, 'CASHIER') as cashier_role,
        COALESCE((SELECT SUM(si.quantity * (si.unit_price - si.unit_cost)) FROM $_itemsTable si WHERE si.sale_id = s.id), 0) - s.discount as profit,
        COALESCE((SELECT SUM(ABS(r.total_amount)) FROM $_salesTable r WHERE r.refund_for_sale_id = s.id), 0) as refunded_amount,
        COALESCE((SELECT COUNT(*) FROM $_salesTable r WHERE r.refund_for_sale_id = s.id), 0) as refund_count
      FROM $_salesTable s
      LEFT JOIN users u ON u.id = s.user_id
      $where
      ORDER BY s.created_at DESC
    ''', whereArgs);
  }

  /// Get sale with its items
  static Future<Map<String, dynamic>?> getSaleWithItems(String saleId) async {
    final sales = await DatabaseService.rawQuery(
      '''
      SELECT
        s.*,
        COALESCE(
          NULLIF(TRIM(u.name), ''),
          CASE
            WHEN s.user_id = 'admin' THEN 'Admin'
            WHEN COALESCE(s.user_id, '') = '' THEN 'Unknown Cashier'
            ELSE s.user_id
          END
        ) as cashier_name,
        COALESCE(u.role, 'CASHIER') as cashier_role
      FROM $_salesTable s
      LEFT JOIN users u ON u.id = s.user_id
      WHERE s.id = ?
      ''',
      [saleId],
    );
    if (sales.isEmpty) {
      return null;
    }
    final sale = sales.first;

    final items = await DatabaseService.rawQuery(
      '''SELECT si.*, p.name as product_name, p.barcode 
         FROM $_itemsTable si 
         JOIN products p ON si.product_id = p.id 
         WHERE si.sale_id = ?''',
      [saleId],
    );

    return {...sale, 'items': items};
  }

  static Future<List<Map<String, dynamic>>> getRefundableItems(
    String saleId,
  ) async {
    final details = await getSaleWithItems(saleId);
    if (details == null) {
      throw Exception('Sale not found');
    }

    final items =
        details['items'] as List<Map<String, dynamic>>? ??
        <Map<String, dynamic>>[];
    final refundedRows = await DatabaseService.rawQuery(
      '''
      SELECT
        si.product_id,
        COALESCE(SUM(-si.quantity), 0) as refunded_quantity
      FROM $_salesTable r
      JOIN $_itemsTable si ON si.sale_id = r.id
      WHERE r.refund_for_sale_id = ?
      GROUP BY si.product_id
      ''',
      [saleId],
    );

    final refundedByProduct = <String, double>{};
    for (final row in refundedRows) {
      refundedByProduct[row['product_id'] as String] = _money(
        row['refunded_quantity'] as num?,
      );
    }

    return items
        .map((item) {
          final soldQuantity = _money(item['quantity'] as num?).abs();
          final refundedQuantity = refundedByProduct[item['product_id']] ?? 0.0;
          final refundableQuantity = soldQuantity - refundedQuantity;

          return {
            ...item,
            'sold_quantity': soldQuantity,
            'refunded_quantity': refundedQuantity,
            'refundable_quantity': refundableQuantity < 0.001
                ? 0.0
                : refundableQuantity,
          };
        })
        .where((item) => _money(item['refundable_quantity'] as num?) > 0.0)
        .toList();
  }

  static Future<String> refundSale({
    required String saleId,
    required String userId,
    String? note,
    List<Map<String, dynamic>>? items,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'issue refunds');
    final original = await getSaleWithItems(saleId);
    if (original == null) {
      throw Exception('Sale not found');
    }

    final paymentType = (original['payment_type'] as String? ?? 'cash')
        .toLowerCase();
    if (paymentType.startsWith('refund')) {
      throw Exception('Refund sales cannot be refunded again');
    }

    final amountPaid = (original['amount_paid'] as num? ?? 0).toDouble();
    final balanceDue = (original['balance_due'] as num? ?? 0).toDouble();
    if (paymentType == 'kopesha' && amountPaid > 0) {
      throw Exception(
        'Kopesha sales with recorded repayments cannot be refunded yet',
      );
    }

    final refundableItems = await getRefundableItems(saleId);
    if (refundableItems.isEmpty) {
      throw Exception('This sale has no refundable items left');
    }

    final requestedItems = items ?? refundableItems;
    if (requestedItems.isEmpty) {
      throw Exception('Choose at least one item to return');
    }

    final refundableByProduct = <String, Map<String, dynamic>>{
      for (final item in refundableItems) item['product_id'] as String: item,
    };

    final selectedItems = <Map<String, dynamic>>[];
    final productsById = <String, Map<String, dynamic>>{};
    for (final item in requestedItems) {
      final productId = item['product_id'] as String?;
      if (productId == null || !refundableByProduct.containsKey(productId)) {
        throw Exception('A selected refund item is not refundable');
      }

      productsById[productId] ??=
          await DatabaseService.queryById('products', productId) ??
          <String, dynamic>{'unit': item['unit']};

      final source = refundableByProduct[productId]!;
      final quantity = _money(item['quantity'] as num?);
      final refundableQuantity = _money(source['refundable_quantity'] as num?);

      if (quantity <= 0) {
        continue;
      }
      if (quantity - refundableQuantity > 0.001) {
        throw Exception(
          'Return quantity for ${source['product_name']} is higher than refundable stock',
        );
      }

      selectedItems.add({...source, 'quantity': quantity});
    }

    if (selectedItems.isEmpty) {
      throw Exception('Choose at least one valid item quantity to return');
    }

    final refundId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final refundNote = note?.trim().isEmpty == true ? null : note?.trim();
    final originalTotal = (original['total_amount'] as num? ?? 0).toDouble();
    final originalTax = (original['tax'] as num? ?? 0).toDouble();
    final originalDiscount = (original['discount'] as num? ?? 0).toDouble();
    final originalSubtotal = _roundMoney(
      originalTotal - originalTax + originalDiscount,
    );
    final selectedSubtotal = _roundMoney(
      selectedItems.fold<double>(
        0.0,
        (sum, item) =>
            sum +
            (_money(item['quantity'] as num?) *
                _money(item['unit_price'] as num?)),
      ),
    );
    final ratio = originalSubtotal <= 0
        ? 1.0
        : (selectedSubtotal / originalSubtotal);
    final refundTax = _roundMoney(originalTax * ratio);
    final refundDiscount = _roundMoney(originalDiscount * ratio);
    final refundTotal = _roundMoney(
      selectedSubtotal + refundTax - refundDiscount,
    );
    final refundPaymentType = paymentType == 'kopesha'
        ? 'refund_kopesha'
        : 'refund_cash';

    await DatabaseService.db.transaction((txn) async {
      await txn.insert(_salesTable, {
        'id': refundId,
        'total_amount': -refundTotal,
        'tax': -refundTax,
        'discount': -refundDiscount,
        'payment_type': refundPaymentType,
        'user_id': userId,
        'customer_id': original['customer_id'],
        'customer_name': original['customer_name'],
        'refund_for_sale_id': saleId,
        'refund_note': refundNote,
        'amount_paid': 0.0,
        'amount_tendered': 0.0,
        'change_given': 0.0,
        'balance_due': 0.0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      await txn.rawUpdate(
        '''
        UPDATE $_salesTable
        SET
          refund_sale_id = ?,
          refund_note = ?,
          refunded_at = ?,
          updated_at = ?,
          sync_status = ?
        WHERE id = ?
        ''',
        [refundId, refundNote, now, now, 'pending', saleId],
      );

      if (paymentType == 'kopesha' && balanceDue > 0) {
        await txn.rawUpdate(
          '''
          UPDATE customers
          SET
            balance = CASE WHEN balance - ? < 0 THEN 0 ELSE balance - ? END,
            updated_at = ?,
            sync_status = ?
          WHERE id = ?
          ''',
          [refundTotal, refundTotal, now, 'pending', original['customer_id']],
        );

        await txn.rawUpdate(
          '''
          UPDATE $_salesTable
          SET
            balance_due = CASE WHEN balance_due - ? < 0 THEN 0 ELSE balance_due - ? END,
            updated_at = ?,
            sync_status = ?
          WHERE id = ?
          ''',
          [refundTotal, refundTotal, now, 'pending', saleId],
        );
      }

      for (final item in selectedItems) {
        final quantity = (item['quantity'] as num? ?? 0).toDouble();
        final unitCost = (item['unit_cost'] as num? ?? 0).toDouble();
        final product =
            productsById[item['product_id'] as String] ??
            <String, dynamic>{'unit': item['unit']};
        final saleUnit = item['unit'] as String? ?? 'pcs';
        final stockUnit = UnitUtils.stockUnitForProduct(product);
        final stockQuantity =
            UnitUtils.convertQuantity(quantity, saleUnit, stockUnit) ??
            quantity;
        final stockUnitCost = stockQuantity > 0
            ? ((quantity * unitCost) / stockQuantity)
            : unitCost;

        await txn.insert(_itemsTable, {
          'id': _uuid.v4(),
          'quantity': -quantity,
          'unit_price': item['unit_price'],
          'unit_cost': unitCost,
          'unit': item['unit'] ?? 'pcs',
          'sale_id': refundId,
          'product_id': item['product_id'],
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });

        await txn.rawUpdate(
          '''
          UPDATE products
          SET stock = stock + ?, updated_at = ?, sync_status = ?
          WHERE id = ?
          ''',
          [stockQuantity, now, 'pending', item['product_id']],
        );

        await txn.insert('stock_batches', {
          'id': _uuid.v4(),
          'product_id': item['product_id'],
          'quantity_received': stockQuantity,
          'quantity_remaining': stockQuantity,
          'unit_cost': stockUnitCost,
          'received_at': now,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });
      }
    });

    return refundId;
  }

  /// Get today's sales summary
  static Future<Map<String, dynamic>> getTodaySummary({
    String? cashierId,
  }) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final normalizedCashierId = cashierId?.trim();
    final profitWhere = <String>['s2.created_at LIKE ?'];
    final totalWhere = <String>['created_at LIKE ?'];
    final args = <dynamic>['$today%'];

    if (normalizedCashierId != null && normalizedCashierId.isNotEmpty) {
      profitWhere.add('s2.user_id = ?');
      args.add(normalizedCashierId);
    }

    args.add('$today%');
    if (normalizedCashierId != null && normalizedCashierId.isNotEmpty) {
      totalWhere.add('user_id = ?');
      args.add(normalizedCashierId);
    }

    final results = await DatabaseService.rawQuery('''
      SELECT 
        COUNT(*) as total_sales,
        COALESCE(SUM(total_amount), 0) as total_revenue,
        COALESCE(SUM(tax), 0) as total_tax,
        COALESCE(SUM(discount), 0) as total_discount,
        COALESCE((
          SELECT SUM(si.quantity * (si.unit_price - si.unit_cost)) 
          FROM $_itemsTable si 
          JOIN $_salesTable s2 ON si.sale_id = s2.id 
          WHERE ${profitWhere.join(' AND ')}
        ), 0) - COALESCE(SUM(discount), 0) as total_profit
      FROM $_salesTable 
      WHERE ${totalWhere.join(' AND ')}
    ''', args);

    return results.isNotEmpty
        ? results.first
        : {'total_sales': 0, 'total_revenue': 0.0, 'total_profit': 0.0};
  }
}
