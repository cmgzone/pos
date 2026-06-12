import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/features/reports/data/report_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('pos-report-scope-');
    await DatabaseService.overrideDatabasePathForTesting(
      p.join(tempDir.path, 'velora_pos.db'),
    );
    await DatabaseService.initialize();
    DatabaseService.setCurrentBranchId('main_branch');

    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.insert('customers', {
      'id': 'customer-main',
      'branch_id': 'main_branch',
      'name': 'Main customer',
      'balance': 100.0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'synced',
    });
    await DatabaseService.db.insert('customers', {
      'id': 'customer-two',
      'branch_id': 'branch-two',
      'name': 'Branch customer',
      'balance': 200.0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'synced',
    });
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('administrator debtor report includes every branch', () async {
    await SessionService.signIn({
      'id': 'admin-user',
      'name': 'Owner',
      'role': RolePermissions.admin,
    });

    final debtors = await ReportRepository.getTopDebtors();

    expect(debtors.map((row) => row['id']).toSet(), {
      'customer-main',
      'customer-two',
    });
  });

  test('manager debtor report remains on the current branch', () async {
    await SessionService.signIn({
      'id': 'manager-user',
      'name': 'Manager',
      'role': RolePermissions.manager,
    });

    final debtors = await ReportRepository.getTopDebtors();

    expect(debtors.map((row) => row['id']), ['customer-main']);
  });
}
