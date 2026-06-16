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
      'pos-product-lookup-test-',
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

  test('getAll returns active_variant_count from grouped join', () async {
    final now = DateTime.now().toIso8601String();

    await DatabaseService.db.insert('products', {
      'id': 'product-shirt',
      'branch_id': DatabaseService.defaultBranchId,
      'name': 'Shirt',
      'price': 50.0,
      'cost': 20.0,
      'stock': 10.0,
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
      'id': 'variant-red',
      'product_id': 'product-shirt',
      'branch_id': DatabaseService.defaultBranchId,
      'name': 'Red',
      'price': 55.0,
      'cost': 22.0,
      'stock': 4.0,
      'low_stock': 1.0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    await DatabaseService.db.insert('product_variants', {
      'id': 'variant-blue',
      'product_id': 'product-shirt',
      'branch_id': DatabaseService.defaultBranchId,
      'name': 'Blue',
      'price': 55.0,
      'cost': 22.0,
      'stock': 6.0,
      'low_stock': 1.0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    final results = await ProductRepository.getAll();
    final product = results.firstWhere((row) => row['id'] == 'product-shirt');

    expect((product['active_variant_count'] as num).toInt(), 2);
  });

  test('lookupBarcode returns variant row with parent product details', () async {
    final now = DateTime.now().toIso8601String();

    await DatabaseService.db.insert('products', {
      'id': 'product-hat',
      'branch_id': DatabaseService.defaultBranchId,
      'name': 'Hat',
      'price': 30.0,
      'cost': 12.0,
      'stock': 20.0,
      'low_stock': 3.0,
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
      'id': 'variant-green',
      'product_id': 'product-hat',
      'branch_id': DatabaseService.defaultBranchId,
      'name': 'Green',
      'price': 35.0,
      'cost': 14.0,
      'stock': 5.0,
      'low_stock': 1.0,
      'barcode': 'HAT-GREEN-001',
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    final result = await ProductRepository.lookupBarcode('HAT-GREEN-001');

    expect(result, isNotNull);
    expect(result!['result_type'], 'variant');
    expect(result['id'], 'product-hat');
    expect(result['name'], 'Hat');
    expect(result['variant_id'], 'variant-green');
    expect(result['variant_name'], 'Green');
    expect(result['variant_barcode'], 'HAT-GREEN-001');
    expect((result['variant_price'] as num).toDouble(), 35.0);
  });

  test('lookupBarcode returns simple product row', () async {
    final now = DateTime.now().toIso8601String();

    await DatabaseService.db.insert('products', {
      'id': 'product-mug',
      'branch_id': DatabaseService.defaultBranchId,
      'name': 'Mug',
      'price': 15.0,
      'cost': 6.0,
      'stock': 50.0,
      'low_stock': 5.0,
      'unit': 'pcs',
      'stock_unit': 'pcs',
      'sale_unit': 'pcs',
      'sale_to_stock_factor': 1.0,
      'purchase_unit': 'pcs',
      'purchase_to_stock_factor': 1.0,
      'barcode': 'MUG-001',
      'track_stock': 1,
      'has_variants': 0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    final result = await ProductRepository.lookupBarcode('MUG-001');

    expect(result, isNotNull);
    expect(result!['result_type'], 'product');
    expect(result['id'], 'product-mug');
    expect(result['name'], 'Mug');
    expect(result['variant_id'], isNull);
  });

  test('lookupBarcode returns null for unknown barcode', () async {
    final result = await ProductRepository.lookupBarcode('UNKNOWN-BARCODE');
    expect(result, isNull);
  });
}
