import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/utils/expiry_utils.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

class PurchaseRepository {
  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<List<Map<String, dynamic>>> getSuppliers() async {
    return DatabaseService.rawQuery(
      '''
      SELECT
        s.*,
        COALESCE((
          SELECT COUNT(*)
          FROM purchase_invoices p
          WHERE p.supplier_id = s.id
            AND COALESCE(p.branch_id, ?) = ?
        ), 0) as purchase_count,
        COALESCE((
          SELECT SUM(p.total_amount)
          FROM purchase_invoices p
          WHERE p.supplier_id = s.id
            AND COALESCE(p.branch_id, ?) = ?
        ), 0) as total_spend
        ,
        COALESCE((
          SELECT SUM(p.balance_due)
          FROM purchase_invoices p
          WHERE p.supplier_id = s.id
            AND p.deleted_at IS NULL
            AND p.balance_due > 0.009
            AND COALESCE(p.branch_id, ?) = ?
        ), 0) as outstanding_balance
      FROM suppliers s
      WHERE s.deleted_at IS NULL
        AND COALESCE(s.branch_id, ?) = ?
      ORDER BY s.name ASC
    ''',
      [
        ..._currentBranchArgs,
        ..._currentBranchArgs,
        ..._currentBranchArgs,
        ..._currentBranchArgs,
      ],
    );
  }

  static Future<String> createSupplier({
    required String name,
    String? phone,
    String? email,
    String? address,
    String? note,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'create suppliers');
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Supplier name is required');
    }

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    await DatabaseService.insert('suppliers', {
      'id': id,
      'name': trimmedName,
      'phone': phone?.trim(),
      'email': email?.trim(),
      'address': address?.trim(),
      'note': note?.trim(),
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    await AuditLogService.log(
      action: 'create',
      entityTable: 'suppliers',
      entityId: id,
    );
    return id;
  }

  static Future<void> updateSupplier({
    required String id,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? note,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'update suppliers');
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Supplier name is required');
    }

    await DatabaseService.update('suppliers', {
      'name': trimmedName,
      'phone': phone?.trim(),
      'email': email?.trim(),
      'address': address?.trim(),
      'note': note?.trim(),
      'updated_at': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
    }, id);
  }

  static Future<List<Map<String, dynamic>>> getPurchases() async {
    return DatabaseService.rawQuery(
      '''
      SELECT
        p.*,
        COALESCE(COUNT(sb.id), 0) as item_lines,
        COALESCE(SUM(sb.quantity_received), 0) as total_quantity
      FROM purchase_invoices p
      LEFT JOIN stock_batches sb ON sb.purchase_id = p.id
        AND sb.deleted_at IS NULL
        AND COALESCE(sb.branch_id, ?) = ?
      WHERE p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
      GROUP BY p.id
      ORDER BY p.created_at DESC
    ''',
      [..._currentBranchArgs, ..._currentBranchArgs],
    );
  }

  static Future<Map<String, dynamic>?> getPurchaseDetails(
    String purchaseId,
  ) async {
    final purchases = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM purchase_invoices
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ''',
      [purchaseId, ..._currentBranchArgs],
    );
    if (purchases.isEmpty) {
      return null;
    }

    final purchase = purchases.first;
    final items = await DatabaseService.rawQuery(
      '''
      SELECT
        sb.*,
        pr.name as product_name,
        pr.unit as product_unit,
        pr.stock_unit,
        pr.purchase_unit
      FROM stock_batches sb
      JOIN products pr ON pr.id = sb.product_id
      WHERE sb.purchase_id = ?
        AND sb.deleted_at IS NULL
        AND COALESCE(sb.branch_id, ?) = ?
      ORDER BY sb.received_at ASC
      ''',
      [purchaseId, ..._currentBranchArgs],
    );

    return {...purchase, 'items': items};
  }

  static Future<String> createPurchase({
    String? supplierId,
    String? supplierName,
    String? invoiceNumber,
    double amountPaid = 0,
    String? dueDate,
    String? note,
    required List<Map<String, dynamic>> items,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'record purchases');
    if (items.isEmpty) {
      throw Exception('Add at least one product to the purchase');
    }

    final cleanedItems = <Map<String, dynamic>>[];
    double totalAmount = 0.0;

    for (final item in items) {
      final productId = item['product_id'] as String?;
      final quantity = (item['quantity'] as num? ?? 0).toDouble();
      final unitCost = (item['unit_cost'] as num? ?? 0).toDouble();
      final productRows = await DatabaseService.rawQuery(
        '''
        SELECT *
        FROM products
        WHERE id = ?
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        LIMIT 1
        ''',
        [
          productId ?? '',
          DatabaseService.defaultBranchId,
          DatabaseService.currentBranchId,
        ],
      );
      final product = productRows.isEmpty ? null : productRows.first;
      if (product == null) {
        throw Exception('Product not found for purchase line');
      }
      final unit = UnitUtils.normalize(
        item['unit'] as String? ?? UnitUtils.purchaseUnitForProduct(product),
      );
      final stockUnit = UnitUtils.stockUnitForProduct(product);
      final convertedQuantity =
          UnitUtils.convertQuantity(quantity, unit, stockUnit) ?? quantity;
      final convertedUnitCost = convertedQuantity > 0
          ? ((quantity * unitCost) / convertedQuantity)
          : unitCost;

      if (productId == null || productId.isEmpty) {
        throw Exception('Each purchase line needs a product');
      }
      if (quantity <= 0) {
        throw Exception('Purchase quantities must be greater than zero');
      }
      if (unitCost < 0) {
        throw Exception('Unit cost cannot be negative');
      }

      cleanedItems.add({
        'product_id': productId,
        'purchase_quantity': quantity,
        'quantity': convertedQuantity,
        'purchase_unit_cost': unitCost,
        'unit_cost': convertedUnitCost,
        'unit': unit,
        'stock_unit': stockUnit,
        'batch_number': (item['batch_number'] as String?)?.trim(),
        'expiry_date': ExpiryUtils.toStorageString(
          ExpiryUtils.parse(item['expiry_date']),
        ),
      });
      totalAmount += quantity * unitCost;
    }

    final purchaseId = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final cleanAmountPaid = amountPaid.clamp(0, totalAmount).toDouble();
    final balanceDue = (totalAmount - cleanAmountPaid).clamp(0, totalAmount);
    final status = balanceDue <= 0.009
        ? 'paid'
        : cleanAmountPaid > 0.009
        ? 'partial'
        : 'unpaid';

    await DatabaseService.db.transaction((txn) async {
      await txn.insert('purchase_invoices', {
        'id': purchaseId,
        'branch_id': DatabaseService.currentBranchId,
        'supplier_id': supplierId,
        'supplier_name': supplierName?.trim(),
        'invoice_number': invoiceNumber?.trim(),
        'total_amount': totalAmount,
        'amount_paid': cleanAmountPaid,
        'balance_due': balanceDue,
        'due_date': dueDate?.trim(),
        'status': status,
        'note': note?.trim(),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      if (cleanAmountPaid > 0 && (supplierId?.trim().isNotEmpty ?? false)) {
        await txn.insert('supplier_payments', {
          'id': _uuid.v4(),
          'branch_id': DatabaseService.currentBranchId,
          'supplier_id': supplierId,
          'purchase_id': purchaseId,
          'amount': cleanAmountPaid,
          'payment_method': 'cash',
          'reference': invoiceNumber?.trim(),
          'note': 'Initial purchase payment',
          'paid_at': now,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });
      }

      for (final item in cleanedItems) {
        await txn.insert('stock_batches', {
          'id': _uuid.v4(),
          'product_id': item['product_id'],
          'branch_id': DatabaseService.currentBranchId,
          'batch_number': item['batch_number'],
          'quantity_received': item['quantity'],
          'quantity_remaining': item['quantity'],
          'unit_cost': item['unit_cost'],
          'purchase_id': purchaseId,
          'supplier_id': supplierId,
          'expiry_date': item['expiry_date'],
          'received_at': now,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });

        await txn.rawUpdate(
          '''
          UPDATE products
          SET
            stock = stock + ?,
            cost = ?,
            updated_at = ?,
            sync_status = ?
          WHERE id = ?
            AND COALESCE(branch_id, ?) = ?
          ''',
          [
            item['quantity'],
            item['unit_cost'],
            now,
            'pending',
            item['product_id'],
            DatabaseService.defaultBranchId,
            DatabaseService.currentBranchId,
          ],
        );
      }
    });

    await AuditLogService.log(
      action: 'create',
      entityTable: 'purchase_invoices',
      entityId: purchaseId,
    );
    return purchaseId;
  }

  static Future<String> recordSupplierPayment({
    required String supplierId,
    String? purchaseId,
    required double amount,
    String paymentMethod = 'cash',
    String? reference,
    String? note,
    DateTime? paidAt,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'record supplier payments');
    final cleanSupplierId = supplierId.trim();
    if (cleanSupplierId.isEmpty) {
      throw Exception('Choose a supplier');
    }
    if (amount <= 0) {
      throw Exception('Payment amount must be greater than zero');
    }

    final now = DateTime.now().toIso8601String();
    final paidAtText = (paidAt ?? DateTime.now()).toIso8601String();
    final paymentId = _uuid.v4();
    await DatabaseService.db.transaction((txn) async {
      await txn.insert('supplier_payments', {
        'id': paymentId,
        'branch_id': DatabaseService.currentBranchId,
        'supplier_id': cleanSupplierId,
        'purchase_id': purchaseId?.trim(),
        'amount': amount,
        'payment_method': paymentMethod.trim().isEmpty
            ? 'cash'
            : paymentMethod.trim(),
        'reference': reference?.trim(),
        'note': note?.trim(),
        'paid_at': paidAtText,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      if (purchaseId != null && purchaseId.trim().isNotEmpty) {
        final purchases = await txn.query(
          'purchase_invoices',
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [purchaseId.trim()],
          limit: 1,
        );
        if (purchases.isNotEmpty) {
          final purchase = purchases.first;
          final total = (purchase['total_amount'] as num? ?? 0).toDouble();
          final currentPaid = (purchase['amount_paid'] as num? ?? 0).toDouble();
          final nextPaid = (currentPaid + amount).clamp(0, total).toDouble();
          final balance = (total - nextPaid).clamp(0, total).toDouble();
          final status = balance <= 0.009
              ? 'paid'
              : nextPaid > 0.009
              ? 'partial'
              : 'unpaid';
          await txn.update(
            'purchase_invoices',
            {
              'amount_paid': nextPaid,
              'balance_due': balance,
              'status': status,
              'updated_at': now,
              'sync_status': 'pending',
            },
            where: 'id = ?',
            whereArgs: [purchaseId.trim()],
          );
        }
      } else {
        var remaining = amount;
        final purchases = await txn.query(
          'purchase_invoices',
          where:
              'supplier_id = ? AND deleted_at IS NULL AND balance_due > 0.009 AND COALESCE(branch_id, ?) = ?',
          whereArgs: [cleanSupplierId, ..._currentBranchArgs],
          orderBy: 'created_at ASC',
        );
        for (final purchase in purchases) {
          if (remaining <= 0.009) {
            break;
          }
          final total = (purchase['total_amount'] as num? ?? 0).toDouble();
          final currentPaid = (purchase['amount_paid'] as num? ?? 0).toDouble();
          final balance = (purchase['balance_due'] as num? ?? 0).toDouble();
          final applied = remaining > balance ? balance : remaining;
          final nextPaid = (currentPaid + applied).clamp(0, total).toDouble();
          final nextBalance = (total - nextPaid).clamp(0, total).toDouble();
          final status = nextBalance <= 0.009 ? 'paid' : 'partial';
          await txn.update(
            'purchase_invoices',
            {
              'amount_paid': nextPaid,
              'balance_due': nextBalance,
              'status': status,
              'updated_at': now,
              'sync_status': 'pending',
            },
            where: 'id = ?',
            whereArgs: [purchase['id']],
          );
          remaining -= applied;
        }
      }
    });

    await AuditLogService.log(
      action: 'create',
      entityTable: 'supplier_payments',
      entityId: paymentId,
    );
    return paymentId;
  }

  static Future<List<Map<String, dynamic>>> getSupplierLedger(
    String supplierId,
  ) async {
    final cleanSupplierId = supplierId.trim();
    if (cleanSupplierId.isEmpty) {
      return const [];
    }
    return DatabaseService.rawQuery(
      '''
      SELECT
        'purchase' as entry_type,
        id,
        invoice_number as reference,
        total_amount as debit,
        amount_paid as credit,
        balance_due,
        status,
        created_at as entry_at,
        note
      FROM purchase_invoices
      WHERE supplier_id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      UNION ALL
      SELECT
        'payment' as entry_type,
        id,
        reference,
        0 as debit,
        amount as credit,
        0 as balance_due,
        'paid' as status,
        paid_at as entry_at,
        note
      FROM supplier_payments
      WHERE supplier_id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY entry_at DESC
      ''',
      [
        cleanSupplierId,
        ..._currentBranchArgs,
        cleanSupplierId,
        ..._currentBranchArgs,
      ],
    );
  }

  static Future<Map<String, dynamic>> getSupplierStatement(
    String supplierId,
  ) async {
    final cleanSupplierId = supplierId.trim();
    if (cleanSupplierId.isEmpty) {
      throw Exception('Supplier is required');
    }
    final supplierRows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM suppliers
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [cleanSupplierId, ..._currentBranchArgs],
    );
    if (supplierRows.isEmpty) {
      throw Exception('Supplier not found');
    }

    final ledgerRows = await DatabaseService.rawQuery(
      '''
      SELECT
        'purchase' as entry_type,
        id,
        invoice_number as reference,
        total_amount as debit,
        0 as credit,
        balance_due,
        due_date,
        status,
        created_at as entry_at,
        note
      FROM purchase_invoices
      WHERE supplier_id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      UNION ALL
      SELECT
        'payment' as entry_type,
        id,
        reference,
        0 as debit,
        amount as credit,
        0 as balance_due,
        NULL as due_date,
        'paid' as status,
        paid_at as entry_at,
        note
      FROM supplier_payments
      WHERE supplier_id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY entry_at ASC, entry_type ASC
      ''',
      [
        cleanSupplierId,
        ..._currentBranchArgs,
        cleanSupplierId,
        ..._currentBranchArgs,
      ],
    );

    var runningBalance = 0.0;
    final ledger = <Map<String, dynamic>>[];
    for (final row in ledgerRows) {
      final debit = (row['debit'] as num? ?? 0).toDouble();
      final credit = (row['credit'] as num? ?? 0).toDouble();
      runningBalance += debit - credit;
      ledger.add({...row, 'running_balance': runningBalance});
    }

    final agingRows = await DatabaseService.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE
          WHEN due_date IS NULL OR TRIM(due_date) = '' OR date(due_date) >= date('now', 'localtime')
          THEN balance_due ELSE 0 END), 0) AS current_amount,
        COALESCE(SUM(CASE
          WHEN date(due_date) < date('now', 'localtime')
           AND julianday('now', 'localtime') - julianday(due_date) BETWEEN 1 AND 30
          THEN balance_due ELSE 0 END), 0) AS d1_30_amount,
        COALESCE(SUM(CASE
          WHEN julianday('now', 'localtime') - julianday(due_date) BETWEEN 31 AND 60
          THEN balance_due ELSE 0 END), 0) AS d31_60_amount,
        COALESCE(SUM(CASE
          WHEN julianday('now', 'localtime') - julianday(due_date) BETWEEN 61 AND 90
          THEN balance_due ELSE 0 END), 0) AS d61_90_amount,
        COALESCE(SUM(CASE
          WHEN julianday('now', 'localtime') - julianday(due_date) > 90
          THEN balance_due ELSE 0 END), 0) AS over90_amount,
        COALESCE(SUM(balance_due), 0) AS total_outstanding,
        COUNT(CASE WHEN balance_due > 0.009 THEN 1 END) AS open_invoice_count
      FROM purchase_invoices
      WHERE supplier_id = ?
        AND deleted_at IS NULL
        AND balance_due > 0.009
        AND COALESCE(branch_id, ?) = ?
      ''',
      [cleanSupplierId, ..._currentBranchArgs],
    );

    final openInvoices = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM purchase_invoices
      WHERE supplier_id = ?
        AND deleted_at IS NULL
        AND balance_due > 0.009
        AND COALESCE(branch_id, ?) = ?
      ORDER BY
        CASE WHEN due_date IS NULL OR TRIM(due_date) = '' THEN 1 ELSE 0 END,
        due_date ASC,
        created_at ASC
      ''',
      [cleanSupplierId, ..._currentBranchArgs],
    );

    return {
      'supplier': supplierRows.first,
      'ledger': ledger,
      'aging': agingRows.isEmpty ? <String, dynamic>{} : agingRows.first,
      'open_invoices': openInvoices,
    };
  }

  static Future<List<Map<String, dynamic>>> getSupplierAging() {
    return DatabaseService.rawQuery(
      '''
      SELECT
        s.id,
        s.name,
        s.phone,
        s.email,
        COALESCE(SUM(CASE
          WHEN p.due_date IS NULL OR TRIM(p.due_date) = '' OR date(p.due_date) >= date('now', 'localtime')
          THEN p.balance_due ELSE 0 END), 0) AS current_amount,
        COALESCE(SUM(CASE
          WHEN date(p.due_date) < date('now', 'localtime')
           AND julianday('now', 'localtime') - julianday(p.due_date) BETWEEN 1 AND 30
          THEN p.balance_due ELSE 0 END), 0) AS d1_30_amount,
        COALESCE(SUM(CASE
          WHEN julianday('now', 'localtime') - julianday(p.due_date) BETWEEN 31 AND 60
          THEN p.balance_due ELSE 0 END), 0) AS d31_60_amount,
        COALESCE(SUM(CASE
          WHEN julianday('now', 'localtime') - julianday(p.due_date) BETWEEN 61 AND 90
          THEN p.balance_due ELSE 0 END), 0) AS d61_90_amount,
        COALESCE(SUM(CASE
          WHEN julianday('now', 'localtime') - julianday(p.due_date) > 90
          THEN p.balance_due ELSE 0 END), 0) AS over90_amount,
        COALESCE(SUM(p.balance_due), 0) AS total_outstanding,
        COUNT(p.id) AS open_invoice_count
      FROM suppliers s
      JOIN purchase_invoices p ON p.supplier_id = s.id
        AND p.deleted_at IS NULL
        AND p.balance_due > 0.009
        AND COALESCE(p.branch_id, ?) = ?
      WHERE s.deleted_at IS NULL
        AND COALESCE(s.branch_id, ?) = ?
      GROUP BY s.id
      ORDER BY total_outstanding DESC, s.name ASC
      ''',
      [..._currentBranchArgs, ..._currentBranchArgs],
    );
  }

  static Future<List<Map<String, dynamic>>> getPurchaseOrders() {
    return DatabaseService.rawQuery('''
      SELECT *
      FROM purchase_orders
      WHERE deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY created_at DESC
      ''', _currentBranchArgs);
  }

  static Future<Map<String, dynamic>?> getPurchaseOrderDetails(
    String orderId,
  ) async {
    final orders = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM purchase_orders
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [orderId, ..._currentBranchArgs],
    );
    if (orders.isEmpty) {
      return null;
    }
    final items = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM purchase_order_items
      WHERE purchase_order_id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY created_at ASC
      ''',
      [orderId, ..._currentBranchArgs],
    );
    return {...orders.first, 'items': items};
  }

  static Future<String> createPurchaseOrder({
    String? supplierId,
    String? supplierName,
    String? orderNumber,
    String? expectedOn,
    String? note,
    required List<Map<String, dynamic>> items,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'create purchase orders');
    if (items.isEmpty) {
      throw Exception('Add at least one product to the purchase order');
    }

    final cleanedItems = <Map<String, dynamic>>[];
    double totalAmount = 0;
    for (final item in items) {
      final productId = (item['product_id'] as String?)?.trim();
      final quantity = (item['quantity'] as num? ?? 0).toDouble();
      final unitCost = (item['unit_cost'] as num? ?? 0).toDouble();
      if (productId == null || productId.isEmpty || quantity <= 0) {
        throw Exception(
          'Each purchase order line needs a product and quantity',
        );
      }
      if (unitCost < 0) {
        throw Exception('Unit cost cannot be negative');
      }
      final productRows = await DatabaseService.rawQuery(
        '''
        SELECT name, purchase_unit, unit
        FROM products
        WHERE id = ?
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        LIMIT 1
        ''',
        [productId, ..._currentBranchArgs],
      );
      if (productRows.isEmpty) {
        throw Exception('Product not found for purchase order line');
      }
      final product = productRows.first;
      final lineTotal = quantity * unitCost;
      totalAmount += lineTotal;
      cleanedItems.add({
        'product_id': productId,
        'product_name': product['name'] as String? ?? 'Product',
        'quantity': quantity,
        'unit': UnitUtils.normalize(
          item['unit'] as String? ??
              (product['purchase_unit'] as String?) ??
              (product['unit'] as String?) ??
              'pcs',
        ),
        'unit_cost': unitCost,
        'line_total': lineTotal,
      });
    }

    final now = DateTime.now().toIso8601String();
    final orderId = _uuid.v4();
    await DatabaseService.db.transaction((txn) async {
      await txn.insert('purchase_orders', {
        'id': orderId,
        'branch_id': DatabaseService.currentBranchId,
        'supplier_id': supplierId?.trim(),
        'supplier_name': supplierName?.trim(),
        'order_number': orderNumber?.trim(),
        'status': 'draft',
        'total_amount': totalAmount,
        'expected_on': expectedOn?.trim(),
        'note': note?.trim(),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      for (final item in cleanedItems) {
        await txn.insert('purchase_order_items', {
          'id': _uuid.v4(),
          'branch_id': DatabaseService.currentBranchId,
          'purchase_order_id': orderId,
          'product_id': item['product_id'],
          'product_name': item['product_name'],
          'quantity': item['quantity'],
          'unit': item['unit'],
          'unit_cost': item['unit_cost'],
          'line_total': item['line_total'],
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });
      }
    });

    await AuditLogService.log(
      action: 'create',
      entityTable: 'purchase_orders',
      entityId: orderId,
    );
    return orderId;
  }

  static Future<String> receivePurchaseOrder(String orderId) async {
    await LicenseService.ensureWriteAccess(action: 'receive purchase orders');
    final details = await getPurchaseOrderDetails(orderId);
    if (details == null) {
      throw Exception('Purchase order not found');
    }
    final status = details['status']?.toString();
    if (status == 'received') {
      throw Exception('Purchase order is already received');
    }
    final rawItems = details['items'] as List? ?? const [];
    final items = rawItems
        .whereType<Map>()
        .map(
          (item) => {
            'product_id': item['product_id'],
            'quantity': item['quantity'],
            'unit': item['unit'],
            'unit_cost': item['unit_cost'],
          },
        )
        .toList();
    final purchaseId = await createPurchase(
      supplierId: details['supplier_id'] as String?,
      supplierName: details['supplier_name'] as String?,
      invoiceNumber: details['order_number'] as String?,
      note:
          'Received from purchase order ${details['order_number'] ?? orderId}',
      items: items,
    );
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update('purchase_orders', {
      'status': 'received',
      'updated_at': now,
      'sync_status': 'pending',
    }, orderId);
    return purchaseId;
  }

  static Future<List<Map<String, dynamic>>>
  getPendingApprovals() => DatabaseService.rawQuery(
    'SELECT * FROM purchase_orders WHERE status = \'pending_approval\' AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY submitted_at ASC',
    _currentBranchArgs,
  );
  static Future<void> submitPurchaseOrder(
    String orderId, {
    double threshold = 50000,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'submit purchase orders');
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update('purchase_orders', {
      'approval_required': 1,
      'status': 'pending_approval',
      'submitted_by': SessionService.currentUserId,
      'submitted_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    }, orderId);
  }

  static Future<void> decidePurchaseOrder(
    String orderId, {
    required bool approved,
    String? note,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'approve purchase orders');
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update('purchase_orders', {
      'status': approved ? 'approved' : 'rejected',
      'approved_by': SessionService.currentUserId,
      'approved_at': now,
      'approval_note': note?.trim(),
      'updated_at': now,
      'sync_status': 'pending',
    }, orderId);
  }
}
