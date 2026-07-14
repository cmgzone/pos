import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/features/restaurant/data/restaurant_repository.dart';
import 'package:pos_app/features/sales/data/held_sale_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({
      'current_user_id': 'admin-1',
      'current_user_name': 'Restaurant manager',
      'current_user_role': RolePermissions.admin,
    });
    await SessionService.init();
    tempDir = await Directory.systemTemp.createTemp('piki-restaurant-repo-');
    await DatabaseService.overrideDatabasePathForTesting(
      p.join(tempDir.path, 'restaurant.db'),
    );
    await DatabaseService.initialize();
    DatabaseService.setCurrentBranchId(DatabaseService.defaultBranchId);
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.insert('users', {
      'id': 'admin-1',
      'name': 'Restaurant manager',
      'email': 'manager@example.com',
      'password': 'test-only',
      'role': RolePermissions.admin,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'synced',
    });
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('restaurant menu excludes retail and variant-parent products', () async {
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.insert('categories', {
      'id': 'mains',
      'branch_id': DatabaseService.defaultBranchId,
      'name': 'Mains',
      'created_at': now,
      'updated_at': now,
      'sync_status': 'synced',
    });
    await _insertProduct(
      id: 'menu-fish',
      name: 'Grilled fish',
      menu: true,
      categoryId: 'mains',
      now: now,
    );
    await _insertProduct(
      id: 'retail-soap',
      name: 'Laundry soap',
      menu: false,
      now: now,
    );
    await _insertProduct(
      id: 'variant-parent',
      name: 'Pizza sizes',
      menu: true,
      hasVariants: true,
      now: now,
    );

    final menu = await RestaurantRepository.getMenuItems();

    expect(menu.map((item) => item['id']), ['menu-fish']);
    expect(menu.single['category_name'], 'Mains');
  });

  test(
    'preparing one bill commits promptly and keeps its audit in the same transaction',
    () async {
      final now = DateTime.now().toIso8601String();
      await _insertProduct(
        id: 'menu-tea',
        name: 'Masala tea',
        menu: true,
        now: now,
      );
      await DatabaseService.db.insert('table_orders', {
        'id': 'order-fast-bill',
        'branch_id': DatabaseService.defaultBranchId,
        'table_id': 'table-fast-bill',
        'order_no': 'T1002',
        'status': 'open',
        'guest_count': 1,
        'items_json': '[]',
        'subtotal': 180,
        'tax': 0,
        'discount': 0,
        'total': 180,
        'split_count': 1,
        'opened_at': now,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      });
      await DatabaseService.db.insert('restaurant_tables', {
        'id': 'table-fast-bill',
        'branch_id': DatabaseService.defaultBranchId,
        'name': 'Table 2',
        'seats': 2,
        'status': 'occupied',
        'position_x': 0,
        'position_y': 0,
        'current_order_id': 'order-fast-bill',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'synced',
      });

      final billIds = await RestaurantRepository.prepareBill(
        table: const {
          'id': 'table-fast-bill',
          'name': 'Table 2',
          'order_id': 'order-fast-bill',
          'items': [
            {
              'id': 'order-item-tea',
              'product_id': 'menu-tea',
              'product_name': 'Masala tea',
              'quantity': 1.0,
              'unit_price': 180.0,
              'cost': 40.0,
              'unit': 'item',
              'status': 'served',
            },
          ],
        },
      ).timeout(const Duration(seconds: 2));

      expect(billIds, hasLength(1));
      expect(await RestaurantRepository.getBill(billIds.single), isNotNull);
      final order = await DatabaseService.queryById(
        'table_orders',
        'order-fast-bill',
      );
      final table = await DatabaseService.queryById(
        'restaurant_tables',
        'table-fast-bill',
      );
      expect(order?['status'], 'checkout');
      expect(table?['status'], 'checkout');

      final auditRows = await DatabaseService.rawQuery(
        '''
        SELECT id FROM audit_logs
        WHERE action = ? AND entity_table = ? AND entity_id = ?
        ''',
        ['hold', 'held_sales', billIds.single],
      );
      expect(auditRows, hasLength(1));
    },
  );

  test(
    'paying the final restaurant bill records sale and releases table',
    () async {
      final now = DateTime.now().toIso8601String();
      await _insertProduct(
        id: 'menu-fish',
        name: 'Grilled fish',
        menu: true,
        now: now,
      );
      await DatabaseService.db.insert('table_orders', {
        'id': 'order-1',
        'branch_id': DatabaseService.defaultBranchId,
        'table_id': 'table-1',
        'order_no': 'T1001',
        'status': 'checkout',
        'guest_count': 2,
        'items_json': '[]',
        'subtotal': 500,
        'tax': 0,
        'discount': 0,
        'total': 500,
        'split_count': 1,
        'opened_at': now,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      await DatabaseService.db.insert('restaurant_tables', {
        'id': 'table-1',
        'branch_id': DatabaseService.defaultBranchId,
        'name': 'Terrace 1',
        'seats': 2,
        'status': 'checkout',
        'position_x': 0,
        'position_y': 0,
        'current_order_id': 'order-1',
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      final billId = await HeldSaleRepository.createHold(
        name: 'Terrace 1 · Bill 1/1',
        subtotal: 500,
        tax: 0,
        discount: 0,
        total: 500,
        userId: 'admin-1',
        cashierName: 'Restaurant manager',
        source: 'restaurant',
        sourceRef: 'order-1',
        items: const [
          {
            'product_id': 'menu-fish',
            'product_name': 'Grilled fish',
            'quantity': 1.0,
            'unit_price': 500.0,
            'cost': 0.0,
            'unit': 'item',
          },
        ],
      );

      final saleId = await RestaurantRepository.payBill(
        holdId: billId,
        paymentType: 'Card',
        isCashDrawer: false,
        paymentProvider: 'card',
        paymentStatus: 'paid',
      );

      expect(await DatabaseService.queryById('sales', saleId), isNotNull);
      expect(await RestaurantRepository.getBill(billId), isNull);
      final table = await DatabaseService.queryById(
        'restaurant_tables',
        'table-1',
      );
      final order = await DatabaseService.queryById('table_orders', 'order-1');
      expect(table?['status'], 'available');
      expect(table?['current_order_id'], isNull);
      expect(order?['status'], 'closed');
      expect(order?['closed_at'], isNotNull);
    },
  );
}

Future<void> _insertProduct({
  required String id,
  required String name,
  required bool menu,
  required String now,
  String? categoryId,
  bool hasVariants = false,
}) {
  return DatabaseService.db.insert('products', {
    'id': id,
    'branch_id': DatabaseService.defaultBranchId,
    'name': name,
    'price': 100,
    'stock': 0,
    'low_stock': 0,
    'unit': 'item',
    'stock_unit': 'item',
    'sale_unit': 'item',
    'sale_to_stock_factor': 1,
    'purchase_unit': 'item',
    'purchase_to_stock_factor': 1,
    'is_restaurant_menu': menu ? 1 : 0,
    'category_id': categoryId,
    'track_stock': 0,
    'has_variants': hasVariants ? 1 : 0,
    'created_at': now,
    'updated_at': now,
    'sync_status': 'synced',
  });
}
