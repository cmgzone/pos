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
import 'package:pos_app/features/app/app_shell.dart';
import 'package:pos_app/features/loyalty/presentation/loyalty_screen.dart';
import 'package:pos_app/features/products/data/product_provider.dart';
import 'package:pos_app/features/sales/data/cart_provider.dart';
import 'package:pos_app/features/sales/data/held_sale_provider.dart';
import 'package:pos_app/features/shifts/data/shift_provider.dart';
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
      'current_user_id': 'restaurant-launch-admin',
      'current_user_name': 'Restaurant manager',
      'current_user_role': RolePermissions.admin,
      'setup_checklist_dismissed_restaurant-launch-admin': true,
      'training.prompt_dismissed.restaurant-launch-admin': true,
    });
    await SessionService.init();
    ShopSettings.resetForTesting();
    await ShopSettings.init();
    tempDir = await Directory.systemTemp.createTemp('piki-restaurant-launch-');
    await DatabaseService.overrideDatabasePathForTesting(
      p.join(tempDir.path, 'restaurant-launch.db'),
    );
    await DatabaseService.initialize();
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets(
    'restaurant workspace opens restaurant service without retail feature grid',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 1600);
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
            home: const AppShell(runStartupTasks: false),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('Floor, kitchen & bills ready'), findsOneWidget);
      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(find.textContaining('tools ready'), findsAtLeastNWidgets(1));

      await tester.tap(find.text('Restaurant'));
      tester.view.physicalSize = const Size(360, 720);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('CORE FEATURES'), findsNothing);
      expect(find.text('POS'), findsNothing);
      expect(find.text('Floor plan'), findsOneWidget);
      expect(find.text('Kitchen board'), findsOneWidget);
      expect(find.text('Bills'), findsOneWidget);
      expect(find.byTooltip('Add table'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'embedded mobile POS removes duplicate and dead navigation icons',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            syncControllerProvider.overrideWith(_TestSyncController.new),
            posCategoriesProvider.overrideWith((ref) async => const []),
            filteredProductsProvider.overrideWith((ref) async => const []),
          ],
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: 'Inter',
              colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
            ),
            home: const AppShell(initialIndex: 0, runStartupTasks: false),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byIcon(Icons.menu), findsNothing);
      expect(find.byTooltip('All modules'), findsNothing);
      expect(find.byTooltip('Notifications'), findsOneWidget);
      final pikiAutoListen = find.byKey(
        const ValueKey('pos-header-piki-auto-listen'),
      );
      expect(pikiAutoListen, findsOneWidget);
      expect(find.text('Quick picks'), findsNothing);
      expect(
        (tester.getCenter(pikiAutoListen).dy -
                tester.getCenter(find.byTooltip('Notifications')).dy)
            .abs(),
        lessThan(2),
      );
      expect(
        find.byKey(const ValueKey('pos-header-module-badge')),
        findsNothing,
      );
      expect(find.text(ShopSettings.shopName), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      expect(
        find.byKey(const ValueKey('business-header-logo')),
        findsOneWidget,
      );
      expect(find.text('Sale'), findsOneWidget);
      expect(find.text('Quotation'), findsOneWidget);
      final modeTabs = find.byKey(const ValueKey('pos-mode-tabs'));
      final moduleNavigation = find.byKey(
        const ValueKey('module-navigation-bar'),
      );
      expect(
        find.descendant(of: moduleNavigation, matching: modeTabs),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AppBar), matching: modeTabs),
        findsNothing,
      );
      expect(
        (tester.getCenter(modeTabs).dy -
                tester.getCenter(find.byTooltip('Notifications')).dy)
            .abs(),
        lessThan(2),
      );
      expect(
        find.descendant(of: modeTabs, matching: find.byType(Icon)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(320, 700);
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reference-style product card fits compact POS layouts', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncControllerProvider.overrideWith(_TestSyncController.new),
          cartProvider.overrideWith(_TestCartNotifier.new),
          heldSalesProvider.overrideWith((ref) async => const []),
          currentShiftProvider.overrideWith((ref) async => null),
          currentShiftSummaryProvider.overrideWith((ref) async => const {}),
          posCategoriesProvider.overrideWith((ref) async => const []),
          filteredProductsProvider.overrideWith(
            (ref) async => const [
              {
                'id': 'reference-card-product',
                'name': 'Wireless Headphones',
                'price': 4999.0,
                'old_price': 5500.0,
                'rating': 4.8,
                'review_count': 125,
                'sold_count': 320,
                'stock': 128.0,
                'low_stock': 5.0,
              },
            ],
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Inter',
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
          ),
          home: const AppShell(initialIndex: 0, runStartupTasks: false),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      find.byKey(const ValueKey('pos-product-card-reference-card-product')),
      findsOneWidget,
    );
    expect(find.text('Wireless Headphones'), findsOneWidget);
    expect(find.text('KSh 4,999'), findsOneWidget);
    expect(find.text('KSh 5,500'), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.text('Add to Cart'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(320, 700);
    await tester.pump(const Duration(milliseconds: 220));
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('(125)'), findsOneWidget);
    expect(find.text('Sold 320'), findsOneWidget);
    expect(find.text('Current Sale'), findsOneWidget);
    expect(find.text('Edit quantity'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && (widget.data ?? '').startsWith('Pay '),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('loyalty shows only customers with points and keeps settings', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 700);
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
          home: LoyaltyScreen(
            loadRules: () async => const {'is_active': 1},
            loadCustomers: () async => const [
              {
                'id': 'customer-with-points',
                'name': 'Amina Points',
                'phone': '0700000001',
                'loyalty_points': 120,
              },
              {
                'id': 'customer-without-points',
                'name': 'Zero Balance',
                'phone': '0700000002',
                'loyalty_points': 0,
              },
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Customers with points'), findsOneWidget);
    expect(find.text('Amina Points'), findsOneWidget);
    expect(find.text('120 pts'), findsOneWidget);
    expect(find.text('Zero Balance'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Settings'), findsOneWidget);
    expect(find.text('Loyalty is Active'), findsNothing);
    expect(find.text('How it works'), findsNothing);
    expect(find.text('Earn rate'), findsNothing);
    expect(find.text('Gift card reward'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin can navigate every module without phone overflows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncControllerProvider.overrideWith(_TestSyncController.new),
          posCategoriesProvider.overrideWith((ref) async => const []),
          filteredProductsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'Inter',
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
          ),
          home: const AppShell(runStartupTasks: false),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    const moduleIndices = <int>[
      35,
      5,
      0,
      36,
      4,
      1,
      12,
      2,
      3,
      15,
      18,
      19,
      20,
      6,
      8,
      34,
      7,
      10,
      21,
      22,
      23,
      27,
      31,
      30,
      9,
      13,
      14,
      24,
      25,
      26,
      28,
      32,
      33,
      16,
    ];

    for (final index in moduleIndices) {
      AppShell.selectIndex(index);
      await tester.pump(const Duration(milliseconds: 180));
      expect(
        tester.takeException(),
        isNull,
        reason: 'Module index $index produced a layout or navigation error',
      );
    }
  });

  testWidgets('module launcher fits a compact desktop window', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 640);
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
          home: const AppShell(runStartupTasks: false),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Today at a glance'), findsOneWidget);
    expect(find.text('Choose your workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retail launcher replaces banner with module search', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 800);
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
          home: const AppShell(runStartupTasks: false),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    await tester.tap(find.text('Retail POS'));
    await tester.pump(const Duration(milliseconds: 700));

    final searchField = find.byKey(
      const ValueKey('retail-module-search-field'),
    );
    expect(searchField, findsOneWidget);
    expect(find.text('Today at a glance'), findsNothing);

    await tester.enterText(searchField, 'Purchases');
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('1 module found'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'Purchases',
      ),
      findsOneWidget,
    );
    expect(find.text('POS'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.enterText(searchField, 'not a module');
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('No retail modules found'), findsOneWidget);

    tester.view.physicalSize = const Size(360, 720);
    await tester.pump(const Duration(milliseconds: 220));

    expect(searchField, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retail launcher uses a stacked two-column mobile grid', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> openRetail() async {
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
            home: const AppShell(runStartupTasks: false),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text('Retail POS'));
      await tester.pump(const Duration(milliseconds: 700));
    }

    await openRetail();
    for (final size in const [
      Size(320, 720),
      Size(360, 720),
      Size(390, 800),
      Size(430, 800),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump(const Duration(milliseconds: 300));
      // Mobile search placeholder and hidden shortcut.
      expect(find.text('Search modules...'), findsOneWidget);
      expect(find.text('Ctrl + K'), findsNothing);
      // Start Here modules are always present and must display fully.
      expect(find.text('POS'), findsWidgets);
      expect(find.text('Dashboard'), findsWidgets);
      // No layout overflow at narrow widths.
      expect(tester.takeException(), isNull);
    }
  });
}

class _TestSyncController extends SyncController {
  @override
  SyncState build() => SyncState.initial(isOnline: false);
}

class _TestCartNotifier extends CartNotifier {
  @override
  List<CartItem> build() => [
    CartItem(
      productId: 'reference-card-product',
      productName: 'Wireless Headphones',
      unitPrice: 4999,
      cost: 3000,
      maxStock: 128,
      stockOnHand: 128,
      saleToStockFactor: 1,
      unit: 'pcs',
      stockUnit: 'pcs',
    ),
  ];
}
