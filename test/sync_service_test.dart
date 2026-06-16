import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/core/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('pull order applies parent rows before customer invoices and items', () {
    final order = SyncService.pullTableOrderForTesting;

    expect(order.indexOf('sales'), greaterThanOrEqualTo(0));
    expect(order.indexOf('services'), greaterThanOrEqualTo(0));
    expect(order.indexOf('customer_invoices'), greaterThanOrEqualTo(0));
    expect(order.indexOf('customer_invoice_items'), greaterThanOrEqualTo(0));

    expect(
      order.indexOf('sales'),
      lessThan(order.indexOf('customer_invoices')),
    );
    expect(
      order.indexOf('services'),
      lessThan(order.indexOf('customer_invoice_items')),
    );
    expect(
      order.indexOf('customer_invoices'),
      lessThan(order.indexOf('customer_invoice_items')),
    );
  });

  test(
    'cashier sync ignores local default branch placeholder errors',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues({});

      await DatabaseService.overrideDatabasePathForTesting(':memory:');
      await DatabaseService.initialize();
      await SessionService.signIn({
        'id': 'cashier-1',
        'name': 'Cashier',
        'role': RolePermissions.cashier,
      });
      await DatabaseService.db.update(
        'branches',
        {'sync_status': 'error'},
        where: 'id = ?',
        whereArgs: [DatabaseService.defaultBranchId],
      );

      await SyncService.normalizeLocalSystemRowsForTesting();
      final snapshot = await SyncService.getLocalSnapshot();

      expect(snapshot.errorCount, 0);
      expect(snapshot.pendingChanges['branches'], isEmpty);

      await DatabaseService.overrideDatabasePathForTesting(null);
    },
  );

  test(
    'synced local rows accept cloud stock revisions with older timestamps',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      await DatabaseService.overrideDatabasePathForTesting(':memory:');
      await DatabaseService.initialize();
      await DatabaseService.db.insert('products', {
        'id': 'product-1',
        'branch_id': DatabaseService.defaultBranchId,
        'name': 'Bread',
        'price': 60.0,
        'stock': 20.0,
        'low_stock': 5.0,
        'unit': 'pcs',
        'stock_unit': 'pcs',
        'sale_unit': 'pcs',
        'sale_to_stock_factor': 1.0,
        'purchase_unit': 'pcs',
        'purchase_to_stock_factor': 1.0,
        'track_stock': 1,
        'has_variants': 0,
        'created_at': '2026-06-12T12:18:25.153Z',
        'updated_at': '2026-06-12T12:18:25.153Z',
        'sync_status': 'synced',
      });

      await DatabaseService.db.transaction((txn) async {
        await SyncService.applyRemoteRowForTesting(txn, 'products', {
          'id': 'product-1',
          'branch_id': DatabaseService.defaultBranchId,
          'name': 'Bread',
          'price': 60.0,
          'stock': 17.0,
          'low_stock': 5.0,
          'unit': 'pcs',
          'stock_unit': 'pcs',
          'sale_unit': 'pcs',
          'sale_to_stock_factor': 1.0,
          'purchase_unit': 'pcs',
          'purchase_to_stock_factor': 1.0,
          'track_stock': 1,
          'has_variants': 0,
          'created_at': '2026-06-12T12:18:25.153Z',
          'updated_at': '2026-06-12T09:57:43.701Z',
          'sync_status': 'synced',
        });
      });

      final product = await DatabaseService.queryById('products', 'product-1');

      expect(product?['stock'], 17.0);
      expect(product?['updated_at'], '2026-06-12T09:57:43.701Z');

      await DatabaseService.overrideDatabasePathForTesting(null);
    },
  );

  test(
    'fresh pull skips deleted product tombstones with missing categories',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      await DatabaseService.overrideDatabasePathForTesting(':memory:');
      await DatabaseService.initialize();

      await DatabaseService.db.transaction((txn) async {
        await SyncService.applyRemoteRowForTesting(txn, 'products', {
          'id': 'deleted-product-1',
          'branch_id': DatabaseService.defaultBranchId,
          'name': 'Deleted Speaker',
          'price': 79.99,
          'stock': 0.0,
          'low_stock': 0.0,
          'unit': 'pcs',
          'stock_unit': 'pcs',
          'sale_unit': 'pcs',
          'sale_to_stock_factor': 1.0,
          'purchase_unit': 'pcs',
          'purchase_to_stock_factor': 1.0,
          'category_id': 'missing-category',
          'track_stock': 1,
          'has_variants': 0,
          'created_at': '2026-06-13T21:26:21.542Z',
          'updated_at': '2026-06-14T00:24:30.165Z',
          'deleted_at': '2026-06-14T00:24:30.165Z',
          'sync_status': 'synced',
        });
      });

      final product = await DatabaseService.queryById(
        'products',
        'deleted-product-1',
      );
      expect(product, isNull);

      await DatabaseService.overrideDatabasePathForTesting(null);
    },
  );
}
