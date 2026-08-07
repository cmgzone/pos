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

  test(
    'receiving auto-creates the product when the branch does not stock it',
    () async {
      final now = DateTime.now().toIso8601String();

      await DatabaseService.db.insert('branches', {
        'id': 'branch-b',
        'name': 'Branch B',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      await DatabaseService.db.insert('products', {
        'id': 'source-product',
        'branch_id': DatabaseService.defaultBranchId,
        'name': 'Engine Oil 5L',
        'price': 450,
        'cost': 300,
        'stock': 8,
        'low_stock': 2,
        'unit': 'pcs',
        'stock_unit': 'pcs',
        'sale_unit': 'pcs',
        'sale_to_stock_factor': 1,
        'purchase_unit': 'pcs',
        'purchase_to_stock_factor': 1,
        'barcode': 'ENG-OIL-5L',
        'track_stock': 1,
        'has_variants': 0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      await DatabaseService.db.insert('stock_batches', {
        'id': 'source-batch',
        'branch_id': DatabaseService.defaultBranchId,
        'product_id': 'source-product',
        'batch_number': 'SRC-1',
        'quantity_received': 8,
        'quantity_remaining': 8,
        'unit_cost': 300,
        'received_at': now,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      final transferId = await StockTransferRepository.requestTransfer(
        toBranchId: 'branch-b',
        productId: 'source-product',
        quantity: 5,
      );
      await StockTransferRepository.updateStatus(transferId, status: 'approved');

      DatabaseService.setCurrentBranchId('branch-b');
      await StockTransferRepository.updateStatus(transferId, status: 'received');

      final created = await DatabaseService.rawQuery(
        '''
        SELECT id, name, barcode, price, stock, sync_status
        FROM products
        WHERE COALESCE(branch_id, ?) = ? AND name = ?
        ''',
        [DatabaseService.defaultBranchId, 'branch-b', 'Engine Oil 5L'],
      );
      expect(created, hasLength(1));
      expect(created.single['id'], isNot('source-product'));
      expect(created.single['barcode'], 'ENG-OIL-5L');
      expect((created.single['price'] as num).toDouble(), 450);
      expect((created.single['stock'] as num).toDouble(), 5);
      expect(created.single['sync_status'], 'pending');

      final batches = await DatabaseService.rawQuery(
        'SELECT quantity_remaining, unit_cost FROM stock_batches WHERE product_id = ?',
        [created.single['id']],
      );
      expect(batches, hasLength(1));
      expect((batches.single['quantity_remaining'] as num).toDouble(), 5);
      expect((batches.single['unit_cost'] as num).toDouble(), 300);
    },
  );

  test('a branch can request stock in from another branch', () async {
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
      stock: 6,
      cost: 25,
      now: now,
    );
    await DatabaseService.db.insert('stock_batches', {
      'id': 'source-batch',
      'branch_id': DatabaseService.defaultBranchId,
      'product_id': 'source-product',
      'batch_number': 'SRC-1',
      'quantity_received': 6,
      'quantity_remaining': 6,
      'unit_cost': 25,
      'received_at': now,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });

    DatabaseService.setCurrentBranchId('branch-b');
    final transferId = await StockTransferRepository.requestStockIn(
      fromBranchId: DatabaseService.defaultBranchId,
      productId: 'source-product',
      quantity: 4,
      note: 'Running low',
    );

    var transfer = await DatabaseService.queryById(
      'stock_transfers',
      transferId,
    );
    expect(transfer?['status'], 'requested');
    expect(transfer?['from_branch_id'], DatabaseService.defaultBranchId);
    expect(transfer?['to_branch_id'], 'branch-b');

    DatabaseService.setCurrentBranchId(DatabaseService.defaultBranchId);
    await StockTransferRepository.updateStatus(transferId, status: 'approved');

    DatabaseService.setCurrentBranchId('branch-b');
    await StockTransferRepository.updateStatus(transferId, status: 'received');

    transfer = await DatabaseService.queryById('stock_transfers', transferId);
    expect(transfer?['status'], 'received');

    final source = await DatabaseService.queryById(
      'products',
      'source-product',
    );
    expect((source?['stock'] as num).toDouble(), 2);

    final created = await DatabaseService.rawQuery(
      '''
      SELECT id, stock
      FROM products
      WHERE COALESCE(branch_id, ?) = ? AND name = ?
      ''',
      [DatabaseService.defaultBranchId, 'branch-b', 'Leather Cleaner'],
    );
    expect(created, hasLength(1));
    expect((created.single['stock'] as num).toDouble(), 4);
  });

  test(
    'list for current branch joins branch names without ambiguous columns',
    () async {
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

      final transferId = await StockTransferRepository.requestTransfer(
        toBranchId: 'branch-b',
        productId: 'source-product',
        quantity: 2,
      );
      await StockTransferRepository.updateStatus(
        transferId,
        status: 'approved',
      );

      final transfers = await StockTransferRepository.getForCurrentBranch();
      final requestedTransfers =
          await StockTransferRepository.getForCurrentBranch(
            status: 'requested',
          );
      final approvedTransfers =
          await StockTransferRepository.getForCurrentBranch(status: 'approved');

      expect(transfers, hasLength(1));
      expect(transfers.single['id'], transferId);
      expect(transfers.single['from_branch_name'], isNotEmpty);
      expect(transfers.single['to_branch_name'], 'Branch B');
      expect(requestedTransfers, isEmpty);
      expect(approvedTransfers.single['id'], transferId);
    },
  );
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
