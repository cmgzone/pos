import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late String databasePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'pos-db-migration-test-',
    );
    databasePath =
        '${tempDirectory.path}${Platform.pathSeparator}legacy_velora_pos.db';

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final legacyDatabase = await openDatabase(
      databasePath,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE stock_batches (
            id TEXT PRIMARY KEY,
            product_id TEXT NOT NULL,
            quantity_received REAL NOT NULL DEFAULT 0,
            quantity_remaining REAL NOT NULL DEFAULT 0,
            unit_cost REAL NOT NULL DEFAULT 0,
            received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            finished_at TEXT,
            sync_status TEXT NOT NULL DEFAULT 'pending'
          )
        ''');
        await database.execute(
          'CREATE INDEX idx_stock_batches_product ON stock_batches(product_id)',
        );
        await database.execute('''
          CREATE TABLE stock_transfers (
            id TEXT PRIMARY KEY,
            from_branch_id TEXT NOT NULL,
            to_branch_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            quantity REAL NOT NULL DEFAULT 0
          )
        ''');
      },
    );
    await legacyDatabase.close();

    await DatabaseService.overrideDatabasePathForTesting(databasePath);
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'repairs legacy stock batch schema before creating new indexes',
    () async {
      await DatabaseService.initialize();

      final columns = (await DatabaseService.rawQuery(
        "PRAGMA table_info('stock_batches')",
      )).map((row) => row['name'] as String?).whereType<String>().toSet();

      expect(
        columns,
        containsAll(<String>[
          'purchase_id',
          'supplier_id',
          'expiry_date',
          'created_at',
          'updated_at',
          'deleted_at',
        ]),
      );

      final indexNames = (await DatabaseService.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index' AND tbl_name = 'stock_batches'
    ''')).map((row) => row['name'] as String?).whereType<String>().toSet();

      expect(indexNames, contains('idx_stock_batches_purchase_id'));
      expect(indexNames, contains('idx_stock_batches_received_at'));
      expect(indexNames, contains('idx_stock_batches_expiry_date'));

      final shiftTables = await DatabaseService.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table' AND name IN ('shifts', 'cash_movements', 'sales')
    ''');
      final tableNames = shiftTables
          .map((row) => row['name'] as String?)
          .whereType<String>()
          .toSet();

      expect(
        tableNames,
        containsAll(<String>['shifts', 'cash_movements', 'sales']),
      );

      final salesColumns = (await DatabaseService.rawQuery(
        "PRAGMA table_info('sales')",
      )).map((row) => row['name'] as String?).whereType<String>().toSet();

      expect(salesColumns, contains('shift_id'));

      final stockTransferColumns = (await DatabaseService.rawQuery(
        "PRAGMA table_info('stock_transfers')",
      )).map((row) => row['name'] as String?).whereType<String>().toSet();

      expect(
        stockTransferColumns,
        containsAll(<String>[
          'branch_id',
          'product_name',
          'unit',
          'status',
          'requested_by',
          'approved_by',
          'received_by',
          'note',
          'requested_at',
          'approved_at',
          'received_at',
          'created_at',
          'updated_at',
          'deleted_at',
          'sync_status',
        ]),
      );

      final stockTransferIndexNames = (await DatabaseService.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index' AND tbl_name = 'stock_transfers'
    ''')).map((row) => row['name'] as String?).whereType<String>().toSet();

      expect(
        stockTransferIndexNames,
        contains('idx_stock_transfers_from_to_status'),
      );
    },
  );
}
