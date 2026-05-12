import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../features/auth/data/auth_password_service.dart';
import 'license_service.dart';
import 'sync_settings_service.dart';

/// Response from cloud authentication endpoints.
class CloudAuthResponse {
  final Map<String, dynamic> business;
  final String accessToken;
  final Map<String, dynamic> subscription;
  final Map<String, dynamic> license;
  final Map<String, dynamic> user;
  final Map<String, dynamic> selectedPlan;
  final Map<String, dynamic> selectedMarket;
  final Map<String, dynamic>? checkoutContext;
  final bool checkoutRequired;

  const CloudAuthResponse({
    required this.business,
    required this.accessToken,
    required this.subscription,
    required this.license,
    required this.user,
    required this.selectedPlan,
    required this.selectedMarket,
    required this.checkoutContext,
    required this.checkoutRequired,
  });

  factory CloudAuthResponse.fromJson(Map<String, dynamic> json) {
    return CloudAuthResponse(
      business: json['business'] is Map<String, dynamic>
          ? json['business'] as Map<String, dynamic>
          : const <String, dynamic>{},
      accessToken: (json['accessToken'] as String?) ?? '',
      subscription: json['subscription'] is Map<String, dynamic>
          ? json['subscription'] as Map<String, dynamic>
          : const <String, dynamic>{},
      license: json['license'] is Map<String, dynamic>
          ? json['license'] as Map<String, dynamic>
          : const <String, dynamic>{},
      user: json['user'] is Map<String, dynamic>
          ? json['user'] as Map<String, dynamic>
          : const <String, dynamic>{},
      selectedPlan: json['selectedPlan'] is Map<String, dynamic>
          ? json['selectedPlan'] as Map<String, dynamic>
          : const <String, dynamic>{},
      selectedMarket: json['selectedMarket'] is Map<String, dynamic>
          ? json['selectedMarket'] as Map<String, dynamic>
          : const <String, dynamic>{},
      checkoutContext: json['checkoutContext'] is Map<String, dynamic>
          ? json['checkoutContext'] as Map<String, dynamic>
          : null,
      checkoutRequired: json['checkoutRequired'] == true,
    );
  }
}

/// Handles cloud-based registration and login for the SaaS model.
///
/// Account creation requires an internet connection. Once registered, the
/// credentials are stored locally for offline access.
class CloudAuthService {
  static const _timeout = Duration(seconds: 30);

  /// Register a new business account on the cloud backend.
  ///
  /// This creates a business, subscription, device, and admin user in one
  /// atomic transaction on the server. Throws on network failure or if
  /// the email is already registered (409).
  static Future<CloudAuthResponse> registerOnline({
    required String backendUrl,
    required String businessName,
    required String ownerName,
    required String ownerEmail,
    required String phone,
    required String password,
    required String deviceId,
    required String countryCode,
    required String requestedPlanCode,
    required String sellingMode,
    String? provider,
  }) async {
    final normalizedUrl = backendUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw Exception('Cloud backend URL is not configured.');
    }

    // Hash the password before sending to the server
    final hashedPassword = AuthPasswordService.hashPassword(password);

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$normalizedUrl/auth/register'),
            headers: const {HttpHeaders.contentTypeHeader: 'application/json'},
            body: jsonEncode({
              'businessName': businessName.trim(),
              'ownerName': ownerName.trim(),
              'ownerEmail': ownerEmail.trim().toLowerCase(),
              'phone': phone.trim(),
              'password': hashedPassword,
              'deviceId': deviceId,
              'deviceName': _deviceName,
              'countryCode': countryCode,
              'requestedPlanCode': requestedPlanCode,
              'sellingMode': sellingMode,
              if (provider != null && provider.trim().isNotEmpty)
                'provider': provider.trim(),
            }),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);

      if (response.statusCode == 409) {
        final message =
            _readText(body['error']) ??
            'An account with that email already exists.';
        throw Exception(message);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message =
            _readText(body['error']) ??
            'Registration failed (${response.statusCode})';
        throw Exception(message);
      }

      if (body['ok'] != true) {
        throw Exception(
          _readText(body['error']) ?? 'Unexpected registration response.',
        );
      }

      return CloudAuthResponse.fromJson(body);
    } on http.ClientException {
      throw Exception(
        'Could not reach the cloud server. Check your internet connection and try again.',
      );
    } on SocketException {
      throw Exception(
        'No internet connection. An internet connection is required to create an account.',
      );
    } finally {
      client.close();
    }
  }

  /// Authenticate an existing user against the cloud backend.
  ///
  /// Sends the hashed password to the server for verification. Returns
  /// the full access response on success. Throws on network failure or
  /// invalid credentials (401).
  static Future<CloudAuthResponse> loginOnline({
    required String backendUrl,
    required String email,
    required String hashedPassword,
    required String deviceId,
  }) async {
    final normalizedUrl = backendUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw Exception('Cloud backend URL is not configured.');
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$normalizedUrl/auth/login'),
            headers: const {HttpHeaders.contentTypeHeader: 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'password': hashedPassword,
              'deviceId': deviceId,
              'deviceName': _deviceName,
            }),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);

      if (response.statusCode == 401) {
        final message =
            _readText(body['error']) ?? 'Invalid email or password.';
        throw Exception(message);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message =
            _readText(body['error']) ?? 'Login failed (${response.statusCode})';
        throw Exception(message);
      }

      if (body['ok'] != true) {
        throw Exception(
          _readText(body['error']) ?? 'Unexpected login response.',
        );
      }

      return CloudAuthResponse.fromJson(body);
    } on http.ClientException {
      throw Exception(
        'Could not reach the cloud server. Check your internet connection.',
      );
    } on SocketException {
      throw Exception(
        'No internet connection. Try signing in offline if you have previously logged in.',
      );
    } finally {
      client.close();
    }
  }

  /// Persist the cloud auth response locally: store the license binding,
  /// sync settings, and return the user record for local DB insertion.
  static Future<void> persistCloudResponse(CloudAuthResponse response) async {
    await LicenseService.init();
    await SyncSettingsService.init();
    await LicenseService.storeAccessResponse({
      'business': response.business,
      'accessToken': response.accessToken,
      'subscription': response.subscription,
      'license': response.license,
    });
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isNotEmpty) {
      try {
        await LicenseService.ensureOnlineLicense(
          backendUrl: backendUrl,
          deviceId: await SyncSettingsService.getOrCreateDeviceId(),
          businessName: (response.business['name'] as String?) ?? '',
          ownerName: (response.user['name'] as String?) ?? '',
          ownerEmail: (response.user['email'] as String?) ?? '',
          forceRefresh: true,
        );
      } catch (_) {
        // If the license refresh fails, we still have valid data from registration
      }
    }
  }

  static Map<String, dynamic> _decodeJson(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return const <String, dynamic>{};
  }

  static String? _readText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static String get _deviceName {
    try {
      return 'Velora ${Platform.operatingSystem}';
    } catch (_) {
      return 'Velora device';
    }
  }
}
