import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/constants/app_constants.dart';
import 'package:pos_app/core/services/catalog_qr_poster_service.dart';
import 'package:pos_app/core/services/catalog_share_service.dart';
import 'package:pos_app/core/services/shop_settings.dart';
import 'package:pos_app/core/services/sync_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'catalog link uses the public host even when sync points to localhost',
    () async {
      SharedPreferences.setMockInitialValues({
        'sync_backend_url': 'http://127.0.0.1:3000/api',
        'currency': 'KSh',
      });
      await ShopSettings.init();
      await SyncSettingsService.init();

      expect(SyncSettingsService.backendUrl, 'http://127.0.0.1:3000/api');
      expect(
        CatalogShareService.buildCatalogUrl('business-id'),
        'https://pikipos.com/catalog/business-id?branchId=main_branch&currency=KSh',
      );
    },
  );

  test('deprecated Render sync backend migrates to Piki production', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'sync_backend_url',
      'https://pos-e0hs.onrender.com/api',
    );

    await SyncSettingsService.init();

    expect(SyncSettingsService.backendUrl, AppConstants.productionApiBaseUrl);
  });

  test('bare production backend host normalizes to the API root', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_backend_url', 'pikipos.com');

    await SyncSettingsService.init();

    expect(SyncSettingsService.backendUrl, AppConstants.productionApiBaseUrl);
  });

  test('resetting sync progress clears the employee data scope', () async {
    await SyncSettingsService.setSyncScopeKey('employee:CASHIER:main_branch');
    expect(SyncSettingsService.syncScopeKey, 'employee:CASHIER:main_branch');

    await SyncSettingsService.resetSyncProgress();

    expect(SyncSettingsService.syncScopeKey, isEmpty);
  });

  test('catalog QR poster builds a publishable PDF', () async {
    const info = CatalogShareInfo(
      url: 'https://pikipos.com/catalog/business-id?currency=KSh',
      businessName: 'My Shop',
    );

    final poster = await CatalogQrPosterService.buildPoster(info);

    expect(poster, isNotEmpty);
    expect(String.fromCharCodes(poster.take(4)), '%PDF');
  });
}
