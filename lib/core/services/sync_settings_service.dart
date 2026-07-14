import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import 'license_service.dart';

class SyncSettingsService {
  static SharedPreferences? _prefs;
  static const _uuid = Uuid();

  static const _keyBackendUrl = 'sync_backend_url';
  static const _keyAutoSync = 'sync_auto_enabled';
  static const _keySyncScope = 'sync_scope_key';
  static const _keyMyBusinesses = 'sync_my_businesses';
  static const _deprecatedBackendUrls = {
    'https://pos-e0hs.onrender.com',
    'https://pos-e0hs.onrender.com/api',
  };

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _migrateDeprecatedBackendUrl();
  }

  @visibleForTesting
  static void resetForTesting() {
    _prefs = null;
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

  /// Persisted list of businesses this account can switch between. Only set
  /// for accounts that own more than one business.
  static List<Map<String, dynamic>> get myBusinesses {
    final raw = _prefs?.getString(_keyMyBusinesses);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = (jsonDecode(raw) as List?)?.whereType<Map>().toList();
      return decoded?.map((e) => Map<String, dynamic>.from(e)).toList() ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> setMyBusinesses(
    List<Map<String, dynamic>> businesses,
  ) async {
    final prefs = _prefs;
    if (prefs == null) return;
    if (businesses.isEmpty) {
      await prefs.remove(_keyMyBusinesses);
      return;
    }
    await prefs.setString(_keyMyBusinesses, jsonEncode(businesses));
  }

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

  static String get syncScopeKey =>
      (_prefs?.getString(_keySyncScope) ?? '').trim();

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

  static Future<void> setSyncScopeKey(String? value) async {
    await init();
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      await _prefs!.remove(_keySyncScope);
      return;
    }
    await _prefs!.setString(_keySyncScope, normalized);
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

  /// Creates a candidate identity without changing the active account's
  /// persisted device binding. Registration commits it only after the server
  /// has accepted the new account and the old local snapshot is safe to leave.
  static String generateFreshDeviceId() => _uuid.v4();

  static Future<void> setDeviceId(String? value) async {
    await init();
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      await _prefs!.remove(AppConstants.keySyncDeviceId);
      return;
    }
    await _prefs!.setString(AppConstants.keySyncDeviceId, normalized);
  }

  /// Generates a brand-new device identity and persists it, discarding any
  /// previously stored device id.
  ///
  /// Use this when registering a new account on a device that already belongs
  /// to another account: each account must be bound to its own device id, and
  /// reusing the install-wide id would reassign the device from the existing
  /// business to the new one on the backend.
  static Future<String> regenerateDeviceId() async {
    final created = generateFreshDeviceId();
    await setDeviceId(created);
    return created;
  }

  static Future<void> resetSyncProgress() async {
    await init();
    await _prefs!.remove(AppConstants.keySyncCursor);
    await _prefs!.remove(_keySyncScope);
    await _prefs!.remove(AppConstants.keyLastSync);
    await _prefs!.remove(AppConstants.keyLocalBusinessId);
  }

  static String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    var normalized = trimmed;
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(normalized)) {
      final lower = normalized.toLowerCase();
      final localHost =
          lower.startsWith('localhost') ||
          lower.startsWith('127.') ||
          lower.startsWith('10.') ||
          lower.startsWith('192.168.');
      normalized = '${localHost ? 'http' : 'https'}://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return normalized;
    }

    final path = uri.path.trim();
    if (path.isEmpty || path == '/') {
      return uri.replace(path: '/api', query: null, fragment: null).toString();
    }
    return uri.replace(query: null, fragment: null).toString();
  }

  static Future<void> _migrateDeprecatedBackendUrl() async {
    final prefs = _prefs;
    if (prefs == null) {
      return;
    }

    final saved = _normalizeUrl(prefs.getString(_keyBackendUrl) ?? '');
    if (_deprecatedBackendUrls.contains(saved)) {
      await prefs.setString(_keyBackendUrl, AppConstants.productionApiBaseUrl);
    }
  }
}
