import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/core/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    tempDir = await Directory.systemTemp.createTemp('pos-db-test-');
    testDbPath = p.join(tempDir.path, 'velora_pos.db');

    final legacyDatabase = await openDatabase(
      testDbPath,
      version: 7,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE stock_batches (
            id TEXT PRIMARY KEY,
            product_id TEXT NOT NULL,
            quantity_received REAL NOT NULL DEFAULT 0,
            quantity_remaining REAL NOT NULL DEFAULT 0,
            unit_cost REAL NOT NULL DEFAULT 0,
            received_at TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            deleted_at TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending'
          )
        ''');
      },
    );

    await legacyDatabase.close();
    await DatabaseService.overrideDatabasePathForTesting(testDbPath);
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'initialize repairs legacy stock_batches schema before creating indexes',
    () async {
      await DatabaseService.initialize();

      final columns = await DatabaseService.db.rawQuery(
        "PRAGMA table_info('stock_batches')",
      );
      final columnNames = columns
          .map((row) => row['name'] as String? ?? '')
          .toSet();

      final indexes = await DatabaseService.db.rawQuery(
        "PRAGMA index_list('stock_batches')",
      );
      final indexNames = indexes
          .map((row) => row['name'] as String? ?? '')
          .toSet();

      expect(columnNames, contains('purchase_id'));
      expect(indexNames, contains('idx_stock_batches_purchase_id'));
    },
  );

  test('initialize adds branch routing to catalog orders', () async {
    await DatabaseService.initialize();

    final columns = await DatabaseService.db.rawQuery(
      "PRAGMA table_info('public_catalog_orders')",
    );
    final columnNames = columns
        .map((row) => row['name'] as String? ?? '')
        .toSet();

    expect(columnNames, contains('branch_id'));
  });
}
