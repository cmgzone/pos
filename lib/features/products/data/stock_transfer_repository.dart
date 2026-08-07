import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

class StockTransferRepository {
  static const _table = 'stock_transfers';

  static Future<List<Map<String, dynamic>>> getForCurrentBranch({
    String status = 'all',
  }) async {
    final clauses = <String>[
      'st.deleted_at IS NULL',
      '(st.from_branch_id = ? OR st.to_branch_id = ?)',
    ];
    final args = <dynamic>[
      DatabaseService.currentBranchId,
      DatabaseService.currentBranchId,
    ];
    final cleanStatus = status.trim();
    if (cleanStatus.isNotEmpty && cleanStatus != 'all') {
      clauses.add('st.status = ?');
      args.add(cleanStatus);
    }

    return DatabaseService.rawQuery('''
      SELECT st.*, fb.name AS from_branch_name, tb.name AS to_branch_name
      FROM $_table st
      LEFT JOIN branches fb ON fb.id = st.from_branch_id
      LEFT JOIN branches tb ON tb.id = st.to_branch_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY st.created_at DESC
      ''', args);
  }

  static Future<String> requestTransfer({
    required String toBranchId,
    required String productId,
    required double quantity,
    String? note,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'request stock transfers');
    final cleanToBranchId = toBranchId.trim();
    if (cleanToBranchId.isEmpty) {
      throw Exception('Choose a destination branch');
    }
    if (cleanToBranchId == DatabaseService.currentBranchId) {
      throw Exception('Choose a different destination branch');
    }
    if (quantity <= 0) {
      throw Exception('Transfer quantity must be greater than zero');
    }

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
        productId,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
      ],
    );
    if (productRows.isEmpty) {
      throw Exception('Product not found in the current branch');
    }
    final product = productRows.first;
    final stock = (product['stock'] as num? ?? 0).toDouble();
    if (stock + 0.001 < quantity) {
      throw Exception('Not enough stock in this branch');
    }

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await DatabaseService.insert(_table, {
      'id': id,
      'branch_id': DatabaseService.currentBranchId,
      'from_branch_id': DatabaseService.currentBranchId,
      'to_branch_id': cleanToBranchId,
      'product_id': productId,
      'product_name': product['name'] as String? ?? 'Product',
      'quantity': quantity,
      'unit': UnitUtils.stockUnitForProduct(product),
      'status': 'requested',
      'requested_by': SessionService.currentUserId,
      'note': note?.trim(),
      'requested_at': now,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    await AuditLogService.log(
      action: 'request',
      entityTable: _table,
      entityId: id,
    );
    return id;
  }

  /// Lets the current branch ask another branch for stock it does not have.
  /// The source branch approves the request, then this branch receives it.
  static Future<String> requestStockIn({
    required String fromBranchId,
    required String productId,
    required double quantity,
    String? note,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'request stock transfers');
    final cleanFromBranchId = fromBranchId.trim();
    if (cleanFromBranchId.isEmpty) {
      throw Exception('Choose the branch to request stock from');
    }
    if (cleanFromBranchId == DatabaseService.currentBranchId) {
      throw Exception('Choose a different branch to request stock from');
    }
    if (quantity <= 0) {
      throw Exception('Requested quantity must be greater than zero');
    }

    final productRows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM products
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [productId, DatabaseService.defaultBranchId, cleanFromBranchId],
    );
    if (productRows.isEmpty) {
      throw Exception('Product not found in the selected branch');
    }
    final product = productRows.first;

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await DatabaseService.insert(_table, {
      'id': id,
      'branch_id': DatabaseService.currentBranchId,
      'from_branch_id': cleanFromBranchId,
      'to_branch_id': DatabaseService.currentBranchId,
      'product_id': productId,
      'product_name': product['name'] as String? ?? 'Product',
      'quantity': quantity,
      'unit': UnitUtils.stockUnitForProduct(product),
      'status': 'requested',
      'requested_by': SessionService.currentUserId,
      'note': note?.trim(),
      'requested_at': now,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    await AuditLogService.log(
      action: 'request',
      entityTable: _table,
      entityId: id,
    );
    return id;
  }

  static Future<void> updateStatus(
    String id, {
    required String status,
    String? note,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'update stock transfers');
    final cleanStatus = status.trim();
    if (!{'approved', 'received', 'cancelled'}.contains(cleanStatus)) {
      throw Exception('Unsupported transfer status');
    }

    if (cleanStatus == 'received') {
      await _receiveTransfer(id, note: note);
      return;
    }

    final now = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'status': cleanStatus,
      'note': note?.trim(),
      'updated_at': now,
      'sync_status': 'pending',
    };
    if (cleanStatus == 'approved') {
      payload['approved_by'] = SessionService.currentUserId;
      payload['approved_at'] = now;
    }

    await DatabaseService.update(_table, payload, id);
    await AuditLogService.log(
      action: cleanStatus == 'approved' ? 'approve' : 'cancel',
      entityTable: _table,
      entityId: id,
      branchId: DatabaseService.currentBranchId,
    );
  }

  static Future<void> _receiveTransfer(String id, {String? note}) async {
    final database = DatabaseService.db;
    final now = DateTime.now().toIso8601String();
    String? autoCreatedProductId;

    await database.transaction((txn) async {
      final transferRows = await txn.query(
        _table,
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
        limit: 1,
      );
      if (transferRows.isEmpty) {
        throw Exception('Transfer not found');
      }
      final transfer = Map<String, dynamic>.from(transferRows.first);
      final status = transfer['status'] as String? ?? 'requested';
      if (status != 'approved') {
        throw Exception('Only approved transfers can be received');
      }

      final toBranchId = transfer['to_branch_id'] as String? ?? '';
      if (toBranchId != DatabaseService.currentBranchId) {
        throw Exception('Switch to the destination branch before receiving');
      }

      final fromBranchId = transfer['from_branch_id'] as String? ?? '';
      final sourceProductId = transfer['product_id'] as String? ?? '';
      final quantity = (transfer['quantity'] as num? ?? 0).toDouble();
      if (fromBranchId.isEmpty || sourceProductId.isEmpty || quantity <= 0) {
        throw Exception('Transfer details are incomplete');
      }

      final sourceProduct = await _findSourceProduct(
        txn,
        productId: sourceProductId,
        branchId: fromBranchId,
      );
      if (sourceProduct == null) {
        throw Exception('Source branch product was not found');
      }
      final sourceStock = (sourceProduct['stock'] as num? ?? 0).toDouble();
      if (sourceStock + 0.001 < quantity) {
        throw Exception('Source branch no longer has enough stock');
      }

      var destinationProduct = await _findDestinationProduct(
        txn,
        sourceProduct: sourceProduct,
        branchId: toBranchId,
      );
      if (destinationProduct == null) {
        destinationProduct = await _createDestinationProduct(
          txn,
          sourceProduct: sourceProduct,
          branchId: toBranchId,
          now: now,
        );
        autoCreatedProductId = destinationProduct['id'] as String;
      }

      final sourceUnit = UnitUtils.stockUnitForProduct(sourceProduct);
      final destinationUnit = UnitUtils.stockUnitForProduct(destinationProduct);
      final destinationQuantity =
          UnitUtils.convertQuantity(quantity, sourceUnit, destinationUnit) ??
          quantity;
      final avgUnitCost = await _decrementSourceBatches(
        txn,
        productId: sourceProductId,
        branchId: fromBranchId,
        quantity: quantity,
        fallbackUnitCost: (sourceProduct['cost'] as num? ?? 0).toDouble(),
        now: now,
      );
      final destinationUnitCost = destinationQuantity > 0
          ? (quantity * avgUnitCost) / destinationQuantity
          : avgUnitCost;
      final destinationProductId = destinationProduct['id'] as String;

      await txn.rawUpdate(
        '''
        UPDATE products
        SET stock = MAX(stock - ?, 0),
            updated_at = ?,
            sync_status = 'pending'
        WHERE id = ?
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        ''',
        [
          quantity,
          now,
          sourceProductId,
          DatabaseService.defaultBranchId,
          fromBranchId,
        ],
      );
      await txn.insert('stock_batches', {
        'id': _uuid.v4(),
        'branch_id': toBranchId,
        'product_id': destinationProductId,
        'batch_number': 'Transfer ${id.substring(0, 8)}',
        'quantity_received': destinationQuantity,
        'quantity_remaining': destinationQuantity,
        'unit_cost': destinationUnitCost,
        'received_at': now,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      await txn.rawUpdate(
        '''
        UPDATE products
        SET stock = stock + ?,
            cost = ?,
            updated_at = ?,
            sync_status = 'pending'
        WHERE id = ?
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        ''',
        [
          destinationQuantity,
          destinationUnitCost,
          now,
          destinationProductId,
          DatabaseService.defaultBranchId,
          toBranchId,
        ],
      );
      await txn.update(
        _table,
        {
          'status': 'received',
          'received_by': SessionService.currentUserId,
          'received_at': now,
          'note': note?.trim(),
          'updated_at': now,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });

    await AuditLogService.log(
      action: 'receive',
      entityTable: _table,
      entityId: id,
      branchId: DatabaseService.currentBranchId,
    );
    if (autoCreatedProductId != null) {
      await AuditLogService.log(
        action: 'create',
        entityTable: 'products',
        entityId: autoCreatedProductId,
        branchId: DatabaseService.currentBranchId,
      );
    }
    await AuditLogService.log(
      action: 'transfer_stock_out',
      entityTable: 'products',
      entityId: id,
    );
    await AuditLogService.log(
      action: 'transfer_stock_in',
      entityTable: 'products',
      entityId: id,
      branchId: DatabaseService.currentBranchId,
    );
  }

  static Future<Map<String, dynamic>?> _findSourceProduct(
    dynamic txn, {
    required String productId,
    required String branchId,
  }) async {
    final rows = await txn.rawQuery(
      '''
      SELECT *
      FROM products
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [productId, DatabaseService.defaultBranchId, branchId],
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  static Future<Map<String, dynamic>?> _findDestinationProduct(
    dynamic txn, {
    required Map<String, dynamic> sourceProduct,
    required String branchId,
  }) async {
    final barcode = (sourceProduct['barcode'] as String? ?? '').trim();
    if (barcode.isNotEmpty) {
      final rows = await txn.rawQuery(
        '''
        SELECT *
        FROM products
        WHERE deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
          AND TRIM(barcode) = ?
        LIMIT 1
        ''',
        [DatabaseService.defaultBranchId, branchId, barcode],
      );
      if (rows.isNotEmpty) return Map<String, dynamic>.from(rows.first);
    }

    final sku = (sourceProduct['sku'] as String? ?? '').trim();
    if (sku.isNotEmpty) {
      final rows = await txn.rawQuery(
        '''
        SELECT *
        FROM products
        WHERE deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
          AND LOWER(TRIM(sku)) = LOWER(?)
        LIMIT 1
        ''',
        [DatabaseService.defaultBranchId, branchId, sku],
      );
      if (rows.isNotEmpty) return Map<String, dynamic>.from(rows.first);
    }

    final name = (sourceProduct['name'] as String? ?? '').trim();
    if (name.isEmpty) {
      return null;
    }
    final rows = await txn.rawQuery(
      '''
      SELECT *
      FROM products
      WHERE deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
        AND LOWER(TRIM(name)) = LOWER(?)
      LIMIT 1
      ''',
      [DatabaseService.defaultBranchId, branchId, name],
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  /// Copies the source product into the destination branch so a transfer can
  /// be received even when the branch has never stocked the item before.
  static Future<Map<String, dynamic>> _createDestinationProduct(
    dynamic txn, {
    required Map<String, dynamic> sourceProduct,
    required String branchId,
    required String now,
  }) async {
    final id = _uuid.v4();
    final unit = (sourceProduct['unit'] as String? ?? '').trim().isEmpty
        ? 'pcs'
        : sourceProduct['unit'] as String;
    final row = <String, dynamic>{
      'id': id,
      'branch_id': branchId,
      'name': sourceProduct['name'] as String? ?? 'Product',
      'price': sourceProduct['price'] ?? 0,
      'cost': sourceProduct['cost'],
      'stock': 0,
      'low_stock': sourceProduct['low_stock'] ?? 0,
      'unit': unit,
      'stock_unit': sourceProduct['stock_unit'] ?? unit,
      'sale_unit': sourceProduct['sale_unit'] ?? unit,
      'sale_to_stock_factor': sourceProduct['sale_to_stock_factor'] ?? 1,
      'purchase_unit': sourceProduct['purchase_unit'] ?? unit,
      'purchase_to_stock_factor':
          sourceProduct['purchase_to_stock_factor'] ?? 1,
      'sku': sourceProduct['sku'],
      'barcode': sourceProduct['barcode'],
      'image_url': sourceProduct['image_url'],
      'brand': sourceProduct['brand'],
      'description': sourceProduct['description'],
      'image_urls_json': sourceProduct['image_urls_json'],
      'show_online': sourceProduct['show_online'] ?? 1,
      'is_featured': sourceProduct['is_featured'] ?? 0,
      'category_id': await _matchingCategoryId(
        txn,
        sourceProduct: sourceProduct,
        branchId: branchId,
      ),
      'track_stock': sourceProduct['track_stock'] ?? 1,
      'has_variants': 0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    };
    if (sourceProduct.containsKey('is_restaurant_menu')) {
      row['is_restaurant_menu'] = sourceProduct['is_restaurant_menu'] ?? 0;
    }
    await txn.insert('products', row);
    return row;
  }

  /// Categories are branch-scoped, so the source category is only carried
  /// over when the destination branch has a category with the same name.
  static Future<String?> _matchingCategoryId(
    dynamic txn, {
    required Map<String, dynamic> sourceProduct,
    required String branchId,
  }) async {
    final sourceCategoryId =
        (sourceProduct['category_id'] as String? ?? '').trim();
    if (sourceCategoryId.isEmpty) return null;

    final sourceCategories = await txn.rawQuery(
      'SELECT name FROM categories WHERE id = ? AND deleted_at IS NULL LIMIT 1',
      [sourceCategoryId],
    );
    if (sourceCategories.isEmpty) return null;
    final name = (sourceCategories.first['name'] as String? ?? '').trim();
    if (name.isEmpty) return null;

    final rows = await txn.rawQuery(
      '''
      SELECT id
      FROM categories
      WHERE deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
        AND LOWER(TRIM(name)) = LOWER(?)
      LIMIT 1
      ''',
      [DatabaseService.defaultBranchId, branchId, name],
    );
    return rows.isEmpty ? null : rows.first['id'] as String?;
  }

  static Future<double> _decrementSourceBatches(
    dynamic txn, {
    required String productId,
    required String branchId,
    required double quantity,
    required double fallbackUnitCost,
    required String now,
  }) async {
    var remaining = quantity;
    var consumedCost = 0.0;
    final batches = await txn.rawQuery(
      '''
      SELECT id, quantity_remaining, unit_cost
      FROM stock_batches
      WHERE product_id = ?
        AND deleted_at IS NULL
        AND quantity_remaining > 0
        AND COALESCE(branch_id, ?) = ?
      ORDER BY
        CASE WHEN expiry_date IS NULL OR TRIM(expiry_date) = '' THEN 1 ELSE 0 END,
        date(expiry_date) ASC,
        received_at ASC
      ''',
      [productId, DatabaseService.defaultBranchId, branchId],
    );

    for (final row in batches) {
      if (remaining <= 0) break;
      final available = (row['quantity_remaining'] as num? ?? 0).toDouble();
      if (available <= 0) continue;
      final take = available < remaining ? available : remaining;
      final unitCost = (row['unit_cost'] as num? ?? fallbackUnitCost)
          .toDouble();
      consumedCost += take * unitCost;
      remaining -= take;
      await txn.rawUpdate(
        '''
        UPDATE stock_batches
        SET quantity_remaining = quantity_remaining - ?,
            finished_at = CASE WHEN quantity_remaining - ? <= 0 THEN ? ELSE finished_at END,
            updated_at = ?,
            sync_status = 'pending'
        WHERE id = ?
        ''',
        [take, take, now, now, row['id']],
      );
    }

    if (remaining > 0.001) {
      consumedCost += remaining * fallbackUnitCost;
    }
    return quantity > 0 ? consumedCost / quantity : fallbackUnitCost;
  }
}
