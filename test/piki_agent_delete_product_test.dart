import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/core/services/license_service.dart';
import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/features/agent/data/piki_agent_service.dart';
import 'package:pos_app/features/products/data/product_repository.dart';
import 'package:pos_app/features/products/data/product_variant_repository.dart';
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
      'pos-piki-delete-product-test-',
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

  test('delete_product soft-deletes a matching product', () async {
    final productId = await ProductRepository.create(
      name: 'Delete Me',
      price: 25,
      stock: 4,
    );

    final result = await PikiAgentService.executeAgentTool(
      PikiAgentService.toolDeleteProduct,
      args: {'query': 'Delete Me'},
    );

    expect(result['success'], isTrue);
    expect(result['deleted_type'], 'product');
    expect(result['product_id'], productId);

    final row = await DatabaseService.queryById('products', productId);
    expect(row?['deleted_at'], isNotNull);
    expect(await ProductRepository.searchForPos('Delete Me'), isEmpty);
  });

  test(
    'delete_product can delete a matched variant and resync parent stock',
    () async {
      final productId = await ProductRepository.create(
        name: 'Sneaker',
        price: 100,
        stock: 0,
        hasVariants: true,
      );
      final blueVariantId = await ProductVariantRepository.create(
        productId: productId,
        name: 'Blue',
        price: 120,
        stock: 3,
      );
      await ProductVariantRepository.create(
        productId: productId,
        name: 'Red',
        price: 125,
        stock: 5,
      );
      await ProductVariantRepository.syncAggregateStock(productId);

      final result = await PikiAgentService.executeAgentTool(
        PikiAgentService.toolDeleteProduct,
        args: {'query': 'Blue'},
      );

      expect(result['success'], isTrue);
      expect(result['deleted_type'], 'variant');
      expect(result['variant_id'], blueVariantId);

      final variant = await DatabaseService.queryById(
        'product_variants',
        blueVariantId,
      );
      expect(variant?['deleted_at'], isNotNull);

      final parent = await ProductRepository.getById(productId);
      expect((parent?['stock'] as num).toDouble(), 5);
    },
  );

  test('delete_product refuses ambiguous product matches', () async {
    await ProductRepository.create(name: 'Milk 500ml', price: 70);
    await ProductRepository.create(name: 'Milk 1L', price: 120);

    await expectLater(
      PikiAgentService.executeAgentTool(
        PikiAgentService.toolDeleteProduct,
        args: {'query': 'Milk'},
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('more than one product'),
        ),
      ),
    );

    expect(await ProductRepository.searchForPos('Milk'), hasLength(2));
  });
}
