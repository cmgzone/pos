import 'package:dio/dio.dart';

import 'license_service.dart';
import 'sync_settings_service.dart';

class PosMpesaConfig {
  final bool active;
  final String providerLabel;
  final String countryCode;
  final String currency;
  final String? message;

  const PosMpesaConfig({
    required this.active,
    required this.providerLabel,
    required this.countryCode,
    required this.currency,
    this.message,
  });

  factory PosMpesaConfig.fromJson(Map<String, dynamic> json) {
    return PosMpesaConfig(
      active: json['active'] == true,
      providerLabel: json['providerLabel']?.toString() ?? 'M-Pesa',
      countryCode: json['countryCode']?.toString() ?? 'KE',
      currency: json['currency']?.toString() ?? 'KES',
      message: json['message']?.toString(),
    );
  }
}

class PosPayment {
  final String id;
  final String provider;
  final String status;
  final String? receiptNumber;
  final String? externalReference;
  final Map<String, dynamic> metadata;

  const PosPayment({
    required this.id,
    required this.provider,
    required this.status,
    required this.receiptNumber,
    required this.externalReference,
    required this.metadata,
  });

  factory PosPayment.fromJson(Map<String, dynamic> json) {
    return PosPayment(
      id: json['id']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      receiptNumber: json['receiptNumber']?.toString(),
      externalReference: json['externalReference']?.toString(),
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : const {},
    );
  }

  bool get isPaid => status == 'paid';
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
