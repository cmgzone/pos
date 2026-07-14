import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/core/services/shop_settings.dart';
import 'package:pos_app/core/services/sync_controller.dart';
import 'package:pos_app/core/theme/app_colors.dart';
import 'package:pos_app/features/restaurant/presentation/restaurant_payment_screen.dart';
import 'package:pos_app/features/restaurant/presentation/restaurant_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({
      'currency': 'KSh',
      'current_user_id': 'restaurant-layout-admin',
      'current_user_name': 'Restaurant manager',
      'current_user_role': RolePermissions.admin,
    });
    await SessionService.init();
    ShopSettings.resetForTesting();
    await ShopSettings.init();
    tempDir = await Directory.systemTemp.createTemp('piki-restaurant-layout-');
    await DatabaseService.overrideDatabasePathForTesting(
      p.join(tempDir.path, 'restaurant.db'),
    );
    await DatabaseService.initialize();
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.insert('users', {
      'id': 'restaurant-layout-admin',
      'name': 'Restaurant manager',
      'email': 'layout-manager@example.com',
      'password': 'test-only',
      'role': RolePermissions.admin,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'synced',
    });
    await _seedOrder();
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpOrder(
    WidgetTester tester,
    Size size, {
    Map<String, dynamic>? initialTable,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncControllerProvider.overrideWith(_TestSyncController.new),
        ],
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Inter',
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
          ),
          home: RestaurantOrderScreen(
            tableId: 'table-1',
            orderId: 'order-1',
            tableName: 'Terrace 4',
            initialTable: initialTable ?? _previewTable,
            initialMenu: _previewMenu,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 350)),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Restaurant menu').evaluate().isNotEmpty) break;
    }
  }

  testWidgets('table order fits a compact phone without overflow', (
    tester,
  ) async {
    await pumpOrder(tester, const Size(360, 720));

    expect(
      find.text('Restaurant menu'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.text('Order (1)'), findsOneWidget);
    expect(find.text('Grilled tilapia'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('table order shows menu and ticket together on desktop', (
    tester,
  ) async {
    await pumpOrder(tester, const Size(1280, 800));

    expect(
      find.text('Restaurant menu'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.text('Order T1001'), findsOneWidget);
    expect(find.text('Send 1 to kitchen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restaurant payment stays focused on the table bill on phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Inter',
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        ),
        home: const RestaurantPaymentScreen(
          billId: 'bill-1',
          initialBill: _previewBill,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Table payment'), findsOneWidget);
    expect(find.text('Grilled tilapia'), findsOneWidget);
    expect(find.text('Choose payment'), findsOneWidget);
    expect(find.text('Products'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one bill commits and opens table payment immediately', (
    tester,
  ) async {
    final readyTable = Map<String, dynamic>.from(_previewTable)
      ..['items'] = [
        {
          ..._previewTable['items']!.first as Map<String, dynamic>,
          'status': 'served',
        },
      ];
    await pumpOrder(tester, const Size(360, 800), initialTable: readyTable);

    await tester.tap(find.text('Order (1)'));
    await tester.pump();
    await tester.tap(find.text('Prepare bill'));
    await tester.pumpAndSettle();
    expect(find.text('One bill'), findsOneWidget);

    await tester.tap(find.text('One bill'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 2)),
    );
    for (var i = 0; i < 20; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Choose payment').evaluate().isNotEmpty) break;
    }

    expect(
      find.text('Table payment'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    expect(find.text('Choose payment'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

const _previewTable = <String, dynamic>{
  'id': 'table-1',
  'name': 'Terrace 4',
  'order_id': 'order-1',
  'order_no': 'T1001',
  'guest_count': 2,
  'total': 850.0,
  'items': <Map<String, dynamic>>[
    <String, dynamic>{
      'id': 'item-1',
      'product_id': 'fish',
      'product_name': 'Grilled tilapia',
      'quantity': 1.0,
      'unit_price': 850.0,
      'cost': 0.0,
      'unit': 'item',
      'status': 'draft',
    },
  ],
};

const _previewMenu = <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 'fish',
    'name': 'Grilled tilapia',
    'price': 850.0,
    'category_name': 'Mains',
  },
];

const _previewBill = <String, dynamic>{
  'id': 'bill-1',
  'name': 'Terrace 4 · Bill 1/1',
  'source': 'restaurant',
  'source_ref': 'order-1',
  'subtotal': 850.0,
  'tax': 0.0,
  'discount': 0.0,
  'total': 850.0,
  'items': <Map<String, dynamic>>[
    <String, dynamic>{
      'product_id': 'fish',
      'product_name': 'Grilled tilapia',
      'quantity': 1.0,
      'unit_price': 850.0,
      'cost': 0.0,
      'unit': 'item',
    },
  ],
};

class _TestSyncController extends SyncController {
  @override
  SyncState build() => SyncState.initial(isOnline: false);
}

Future<void> _seedOrder() async {
  final now = DateTime.now().toIso8601String();
  await DatabaseService.db.insert('categories', {
    'id': 'mains',
    'branch_id': DatabaseService.defaultBranchId,
    'name': 'Mains',
    'created_at': now,
    'updated_at': now,
    'sync_status': 'synced',
  });
  await DatabaseService.db.insert('products', {
    'id': 'fish',
    'branch_id': DatabaseService.defaultBranchId,
    'name': 'Grilled tilapia',
    'price': 850,
    'stock': 0,
    'low_stock': 0,
    'unit': 'item',
    'stock_unit': 'item',
    'sale_unit': 'item',
    'sale_to_stock_factor': 1,
    'purchase_unit': 'item',
    'purchase_to_stock_factor': 1,
    'is_restaurant_menu': 1,
    'category_id': 'mains',
    'track_stock': 0,
    'has_variants': 0,
    'created_at': now,
    'updated_at': now,
    'sync_status': 'synced',
  });
  final items = [
    {
      'id': 'item-1',
      'product_id': 'fish',
      'product_name': 'Grilled tilapia',
      'quantity': 1.0,
      'unit_price': 850.0,
      'cost': 0.0,
      'unit': 'item',
      'status': 'draft',
    },
  ];
  await DatabaseService.db.insert('table_orders', {
    'id': 'order-1',
    'branch_id': DatabaseService.defaultBranchId,
    'table_id': 'table-1',
    'order_no': 'T1001',
    'status': 'open',
    'guest_count': 2,
    'items_json': jsonEncode(items),
    'subtotal': 850,
    'tax': 0,
    'discount': 0,
    'total': 850,
    'split_count': 1,
    'opened_at': now,
    'created_at': now,
    'updated_at': now,
    'sync_status': 'synced',
  });
  await DatabaseService.db.insert('restaurant_tables', {
    'id': 'table-1',
    'branch_id': DatabaseService.defaultBranchId,
    'name': 'Terrace 4',
    'area': 'Terrace',
    'seats': 4,
    'status': 'occupied',
    'position_x': 0,
    'position_y': 0,
    'current_order_id': 'order-1',
    'created_at': now,
    'updated_at': now,
    'sync_status': 'synced',
  });
}
