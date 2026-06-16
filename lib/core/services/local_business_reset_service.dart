import 'database_service.dart';
import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_service.dart';
import 'sync_settings_service.dart';

class BusinessSwitchBlockedException implements Exception {
  final int unsyncedCount;
  final List<String> affectedTables;

  const BusinessSwitchBlockedException({
    required this.unsyncedCount,
    required this.affectedTables,
  });

  @override
  String toString() {
    final tableSummary = affectedTables.isEmpty
        ? ''
        : ' Affected areas: ${affectedTables.join(', ')}.';
    return 'Account switch blocked. This phone has $unsyncedCount unsynced '
        '${unsyncedCount == 1 ? 'change' : 'changes'} from the current '
        'business.$tableSummary Sign in to the current business, open '
        'Settings > Cloud Sync, and sync before using another account.';
  }
}

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

    if (SyncSettingsService.localBusinessId.isNotEmpty) {
      final snapshot = await SyncService.getLocalSnapshot();
      final unsyncedCount = snapshot.pendingCount + snapshot.conflictCount;
      if (unsyncedCount > 0) {
        final affectedTables = snapshot.pendingChanges.entries
            .where((entry) => entry.value.isNotEmpty)
            .map((entry) => entry.key)
            .toList();
        if (snapshot.conflictCount > 0 &&
            !affectedTables.contains('conflicts')) {
          affectedTables.add('conflicts');
        }
        throw BusinessSwitchBlockedException(
          unsyncedCount: unsyncedCount,
          affectedTables: affectedTables.take(4).toList(),
        );
      }
    }

    await SessionService.signOut();
    await SyncSettingsService.resetSyncProgress();
    await LicenseService.clearBinding();
    await ShopSettings.resetForBusinessSwitch();
    await DatabaseService.wipeAndReinitialize();
  }
}
