import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/core/services/license_service.dart';
import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/features/products/data/product_import_service.dart';
import 'package:pos_app/features/products/data/product_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LicenseService.init();
    await SessionService.init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await SessionService.signOut();
    await SessionService.signIn({
      'id': 'admin-1',
      'name': 'Admin',
      'email': 'admin@example.com',
      'role': RolePermissions.admin,
    });

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    tempDir = await Directory.systemTemp.createTemp(
      'pos-product-import-variant-test-',
    );
    await DatabaseService.overrideDatabasePathForTesting(
      p.join(tempDir.path, 'velora_pos.db'),
    );
    await DatabaseService.initialize();
    DatabaseService.setCurrentBranchId(DatabaseService.defaultBranchId);
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);
    await SessionService.signOut();

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'imports explicit variant rows under an existing parent product',
    () async {
      final parentId = await _createProduct('Fresh Milk');

      final result = await ProductImportService.importRows([
        ['name', 'variant_name', 'price', 'stock', 'barcode'],
        ['Fresh Milk', '500ml', '70', '24', 'MILK500'],
      ], fileName: 'milk.csv');

      expect(result.created, 1);
      expect(result.skipped, 0);

      final variants = await _variantsFor(parentId);
      expect(variants, hasLength(1));
      expect(variants.single['name'], '500ml');
      expect(variants.single['barcode'], 'MILK500');
      expect((variants.single['price'] as num).toDouble(), 70);
      expect((variants.single['stock'] as num).toDouble(), 24);

      final parent = await ProductRepository.getById(parentId);
      expect(parent?['has_variants'], 1);
      expect((parent?['stock'] as num).toDouble(), 24);
    },
  );

  test(
    'infers a variant from product name when parent already exists',
    () async {
      final parentId = await _createProduct('Fresh Milk');

      final result = await ProductImportService.importRows([
        ['name', 'price', 'stock'],
        ['Fresh Milk 500ml', '70', '24'],
      ], fileName: 'milk.csv');

      expect(result.created, 1);
      expect(result.skipped, 0);

      final variants = await _variantsFor(parentId);
      expect(variants, hasLength(1));
      expect(variants.single['name'], '500ml');

      final duplicateProducts = await _productsNamed('Fresh Milk 500ml');
      expect(duplicateProducts, isEmpty);
    },
  );

  test(
    'creates a parent plus variant when row has full name and variant name',
    () async {
      final result = await ProductImportService.importRows([
        ['name', 'variant_name', 'price', 'stock'],
        ['Fresh Milk 500ml', '500ml', '70', '24'],
      ], fileName: 'milk.csv');

      expect(result.created, 1);
      expect(result.skipped, 0);

      final parents = await _productsNamed('Fresh Milk');
      expect(parents, hasLength(1));
      expect((parents.single['stock'] as num).toDouble(), 24);

      final variants = await _variantsFor(parents.single['id'] as String);
      expect(variants, hasLength(1));
      expect(variants.single['name'], '500ml');

      final duplicateProducts = await _productsNamed('Fresh Milk 500ml');
      expect(duplicateProducts, isEmpty);
    },
  );

  test(
    'keeps a variant-looking name as a product when no parent matches',
    () async {
      final result = await ProductImportService.importRows([
        ['name', 'price', 'stock'],
        ['Fresh Milk 500ml', '70', '24'],
      ], fileName: 'milk.csv');

      expect(result.created, 1);
      expect(result.skipped, 0);

      final products = await _productsNamed('Fresh Milk 500ml');
      expect(products, hasLength(1));
      expect((products.single['stock'] as num).toDouble(), 24);

      final variants = await DatabaseService.rawQuery(
        'SELECT * FROM product_variants WHERE deleted_at IS NULL',
      );
      expect(variants, isEmpty);
    },
  );
}

Future<String> _createProduct(String name) {
  return ProductRepository.create(name: name, price: 0, stock: 0);
}

Future<List<Map<String, dynamic>>> _productsNamed(String name) {
  return DatabaseService.rawQuery(
    '''
    SELECT *
    FROM products
    WHERE name = ?
      AND deleted_at IS NULL
      AND COALESCE(branch_id, ?) = ?
    ''',
    [name, DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
  );
}

Future<List<Map<String, dynamic>>> _variantsFor(String productId) {
  return DatabaseService.rawQuery(
    '''
    SELECT *
    FROM product_variants
    WHERE product_id = ?
      AND deleted_at IS NULL
      AND COALESCE(branch_id, ?) = ?
    ORDER BY name ASC
    ''',
    [
      productId,
      DatabaseService.defaultBranchId,
      DatabaseService.currentBranchId,
    ],
  );
}
