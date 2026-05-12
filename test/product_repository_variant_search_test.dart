import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/features/products/data/product_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    tempDir = await Directory.systemTemp.createTemp(
      'pos-product-variant-search-test-',
    );
    testDbPath = p.join(tempDir.path, 'velora_pos.db');

    await DatabaseService.overrideDatabasePathForTesting(testDbPath);
    await DatabaseService.initialize();
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'searchForPos returns variant rows with sellable price, cost, and stock',
    () async {
      final now = DateTime.now().toIso8601String();

      await DatabaseService.db.insert('products', {
        'id': 'product-sneaker',
        'branch_id': DatabaseService.defaultBranchId,
        'name': 'Sneaker',
        'price': 100.0,
        'cost': 40.0,
        'stock': 8.0,
        'low_stock': 2.0,
        'unit': 'pcs',
        'stock_unit': 'pcs',
        'sale_unit': 'pcs',
        'sale_to_stock_factor': 1.0,
        'purchase_unit': 'pcs',
        'purchase_to_stock_factor': 1.0,
        'track_stock': 1,
        'has_variants': 1,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      await DatabaseService.db.insert('product_variants', {
        'id': 'variant-ocean-blue',
        'product_id': 'product-sneaker',
        'branch_id': DatabaseService.defaultBranchId,
        'name': 'Ocean Blue',
        'price': 120.0,
        'cost': 50.0,
        'stock': 3.0,
        'low_stock': 1.0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      final results = await ProductRepository.searchForPos('Ocean Blue');
      final variantRow = results.firstWhere(
        (row) => row['matched_variant_id'] == 'variant-ocean-blue',
      );

      expect(variantRow['result_type'], 'variant');
      expect(variantRow['matched_variant_name'], 'Ocean Blue');
      expect((variantRow['matched_variant_price'] as num).toDouble(), 120.0);
      expect((variantRow['matched_variant_cost'] as num).toDouble(), 50.0);
      expect((variantRow['matched_variant_stock'] as num).toDouble(), 3.0);
    },
  );
}
