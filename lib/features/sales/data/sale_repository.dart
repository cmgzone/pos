import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/audit_log_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

class SaleRepository {
  static const _salesTable = 'sales';
  static const _itemsTable = 'sale_items';
  static const _serviceItemsTable = 'service_sale_items';

  static double _money(num? value) => (value ?? 0).toDouble();

  static double _roundMoney(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  static String _effectiveBranchId(String? branchId) {
    final cleanBranchId = branchId?.trim() ?? '';
    return cleanBranchId.isEmpty
        ? DatabaseService.currentBranchId
        : cleanBranchId;
  }

  static String _serviceRefundKey({
    required String? serviceOrderId,
    required String? serviceId,
    required String? serviceName,
  }) {
    final orderId = serviceOrderId?.trim() ?? '';
    if (orderId.isNotEmpty) {
      return 'service_order:$orderId';
    }

    final templateId = serviceId?.trim() ?? '';
    final label = serviceName?.trim() ?? '';
    return 'service:$templateId:$label';
  }

  static String _productRefundKey({
    required String? productId,
    required String? variantId,
  }) {
    final product = productId?.trim() ?? '';
    final variant = variantId?.trim() ?? '';
    return 'product:$product:$variant';
  }

  /// Create a complete sale with items (transactional)
  static Future<String> createSale({
    required double totalAmount,
    required double tax,
    required double discount,
    required String paymentType,
    bool isCashDrawer = false,
    required String userId,
    String? shiftId,
    required List<Map<String, dynamic>> items,
    double? amountTendered,
    double? changeGiven,
    String? customerId,
    String? customerName,
    String? dueDate,
    String? paymentProvider,
    String? paymentReference,
    String? paymentStatus,
    Map<String, dynamic>? paymentMetadata,
    DateTime? createdAt,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'complete sales');
    final isKopesha = paymentType.toLowerCase() == 'kopesha';
    if (isKopesha && (customerId == null || customerName == null)) {
      throw Exception('Kopesha sales require a customer');
    }
    if (isKopesha && (dueDate == null || dueDate.isEmpty)) {
      throw Exception('Kopesha sales require a due date');
    }

    final saleId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final saleTimestamp = (createdAt ?? DateTime.now()).toIso8601String();
    final amountPaid = isKopesha ? 0.0 : totalAmount;
    final balanceDue = isKopesha ? totalAmount : 0.0;
    final normalizedAmountTendered = isCashDrawer
        ? _roundMoney(amountTendered ?? totalAmount)
        : 0.0;
    final normalizedChangeGiven = isCashDrawer
        ? _roundMoney(changeGiven ?? (normalizedAmountTendered - totalAmount))
        : 0.0;

    if (isCashDrawer && normalizedAmountTendered + 0.001 < totalAmount) {
      throw Exception('Cash received must be at least the sale total');
    }

    final productItems = items
        .where(
          (item) => (item['line_type'] as String? ?? 'product') != 'service',
        )
        .toList();
    final serviceItems = items
        .where((item) => (item['line_type'] as String? ?? '') == 'service')
        .toList();

    // Fetch products, variants, and stock batches in bulk (N+1 query fix)
    final productIds = productItems
        .map((item) => item['product_id'] as String)
        .toSet()
        .toList();
    final variantIds = productItems
        .map((item) => item['variant_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();

    final List<Map<String, dynamic>> productsList;
    if (productIds.isNotEmpty) {
      final placeholders = List.filled(productIds.length, '?').join(',');
      productsList = await DatabaseService.rawQuery(
        'SELECT * FROM products WHERE id IN ($placeholders)',
        productIds,
      );
    } else {
      productsList = [];
    }
    final productsMap = {for (final p in productsList) p['id'] as String: p};

    final List<Map<String, dynamic>> variantsList;
    if (variantIds.isNotEmpty) {
      final placeholders = List.filled(variantIds.length, '?').join(',');
      variantsList = await DatabaseService.rawQuery(
        'SELECT * FROM product_variants WHERE id IN ($placeholders)',
        variantIds,
      );
    } else {
      variantsList = [];
    }
    final variantsMap = {for (final v in variantsList) v['id'] as String: v};

    final nonVariantProductIds = productItems
        .where((item) => item['variant_id'] == null)
        .map((item) => item['product_id'] as String)
        .toSet()
        .toList();

    final List<Map<String, dynamic>> allBatches;
    if (nonVariantProductIds.isNotEmpty) {
      final placeholders = List.filled(
        nonVariantProductIds.length,
        '?',
      ).join(',');
      allBatches = await DatabaseService.rawQuery(
        '''
        SELECT * FROM stock_batches
        WHERE product_id IN ($placeholders)
          AND quantity_remaining > 0
          AND COALESCE(branch_id, ?) = ?
        ORDER BY
          CASE WHEN expiry_date IS NULL OR TRIM(expiry_date) = '' THEN 1 ELSE 0 END ASC,
          date(expiry_date) ASC,
          received_at ASC
        ''',
        [
          ...nonVariantProductIds,
          DatabaseService.defaultBranchId,
          DatabaseService.currentBranchId,
        ],
      );
    } else {
      allBatches = [];
    }

    final batchesMap = <String, List<Map<String, dynamic>>>{};
    for (final batch in allBatches) {
      final pid = batch['product_id'] as String;
      batchesMap.putIfAbsent(pid, () => []).add(batch);
    }

    final requiredBatches = <String, List<Map<String, dynamic>>>{};
    final tracksStockByProduct = <String, bool>{};
    for (final item in productItems) {
      final pid = item['product_id'] as String;
      final variantId = item['variant_id'] as String?;
      final qty = (item['quantity'] as num).toDouble();
      final saleToStockFactor = (item['sale_to_stock_factor'] as num? ?? 1)
          .toDouble();
      final stockQty = qty * saleToStockFactor;
      final product = productsMap[pid];
      if (product == null) throw Exception('Product not found');
      final tracksStock = UnitUtils.tracksStock(product);
      tracksStockByProduct[pid] = tracksStock;

      if (!tracksStock) {
        continue;
      }

      if (variantId != null) {
        // Variant: validate stock directly, no FIFO batch lookup.
        final variant = variantsMap[variantId];
        if (variant == null) throw Exception('Product variant not found');
        final variantStock = (variant['stock'] as num? ?? 0).toDouble();
        if (variantStock < stockQty - 0.001) {
          throw Exception('Not enough stock for variant "${variant['name']}"');
        }
        continue;
      }

      final batches = batchesMap[pid] ?? [];

      final mutableBatches = List<Map<String, dynamic>>.from(batches);
      final batchStock = mutableBatches.fold<double>(
        0.0,
        (sum, b) => sum + ((b['quantity_remaining'] as num? ?? 0).toDouble()),
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
      'branch_id': DatabaseService.currentBranchId,
      'total_amount': totalAmount,
      'tax': tax,
      'discount': discount,
      'payment_type': paymentType,
      'is_cash_drawer': isCashDrawer ? 1 : 0,
      'user_id': userId,
      'shift_id': shiftId,
      'customer_id': customerId,
      'customer_name': customerName,
      'due_date': dueDate,
      'amount_paid': amountPaid,
      'amount_tendered': normalizedAmountTendered,
      'change_given': normalizedChangeGiven < 0 ? 0.0 : normalizedChangeGiven,
      'balance_due': balanceDue,
      'payment_provider': paymentProvider,
      'payment_reference': paymentReference,
      'payment_status': paymentStatus,
      'payment_metadata_json': paymentMetadata == null
          ? null
          : jsonEncode(paymentMetadata),
      'etims_status': 'not_submitted',
      'created_at': saleTimestamp,
      'updated_at': now,
      'sync_status': 'pending',
    });

    if (customerId != null && balanceDue > 0) {
      batch.rawUpdate(
        'UPDATE customers SET balance = balance + ?, updated_at = ?, sync_status = ? WHERE id = ?',
        [balanceDue, now, 'pending', customerId],
      );
    }

    for (final item in productItems) {
      final pid = item['product_id'] as String;
      final variantId = item['variant_id'] as String?;
      final qty = (item['quantity'] as num).toDouble();
      final unit = item['unit'] as String? ?? 'pcs';
      final saleToStockFactor = (item['sale_to_stock_factor'] as num? ?? 1)
          .toDouble();
      final stockQty = qty * saleToStockFactor;
      final tracksStock = tracksStockByProduct[pid] ?? true;

      if (variantId != null) {
        // ── Variant path: direct deduction, no FIFO ──────────────────────────
        final unitCost = (item['unit_cost'] as num? ?? 0).toDouble();
        batch.insert(_itemsTable, {
          'id': _uuid.v4(),
          'quantity': qty,
          'unit_price': item['unit_price'],
          'unit_cost': unitCost,
          'unit': unit,
          'sale_id': saleId,
          'product_id': pid,
          'variant_id': variantId,
          'created_at': saleTimestamp,
          'updated_at': now,
          'sync_status': 'pending',
        });
        if (!tracksStock) {
          continue;
        }
        batch.rawUpdate(
          'UPDATE product_variants SET stock = stock - ? WHERE id = ?',
          [stockQty, variantId],
        );
        batch.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [
          stockQty,
          pid,
        ]);
        continue;
      }

      // ── Non-variant: FIFO batch deduction ────────────────────────────────
      if (!tracksStock) {
        batch.insert(_itemsTable, {
          'id': _uuid.v4(),
          'quantity': qty,
          'unit_price': item['unit_price'],
          'unit_cost': (item['unit_cost'] as num? ?? 0).toDouble(),
          'unit': unit,
          'sale_id': saleId,
          'product_id': pid,
          'created_at': saleTimestamp,
          'updated_at': now,
          'sync_status': 'pending',
        });
        continue;
      }

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
          totalCostAccumulated += availableInBatch * bCost;
          remainingToFulfill -= availableInBatch;
          if (!isFallback) {
            batch.rawUpdate(
              'UPDATE stock_batches SET quantity_remaining = 0, finished_at = ?, updated_at = ? WHERE id = ?',
              [now, now, bId],
            );
          }
        } else {
          totalCostAccumulated += remainingToFulfill * bCost;
          if (!isFallback) {
            batch.rawUpdate(
              'UPDATE stock_batches SET quantity_remaining = quantity_remaining - ?, updated_at = ? WHERE id = ?',
              [remainingToFulfill, now, bId],
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
        'created_at': saleTimestamp,
        'updated_at': now,
        'sync_status': 'pending',
      });
      batch.rawUpdate('UPDATE products SET stock = stock - ? WHERE id = ?', [
        stockQty,
        pid,
      ]);
    }

    for (final item in serviceItems) {
      batch.insert(_serviceItemsTable, {
        'id': _uuid.v4(),
        'sale_id': saleId,
        'service_order_id': item['service_order_id'],
        'service_id': item['service_id'],
        'service_name': item['product_name'] ?? 'Service',
        'quantity': (item['quantity'] as num?)?.toDouble() ?? 1.0,
        'unit_price': (item['unit_price'] as num?)?.toDouble() ?? 0.0,
        'created_at': saleTimestamp,
        'updated_at': now,
        'sync_status': 'pending',
      });

      final orderId = item['service_order_id'] as String?;
      if (orderId != null && orderId.isNotEmpty) {
        batch.rawUpdate(
          '''
          UPDATE service_orders
          SET sale_id = ?, status = ?, updated_at = ?, sync_status = ?
          WHERE id = ?
          ''',
          [saleId, 'paid', now, 'pending', orderId],
        );
      }
    }

    await batch.commit(noResult: true);
    DatabaseService.notifyLocalChange();
    await AuditLogService.log(
      action: 'create',
      entityTable: _salesTable,
      entityId: saleId,
    );
    return saleId;
  }

  /// Get all sales, optionally filtered by date range
  static Future<List<Map<String, dynamic>>> getAll({
    String? startDate,
    String? endDate,
    String? cashierId,
    String? branchId,
    bool includeAllBranches = false,
  }) async {
    final clauses = <String>[];
    final whereArgs = <dynamic>[];
    final normalizedCashierId = cashierId?.trim();
    final effectiveBranchId = _effectiveBranchId(branchId);

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
    final canUseAllBranches =
        includeAllBranches &&
        RolePermissions.normalizeRole(SessionService.currentUserRole) ==
            RolePermissions.admin;
    if (!canUseAllBranches) {
      clauses.add('COALESCE(s.branch_id, ?) = ?');
      whereArgs.addAll([DatabaseService.defaultBranchId, effectiveBranchId]);
    }
    clauses.add('s.deleted_at IS NULL');
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
        (
          COALESCE((SELECT SUM(si.quantity * (si.unit_price - si.unit_cost)) FROM $_itemsTable si WHERE si.sale_id = s.id), 0)
          + COALESCE((SELECT SUM(ssi.quantity * ssi.unit_price) FROM $_serviceItemsTable ssi WHERE ssi.sale_id = s.id), 0)
          - s.discount
        ) as profit,
        COALESCE((SELECT SUM(ABS(r.total_amount)) FROM $_salesTable r WHERE r.refund_for_sale_id = s.id), 0) as refunded_amount,
        COALESCE((SELECT COUNT(*) FROM $_salesTable r WHERE r.refund_for_sale_id = s.id), 0) as refund_count,
        COALESCE((SELECT COUNT(*) FROM $_itemsTable si WHERE si.sale_id = s.id), 0) as product_line_count,
        COALESCE((SELECT COUNT(*) FROM $_serviceItemsTable ssi WHERE ssi.sale_id = s.id), 0) as service_line_count,
        (
          SELECT GROUP_CONCAT(ssi.service_name, ', ')
          FROM $_serviceItemsTable ssi
          WHERE ssi.sale_id = s.id
        ) as service_names,
        (
          SELECT GROUP_CONCAT(
            CASE
              WHEN si.variant_id IS NOT NULL THEN p.name || ' - ' || COALESCE(pv.name, '')
              ELSE p.name
            END,
            ', '
          )
          FROM $_itemsTable si
          JOIN products p ON p.id = si.product_id
          LEFT JOIN product_variants pv ON pv.id = si.variant_id
          WHERE si.sale_id = s.id
        ) as product_names
      FROM $_salesTable s
      LEFT JOIN users u ON u.id = s.user_id
      $where
      ORDER BY s.created_at DESC
    ''', whereArgs);
  }

  /// Get sale with its items
  static Future<Map<String, dynamic>?> getSaleWithItems(String saleId) async {
    final canUseAllBranches =
        RolePermissions.normalizeRole(SessionService.currentUserRole) ==
        RolePermissions.admin;
    final branchClause = canUseAllBranches
        ? ''
        : 'AND COALESCE(s.branch_id, ?) = ?';
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
        AND s.deleted_at IS NULL
        $branchClause
      ''',
      canUseAllBranches
          ? [saleId]
          : [
              saleId,
              DatabaseService.defaultBranchId,
              DatabaseService.currentBranchId,
            ],
    );
    if (sales.isEmpty) {
      return null;
    }
    final sale = sales.first;

    final items = await DatabaseService.rawQuery(
      '''
      SELECT
        si.id,
        si.quantity,
        si.unit_price,
        si.unit_cost,
        si.unit,
        si.sale_id,
        si.product_id,
        si.variant_id,
        NULL as service_order_id,
        NULL as service_id,
        CASE WHEN si.variant_id IS NOT NULL
          THEN p.name || ' – ' || COALESCE(pv.name, '')
          ELSE p.name
        END as product_name,
        COALESCE(pv.barcode, p.barcode) as barcode,
        'product' as line_type
      FROM $_itemsTable si
      JOIN products p ON si.product_id = p.id
      LEFT JOIN product_variants pv ON pv.id = si.variant_id
      WHERE si.sale_id = ?
      UNION ALL
      SELECT
        ssi.id,
        ssi.quantity,
        ssi.unit_price,
        0 as unit_cost,
        'job' as unit,
        ssi.sale_id,
        NULL as product_id,
        NULL as variant_id,
        ssi.service_order_id,
        ssi.service_id,
        ssi.service_name as product_name,
        NULL as barcode,
        'service' as line_type
      FROM $_serviceItemsTable ssi
      WHERE ssi.sale_id = ?
      ''',
      [saleId, saleId],
    );

    return {...sale, 'items': items};
  }

  static Future<void> deleteSale(String saleId) async {
    if (!RolePermissions.canRefundSales(SessionService.currentUserRole)) {
      throw Exception('Only a manager or administrator can delete sales');
    }
    await LicenseService.ensureWriteAccess(action: 'delete sales');
    final sale = await getSaleWithItems(saleId);
    if (sale == null) {
      throw Exception('Sale not found');
    }
    final now = DateTime.now().toIso8601String();
    final customerId = sale['customer_id'] as String?;
    final balanceDue = (sale['balance_due'] as num? ?? 0).toDouble();

    await DatabaseService.db.transaction((txn) async {
      await txn.update(
        _salesTable,
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [saleId],
      );
      await txn.update(
        _itemsTable,
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'sale_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );
      await txn.update(
        _serviceItemsTable,
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'sale_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );
      await txn.update(
        'service_orders',
        {
          'sale_id': null,
          'status': 'completed',
          'updated_at': now,
          'sync_status': 'pending',
        },
        where: 'sale_id = ? AND deleted_at IS NULL',
        whereArgs: [saleId],
      );
      if (customerId != null && customerId.isNotEmpty && balanceDue > 0) {
        await txn.rawUpdate(
          '''
          UPDATE customers
          SET balance = CASE WHEN balance - ? < 0 THEN 0 ELSE balance - ? END,
              updated_at = ?,
              sync_status = ?
          WHERE id = ?
          ''',
          [balanceDue, balanceDue, now, 'pending', customerId],
        );
      }
    });
    await AuditLogService.log(
      action: 'delete',
      entityTable: _salesTable,
      entityId: saleId,
      branchId: sale['branch_id'] as String?,
    );
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
        si.variant_id,
        COALESCE(SUM(-si.quantity), 0) as refunded_quantity
      FROM $_salesTable r
      JOIN $_itemsTable si ON si.sale_id = r.id
      WHERE r.refund_for_sale_id = ?
      GROUP BY si.product_id, si.variant_id
      ''',
      [saleId],
    );
    final refundedServiceRows = await DatabaseService.rawQuery(
      '''
      SELECT
        ssi.service_order_id,
        ssi.service_id,
        ssi.service_name,
        COALESCE(SUM(-ssi.quantity), 0) as refunded_quantity
      FROM $_salesTable r
      JOIN $_serviceItemsTable ssi ON ssi.sale_id = r.id
      WHERE r.refund_for_sale_id = ?
      GROUP BY ssi.service_order_id, ssi.service_id, ssi.service_name
      ''',
      [saleId],
    );

    final refundedByProduct = <String, double>{};
    for (final row in refundedRows) {
      refundedByProduct[_productRefundKey(
        productId: row['product_id'] as String?,
        variantId: row['variant_id'] as String?,
      )] = _money(
        row['refunded_quantity'] as num?,
      );
    }
    final refundedByService = <String, double>{};
    for (final row in refundedServiceRows) {
      refundedByService[_serviceRefundKey(
        serviceOrderId: row['service_order_id'] as String?,
        serviceId: row['service_id'] as String?,
        serviceName: row['service_name'] as String?,
      )] = _money(
        row['refunded_quantity'] as num?,
      );
    }

    return items
        .map((item) {
          final lineType = item['line_type'] as String? ?? 'product';
          final soldQuantity = _money(item['quantity'] as num?).abs();
          final refundedQuantity = lineType == 'service'
              ? (refundedByService[_serviceRefundKey(
                      serviceOrderId: item['service_order_id'] as String?,
                      serviceId: item['service_id'] as String?,
                      serviceName: item['product_name'] as String?,
                    )] ??
                    0.0)
              : (refundedByProduct[_productRefundKey(
                      productId: item['product_id'] as String?,
                      variantId: item['variant_id'] as String?,
                    )] ??
                    0.0);
          final refundableQuantity = soldQuantity - refundedQuantity;
          final refundKey = lineType == 'service'
              ? _serviceRefundKey(
                  serviceOrderId: item['service_order_id'] as String?,
                  serviceId: item['service_id'] as String?,
                  serviceName: item['product_name'] as String?,
                )
              : _productRefundKey(
                  productId: item['product_id'] as String?,
                  variantId: item['variant_id'] as String?,
                );

          return {
            ...item,
            'refund_key': refundKey,
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
    String? shiftId,
    String? note,
    List<Map<String, dynamic>>? items,
  }) async {
    if (!RolePermissions.canRefundSales(SessionService.currentUserRole)) {
      throw Exception('Only a manager or administrator can issue refunds');
    }
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

    final refundableByKey = <String, Map<String, dynamic>>{
      for (final item in refundableItems) item['refund_key'] as String: item,
    };

    final selectedItems = <Map<String, dynamic>>[];
    final productsById = <String, Map<String, dynamic>>{};
    for (final item in requestedItems) {
      final refundKey =
          item['refund_key'] as String? ??
          ((item['product_id'] as String?) != null
              ? _productRefundKey(
                  productId: item['product_id'] as String?,
                  variantId: item['variant_id'] as String?,
                )
              : null);
      if (refundKey == null || !refundableByKey.containsKey(refundKey)) {
        throw Exception('A selected refund item is not refundable');
      }

      final source = refundableByKey[refundKey]!;
      final lineType = source['line_type'] as String? ?? 'product';
      final productId = source['product_id'] as String?;
      if (lineType == 'product' && productId != null) {
        productsById[productId] ??=
            await DatabaseService.queryById('products', productId) ??
            <String, dynamic>{'unit': item['unit']};
      }
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

      selectedItems.add({
        ...source,
        'quantity': quantity,
        'refund_key': refundKey,
      });
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
    final isCashDrawer = (original['is_cash_drawer'] as num? ?? 0) == 1;
    final refundPaymentType = 'refund_$paymentType';

    await DatabaseService.db.transaction((txn) async {
      await txn.insert(_salesTable, {
        'id': refundId,
        'branch_id': original['branch_id'] ?? DatabaseService.currentBranchId,
        'total_amount': -refundTotal,
        'tax': -refundTax,
        'discount': -refundDiscount,
        'payment_type': refundPaymentType,
        'is_cash_drawer': isCashDrawer ? 1 : 0,
        'user_id': userId,
        'shift_id': shiftId,
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
        final lineType = item['line_type'] as String? ?? 'product';

        if (lineType == 'service') {
          await txn.insert(_serviceItemsTable, {
            'id': _uuid.v4(),
            'sale_id': refundId,
            'service_order_id': item['service_order_id'],
            'service_id': item['service_id'],
            'service_name': item['product_name'] ?? 'Service',
            'quantity': -quantity,
            'unit_price': item['unit_price'],
            'created_at': now,
            'updated_at': now,
            'sync_status': 'pending',
          });
          continue;
        }

        final productId = item['product_id'] as String;
        final variantId = item['variant_id'] as String?;
        final product =
            productsById[productId] ?? <String, dynamic>{'unit': item['unit']};
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
          'product_id': productId,
          'variant_id': variantId,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });

        if (!UnitUtils.tracksStock(product)) {
          continue;
        }

        if (variantId != null) {
          // Restore variant stock directly.
          await txn.rawUpdate(
            'UPDATE product_variants SET stock = stock + ? WHERE id = ?',
            [stockQuantity, variantId],
          );
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [stockQuantity, productId],
          );
        } else {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock + ? WHERE id = ?',
            [stockQuantity, productId],
          );
          await txn.insert('stock_batches', {
            'id': _uuid.v4(),
            'product_id': productId,
            'branch_id':
                original['branch_id'] ?? DatabaseService.currentBranchId,
            'quantity_received': stockQuantity,
            'quantity_remaining': stockQuantity,
            'unit_cost': stockUnitCost,
            'received_at': now,
            'created_at': now,
            'updated_at': now,
            'sync_status': 'pending',
          });
        }
      }
    });
    DatabaseService.notifyLocalChange();

    await AuditLogService.log(
      action: 'refund',
      entityTable: _salesTable,
      entityId: refundId,
      branchId: original['branch_id'] as String?,
    );
    return refundId;
  }

  /// Get today's sales summary
  static Future<Map<String, dynamic>> getTodaySummary({
    String? cashierId,
    String? branchId,
  }) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final normalizedCashierId = cashierId?.trim();
    final effectiveBranchId = _effectiveBranchId(branchId);
    final profitWhere = <String>[
      's2.created_at LIKE ?',
      's2.deleted_at IS NULL',
      'COALESCE(s2.branch_id, ?) = ?',
    ];
    final totalWhere = <String>[
      'created_at LIKE ?',
      'deleted_at IS NULL',
      'COALESCE(branch_id, ?) = ?',
    ];
    final args = <dynamic>[
      '$today%',
      DatabaseService.defaultBranchId,
      effectiveBranchId,
    ];

    if (normalizedCashierId != null && normalizedCashierId.isNotEmpty) {
      profitWhere.add('s2.user_id = ?');
      args.add(normalizedCashierId);
    }

    args.add('$today%');
    args.addAll([DatabaseService.defaultBranchId, effectiveBranchId]);
    if (normalizedCashierId != null && normalizedCashierId.isNotEmpty) {
      totalWhere.add('user_id = ?');
      args.add(normalizedCashierId);
    }

    final salesWhere = totalWhere.join(' AND ');
    final results = await DatabaseService.rawQuery(
      '''
      SELECT 
        COUNT(*) as total_sales,
        COALESCE(SUM(total_amount), 0) as total_revenue,
        COALESCE(SUM(tax), 0) as total_tax,
        COALESCE(SUM(discount), 0) as total_discount,
        (
          COALESCE((
            SELECT SUM(si.quantity * (si.unit_price - si.unit_cost))
            FROM $_itemsTable si
            JOIN $_salesTable s2 ON si.sale_id = s2.id
            WHERE ${profitWhere.join(' AND ')}
          ), 0)
          + COALESCE((
            SELECT SUM(ssi.quantity * ssi.unit_price)
            FROM $_serviceItemsTable ssi
            JOIN $_salesTable s3 ON ssi.sale_id = s3.id
            WHERE ${normalizedCashierId != null && normalizedCashierId.isNotEmpty ? "s3.created_at LIKE ? AND s3.deleted_at IS NULL AND COALESCE(s3.branch_id, ?) = ? AND s3.user_id = ?" : "s3.created_at LIKE ? AND s3.deleted_at IS NULL AND COALESCE(s3.branch_id, ?) = ?"}
          ), 0)
          - COALESCE(SUM(discount), 0)
        ) as total_profit
      FROM $_salesTable 
      WHERE $salesWhere
    ''',
      [
        ...args,
        '$today%',
        DatabaseService.defaultBranchId,
        effectiveBranchId,
        if (normalizedCashierId != null && normalizedCashierId.isNotEmpty)
          normalizedCashierId,
      ],
    );

    return results.isNotEmpty
        ? results.first
        : {'total_sales': 0, 'total_revenue': 0.0, 'total_profit': 0.0};
  }
}
