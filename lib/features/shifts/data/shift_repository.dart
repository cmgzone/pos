import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/session_service.dart';

const _uuid = Uuid();

class ShiftAccessResult {
  final Map<String, dynamic>? currentShift;
  final Map<String, dynamic>? autoClosedShift;

  const ShiftAccessResult({this.currentShift, this.autoClosedShift});
}

class ShiftCashRequirementResult {
  final Map<String, dynamic>? currentShift;
  final Map<String, dynamic>? autoClosedShift;
  final bool autoOpenedShift;
  final bool requiresShift;

  const ShiftCashRequirementResult({
    required this.currentShift,
    required this.autoClosedShift,
    required this.autoOpenedShift,
    required this.requiresShift,
  });
}

class ShiftRepository {
  static const _shiftsTable = 'shifts';
  static const _cashMovementsTable = 'cash_movements';

  static String normalizeActorUserId(String? userId) {
    final normalized = userId?.trim() ?? '';
    return normalized.isEmpty ? 'admin' : normalized;
  }

  static String normalizeActorName(String? name) {
    final normalized = name?.trim() ?? '';
    return normalized.isEmpty ? 'Cashier' : normalized;
  }

  static Future<Map<String, dynamic>?> getOpenShift({
    required String userId,
  }) async {
    final rows = await DatabaseService.queryAll(
      _shiftsTable,
      where: 'user_id = ? AND status = ? AND deleted_at IS NULL',
      whereArgs: [normalizeActorUserId(userId), 'open'],
      orderBy: 'opened_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static bool roleRequiresManagedShift(String? role) {
    return RolePermissions.normalizeRole(role) == RolePermissions.cashier;
  }

  static bool roleCanAutoOpenShift(String? role) {
    return roleRequiresManagedShift(role);
  }

  static Future<ShiftAccessResult> resolveCurrentShift({
    required String userId,
  }) async {
    final shift = await getOpenShift(userId: userId);
    if (shift == null) {
      return const ShiftAccessResult();
    }

    if (!_isShiftFromToday(shift['opened_at'])) {
      final summary = await getShiftSummary(shift['id'] as String);
      final closedShift = await closeShift(
        shiftId: shift['id'] as String,
        closingCashCounted: _money(summary['expected_cash']),
        note: _buildAutoCloseNote(shift['note'] as String?),
      );
      return ShiftAccessResult(autoClosedShift: closedShift);
    }

    return ShiftAccessResult(currentShift: shift);
  }

  static Future<ShiftCashRequirementResult> ensureShiftForCashHandling({
    required String userId,
    required String cashierName,
    required String role,
  }) async {
    final access = await resolveCurrentShift(userId: userId);
    if (!roleRequiresManagedShift(role)) {
      return ShiftCashRequirementResult(
        currentShift: access.currentShift,
        autoClosedShift: access.autoClosedShift,
        autoOpenedShift: false,
        requiresShift: false,
      );
    }

    if (access.currentShift != null) {
      return ShiftCashRequirementResult(
        currentShift: access.currentShift,
        autoClosedShift: access.autoClosedShift,
        autoOpenedShift: false,
        requiresShift: true,
      );
    }

    if (!roleCanAutoOpenShift(role)) {
      return ShiftCashRequirementResult(
        currentShift: null,
        autoClosedShift: access.autoClosedShift,
        autoOpenedShift: false,
        requiresShift: true,
      );
    }

    final autoOpenedShift = await openShift(
      userId: userId,
      cashierName: cashierName,
      openingCash: 0,
      note: 'Auto-opened on first cash transaction.',
    );
    return ShiftCashRequirementResult(
      currentShift: autoOpenedShift,
      autoClosedShift: access.autoClosedShift,
      autoOpenedShift: true,
      requiresShift: true,
    );
  }

  static Future<Map<String, dynamic>?> getShiftById(String shiftId) async {
    final rows = await DatabaseService.queryAll(
      _shiftsTable,
      where: 'id = ?',
      whereArgs: [shiftId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, dynamic>>> getRecentShifts({
    String? userId,
    int limit = 20,
  }) async {
    final safeLimit = limit < 1 ? 1 : limit;
    final clauses = <String>['deleted_at IS NULL'];
    final args = <dynamic>[];
    final normalizedUserId = userId?.trim();
    if (normalizedUserId != null && normalizedUserId.isNotEmpty) {
      clauses.add('user_id = ?');
      args.add(normalizeActorUserId(normalizedUserId));
    }

    return DatabaseService.rawQuery('''
      SELECT *
      FROM $_shiftsTable
      WHERE ${clauses.join(' AND ')}
      ORDER BY
        CASE WHEN status = 'open' THEN 0 ELSE 1 END,
        opened_at DESC,
        id DESC
      LIMIT $safeLimit
      ''', args);
  }

  static Future<Map<String, dynamic>> getClosedShiftSummary({
    String? date,
    String? userId,
  }) async {
    final targetDate =
        date ?? DateTime.now().toIso8601String().substring(0, 10);
    final clauses = <String>[
      "status = 'closed'",
      'deleted_at IS NULL',
      'closed_at IS NOT NULL',
      'DATE(closed_at) = ?',
    ];
    final args = <dynamic>[targetDate];
    final normalizedUserId = userId?.trim();
    if (normalizedUserId != null && normalizedUserId.isNotEmpty) {
      clauses.add('user_id = ?');
      args.add(normalizeActorUserId(normalizedUserId));
    }

    final rows = await DatabaseService.rawQuery('''
      SELECT
        COUNT(*) AS closed_shift_count,
        COUNT(CASE WHEN ABS(difference) < 0.009 THEN 1 END) AS balanced_shift_count,
        COUNT(CASE WHEN difference > 0.009 THEN 1 END) AS over_shift_count,
        COUNT(CASE WHEN difference < -0.009 THEN 1 END) AS short_shift_count,
        COALESCE(SUM(expected_cash), 0) AS expected_cash_total,
        COALESCE(SUM(closing_cash_counted), 0) AS counted_cash_total,
        COALESCE(SUM(cash_sales_total), 0) AS cash_sales_total,
        COALESCE(SUM(cash_refunds_total), 0) AS cash_refunds_total,
        COALESCE(SUM(cash_in_total), 0) AS cash_in_total,
        COALESCE(SUM(cash_out_total), 0) AS cash_out_total,
        COALESCE(SUM(difference), 0) AS net_difference
      FROM $_shiftsTable
      WHERE ${clauses.join(' AND ')}
    ''', args);

    return rows.isEmpty ? <String, dynamic>{} : rows.first;
  }

  static Future<List<Map<String, dynamic>>> getClosedShifts({
    String? date,
    String? userId,
    int limit = 20,
  }) async {
    final targetDate =
        date ?? DateTime.now().toIso8601String().substring(0, 10);
    final safeLimit = limit < 1 ? 1 : limit;
    final clauses = <String>[
      "status = 'closed'",
      'deleted_at IS NULL',
      'closed_at IS NOT NULL',
      'DATE(closed_at) = ?',
    ];
    final args = <dynamic>[targetDate];
    final normalizedUserId = userId?.trim();
    if (normalizedUserId != null && normalizedUserId.isNotEmpty) {
      clauses.add('user_id = ?');
      args.add(normalizeActorUserId(normalizedUserId));
    }

    return DatabaseService.rawQuery('''
      SELECT
        id,
        user_id,
        cashier_name,
        opening_cash,
        closing_cash_counted,
        expected_cash,
        cash_sales_total,
        cash_refunds_total,
        cash_in_total,
        cash_out_total,
        difference,
        note,
        opened_at,
        closed_at
      FROM $_shiftsTable
      WHERE ${clauses.join(' AND ')}
      ORDER BY closed_at DESC, id DESC
      LIMIT $safeLimit
    ''', args);
  }

  static Future<List<Map<String, dynamic>>> getCashMovements(
    String shiftId,
  ) async {
    return DatabaseService.queryAll(
      _cashMovementsTable,
      where: 'shift_id = ? AND deleted_at IS NULL',
      whereArgs: [shiftId],
      orderBy: 'created_at DESC, id DESC',
    );
  }

  static Future<Map<String, dynamic>> getShiftSummary(String shiftId) async {
    final shift = await getShiftById(shiftId);
    if (shift == null) {
      return emptySummary();
    }

    return _getShiftSummaryWithExecutor(
      DatabaseService.db,
      shiftId,
      shift: shift,
    );
  }

  static Future<Map<String, dynamic>> openShift({
    required String userId,
    required String cashierName,
    required double openingCash,
    String? note,
  }) async {
    final normalizedUserId = normalizeActorUserId(userId);
    final existingShift = await getOpenShift(userId: normalizedUserId);
    if (existingShift != null) {
      throw Exception('This cashier already has an open shift');
    }

    final normalizedOpeningCash = _roundMoney(openingCash);
    if (normalizedOpeningCash < 0) {
      throw Exception('Opening cash cannot be negative');
    }

    final now = DateTime.now().toIso8601String();
    final row = <String, dynamic>{
      'id': _uuid.v4(),
      'user_id': normalizedUserId,
      'cashier_name': normalizeActorName(cashierName),
      'status': 'open',
      'opening_cash': normalizedOpeningCash,
      'closing_cash_counted': 0.0,
      'expected_cash': normalizedOpeningCash,
      'cash_sales_total': 0.0,
      'cash_refunds_total': 0.0,
      'cash_in_total': 0.0,
      'cash_out_total': 0.0,
      'difference': 0.0,
      'note': _normalizedOptionalText(note),
      'opened_at': now,
      'closed_at': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'sync_status': 'pending',
    };

    await DatabaseService.insert(_shiftsTable, row);
    return row;
  }

  static Future<Map<String, dynamic>> recordCashMovement({
    required String shiftId,
    required String userId,
    required String type,
    required double amount,
    String? reason,
  }) async {
    final normalizedType = type.trim().toLowerCase();
    if (normalizedType != 'cash_in' && normalizedType != 'cash_out') {
      throw Exception('Unsupported cash movement type');
    }

    final normalizedAmount = _roundMoney(amount);
    if (normalizedAmount <= 0) {
      throw Exception('Amount must be greater than zero');
    }

    final now = DateTime.now().toIso8601String();
    final normalizedReason = _normalizedOptionalText(reason);

    return DatabaseService.db.transaction((txn) async {
      final shift = await _getShiftByIdWithExecutor(txn, shiftId);
      if (shift == null || (shift['deleted_at'] as String?) != null) {
        throw Exception('Shift not found');
      }
      if ((shift['status'] as String? ?? 'open') != 'open') {
        throw Exception('You can only record cash movements on an open shift');
      }

      final row = <String, dynamic>{
        'id': _uuid.v4(),
        'shift_id': shiftId,
        'user_id': normalizeActorUserId(userId),
        'type': normalizedType,
        'amount': normalizedAmount,
        'reason': normalizedReason,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
        'sync_status': 'pending',
      };

      await txn.insert(_cashMovementsTable, row);
      await txn.update(
        _shiftsTable,
        {'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [shiftId],
      );
      return row;
    });
  }

  static Future<Map<String, dynamic>> closeShift({
    required String shiftId,
    required double closingCashCounted,
    String? note,
  }) async {
    final normalizedClosingCash = _roundMoney(closingCashCounted);
    if (normalizedClosingCash < 0) {
      throw Exception('Closing cash cannot be negative');
    }

    return DatabaseService.db.transaction((txn) async {
      final shift = await _getShiftByIdWithExecutor(txn, shiftId);
      if (shift == null || (shift['deleted_at'] as String?) != null) {
        throw Exception('Shift not found');
      }
      if ((shift['status'] as String? ?? 'open') != 'open') {
        throw Exception('This shift is already closed');
      }

      final summary = await _getShiftSummaryWithExecutor(
        txn,
        shiftId,
        shift: shift,
      );
      final now = DateTime.now().toIso8601String();
      final expectedCash = _money(summary['expected_cash']);
      final difference = _roundMoney(normalizedClosingCash - expectedCash);
      final resolvedNote =
          _normalizedOptionalText(note) ??
          _normalizedOptionalText(shift['note'] as String?);

      final updates = <String, dynamic>{
        'status': 'closed',
        'closing_cash_counted': normalizedClosingCash,
        'expected_cash': expectedCash,
        'cash_sales_total': _money(summary['cash_sales_total']),
        'cash_refunds_total': _money(summary['cash_refunds_total']),
        'cash_in_total': _money(summary['cash_in_total']),
        'cash_out_total': _money(summary['cash_out_total']),
        'difference': difference,
        'note': resolvedNote,
        'closed_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      };

      await txn.update(
        _shiftsTable,
        updates,
        where: 'id = ?',
        whereArgs: [shiftId],
      );

      return {...shift, ...updates};
    });
  }

  static Map<String, dynamic> emptySummary() {
    return const {
      'gross_sales': 0.0,
      'net_sales': 0.0,
      'sale_count': 0,
      'refund_count': 0,
      'cash_sales_total': 0.0,
      'cash_refunds_total': 0.0,
      'kopesha_sales_total': 0.0,
      'kopesha_refunds_total': 0.0,
      'cash_in_total': 0.0,
      'cash_out_total': 0.0,
      'movement_count': 0,
      'opening_cash': 0.0,
      'expected_cash': 0.0,
    };
  }

  static Future<Map<String, dynamic>> _getShiftSummaryWithExecutor(
    DatabaseExecutor executor,
    String shiftId, {
    required Map<String, dynamic> shift,
  }) async {
    final salesStats = await executor.rawQuery(
      '''
      SELECT
        COUNT(*) FILTER (WHERE payment_type NOT LIKE 'refund%') AS sale_count,
        COUNT(*) FILTER (WHERE payment_type LIKE 'refund%') AS refund_count,
        COALESCE(SUM(CASE WHEN total_amount > 0 THEN total_amount ELSE 0 END), 0) AS gross_sales,
        COALESCE(SUM(CASE WHEN total_amount < 0 THEN ABS(total_amount) ELSE 0 END), 0) AS refunded_total,
        COALESCE(SUM(CASE WHEN (is_cash_drawer = 1 OR payment_type = 'cash') AND payment_type NOT LIKE 'refund%' THEN total_amount ELSE 0 END), 0) AS cash_sales_total,
        COALESCE(SUM(CASE WHEN (is_cash_drawer = 1 OR payment_type = 'cash') AND payment_type LIKE 'refund%' THEN ABS(total_amount) ELSE 0 END), 0) AS cash_refunds_total,
        COALESCE(SUM(CASE WHEN payment_type = 'kopesha' THEN total_amount ELSE 0 END), 0) AS kopesha_sales_total,
        COALESCE(SUM(CASE WHEN payment_type = 'refund_kopesha' THEN ABS(total_amount) ELSE 0 END), 0) AS kopesha_refunds_total
      FROM sales
      WHERE shift_id = ? AND deleted_at IS NULL
      ''',
      [shiftId],
    );
    final movementsStats = await executor.rawQuery(
      '''
      SELECT
        COUNT(*) AS movement_count,
        COALESCE(SUM(CASE WHEN type = 'cash_in' THEN amount ELSE 0 END), 0) AS cash_in_total,
        COALESCE(SUM(CASE WHEN type = 'cash_out' THEN amount ELSE 0 END), 0) AS cash_out_total
      FROM $_cashMovementsTable
      WHERE shift_id = ? AND deleted_at IS NULL
      ''',
      [shiftId],
    );

    final salesRow = salesStats.isEmpty
        ? const <String, Object?>{}
        : Map<String, Object?>.from(salesStats.first);
    final movementRow = movementsStats.isEmpty
        ? const <String, Object?>{}
        : Map<String, Object?>.from(movementsStats.first);
    final openingCash = _money(shift['opening_cash']);
    final cashSalesTotal = _money(salesRow['cash_sales_total']);
    final cashRefundsTotal = _money(salesRow['cash_refunds_total']);
    final cashInTotal = _money(movementRow['cash_in_total']);
    final cashOutTotal = _money(movementRow['cash_out_total']);
    final expectedCash = _roundMoney(
      openingCash +
          cashSalesTotal -
          cashRefundsTotal +
          cashInTotal -
          cashOutTotal,
    );

    return {
      'gross_sales': _money(salesRow['gross_sales']),
      'net_sales': _roundMoney(
        _money(salesRow['gross_sales']) - _money(salesRow['refunded_total']),
      ),
      'sale_count': _intValue(salesRow['sale_count']),
      'refund_count': _intValue(salesRow['refund_count']),
      'cash_sales_total': cashSalesTotal,
      'cash_refunds_total': cashRefundsTotal,
      'kopesha_sales_total': _money(salesRow['kopesha_sales_total']),
      'kopesha_refunds_total': _money(salesRow['kopesha_refunds_total']),
      'cash_in_total': cashInTotal,
      'cash_out_total': cashOutTotal,
      'movement_count': _intValue(movementRow['movement_count']),
      'opening_cash': openingCash,
      'expected_cash': expectedCash,
    };
  }

  static Future<Map<String, dynamic>?> _getShiftByIdWithExecutor(
    DatabaseExecutor executor,
    String shiftId,
  ) async {
    final rows = await executor.query(
      _shiftsTable,
      where: 'id = ?',
      whereArgs: [shiftId],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  static bool _isShiftFromToday(Object? openedAt) {
    final date = DateTime.tryParse(openedAt?.toString() ?? '');
    if (date == null) {
      return true;
    }
    final local = date.toLocal();
    final now = DateTime.now();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  static String _buildAutoCloseNote(String? existingNote) {
    final base = _normalizedOptionalText(existingNote);
    const autoCloseLine = 'Auto-closed at start of a new day.';
    if (base == null) {
      return autoCloseLine;
    }
    if (base.contains(autoCloseLine)) {
      return base;
    }
    return '$base\n$autoCloseLine';
  }

  static String? _normalizedOptionalText(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static double _money(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _roundMoney(double value) {
    return double.parse(value.toStringAsFixed(2));
  }
}
