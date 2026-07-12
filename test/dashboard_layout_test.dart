import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_app/core/services/session_service.dart';
import 'package:pos_app/core/services/shop_settings.dart';
import 'package:pos_app/core/theme/app_theme.dart';
import 'package:pos_app/features/app/dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'current_user_id': 'admin-1',
      'current_user_name': 'Charles Michael',
      'current_user_role': RolePermissions.admin,
      'shop_name': 'Michael Store',
      'currency': 'KSh',
    });
    ShopSettings.resetForTesting();
    await ShopSettings.init();
    await SessionService.init();
  });

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required Size size,
    required ThemeMode themeMode,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: const DashboardScreen(
            initialData: DashboardData(
              todaySummary: {
                'total_revenue': 12450,
                'total_sales': 8,
                'total_profit': 4200,
              },
              monthSummary: {'total_revenue': 186500},
              topProductName: 'Milk 500ml',
              pendingOrders: 4,
              activeStaff: 6,
              lowStockProducts: [
                {'name': 'Milk 500ml', 'stock': 3, 'stock_unit': 'pcs'},
                {'name': 'Bread', 'stock': 2, 'stock_unit': 'pcs'},
              ],
              recentSales: [
                {
                  'id': 'sale-1024',
                  'total_amount': 2350,
                  'payment_type': 'Cash',
                  'created_at': '2026-06-14T10:30:00',
                },
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('QUICK ACTIONS').evaluate().isNotEmpty) break;
    }
  }

  testWidgets('dashboard fits a mobile screen in light mode', (tester) async {
    await pumpDashboard(
      tester,
      size: const Size(390, 844),
      themeMode: ThemeMode.light,
    );

    expect(find.textContaining('Charles'), findsOneWidget);
    expect(find.text('QUICK ACTIONS'), findsOneWidget);
    expect(find.text('Sell'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard fits a desktop window in dark mode', (tester) async {
    await pumpDashboard(
      tester,
      size: const Size(1366, 900),
      themeMode: ThemeMode.dark,
    );

    expect(find.text('Michael Store'), findsOneWidget);
    expect(find.text('Sales Today'), findsOneWidget);
    expect(find.text('Sales This Month'), findsOneWidget);
    expect(find.text('Profit Today'), findsOneWidget);
    expect(find.text('Top Product'), findsOneWidget);
    expect(find.text('Low Stock Items'), findsOneWidget);
    expect(find.text('Pending Orders'), findsOneWidget);
    expect(find.text('Active Staff'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
