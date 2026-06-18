import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'sync_settings_service.dart';

/// Resolves the user's 2-letter ISO country code for currency and market
/// selection at signup.
///
/// Detection priority:
///   1. [Platform.localeName] (e.g. `en_US`) — the OS-reported locale region.
///   2. Backend `GET /api/geo/country`, which inspects CDN/proxy headers
///      (`cf-ipcountry`, `x-vercel-ip-country`) and the `accept-language`
///      header.
///
/// The result is cached for the lifetime of the process. A user can always
/// override the detected country via the country picker on the signup screen.
class CountryDetector {
  static String? _cached;
  static bool _attempted = false;

  static Future<String?> detect() async {
    if (_attempted) return _cached;
    _attempted = true;

    final fromLocale = fromLocaleString(Platform.localeName);
    if (fromLocale != null) {
      _cached = fromLocale;
      return _cached;
    }

    final fromBackend = await _fromBackend();
    if (fromBackend != null) {
      _cached = fromBackend;
    }
    return _cached;
  }

  @visibleForTesting
  static void resetForTesting() {
    _cached = null;
    _attempted = false;
  }

  /// Parses a locale identifier like `en_US` or `en-US` and returns the
  /// 2-letter country segment in uppercase, or `null` if none is present.
  @visibleForTesting
  static String? fromLocaleString(String localeName) {
    final clean = localeName.trim();
    if (clean.isEmpty) return null;
    final parts = clean.split(RegExp(r'[-_]'));
    if (parts.length < 2) return null;
    final country = parts.last.toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(country)) return null;
    return country;
  }

  static String? _cachedSync() => _attempted ? _cached : null;

  /// Returns the cached detection result without triggering a new lookup.
  /// Useful for synchronous fallbacks after [detect] has been awaited at
  /// least once during the session.
  static String? get cached => _cachedSync();

  static Future<String?> _fromBackend() async {
    try {
      await SyncSettingsService.init();
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      for (final backendUrl in SyncSettingsService.backendUrlCandidates) {
        try {
          final base = backendUrl.replaceFirst(RegExp(r'/+$'), '');
          final response = await dio.get<Map<String, dynamic>>(
            '$base/api/geo/country',
          );
          final body = response.data ?? const <String, dynamic>{};
          final code = body['countryCode']?.toString().trim().toUpperCase();
          if (code != null && RegExp(r'^[A-Z]{2}$').hasMatch(code)) {
            return code;
          }
        } catch (_) {
          // Try the next backend candidate.
        }
      }
    } catch (_) {
      // Detection is best-effort; failures fall back to the caller's default.
    }
    return null;
  }
}
