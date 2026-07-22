import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/features/sales/data/sale_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String testDbPath;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    tempDir = await Directory.systemTemp.createTemp(
      'pos-sale-refund-test-',
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
    'getRefundableItems returns correct quantities from a single UNION ALL refund query',
    () async {
      final now = DateTime.now().toIso8601String();
      const branchId = 'main_branch';

      await DatabaseService.db.insert('products', {
        'id': 'product-cable',
        'branch_id': branchId,
        'name': 'USB Cable',
        'price': 10.0,
        'cost': 4.0,
        'stock': 100.0,
        'low_stock': 5.0,
        'unit': 'pcs',
        'stock_unit': 'pcs',
        'sale_unit': 'pcs',
        'sale_to_stock_factor': 1.0,
        'purchase_unit': 'pcs',
        'purchase_to_stock_factor': 1.0,
        'track_stock': 1,
        'has_variants': 0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      await DatabaseService.db.insert('services', {
        'id': 'service-install',
        'branch_id': branchId,
        'name': 'Installation',
        'base_price': 25.0,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      await DatabaseService.db.insert('sales', {
        'id': 'sale-1',
        'branch_id': branchId,
        'total_amount': 35.0,
        'tax': 0.0,
        'discount': 0.0,
        'payment_type': 'cash',
        'amount_paid': 35.0,
        'amount_tendered': 35.0,
        'change_given': 0.0,
        'balance_due': 0.0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      await DatabaseService.db.insert('sale_items', {
        'id': 'item-1',
        'sale_id': 'sale-1',
        'product_id': 'product-cable',
        'quantity': 3.0,
        'unit_price': 10.0,
        'unit_cost': 4.0,
        'unit': 'pcs',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      await DatabaseService.db.insert('service_sale_items', {
        'id': 'service-item-1',
        'sale_id': 'sale-1',
        'service_id': 'service-install',
        'service_name': 'Installation',
        'quantity': 1.0,
        'unit_price': 25.0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      // Refund sale: return 1 cable and 1 installation.
      await DatabaseService.db.insert('sales', {
        'id': 'refund-1',
        'branch_id': branchId,
        'total_amount': -35.0,
        'tax': 0.0,
        'discount': 0.0,
        'payment_type': 'refund_cash',
        'refund_for_sale_id': 'sale-1',
        'amount_paid': 0.0,
        'amount_tendered': 0.0,
        'change_given': 0.0,
        'balance_due': 0.0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      await DatabaseService.db.insert('sale_items', {
        'id': 'refund-item-1',
        'sale_id': 'refund-1',
        'product_id': 'product-cable',
        'quantity': -1.0,
        'unit_price': 10.0,
        'unit_cost': 4.0,
        'unit': 'pcs',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      await DatabaseService.db.insert('service_sale_items', {
        'id': 'refund-service-item-1',
        'sale_id': 'refund-1',
        'service_id': 'service-install',
        'service_name': 'Installation',
        'quantity': -1.0,
        'unit_price': 25.0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      final refundableItems = await SaleRepository.getRefundableItems('sale-1');

      // Fully refunded service line is filtered out.
      expect(refundableItems.length, 1);

      final productItem = refundableItems.firstWhere(
        (item) => item['line_type'] == 'product',
      );
      expect(
        (productItem['sold_quantity'] as num).toDouble(),
        3.0,
      );
      expect(
        (productItem['refunded_quantity'] as num).toDouble(),
        1.0,
      );
      expect(
        (productItem['refundable_quantity'] as num).toDouble(),
        2.0,
      );

      expect(
        refundableItems.any((item) => item['line_type'] == 'service'),
        isFalse,
      );
    },
  );
  test(
    'createSale rejects combined product lines that exceed available stock',
    () async {
      final now = DateTime.now().toIso8601String();
      const branchId = 'main_branch';

      await DatabaseService.db.insert('products', {
        'id': 'product-cable',
        'branch_id': branchId,
        'name': 'USB Cable',
        'price': 10.0,
        'cost': 4.0,
        'stock': 5.0,
        'low_stock': 1.0,
        'unit': 'pcs',
        'stock_unit': 'pcs',
        'sale_unit': 'pcs',
        'sale_to_stock_factor': 1.0,
        'purchase_unit': 'pcs',
        'purchase_to_stock_factor': 1.0,
        'track_stock': 1,
        'has_variants': 0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      await DatabaseService.db.insert('stock_batches', {
        'id': 'batch-cable',
        'product_id': 'product-cable',
        'branch_id': branchId,
        'quantity_received': 5.0,
        'quantity_remaining': 5.0,
        'unit_cost': 4.0,
        'received_at': now,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      await expectLater(
        SaleRepository.createSale(
          totalAmount: 60.0,
          tax: 0.0,
          discount: 0.0,
          paymentType: 'cash',
          userId: 'cashier-1',
          items: const [
            {
              'product_id': 'product-cable',
              'quantity': 3.0,
              'unit_price': 10.0,
            },
            {
              'product_id': 'product-cable',
              'quantity': 3.0,
              'unit_price': 10.0,
            },
          ],
        ),
        throwsA(isA<Exception>()),
      );

      final products = await DatabaseService.rawQuery(
        'SELECT stock FROM products WHERE id = ?',
        ['product-cable'],
      );
      final batches = await DatabaseService.rawQuery(
        'SELECT quantity_remaining FROM stock_batches WHERE id = ?',
        ['batch-cable'],
      );
      final sales = await DatabaseService.rawQuery('SELECT id FROM sales');

      expect((products.single['stock'] as num).toDouble(), 5.0);
      expect((batches.single['quantity_remaining'] as num).toDouble(), 5.0);
      expect(sales, isEmpty);
    },
  );
}
