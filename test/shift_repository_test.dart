import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/features/shifts/data/shift_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String databasePath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    tempDir = await Directory.systemTemp.createTemp('pos-shift-test-');
    databasePath = p.join(tempDir.path, 'velora_pos.db');
    await DatabaseService.overrideDatabasePathForTesting(databasePath);
    await DatabaseService.initialize();

    await DatabaseService.insert('users', {
      'id': 'cashier-1',
      'name': 'Shift Cashier',
      'email': 'cashier@example.com',
      'password': 'hashed-password',
      'role': 'CASHIER',
    });
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'open, summarize, and close a shift with reconciliation totals',
    () async {
      final shift = await ShiftRepository.openShift(
        userId: 'cashier-1',
        cashierName: 'Shift Cashier',
        openingCash: 50,
        note: 'Morning float',
      );

      await DatabaseService.insert('sales', {
        'id': 'sale-cash',
        'total_amount': 120.0,
        'tax': 0.0,
        'discount': 0.0,
        'payment_type': 'cash',
        'user_id': 'cashier-1',
        'shift_id': shift['id'],
        'amount_paid': 120.0,
        'amount_tendered': 150.0,
        'change_given': 30.0,
      });
      await DatabaseService.insert('sales', {
        'id': 'sale-credit',
        'total_amount': 60.0,
        'tax': 0.0,
        'discount': 0.0,
        'payment_type': 'kopesha',
        'user_id': 'cashier-1',
        'shift_id': shift['id'],
        'amount_paid': 0.0,
        'balance_due': 60.0,
      });
      await DatabaseService.insert('sales', {
        'id': 'sale-refund',
        'total_amount': -20.0,
        'tax': 0.0,
        'discount': 0.0,
        'payment_type': 'refund_cash',
        'user_id': 'cashier-1',
        'shift_id': shift['id'],
        'amount_paid': 0.0,
      });

      await ShiftRepository.recordCashMovement(
        shiftId: shift['id'] as String,
        userId: 'cashier-1',
        type: 'cash_in',
        amount: 10,
        reason: 'Float top-up',
      );
      await ShiftRepository.recordCashMovement(
        shiftId: shift['id'] as String,
        userId: 'cashier-1',
        type: 'cash_out',
        amount: 5,
        reason: 'Courier payout',
      );

      final summary = await ShiftRepository.getShiftSummary(
        shift['id'] as String,
      );

      expect(summary['opening_cash'], 50.0);
      expect(summary['cash_sales_total'], 120.0);
      expect(summary['cash_refunds_total'], 20.0);
      expect(summary['kopesha_sales_total'], 60.0);
      expect(summary['cash_in_total'], 10.0);
      expect(summary['cash_out_total'], 5.0);
      expect(summary['expected_cash'], 155.0);

      final closedShift = await ShiftRepository.closeShift(
        shiftId: shift['id'] as String,
        closingCashCounted: 150,
        note: 'Drawer handover complete',
      );

      expect(closedShift['status'], 'closed');
      expect(closedShift['expected_cash'], 155.0);
      expect(closedShift['difference'], -5.0);
      expect(closedShift['cash_sales_total'], 120.0);
      expect(closedShift['cash_refunds_total'], 20.0);

      final closedSummary = await ShiftRepository.getClosedShiftSummary();
      final closedShifts = await ShiftRepository.getClosedShifts();

      expect(closedSummary['closed_shift_count'], 1);
      expect(closedSummary['counted_cash_total'], 150.0);
      expect(closedSummary['net_difference'], -5.0);
      expect(closedShifts, hasLength(1));
      expect(closedShifts.first['cashier_name'], 'Shift Cashier');
    },
  );

  test(
    'cashiers auto-open shifts for cash handling while admins can skip',
    () async {
      final cashierResult = await ShiftRepository.ensureShiftForCashHandling(
        userId: 'cashier-1',
        cashierName: 'Shift Cashier',
        role: 'CASHIER',
      );

      expect(cashierResult.requiresShift, isTrue);
      expect(cashierResult.autoOpenedShift, isTrue);
      expect(cashierResult.currentShift, isNotNull);

      final adminResult = await ShiftRepository.ensureShiftForCashHandling(
        userId: 'admin',
        cashierName: 'Admin',
        role: 'ADMIN',
      );

      expect(adminResult.requiresShift, isFalse);
      expect(adminResult.autoOpenedShift, isFalse);
      expect(adminResult.currentShift, isNull);
    },
  );

  test('stale open shifts auto-close at the start of a new day', () async {
    final shift = await ShiftRepository.openShift(
      userId: 'cashier-1',
      cashierName: 'Shift Cashier',
      openingCash: 25,
    );
    await DatabaseService.insert('sales', {
      'id': 'stale-cash-sale',
      'total_amount': 40.0,
      'tax': 0.0,
      'discount': 0.0,
      'payment_type': 'cash',
      'user_id': 'cashier-1',
      'shift_id': shift['id'],
      'amount_paid': 40.0,
      'amount_tendered': 40.0,
      'change_given': 0.0,
    });
    final yesterday = DateTime.now()
        .subtract(const Duration(days: 1))
        .toIso8601String();
    await DatabaseService.db.update(
      'shifts',
      {
        'opened_at': yesterday,
        'created_at': yesterday,
        'updated_at': yesterday,
      },
      where: 'id = ?',
      whereArgs: [shift['id']],
    );

    final access = await ShiftRepository.resolveCurrentShift(
      userId: 'cashier-1',
    );

    expect(access.currentShift, isNull);
    expect(access.autoClosedShift, isNotNull);
    expect(access.autoClosedShift!['status'], 'closed');
    expect(access.autoClosedShift!['difference'], 0.0);
    expect(access.autoClosedShift!['expected_cash'], 65.0);
    expect(
      (access.autoClosedShift!['note'] as String?)?.contains(
        'Auto-closed at start of a new day.',
      ),
      isTrue,
    );
  });
}
