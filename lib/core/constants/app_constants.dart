class AppConstants {
  static const String appName = 'Velora POS';
  static const String appVersion = '1.0.0';

  // App-managed API endpoints
  static const String apiBaseUrl = 'http://localhost:3000/api';
  static const String socketUrl = 'http://localhost:3000';
  static const String licenseSigningSecret =
      'velora-pos-dev-license-secret-change-me';

  // Shared Preferences Keys
  static const String keyToken = 'auth_token';
  static const String keyUserRole = 'user_role';
  static const String keyLastSync = 'last_sync_timestamp';
  static const String keySyncCursor = 'sync_server_cursor';
  static const String keySyncDeviceId = 'sync_device_id';
  static const String keyIsOfflineMode = 'is_offline_mode';
  static const String keyLocalBusinessId = 'local_business_id';
}
