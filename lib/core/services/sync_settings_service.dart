import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'license_service.dart';

class SyncSettingsService {
  static SharedPreferences? _prefs;
  static const _uuid = Uuid();

  static const _keyBackendUrl = 'sync_backend_url';
  static const _keyAutoSync = 'sync_auto_enabled';

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static String get backendUrl {
    final savedUrl = savedBackendUrl;
    if (savedUrl.isNotEmpty) {
      return savedUrl;
    }
    return suggestedBackendUrl;
  }

  static String get savedBackendUrl =>
      _normalizeUrl(_prefs?.getString(_keyBackendUrl) ?? '');

  static String get suggestedBackendUrl => AppConstants.apiBaseUrl;

  static List<String> get backendUrlCandidates {
    final urls = <String>[];
    void add(String value) {
      final normalized = _normalizeUrl(value);
      if (normalized.isNotEmpty && !urls.contains(normalized)) {
        urls.add(normalized);
      }
    }

    add(savedBackendUrl);
    add(suggestedBackendUrl);
    add(AppConstants.productionApiBaseUrl);
    add(AppConstants.debugApiBaseUrl);
    return urls;
  }

  static bool get isConfigured => backendUrl.isNotEmpty;

  static bool get autoSyncEnabled => _prefs?.getBool(_keyAutoSync) ?? true;

  static String get syncCursor {
    final raw = _prefs?.getString(AppConstants.keySyncCursor) ?? '';
    final trimmed = raw.trim();
    return trimmed.isEmpty ? '0' : trimmed;
  }

  static String? get deviceId {
    final raw = _prefs?.getString(AppConstants.keySyncDeviceId);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return raw.trim();
  }

  static DateTime? get lastSyncAt {
    final raw = _prefs?.getString(AppConstants.keyLastSync);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toLocal();
  }

  /// The businessId whose data currently lives in the local SQLite database.
  ///
  /// An empty string means no business has populated the local DB yet
  /// (fresh install or after a wipe).
  static String get localBusinessId {
    final raw = _prefs?.getString(AppConstants.keyLocalBusinessId) ?? '';
    return raw.trim();
  }

  static Future<void> setLocalBusinessId(String id) async {
    await init();
    final normalized = id.trim();
    if (normalized.isEmpty) {
      await _prefs!.remove(AppConstants.keyLocalBusinessId);
    } else {
      await _prefs!.setString(AppConstants.keyLocalBusinessId, normalized);
    }
  }

  static Future<void> setBackendUrl(String value) async {
    await init();
    final normalized = _normalizeUrl(value);
    final previous = backendUrl;
    if (normalized.isEmpty) {
      await _prefs!.remove(_keyBackendUrl);
      await resetSyncProgress();
      await LicenseService.clearBinding();
      return;
    }
    if (previous.isNotEmpty && previous != normalized) {
      await resetSyncProgress();
      await LicenseService.clearBinding();
    }
    await _prefs!.setString(_keyBackendUrl, normalized);
  }

  static Future<void> setAutoSyncEnabled(bool value) async {
    await init();
    await _prefs!.setBool(_keyAutoSync, value);
  }

  static Future<void> setLastSyncAt(DateTime? value) async {
    await init();
    if (value == null) {
      await _prefs!.remove(AppConstants.keyLastSync);
      return;
    }
    await _prefs!.setString(
      AppConstants.keyLastSync,
      value.toUtc().toIso8601String(),
    );
  }

  static Future<void> setSyncCursor(String? value) async {
    await init();
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      await _prefs!.remove(AppConstants.keySyncCursor);
      return;
    }
    await _prefs!.setString(AppConstants.keySyncCursor, normalized);
  }

  static Future<String> getOrCreateDeviceId() async {
    await init();
    final existing = deviceId;
    if (existing != null) {
      return existing;
    }

    final created = _uuid.v4();
    await _prefs!.setString(AppConstants.keySyncDeviceId, created);
    return created;
  }

  static Future<void> resetSyncProgress() async {
    await init();
    await _prefs!.remove(AppConstants.keySyncCursor);
    await _prefs!.remove(AppConstants.keyLastSync);
    await _prefs!.remove(AppConstants.keyLocalBusinessId);
  }

  static String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    var normalized = trimmed;
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
