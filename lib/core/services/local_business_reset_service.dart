import 'database_service.dart';
import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_service.dart';
import 'sync_settings_service.dart';

class BusinessSwitchBlockedException implements Exception {
  final int unsyncedCount;
  final List<String> affectedTables;
  final String? syncFailure;

  const BusinessSwitchBlockedException({
    required this.unsyncedCount,
    required this.affectedTables,
    this.syncFailure,
  });

  @override
  String toString() {
    final tableSummary = affectedTables.isEmpty
        ? ''
        : ' Affected areas: ${affectedTables.join(', ')}.';
    final syncSummary = syncFailure == null || syncFailure!.trim().isEmpty
        ? ''
        : ' Automatic sync could not finish: ${syncFailure!.trim()}.';
    return 'Account switch paused to protect your data. This device has '
        '$unsyncedCount unsynced '
        '${unsyncedCount == 1 ? 'change' : 'changes'} from the current '
        'business.$tableSummary$syncSummary Sign in to the current business, open '
        'Settings > Cloud Sync, and sync before using another account.';
  }
}

/// Clears business-owned local state when the device switches to a different
/// business account.
///
/// This app stores a single business snapshot locally, so switching businesses
/// must wipe the previous business's SQLite data and related preferences.
class LocalBusinessResetService {
  /// Makes the current local snapshot safe before any cloud request is allowed
  /// to bind this physical device to another business.
  ///
  /// Login and registration must call this *before* authenticating the next
  /// account. Otherwise a successful cloud authentication can move the device
  /// binding first and leave the previous business unable to upload its local
  /// changes when the later reset guard rejects the switch.
  static Future<void> prepareForBusinessSwitch({
    SyncProgressCallback? onProgress,
    Future<void> Function()? syncAction,
  }) async {
    await _initializeServices();
    if (SyncSettingsService.localBusinessId.isEmpty) {
      return;
    }

    var snapshot = await SyncService.getLocalSnapshot();
    if (_unsafeChangeCount(snapshot) == 0) {
      return;
    }

    Object? syncFailure;
    try {
      if (syncAction != null) {
        await syncAction();
      } else {
        await SyncService.syncNow(onProgress: onProgress);
      }
    } catch (error) {
      syncFailure = error;
    }

    snapshot = await SyncService.getLocalSnapshot();
    _throwIfUnsafe(snapshot, syncFailure: syncFailure);
  }

  static Future<void> clearForBusinessSwitch() async {
    await _initializeServices();

    if (SyncSettingsService.localBusinessId.isNotEmpty) {
      _throwIfUnsafe(await SyncService.getLocalSnapshot());
    }

    await SessionService.signOut();
    await SyncSettingsService.resetSyncProgress();
    await LicenseService.clearBinding();
    await ShopSettings.resetForBusinessSwitch();
    await DatabaseService.wipeAndReinitialize();
  }

  static Future<void> _initializeServices() async {
    await SessionService.init();
    await SyncSettingsService.init();
    await ShopSettings.init();
  }

  static int _unsafeChangeCount(LocalSyncSnapshot snapshot) {
    return snapshot.pendingCount + snapshot.conflictCount;
  }

  static void _throwIfUnsafe(
    LocalSyncSnapshot snapshot, {
    Object? syncFailure,
  }) {
    final unsyncedCount = _unsafeChangeCount(snapshot);
    if (unsyncedCount == 0) {
      return;
    }

    final affectedTables = snapshot.pendingChanges.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => entry.key)
        .toList();
    if (snapshot.conflictCount > 0 && !affectedTables.contains('conflicts')) {
      affectedTables.add('conflicts');
    }
    throw BusinessSwitchBlockedException(
      unsyncedCount: unsyncedCount,
      affectedTables: affectedTables.take(4).toList(),
      syncFailure: syncFailure?.toString(),
    );
  }
}
