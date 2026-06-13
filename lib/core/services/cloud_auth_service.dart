import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'license_service.dart';
import 'shop_settings.dart';
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

class EmailOtpRequestResponse {
  final String email;
  final bool sent;
  final DateTime? expiresAt;
  final int? retryAfterSeconds;

  const EmailOtpRequestResponse({
    required this.email,
    required this.sent,
    required this.expiresAt,
    required this.retryAfterSeconds,
  });

  factory EmailOtpRequestResponse.fromJson(Map<String, dynamic> json) {
    return EmailOtpRequestResponse(
      email: (json['email'] as String?) ?? '',
      sent: json['sent'] != false,
      expiresAt: _parseAuthDate(json['expiresAt']),
      retryAfterSeconds: json['retryAfterSeconds'] is num
          ? (json['retryAfterSeconds'] as num).round()
          : null,
    );
  }
}

class EmailOtpVerificationResponse {
  final String email;
  final String verificationToken;
  final DateTime? expiresAt;

  const EmailOtpVerificationResponse({
    required this.email,
    required this.verificationToken,
    required this.expiresAt,
  });

  factory EmailOtpVerificationResponse.fromJson(Map<String, dynamic> json) {
    return EmailOtpVerificationResponse(
      email: (json['email'] as String?) ?? '',
      verificationToken: (json['verificationToken'] as String?) ?? '',
      expiresAt: _parseAuthDate(json['expiresAt']),
    );
  }
}

enum CloudAuthFailureKind { network, unauthorized, conflict, server }

class CloudAuthException implements Exception {
  final String message;
  final CloudAuthFailureKind kind;

  const CloudAuthException(this.message, this.kind);

  @override
  String toString() => message;
}

/// Handles cloud-based registration and login for the SaaS model.
///
/// Account creation requires an internet connection. Once registered, the
/// credentials are stored locally for offline access.
class CloudAuthService {
  static const _timeout = Duration(seconds: 75);

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
    required String currency,
    String? requestedPlanCode,
    String? sellingMode,
    String? provider,
    String? platform,
    String? emailVerificationToken,
  }) async {
    final normalizedUrl = backendUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw Exception('Cloud backend URL is not configured.');
    }

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
              'password': password,
              'deviceId': deviceId,
              'deviceName': _deviceName,
              'countryCode': countryCode,
              'currency': ShopSettings.normalizeCurrency(currency),
              if (requestedPlanCode != null &&
                  requestedPlanCode.trim().isNotEmpty)
                'requestedPlanCode': requestedPlanCode.trim(),
              if (sellingMode != null && sellingMode.trim().isNotEmpty)
                'sellingMode': sellingMode.trim(),
              if (provider != null && provider.trim().isNotEmpty)
                'provider': provider.trim(),
              if (platform != null && platform.trim().isNotEmpty)
                'platform': platform.trim(),
              if (emailVerificationToken != null &&
                  emailVerificationToken.trim().isNotEmpty)
                'emailVerificationToken': emailVerificationToken.trim(),
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

  static Future<EmailOtpRequestResponse> requestSignupEmailOtp({
    required String backendUrl,
    required String email,
  }) async {
    return _requestEmailOtp(
      backendUrl: backendUrl,
      email: email,
      purpose: 'signup',
    );
  }

  static Future<EmailOtpRequestResponse> requestPasswordResetOtp({
    required String backendUrl,
    required String email,
  }) async {
    return _requestEmailOtp(
      backendUrl: backendUrl,
      email: email,
      purpose: 'password_reset',
    );
  }

  static Future<EmailOtpRequestResponse> _requestEmailOtp({
    required String backendUrl,
    required String email,
    required String purpose,
  }) async {
    final normalizedUrl = backendUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw Exception('Cloud backend URL is not configured.');
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$normalizedUrl/auth/email-otp/request'),
            headers: const {HttpHeaders.contentTypeHeader: 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'purpose': purpose,
            }),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _readText(body['error']) ??
              'Could not send verification code (${response.statusCode})',
        );
      }
      if (body['ok'] != true) {
        throw Exception(
          _readText(body['error']) ?? 'Unexpected verification response.',
        );
      }
      return EmailOtpRequestResponse.fromJson(body);
    } on http.ClientException {
      throw Exception(
        'Could not reach the cloud server. Check your internet connection and try again.',
      );
    } on SocketException {
      throw Exception(
        'No internet connection. Connect to the internet to verify your email.',
      );
    } on TimeoutException {
      throw Exception('Sending the verification code timed out. Try again.');
    } finally {
      client.close();
    }
  }

  static Future<EmailOtpVerificationResponse> verifySignupEmailOtp({
    required String backendUrl,
    required String email,
    required String code,
  }) async {
    return _verifyEmailOtp(
      backendUrl: backendUrl,
      email: email,
      code: code,
      purpose: 'signup',
    );
  }

  static Future<EmailOtpVerificationResponse> verifyPasswordResetOtp({
    required String backendUrl,
    required String email,
    required String code,
  }) async {
    return _verifyEmailOtp(
      backendUrl: backendUrl,
      email: email,
      code: code,
      purpose: 'password_reset',
    );
  }

  static Future<EmailOtpVerificationResponse> _verifyEmailOtp({
    required String backendUrl,
    required String email,
    required String code,
    required String purpose,
  }) async {
    final normalizedUrl = backendUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw Exception('Cloud backend URL is not configured.');
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$normalizedUrl/auth/email-otp/verify'),
            headers: const {HttpHeaders.contentTypeHeader: 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'code': code.trim(),
              'purpose': purpose,
            }),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _readText(body['error']) ??
              'Could not verify code (${response.statusCode})',
        );
      }
      if (body['ok'] != true) {
        throw Exception(
          _readText(body['error']) ?? 'Unexpected verification response.',
        );
      }
      return EmailOtpVerificationResponse.fromJson(body);
    } on http.ClientException {
      throw Exception(
        'Could not reach the cloud server. Check your internet connection and try again.',
      );
    } on SocketException {
      throw Exception(
        'No internet connection. Connect to the internet to verify your email.',
      );
    } on TimeoutException {
      throw Exception('Verifying the code timed out. Try again.');
    } finally {
      client.close();
    }
  }

  static Future<void> completePasswordReset({
    required String backendUrl,
    required String email,
    required String verificationToken,
    required String newPassword,
  }) async {
    final normalizedUrl = backendUrl.trim();
    if (normalizedUrl.isEmpty) {
      throw Exception('Cloud backend URL is not configured.');
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$normalizedUrl/auth/password-reset/complete'),
            headers: const {HttpHeaders.contentTypeHeader: 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'verificationToken': verificationToken.trim(),
              'newPassword': newPassword,
            }),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _readText(body['error']) ??
              'Could not reset password (${response.statusCode})',
        );
      }
      if (body['ok'] != true) {
        throw Exception(
          _readText(body['error']) ?? 'Unexpected password reset response.',
        );
      }
    } on http.ClientException {
      throw Exception(
        'Could not reach the cloud server. Check your internet connection and try again.',
      );
    } on SocketException {
      throw Exception(
        'No internet connection. Connect to the internet to reset your password.',
      );
    } on TimeoutException {
      throw Exception('Resetting the password timed out. Try again.');
    } finally {
      client.close();
    }
  }

  /// Authenticate an existing user against the cloud backend.
  ///
  /// Sends the typed password to the server for verification. Returns
  /// the full access response on success. Throws on network failure or
  /// invalid credentials (401).
  static Future<CloudAuthResponse> loginOnline({
    required String backendUrl,
    required String email,
    required String password,
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
              'password': password,
              'deviceId': deviceId,
              'deviceName': _deviceName,
            }),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);

      if (response.statusCode == 401) {
        final message =
            _readText(body['error']) ?? 'Invalid email or password.';
        throw CloudAuthException(message, CloudAuthFailureKind.unauthorized);
      }

      if (response.statusCode == 409) {
        final message =
            _readText(body['error']) ??
            'This staff login is assigned to more than one business.';
        throw CloudAuthException(message, CloudAuthFailureKind.conflict);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message =
            _readText(body['error']) ?? 'Login failed (${response.statusCode})';
        throw CloudAuthException(message, CloudAuthFailureKind.server);
      }

      if (body['ok'] != true) {
        throw CloudAuthException(
          _readText(body['error']) ?? 'Unexpected login response.',
          CloudAuthFailureKind.server,
        );
      }

      return CloudAuthResponse.fromJson(body);
    } on http.ClientException {
      throw const CloudAuthException(
        'Could not reach the cloud server. Check your internet connection.',
        CloudAuthFailureKind.network,
      );
    } on SocketException {
      throw const CloudAuthException(
        'No internet connection. Try signing in offline if you have previously logged in.',
        CloudAuthFailureKind.network,
      );
    } on TimeoutException {
      throw const CloudAuthException(
        'Cloud sign in timed out. Try again, or sign in offline if this device has already been verified.',
        CloudAuthFailureKind.network,
      );
    } finally {
      client.close();
    }
  }

  /// Permanently closes the current business on the backend.
  ///
  /// The server requires an admin session and the exact business name as a
  /// confirmation. On success, the public storefront subdomain is released and
  /// existing access tokens are invalidated server-side.
  static Future<Map<String, dynamic>> deleteBusinessOnline({
    required String backendUrl,
    required String accessToken,
    required String deviceId,
    required String confirmBusinessName,
  }) async {
    final normalizedUrl = backendUrl.trim();
    final token = accessToken.trim();
    if (normalizedUrl.isEmpty) {
      throw Exception('Cloud backend URL is not configured.');
    }
    if (token.isEmpty) {
      throw Exception('Cloud access token is missing.');
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$normalizedUrl/business/delete'),
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.authorizationHeader: 'Bearer $token',
            },
            body: jsonEncode({
              'deviceId': deviceId,
              'confirmBusinessName': confirmBusinessName.trim(),
            }),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _readText(body['error']) ??
              'Could not delete business (${response.statusCode})',
        );
      }
      if (body['ok'] != true) {
        throw Exception(
          _readText(body['error']) ?? 'Unexpected business deletion response.',
        );
      }
      return body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : const <String, dynamic>{};
    } on http.ClientException {
      throw Exception(
        'Could not reach the cloud server. Check your internet connection and try again.',
      );
    } on SocketException {
      throw Exception(
        'No internet connection. Connect to the internet to delete the business.',
      );
    } on TimeoutException {
      throw Exception('Deleting the business timed out. Try again.');
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
      return 'Piki ${Platform.operatingSystem}';
    } catch (_) {
      return 'Piki device';
    }
  }
}

DateTime? _parseAuthDate(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}
