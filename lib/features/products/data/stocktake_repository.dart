import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

class StocktakeRepository {
  static const sessionsTable = 'stocktake_sessions';
  static const itemsTable = 'stocktake_items';

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<List<Map<String, dynamic>>> getSessions({
    String status = 'all',
  }) {
    final where = <String>[
      's.deleted_at IS NULL',
      'COALESCE(s.branch_id, ?) = ?',
    ];
    final args = <dynamic>[..._currentBranchArgs];
    if (status.trim().isNotEmpty && status != 'all') {
      where.add('s.status = ?');
      args.add(status.trim());
    }
    return DatabaseService.rawQuery('''
      SELECT s.*,
             COUNT(i.id) AS item_count,
             SUM(CASE WHEN i.status = 'counted' THEN 1 ELSE 0 END) AS counted_count,
             COALESCE(SUM(ABS(COALESCE(i.variance_qty, 0))), 0) AS total_variance
      FROM $sessionsTable s
      LEFT JOIN $itemsTable i
        ON i.session_id = s.id
       AND i.deleted_at IS NULL
      WHERE ${where.join(' AND ')}
      GROUP BY s.id
      ORDER BY s.updated_at DESC, s.created_at DESC
      ''', args);
  }

  static Future<Map<String, dynamic>?> getSession(String sessionId) async {
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM $sessionsTable
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [sessionId, ..._currentBranchArgs],
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, dynamic>>> getItems(
    String sessionId, {
    String? search,
  }) {
    final where = <String>[
      'si.session_id = ?',
      'si.deleted_at IS NULL',
      'COALESCE(si.branch_id, ?) = ?',
    ];
    final args = <dynamic>[sessionId, ..._currentBranchArgs];
    final cleanSearch = search?.trim() ?? '';
    if (cleanSearch.isNotEmpty) {
      where.add('(si.product_name LIKE ? OR p.barcode LIKE ? OR p.sku LIKE ?)');
      final like = '%$cleanSearch%';
      args.addAll([like, like, like]);
    }
    return DatabaseService.rawQuery('''
      SELECT si.*, p.barcode, p.sku, p.image_url
      FROM $itemsTable si
      LEFT JOIN products p ON p.id = si.product_id
      WHERE ${where.join(' AND ')}
      ORDER BY
        CASE si.status WHEN 'pending' THEN 0 ELSE 1 END,
        si.product_name ASC
      ''', args);
  }

  static Future<String> createSession({String? name, String? note}) async {
    await _ensureWriteAccess('start stocktake');
    final now = DateTime.now().toIso8601String();
    final sessionId = _uuid.v4();
    final title = (name?.trim().isNotEmpty == true)
        ? name!.trim()
        : 'Stocktake ${DateTime.now().toString().substring(0, 10)}';
    final products = await DatabaseService.rawQuery('''
      SELECT id, name, stock, stock_unit, unit, cost
      FROM products
      WHERE deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
        AND COALESCE(track_stock, 1) <> 0
        AND COALESCE(has_variants, 0) = 0
      ORDER BY name ASC
      ''', _currentBranchArgs);

    await DatabaseService.db.transaction((txn) async {
      await txn.insert(sessionsTable, {
        'id': sessionId,
        'branch_id': DatabaseService.currentBranchId,
        'name': title,
        'status': 'draft',
        'started_by': SessionService.currentUserId,
        'started_at': now,
        'note': _clean(note),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      for (final product in products) {
        final productId = product['id'] as String;
        await txn.insert(itemsTable, {
          'id': _uuid.v4(),
          'branch_id': DatabaseService.currentBranchId,
          'session_id': sessionId,
          'product_id': productId,
          'product_name': product['name'] as String? ?? 'Product',
          'expected_qty': (product['stock'] as num? ?? 0).toDouble(),
          'counted_qty': null,
          'variance_qty': 0,
          'unit':
              product['stock_unit'] as String? ??
              product['unit'] as String? ??
              UnitUtils.defaultUnit,
          'unit_cost': (product['cost'] as num? ?? 0).toDouble(),
          'status': 'pending',
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });
      }
    });

    await AuditLogService.log(
      action: 'create',
      entityTable: sessionsTable,
      entityId: sessionId,
    );
    return sessionId;
  }

  static Future<void> updateCount({
    required String itemId,
    required double countedQty,
    String? note,
  }) async {
    await _ensureWriteAccess('count stock');
    if (countedQty < 0) {
      throw Exception('Counted quantity cannot be negative.');
    }
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.rawUpdate(
      '''
      UPDATE $itemsTable
      SET counted_qty = ?,
          variance_qty = ? - expected_qty,
          status = 'counted',
          note = ?,
          counted_at = ?,
          updated_at = ?,
          sync_status = 'pending'
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ''',
      [
        countedQty,
        countedQty,
        _clean(note),
        now,
        now,
        itemId,
        ..._currentBranchArgs,
      ],
    );
    await AuditLogService.log(
      action: 'count',
      entityTable: itemsTable,
      entityId: itemId,
    );
  }

  static Future<void> completeSession(String sessionId) async {
    await _ensureWriteAccess('complete stocktake');
    final now = DateTime.now().toIso8601String();

    await DatabaseService.db.transaction((txn) async {
      final sessionRows = await txn.rawQuery(
        '''
        SELECT *
        FROM $sessionsTable
        WHERE id = ?
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        LIMIT 1
        ''',
        [sessionId, ..._currentBranchArgs],
      );
      if (sessionRows.isEmpty) {
        throw Exception('Stocktake session not found.');
      }
      if (sessionRows.first['status'] == 'completed') {
        return;
      }

      final items = await txn.rawQuery(
        '''
        SELECT *
        FROM $itemsTable
        WHERE session_id = ?
          AND status = 'counted'
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        ''',
        [sessionId, ..._currentBranchArgs],
      );
      if (items.isEmpty) {
        throw Exception('Count at least one item before completing stocktake.');
      }

      for (final item in items) {
        final productId = item['product_id'] as String;
        final counted = (item['counted_qty'] as num? ?? 0).toDouble();
        final productRows = await txn.rawQuery(
          '''
          SELECT *
          FROM products
          WHERE id = ?
            AND deleted_at IS NULL
            AND COALESCE(branch_id, ?) = ?
          LIMIT 1
          ''',
          [productId, ..._currentBranchArgs],
        );
        if (productRows.isEmpty) {
          continue;
        }
        final product = productRows.first;
        final currentStock = (product['stock'] as num? ?? 0).toDouble();
        final delta = counted - currentStock;
        if (delta > 0.001) {
          await txn.insert('stock_batches', {
            'id': _uuid.v4(),
            'branch_id': DatabaseService.currentBranchId,
            'product_id': productId,
            'batch_number': 'STK-${DateTime.now().millisecondsSinceEpoch}',
            'quantity_received': delta,
            'quantity_remaining': delta,
            'unit_cost': (item['unit_cost'] as num? ?? 0).toDouble(),
            'received_at': now,
            'created_at': now,
            'updated_at': now,
            'sync_status': 'pending',
          });
        } else if (delta < -0.001) {
          await _decrementBatches(
            txn,
            productId: productId,
            quantity: delta.abs(),
            now: now,
          );
        }
        await txn.rawUpdate(
          '''
          UPDATE products
          SET stock = ?,
              updated_at = ?,
              sync_status = 'pending'
          WHERE id = ?
          ''',
          [counted, now, productId],
        );
      }

      await txn.rawUpdate(
        '''
        UPDATE $sessionsTable
        SET status = 'completed',
            completed_by = ?,
            completed_at = ?,
            updated_at = ?,
            sync_status = 'pending'
        WHERE id = ?
        ''',
        [SessionService.currentUserId, now, now, sessionId],
      );
    });

    await AuditLogService.log(
      action: 'complete',
      entityTable: sessionsTable,
      entityId: sessionId,
    );
  }

  static Future<void> cancelSession(String sessionId) async {
    await _ensureWriteAccess('cancel stocktake');
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.rawUpdate(
      '''
      UPDATE $sessionsTable
      SET status = 'cancelled',
          updated_at = ?,
          sync_status = 'pending'
      WHERE id = ?
        AND status != 'completed'
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ''',
      [now, sessionId, ..._currentBranchArgs],
    );
  }

  static Future<void> _decrementBatches(
    dynamic txn, {
    required String productId,
    required double quantity,
    required String now,
  }) async {
    var remaining = quantity;
    final batches = await txn.rawQuery(
      '''
      SELECT id, quantity_remaining
      FROM stock_batches
      WHERE product_id = ?
        AND quantity_remaining > 0
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY
        CASE WHEN expiry_date IS NULL OR TRIM(expiry_date) = '' THEN 1 ELSE 0 END,
        date(expiry_date) ASC,
        received_at ASC
      ''',
      [productId, ..._currentBranchArgs],
    );
    for (final batch in batches) {
      if (remaining <= 0.001) break;
      final batchId = batch['id'] as String;
      final available = (batch['quantity_remaining'] as num? ?? 0).toDouble();
      final taken = remaining > available ? available : remaining;
      await txn.rawUpdate(
        '''
        UPDATE stock_batches
        SET quantity_remaining = quantity_remaining - ?,
            finished_at = CASE WHEN quantity_remaining - ? <= 0 THEN ? ELSE finished_at END,
            updated_at = ?,
            sync_status = 'pending'
        WHERE id = ?
        ''',
        [taken, taken, now, now, batchId],
      );
      remaining -= taken;
    }
  }

  static Future<void> _ensureWriteAccess(String action) async {
    if (!SessionService.canAccessFeature(UserAccessProfile.featureStocktake)) {
      throw Exception('Your account cannot access stocktake.');
    }
    await LicenseService.ensureWriteAccess(action: action);
    await LicenseService.ensureFeatureAccess(
      featureKey: UserAccessProfile.featureStocktake,
      action: action,
    );
  }

  static String? _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
