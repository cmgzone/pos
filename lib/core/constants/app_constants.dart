class AppConstants {
  static const String appName = 'Piki POS';
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0+1',
  );
  static const String productionApiBaseUrl = 'https://pikipos.com/api';
  static const String productionPublicBaseUrl = 'https://pikipos.com';
  static const String debugApiBaseUrl = 'http://127.0.0.1:3000/api';
  static const String _defaultSocketUrl = 'https://pikipos.com';
  // Embedded Ed25519 public verification key (raw 32 bytes, base64). The
  // matching private key signs licenses on the server and is NEVER shipped in
  // the app, so extracted APKs cannot forge offline licenses.
  static const String licenseSigningPublicKeyRaw =
      'ANELBBdGdvDqdj23GqZQi9eZMYZ0kUASLQHs3t7i/+k=';
  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'support@pikipos.com',
  );

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

  static String get publicCatalogBaseUrl {
    const explicit = String.fromEnvironment(
      'PUBLIC_CATALOG_BASE_URL',
      defaultValue: '',
    );
    final selected = explicit.isNotEmpty ? explicit : productionPublicBaseUrl;
    return selected.replaceFirst(RegExp(r'/+$'), '');
  }

  // Shared Preferences Keys
  static const String keyToken = 'auth_token';
  static const String keyUserRole = 'user_role';
  static const String keyLastSync = 'last_sync_timestamp';
  static const String keySyncCursor = 'sync_server_cursor';
  static const String keySyncDeviceId = 'sync_device_id';
  static const String keyIsOfflineMode = 'is_offline_mode';
  static const String keyLocalBusinessId = 'local_business_id';

  static const double mobileBreakpoint = 800;
  static const double tabletBreakpoint = 1040;
  static const double desktopBreakpoint = 1280;

  static const double maxContentWidth = 1400;
  static const double maxFormWidth = 480;
  static const double maxDialogWidth = 560;

  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 250);
  static const Duration animationSlow = Duration(milliseconds: 400);
}
