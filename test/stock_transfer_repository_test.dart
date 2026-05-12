import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/core/services/license_service.dart';
import 'package:pos_app/features/products/data/stock_transfer_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LicenseService.init();

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    tempDir = await Directory.systemTemp.createTemp('pos-stock-transfer-test-');
    testDbPath = p.join(tempDir.path, 'velora_pos.db');

    await DatabaseService.overrideDatabasePathForTesting(testDbPath);
    await DatabaseService.initialize();
    DatabaseService.setCurrentBranchId(DatabaseService.defaultBranchId);
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('request, approve, and receive moves stock between branches', () async {
    final now = DateTime.now().toIso8601String();

    await DatabaseService.db.insert('branches', {
      'id': 'branch-b',
      'name': 'Branch B',
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    await _insertProduct(
      id: 'source-product',
      branchId: DatabaseService.defaultBranchId,
      stock: 10,
      cost: 40,
      now: now,
    );
    await _insertProduct(
      id: 'destination-product',
      branchId: 'branch-b',
      stock: 2,
      cost: 50,
      now: now,
    );
    await DatabaseService.db.insert('stock_batches', {
      'id': 'source-batch',
      'branch_id': DatabaseService.defaultBranchId,
      'product_id': 'source-product',
      'batch_number': 'SRC-1',
      'quantity_received': 10,
      'quantity_remaining': 10,
      'unit_cost': 40,
      'received_at': now,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    final transferId = await StockTransferRepository.requestTransfer(
      toBranchId: 'branch-b',
      productId: 'source-product',
      quantity: 3,
      note: 'Move display stock',
    );
    await StockTransferRepository.updateStatus(transferId, status: 'approved');

    DatabaseService.setCurrentBranchId('branch-b');
    await StockTransferRepository.updateStatus(transferId, status: 'received');

    final products = await DatabaseService.rawQuery(
      '''
      SELECT id, stock, cost
      FROM products
      WHERE id IN (?, ?)
      ORDER BY id
      ''',
      ['destination-product', 'source-product'],
    );
    final destination = products.firstWhere(
      (row) => row['id'] == 'destination-product',
    );
    final source = products.firstWhere((row) => row['id'] == 'source-product');

    expect((source['stock'] as num).toDouble(), 7);
    expect((destination['stock'] as num).toDouble(), 5);
    expect((destination['cost'] as num).toDouble(), 40);

    final transfer = await DatabaseService.queryById(
      'stock_transfers',
      transferId,
    );
    expect(transfer?['status'], 'received');
    expect(transfer?['received_at'], isNotNull);
  });
}

Future<void> _insertProduct({
  required String id,
  required String branchId,
  required double stock,
  required double cost,
  required String now,
}) {
  return DatabaseService.db.insert('products', {
    'id': id,
    'branch_id': branchId,
    'name': 'Leather Cleaner',
    'price': 120,
    'cost': cost,
    'stock': stock,
    'low_stock': 1,
    'unit': 'pcs',
    'stock_unit': 'pcs',
    'sale_unit': 'pcs',
    'sale_to_stock_factor': 1,
    'purchase_unit': 'pcs',
    'purchase_to_stock_factor': 1,
    'track_stock': 1,
    'has_variants': 0,
    'created_at': now,
    'updated_at': now,
    'sync_status': 'pending',
  });
}
