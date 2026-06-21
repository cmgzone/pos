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

    tempDir = await Directory.systemTemp.createTemp(
      'pos-variant-migration-test-',
    );
    testDbPath = p.join(tempDir.path, 'velora_pos.db');

    final legacyDatabase = await openDatabase(
      testDbPath,
      version: 11,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE sale_items (
            id TEXT PRIMARY KEY,
            sale_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            quantity REAL NOT NULL DEFAULT 0
          )
        ''');
        await database.execute('''
          CREATE TABLE held_sale_items (
            id TEXT PRIMARY KEY,
            held_sale_id TEXT NOT NULL,
            product_id TEXT NOT NULL,
            product_name TEXT NOT NULL,
            quantity REAL NOT NULL DEFAULT 0,
            unit_price REAL NOT NULL DEFAULT 0,
            cost REAL NOT NULL DEFAULT 0,
            max_stock REAL NOT NULL DEFAULT 0,
            stock_on_hand REAL NOT NULL DEFAULT 0,
            sale_to_stock_factor REAL NOT NULL DEFAULT 1,
            line_type TEXT NOT NULL DEFAULT 'product',
            service_order_id TEXT,
            service_id TEXT,
            unit TEXT NOT NULL DEFAULT 'pcs',
            stock_unit TEXT NOT NULL DEFAULT 'pcs',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
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
    'initialize adds held sale variant columns needed for variant hold and resume',
    () async {
      await DatabaseService.initialize();

      final columns = await DatabaseService.db.rawQuery(
        "PRAGMA table_info('held_sale_items')",
      );
      final columnNames = columns
          .map((row) => row['name'] as String? ?? '')
          .toSet();

      expect(columnNames, contains('variant_id'));
      expect(columnNames, contains('variant_name'));

      final colorColumns = await DatabaseService.db.rawQuery(
        "PRAGMA table_info('product_variant_colors')",
      );
      final colorColumnNames = colorColumns
          .map((row) => row['name'] as String? ?? '')
          .toSet();

      expect(colorColumnNames, contains('variant_id'));
      expect(colorColumnNames, contains('image_url'));
    },
  );
}
