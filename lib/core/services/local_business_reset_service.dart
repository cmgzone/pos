import 'database_service.dart';
import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_settings_service.dart';

/// Clears business-owned local state when the device switches to a different
/// business account.
///
/// This app stores a single business snapshot locally, so switching businesses
/// must wipe the previous business's SQLite data and related preferences.
class LocalBusinessResetService {
  static Future<void> clearForBusinessSwitch() async {
    await SessionService.init();
    await SyncSettingsService.init();
    await ShopSettings.init();
    await SessionService.signOut();
    await SyncSettingsService.resetSyncProgress();
    await LicenseService.clearBinding();
    await ShopSettings.resetForBusinessSwitch();
    await DatabaseService.wipeAndReinitialize();
  }
}
