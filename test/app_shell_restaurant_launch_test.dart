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
import 'package:pos_app/features/products/data/product_provider.dart';
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
      expect(
        find.byKey(const ValueKey('pos-header-module-badge')),
        findsNothing,
      );
      expect(find.text('Sale'), findsOneWidget);
      expect(find.text('Quotation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _TestSyncController extends SyncController {
  @override
  SyncState build() => SyncState.initial(isOnline: false);
}
