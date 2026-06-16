import 'package:dio/dio.dart';

import 'license_service.dart';
import 'sync_settings_service.dart';

class PosMpesaConfig {
  final bool active;
  final String providerLabel;
  final String countryCode;
  final String currency;
  final bool merchantConfigured;
  final String? merchantShortcode;
  final String? message;

  const PosMpesaConfig({
    required this.active,
    required this.providerLabel,
    required this.countryCode,
    required this.currency,
    required this.merchantConfigured,
    this.merchantShortcode,
    this.message,
  });

  factory PosMpesaConfig.fromJson(Map<String, dynamic> json) {
    return PosMpesaConfig(
      active: json['active'] == true,
      providerLabel: json['providerLabel']?.toString() ?? 'M-Pesa',
      countryCode: json['countryCode']?.toString() ?? 'KE',
      currency: json['currency']?.toString() ?? 'KES',
      merchantConfigured: json['merchantConfigured'] == true,
      merchantShortcode: json['merchantShortcode']?.toString(),
      message: json['message']?.toString(),
    );
  }
}

class BusinessMpesaSettings {
  final bool isActive;
  final String displayName;
  final Map<String, dynamic> publicConfig;
  final Map<String, dynamic> secretConfig;

  const BusinessMpesaSettings({
    required this.isActive,
    required this.displayName,
    required this.publicConfig,
    required this.secretConfig,
  });

  factory BusinessMpesaSettings.fromJson(Map<String, dynamic> json) {
    return BusinessMpesaSettings(
      isActive: json['isActive'] == true,
      displayName: json['displayName']?.toString() ?? 'M-Pesa',
      publicConfig: json['publicConfig'] is Map<String, dynamic>
          ? json['publicConfig'] as Map<String, dynamic>
          : const {},
      secretConfig: json['secretConfig'] is Map<String, dynamic>
          ? json['secretConfig'] as Map<String, dynamic>
          : const {},
    );
  }
}

class PosPayment {
  final String id;
  final String provider;
  final String status;
  final int amountMinor;
  final String? receiptNumber;
  final String? externalReference;
  final Map<String, dynamic> metadata;

  const PosPayment({
    required this.id,
    required this.provider,
    required this.status,
    required this.amountMinor,
    required this.receiptNumber,
    required this.externalReference,
    required this.metadata,
  });

  factory PosPayment.fromJson(Map<String, dynamic> json) {
    return PosPayment(
      id: json['id']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      amountMinor: (json['amountMinor'] as num? ?? 0).round(),
      receiptNumber: json['receiptNumber']?.toString(),
      externalReference: json['externalReference']?.toString(),
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : const {},
    );
  }

  bool get isPaid => status == 'paid' || status == 'claimed';
  bool get isFailed => status == 'failed';
}

class PosPaymentService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<PosMpesaConfig> fetchMpesaConfig() async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('payments/mpesa/pos-config'),
      queryParameters: {'deviceId': deviceId},
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    return PosMpesaConfig.fromJson(data);
  }

  static Future<BusinessMpesaSettings> fetchBusinessMpesaSettings() async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('business/payment-gateways/mpesa'),
      queryParameters: {'deviceId': deviceId},
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    return BusinessMpesaSettings.fromJson(data);
  }

  static Future<BusinessMpesaSettings> saveBusinessMpesaSettings({
    required bool isActive,
    required String displayName,
    required String shortcode,
    required String transactionType,
    required String accountReference,
    required String consumerKey,
    required String consumerSecret,
    required String passkey,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.put<Map<String, dynamic>>(
      _url('business/payment-gateways/mpesa'),
      data: {
        'deviceId': deviceId,
        'displayName': displayName.trim().isEmpty
            ? 'M-Pesa'
            : displayName.trim(),
        'isActive': isActive,
        'publicConfig': {
          'shortcode': shortcode.trim(),
          'transactionType': transactionType.trim().isEmpty
              ? 'CustomerPayBillOnline'
              : transactionType.trim(),
          'accountReference': accountReference.trim(),
        },
        'secretConfig': {
          'consumerKey': consumerKey.trim(),
          'consumerSecret': consumerSecret.trim(),
          'passkey': passkey.trim(),
        },
      },
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    return BusinessMpesaSettings.fromJson(data);
  }

  static Future<PosPayment> startMpesaCheckout({
    required double amount,
    required String phoneNumber,
    Map<String, dynamic>? metadata,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.post<Map<String, dynamic>>(
      _url('payments/mpesa/pos-checkout'),
      data: {
        'deviceId': deviceId,
        'amountMinor': (amount * 100).round(),
        'phoneNumber': phoneNumber.trim(),
        ...?(metadata == null ? null : {'metadata': metadata}),
      },
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    return PosPayment.fromJson(data);
  }

  static Future<PosPayment> fetchPayment(String paymentId) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('payments/$paymentId'),
      queryParameters: {'deviceId': deviceId},
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    return PosPayment.fromJson(data);
  }

  static Future<PosPayment?> matchManualMpesa({
    String? referenceCode,
    String? phoneNumber,
    double? amount,
    String? checkoutCode,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.post<Map<String, dynamic>>(
      _url('payments/mpesa/claim-c2b'),
      data: {
        'deviceId': deviceId,
        if (referenceCode != null && referenceCode.trim().isNotEmpty)
          'referenceCode': referenceCode.trim(),
        if (phoneNumber != null && phoneNumber.trim().isNotEmpty)
          'phoneNumber': phoneNumber.trim(),
        if (amount != null) 'amountMinor': (amount * 100).round(),
        if (checkoutCode != null && checkoutCode.trim().isNotEmpty)
          'checkoutCode': checkoutCode.trim(),
      },
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'];
    if (data == null) {
      return null;
    }
    return PosPayment.fromJson(data as Map<String, dynamic>);
  }

  static Future<Map<String, dynamic>> testMpesaConnection() async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.post<Map<String, dynamic>>(
      _url('business/payment-gateways/mpesa/test-connection'),
      data: {'deviceId': deviceId},
      options: Options(headers: headers),
    );
    return _requireOk(response)['data'] as Map<String, dynamic>;
  }

  static Future<void> linkSale({
    required String paymentId,
    required String saleId,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.post<Map<String, dynamic>>(
      _url('payments/$paymentId/link-sale'),
      data: {'deviceId': deviceId, 'saleId': saleId},
      options: Options(headers: headers),
    );
    _requireOk(response);
  }

  static String _url(String path) {
    final base = SyncSettingsService.backendUrl.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    return '$base/$path';
  }

  static Future<Map<String, String>> _authHeaders() async {
    await LicenseService.init();
    final token = LicenseService.currentSnapshot.accessToken;
    if (token == null || token.trim().isEmpty) {
      throw Exception('Cloud payment is not activated.');
    }
    return {'Authorization': 'Bearer $token'};
  }

  static Map<String, dynamic> _requireOk(
    Response<Map<String, dynamic>> response,
  ) {
    final body = response.data ?? const <String, dynamic>{};
    if (response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300 &&
        body['ok'] == true) {
      return body;
    }
    throw Exception(body['error']?.toString() ?? 'Payment request failed');
  }
}
