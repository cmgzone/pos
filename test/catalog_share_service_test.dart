import 'package:flutter_test/flutter_test.dart';
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
        'https://pos-e0hs.onrender.com/catalog/business-id?currency=KSh',
      );
    },
  );
}
