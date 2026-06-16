import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/core/services/local_business_reset_service.dart';
import 'package:pos_app/core/services/sync_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    SyncSettingsService.resetForTesting();
    await SyncSettingsService.init();
    await DatabaseService.overrideDatabasePathForTesting(':memory:');
    await DatabaseService.initialize();
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);
  });

  test('blocks business switch when local changes are pending', () async {
    await SyncSettingsService.setLocalBusinessId('business-old');
    await DatabaseService.db.insert('products', {
      'id': 'pending-product',
      'branch_id': DatabaseService.defaultBranchId,
      'name': 'Unsynced Product',
      'price': 100.0,
      'stock': 2.0,
      'low_stock': 0.0,
      'unit': 'pcs',
      'stock_unit': 'pcs',
      'sale_unit': 'pcs',
      'sale_to_stock_factor': 1.0,
      'purchase_unit': 'pcs',
      'purchase_to_stock_factor': 1.0,
      'track_stock': 1,
      'has_variants': 0,
      'created_at': '2026-06-14T00:00:00.000Z',
      'updated_at': '2026-06-14T00:00:00.000Z',
      'sync_status': 'pending',
    });

    await expectLater(
      LocalBusinessResetService.clearForBusinessSwitch(),
      throwsA(
        isA<BusinessSwitchBlockedException>()
            .having(
              (error) => error.unsyncedCount,
              'unsyncedCount',
              greaterThan(0),
            )
            .having(
              (error) => error.affectedTables,
              'affectedTables',
              contains('products'),
            ),
      ),
    );

    expect(SyncSettingsService.localBusinessId, 'business-old');
    expect(
      await DatabaseService.queryById('products', 'pending-product'),
      isNotNull,
    );
  });

  test(
    'allows first business setup when no business owns local data',
    () async {
      expect(SyncSettingsService.localBusinessId, isEmpty);

      await LocalBusinessResetService.clearForBusinessSwitch();

      expect(SyncSettingsService.localBusinessId, isEmpty);
    },
  );

  test('allows switching away from a fully synced business', () async {
    await SyncSettingsService.setLocalBusinessId('business-old');
    await DatabaseService.db.update('branches', {'sync_status': 'synced'});

    await LocalBusinessResetService.clearForBusinessSwitch();

    expect(SyncSettingsService.localBusinessId, isEmpty);
  });
}
