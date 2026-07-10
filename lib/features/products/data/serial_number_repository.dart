import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';

const _uuid = Uuid();

class SerialNumberRepository {
  static const table = 'product_serials';

  static Future<List<Map<String, dynamic>>> getAll({
    String? search,
    String? status,
  }) {
    final where = <String>[
      'ps.deleted_at IS NULL',
      'COALESCE(ps.branch_id, ?) = ?',
    ];
    final args = <dynamic>[
      DatabaseService.defaultBranchId,
      DatabaseService.currentBranchId,
    ];
    final cleanSearch = search?.trim() ?? '';
    if (cleanSearch.isNotEmpty) {
      final like = '%$cleanSearch%';
      where.add('(ps.serial_number LIKE ? OR p.name LIKE ? OR pv.name LIKE ?)');
      args.addAll([like, like, like]);
    }
    if ((status ?? '').trim().isNotEmpty) {
      where.add('ps.status = ?');
      args.add(status!.trim().toLowerCase());
    }
    return DatabaseService.rawQuery('''
      SELECT ps.*,
             p.name AS product_name,
             pv.name AS variant_name
      FROM $table ps
      LEFT JOIN products p ON p.id = ps.product_id
      LEFT JOIN product_variants pv ON pv.id = ps.variant_id
      WHERE ${where.join(' AND ')}
      ORDER BY
        CASE ps.status WHEN 'available' THEN 0 WHEN 'reserved' THEN 1 WHEN 'sold' THEN 2 ELSE 3 END,
        ps.updated_at DESC,
        ps.serial_number ASC
      ''', args);
  }

  static Future<List<Map<String, dynamic>>> getForProduct(
    String productId, {
    String? status,
  }) {
    final where = <String>[
      'ps.product_id = ?',
      'ps.deleted_at IS NULL',
      'COALESCE(ps.branch_id, ?) = ?',
    ];
    final args = <dynamic>[
      productId,
      DatabaseService.defaultBranchId,
      DatabaseService.currentBranchId,
    ];
    if ((status ?? '').trim().isNotEmpty) {
      where.add('ps.status = ?');
      args.add(status!.trim().toLowerCase());
    }
    return DatabaseService.rawQuery('''
      SELECT ps.*,
             p.name AS product_name,
             pv.name AS variant_name
      FROM $table ps
      LEFT JOIN products p ON p.id = ps.product_id
      LEFT JOIN product_variants pv ON pv.id = ps.variant_id
      WHERE ${where.join(' AND ')}
      ORDER BY ps.status ASC, ps.serial_number ASC
      ''', args);
  }

  static Future<List<Map<String, dynamic>>> warrantyWatch({int days = 60}) {
    return DatabaseService.rawQuery(
      '''
      SELECT ps.*,
             p.name AS product_name,
             pv.name AS variant_name
      FROM $table ps
      LEFT JOIN products p ON p.id = ps.product_id
      LEFT JOIN product_variants pv ON pv.id = ps.variant_id
      WHERE ps.deleted_at IS NULL
        AND COALESCE(ps.branch_id, ?) = ?
        AND ps.warranty_expires_at IS NOT NULL
        AND TRIM(ps.warranty_expires_at) <> ''
        AND date(ps.warranty_expires_at) <= date('now', '+$days days')
      ORDER BY date(ps.warranty_expires_at) ASC, ps.serial_number ASC
      ''',
      [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
    );
  }

  static Future<Map<String, dynamic>?> findAvailableBySerial(
    String serialNumber,
  ) async {
    final clean = serialNumber.trim();
    if (clean.isEmpty) {
      return null;
    }
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT ps.*,
             p.name AS product_name,
             p.price,
             p.cost,
             p.stock,
             p.sale_unit,
             p.stock_unit,
             p.sale_to_stock_factor,
             p.track_stock,
             p.has_variants,
             pv.name AS variant_name,
             pv.price AS variant_price,
             pv.cost AS variant_cost,
             pv.stock AS variant_stock
      FROM $table ps
      JOIN products p ON p.id = ps.product_id AND p.deleted_at IS NULL
      LEFT JOIN product_variants pv ON pv.id = ps.variant_id
      WHERE LOWER(ps.serial_number) = LOWER(?)
        AND ps.status = 'available'
        AND ps.deleted_at IS NULL
        AND COALESCE(ps.branch_id, ?) = ?
      LIMIT 1
      ''',
      [clean, DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<int> createMany({
    required String productId,
    String? variantId,
    String? stockBatchId,
    String? purchaseId,
    required Iterable<String> serialNumbers,
    String? warrantyExpiresAt,
    String? note,
  }) async {
    await _ensureSerialWriteAccess();
    final normalized = <String>[];
    for (final value in serialNumbers) {
      final clean = value.trim();
      if (clean.isNotEmpty &&
          !normalized.any(
            (existing) => existing.toLowerCase() == clean.toLowerCase(),
          )) {
        normalized.add(clean);
      }
    }
    if (normalized.isEmpty) {
      throw Exception('Enter at least one serial number.');
    }

    final now = DateTime.now().toIso8601String();
    var inserted = 0;
    await DatabaseService.db.transaction((txn) async {
      for (final serial in normalized) {
        final duplicate = await txn.rawQuery(
          '''
          SELECT id
          FROM $table
          WHERE LOWER(serial_number) = LOWER(?)
            AND deleted_at IS NULL
          LIMIT 1
          ''',
          [serial],
        );
        if (duplicate.isNotEmpty) {
          continue;
        }
        await txn.insert(table, {
          'id': _uuid.v4(),
          'branch_id': DatabaseService.currentBranchId,
          'product_id': productId,
          'variant_id': _clean(variantId),
          'stock_batch_id': _clean(stockBatchId),
          'purchase_id': _clean(purchaseId),
          'serial_number': serial,
          'status': 'available',
          'warranty_expires_at': _clean(warrantyExpiresAt),
          'note': _clean(note),
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });
        inserted += 1;
      }
    });
    return inserted;
  }

  static Future<void> markSold({
    required Iterable<String> serialNumbers,
    required String saleId,
    String? saleItemId,
  }) async {
    final serials = serialNumbers
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (serials.isEmpty) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    final placeholders = List.filled(serials.length, '?').join(',');
    await DatabaseService.db.rawUpdate(
      '''
      UPDATE $table
      SET status = 'sold',
          sale_id = ?,
          sale_item_id = ?,
          updated_at = ?,
          sync_status = 'pending'
      WHERE LOWER(serial_number) IN ($placeholders)
        AND status = 'available'
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ''',
      [
        saleId,
        saleItemId,
        now,
        ...serials.map((serial) => serial.toLowerCase()),
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
      ],
    );
  }

  static Future<void> _ensureSerialWriteAccess() async {
    if (!SessionService.canAccessFeature(
      UserAccessProfile.featureSerialTracking,
    )) {
      throw Exception('Your account cannot manage serial numbers.');
    }
    await LicenseService.ensureWriteAccess(action: 'manage serial numbers');
    await LicenseService.ensureFeatureAccess(
      featureKey: UserAccessProfile.featureSerialTracking,
      action: 'serial number tracking',
    );
  }

  static String? _clean(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
