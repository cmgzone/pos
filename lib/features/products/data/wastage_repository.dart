import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/utils/unit_utils.dart';

const _uuid = Uuid();

class WastageRepository {
  static const table = 'wastage_logs';

  static List<dynamic> get _branchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<List<Map<String, dynamic>>> getAll({int limit = 100}) {
    return DatabaseService.rawQuery(
      '''
      SELECT *
      FROM $table
      WHERE deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY datetime(recorded_at) DESC, datetime(created_at) DESC
      LIMIT ?
      ''',
      [..._branchArgs, limit.clamp(1, 500)],
    );
  }

  static Future<String> record({
    required Map<String, dynamic> product,
    required double quantity,
    required String reason,
    String? note,
  }) async {
    await _ensureWriteAccess();
    if (quantity <= 0) {
      throw Exception('Enter a quantity greater than zero.');
    }
    final productId = product['id']?.toString() ?? '';
    if (productId.isEmpty) {
      throw Exception('Choose a product to record wastage.');
    }

    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    await DatabaseService.db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''
        SELECT id, name, stock, stock_unit, unit, cost
        FROM products
        WHERE id = ?
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        LIMIT 1
        ''',
        [productId, ..._branchArgs],
      );
      if (rows.isEmpty) throw Exception('The selected product is unavailable.');
      final current = rows.first;
      final stock = (current['stock'] as num? ?? 0).toDouble();
      if (quantity > stock + 0.001) {
        throw Exception(
          'Only ${UnitUtils.formatWithUnit(stock, current['stock_unit'] as String?)} is available.',
        );
      }
      final unit =
          current['stock_unit'] as String? ??
          current['unit'] as String? ??
          UnitUtils.defaultUnit;
      await txn.insert(table, {
        'id': id,
        'branch_id': DatabaseService.currentBranchId,
        'product_id': productId,
        'product_name': current['name'] as String? ?? 'Product',
        'quantity': quantity,
        'unit': unit,
        'unit_cost': (current['cost'] as num? ?? 0).toDouble(),
        'reason': _normalizeReason(reason),
        'note': _clean(note),
        'recorded_by': SessionService.currentUserId,
        'recorded_at': now,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      await txn.rawUpdate(
        '''
        UPDATE products
        SET stock = stock - ?, updated_at = ?, sync_status = 'pending'
        WHERE id = ?
        ''',
        [quantity, now, productId],
      );
      await _decrementBatches(
        txn,
        productId: productId,
        quantity: quantity,
        now: now,
      );
    });
    await AuditLogService.log(
      action: 'create',
      entityTable: table,
      entityId: id,
    );
    DatabaseService.notifyLocalChange();
    return id;
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
      WHERE product_id = ? AND quantity_remaining > 0 AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY CASE WHEN expiry_date IS NULL OR TRIM(expiry_date) = '' THEN 1 ELSE 0 END,
               date(expiry_date) ASC, received_at ASC
      ''',
      [productId, ..._branchArgs],
    );
    for (final batch in batches) {
      if (remaining <= 0.001) break;
      final available = (batch['quantity_remaining'] as num? ?? 0).toDouble();
      final deducted = remaining > available ? available : remaining;
      await txn.rawUpdate(
        '''
        UPDATE stock_batches
        SET quantity_remaining = quantity_remaining - ?,
            finished_at = CASE WHEN quantity_remaining - ? <= 0 THEN ? ELSE finished_at END,
            updated_at = ?, sync_status = 'pending'
        WHERE id = ?
        ''',
        [deducted, deducted, now, now, batch['id']],
      );
      remaining -= deducted;
    }
  }

  static Future<void> _ensureWriteAccess() async {
    if (!SessionService.canAccessFeature(UserAccessProfile.featureWastage)) {
      throw Exception('Your account cannot record wastage.');
    }
    await LicenseService.ensureWriteAccess(action: 'record wastage');
    await LicenseService.ensureFeatureAccess(
      featureKey: UserAccessProfile.featureWastage,
      action: 'wastage tracking',
    );
  }

  static String _normalizeReason(String value) {
    const allowed = {
      'wastage',
      'spoilage',
      'damage',
      'expiry',
      'theft',
      'other',
    };
    final normalized = value.trim().toLowerCase();
    return allowed.contains(normalized) ? normalized : 'other';
  }

  static String? _clean(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }
}
