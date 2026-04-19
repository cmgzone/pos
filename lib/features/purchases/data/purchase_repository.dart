import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

class PurchaseRepository {
  static Future<List<Map<String, dynamic>>> getSuppliers() async {
    return DatabaseService.rawQuery('''
      SELECT
        s.*,
        COALESCE((
          SELECT COUNT(*)
          FROM purchase_invoices p
          WHERE p.supplier_id = s.id
        ), 0) as purchase_count,
        COALESCE((
          SELECT SUM(p.total_amount)
          FROM purchase_invoices p
          WHERE p.supplier_id = s.id
        ), 0) as total_spend
      FROM suppliers s
      ORDER BY s.name ASC
    ''');
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

    return id;
  }

  static Future<List<Map<String, dynamic>>> getPurchases() async {
    return DatabaseService.rawQuery('''
      SELECT
        p.*,
        COALESCE(COUNT(sb.id), 0) as item_lines,
        COALESCE(SUM(sb.quantity_received), 0) as total_quantity
      FROM purchase_invoices p
      LEFT JOIN stock_batches sb ON sb.purchase_id = p.id
      GROUP BY p.id
      ORDER BY p.created_at DESC
    ''');
  }

  static Future<Map<String, dynamic>?> getPurchaseDetails(
    String purchaseId,
  ) async {
    final purchases = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM purchase_invoices
      WHERE id = ?
      ''',
      [purchaseId],
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
      ORDER BY sb.received_at ASC
      ''',
      [purchaseId],
    );

    return {...purchase, 'items': items};
  }

  static Future<String> createPurchase({
    String? supplierId,
    String? supplierName,
    String? invoiceNumber,
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
      final product = await DatabaseService.queryById(
        'products',
        productId ?? '',
      );
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
      });
      totalAmount += quantity * unitCost;
    }

    final purchaseId = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    await DatabaseService.db.transaction((txn) async {
      await txn.insert('purchase_invoices', {
        'id': purchaseId,
        'supplier_id': supplierId,
        'supplier_name': supplierName?.trim(),
        'invoice_number': invoiceNumber?.trim(),
        'total_amount': totalAmount,
        'note': note?.trim(),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      for (final item in cleanedItems) {
        await txn.insert('stock_batches', {
          'id': _uuid.v4(),
          'product_id': item['product_id'],
          'quantity_received': item['quantity'],
          'quantity_remaining': item['quantity'],
          'unit_cost': item['unit_cost'],
          'purchase_id': purchaseId,
          'supplier_id': supplierId,
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
          ''',
          [
            item['quantity'],
            item['unit_cost'],
            now,
            'pending',
            item['product_id'],
          ],
        );
      }
    });

    return purchaseId;
  }
}
