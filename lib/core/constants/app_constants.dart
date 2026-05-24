

class AppConstants {
  static const String appName = 'Piki POS';
  static const String appVersion = '1.0.0';
  static const String productionApiBaseUrl =
      'https://pos-e0hs.onrender.com/api';
  static const String debugApiBaseUrl = 'http://127.0.0.1:3000/api';
  static const String _defaultSocketUrl = 'https://pos-e0hs.onrender.com';
  static const String _defaultLicenseSigningSecret =
      'velora-pos-dev-license-secret-change-me';

  // App-managed API endpoints
  static String get apiBaseUrl {
    const explicit = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return productionApiBaseUrl;
  }

  static String get socketUrl {
    const explicit = String.fromEnvironment('SOCKET_URL', defaultValue: '');
    if (explicit.isNotEmpty) {
      return explicit;
    }

    final apiUrl = apiBaseUrl;
    if (apiUrl.endsWith('/api')) {
      return apiUrl.substring(0, apiUrl.length - 4);
    }
    final uri = Uri.tryParse(apiUrl);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$port';
    }
    return _defaultSocketUrl;
  }

  static String get licenseSigningSecret {
    const explicit = String.fromEnvironment(
      'LICENSE_SIGNING_SECRET',
      defaultValue: '',
    );
    if (explicit.isNotEmpty) {
      return explicit;
    }
    // Fall back to the built-in dev secret so the app can launch even when
    // the env var is not supplied.  For production, pass a real secret via
    // --dart-define=LICENSE_SIGNING_SECRET=<value>.
    return _defaultLicenseSigningSecret;
  }

  // Shared Preferences Keys
  static const String keyToken = 'auth_token';
  static const String keyUserRole = 'user_role';
  static const String keyLastSync = 'last_sync_timestamp';
  static const String keySyncCursor = 'sync_server_cursor';
  static const String keySyncDeviceId = 'sync_device_id';
  static const String keyIsOfflineMode = 'is_offline_mode';
  static const String keyLocalBusinessId = 'local_business_id';
}
