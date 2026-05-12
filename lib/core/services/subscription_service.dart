import 'package:dio/dio.dart';

import 'license_service.dart';
import 'sync_settings_service.dart';

class SubscriptionPlanPrice {
  final String id;
  final String planCode;
  final String countryCode;
  final String currency;
  final int amountMinor;
  final String billingPeriod;
  final String provider;

  const SubscriptionPlanPrice({
    required this.id,
    required this.planCode,
    required this.countryCode,
    required this.currency,
    required this.amountMinor,
    required this.billingPeriod,
    required this.provider,
  });

  factory SubscriptionPlanPrice.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlanPrice(
      id: json['id']?.toString() ?? '',
      planCode: json['planCode']?.toString() ?? '',
      countryCode: json['countryCode']?.toString() ?? 'GLOBAL',
      currency: json['currency']?.toString() ?? 'USD',
      amountMinor: (json['amountMinor'] as num? ?? 0).toInt(),
      billingPeriod: json['billingPeriod']?.toString() ?? 'monthly',
      provider: json['provider']?.toString() ?? 'google_pay',
    );
  }

  String get displayAmount =>
      '$currency ${(amountMinor / 100).toStringAsFixed(currency == 'KES' ? 0 : 2)}';
}

class SubscriptionMarket {
  final String countryCode;
  final String label;
  final String currency;
  final String provider;
  final String providerLabel;

  const SubscriptionMarket({
    required this.countryCode,
    required this.label,
    required this.currency,
    required this.provider,
    required this.providerLabel,
  });

  factory SubscriptionMarket.fromJson(Map<String, dynamic> json) {
    return SubscriptionMarket(
      countryCode: json['countryCode']?.toString() ?? 'GLOBAL',
      label: json['label']?.toString() ?? 'Other Countries',
      currency: json['currency']?.toString() ?? 'USD',
      provider: json['provider']?.toString() ?? 'google_pay',
      providerLabel: json['providerLabel']?.toString() ?? 'Google Pay',
    );
  }

  String get key => '$countryCode:$provider';

  String get displayLabel => '$label - $providerLabel';
}

class SubscriptionPlanSummary {
  final String code;
  final String name;
  final String description;
  final List<String> features;
  final SubscriptionEntitlements entitlements;
  final List<SubscriptionPlanPrice> prices;
  final SubscriptionPlanPrice? price;

  const SubscriptionPlanSummary({
    required this.code,
    required this.name,
    required this.description,
    required this.features,
    required this.entitlements,
    required this.prices,
    required this.price,
  });

  factory SubscriptionPlanSummary.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'];
    return SubscriptionPlanSummary(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      features: rawFeatures is List
          ? rawFeatures.map((item) => item.toString()).toList()
          : const [],
      entitlements: SubscriptionEntitlements.fromJson(json['entitlements']),
      prices: json['prices'] is List
          ? (json['prices'] as List)
                .whereType<Map<String, dynamic>>()
                .map(SubscriptionPlanPrice.fromJson)
                .toList()
          : const [],
      price: json['price'] is Map<String, dynamic>
          ? SubscriptionPlanPrice.fromJson(
              json['price'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  SubscriptionPlanPrice? priceFor(SubscriptionMarket market) {
    return prices.where((price) {
          return price.countryCode == market.countryCode &&
              price.provider == market.provider;
        }).firstOrNull ??
        prices.where((price) {
          return price.countryCode == 'GLOBAL' &&
              price.provider == market.provider;
        }).firstOrNull ??
        price;
  }
}

class SubscriptionCatalog {
  final String? countryCode;
  final String? provider;
  final SubscriptionMarket? selectedMarket;
  final List<SubscriptionMarket> markets;
  final List<SubscriptionPlanSummary> plans;
  final Map<String, dynamic>? googlePayConfig;

  const SubscriptionCatalog({
    required this.countryCode,
    required this.provider,
    required this.selectedMarket,
    required this.markets,
    required this.plans,
    required this.googlePayConfig,
  });
}

class SubscriptionCheckoutResult {
  final String paymentId;
  final String provider;
  final String status;
  final String? message;
  final Map<String, dynamic>? googlePayConfig;

  const SubscriptionCheckoutResult({
    required this.paymentId,
    required this.provider,
    required this.status,
    required this.message,
    required this.googlePayConfig,
  });

  factory SubscriptionCheckoutResult.fromJson(Map<String, dynamic> json) {
    final mpesa = json['mpesa'];
    return SubscriptionCheckoutResult(
      paymentId: json['id']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      message:
          json['message']?.toString() ??
          (mpesa is Map ? mpesa['message']?.toString() : null),
      googlePayConfig: json['googlePayConfig'] is Map<String, dynamic>
          ? json['googlePayConfig'] as Map<String, dynamic>
          : null,
    );
  }
}

class SubscriptionService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<SubscriptionCatalog> fetchPlans({
    String? countryCode,
    String? provider,
  }) async {
    await SyncSettingsService.init();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('subscription/plans'),
      queryParameters: {
        if (countryCode != null && countryCode.trim().isNotEmpty)
          'countryCode': countryCode,
        if (provider != null && provider.trim().isNotEmpty)
          'provider': provider,
      },
    );
    final body = _requireOk(response);
    final rawPlans = body['plans'];
    final rawMarkets = body['markets'];
    return SubscriptionCatalog(
      countryCode: body['countryCode']?.toString(),
      provider: body['provider']?.toString(),
      selectedMarket: body['selectedMarket'] is Map<String, dynamic>
          ? SubscriptionMarket.fromJson(
              body['selectedMarket'] as Map<String, dynamic>,
            )
          : null,
      markets: rawMarkets is List
          ? rawMarkets
                .whereType<Map<String, dynamic>>()
                .map(SubscriptionMarket.fromJson)
                .toList()
          : const [],
      plans: rawPlans is List
          ? rawPlans
                .whereType<Map<String, dynamic>>()
                .map(SubscriptionPlanSummary.fromJson)
                .toList()
          : const [],
      googlePayConfig: body['googlePayConfig'] is Map<String, dynamic>
          ? body['googlePayConfig'] as Map<String, dynamic>
          : null,
    );
  }

  static Future<Map<String, dynamic>> fetchCurrent({
    String? countryCode,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('subscription/current'),
      queryParameters: {
        if (countryCode != null && countryCode.trim().isNotEmpty)
          'countryCode': countryCode,
        'deviceId': deviceId,
      },
      options: Options(headers: headers),
    );
    return _requireOk(response)['data'] as Map<String, dynamic>;
  }

  static Future<SubscriptionCheckoutResult> startCheckout({
    required String planCode,
    required String countryCode,
    required String provider,
    String? phoneNumber,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.post<Map<String, dynamic>>(
      _url('subscription/checkout'),
      data: {
        'deviceId': deviceId,
        'planCode': planCode,
        'countryCode': countryCode,
        'provider': provider,
        ...?(phoneNumber == null ? null : {'phoneNumber': phoneNumber}),
      },
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    return SubscriptionCheckoutResult.fromJson(data);
  }

  static Future<Map<String, dynamic>> confirmGooglePay({
    required String paymentId,
    required Map<String, dynamic> paymentData,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _dio.post<Map<String, dynamic>>(
      _url('subscription/google-pay/confirm'),
      data: {
        'deviceId': deviceId,
        'paymentId': paymentId,
        'paymentData': paymentData,
      },
      options: Options(headers: headers),
    );
    return _requireOk(response)['data'] as Map<String, dynamic>;
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
      throw Exception('Cloud subscription is not activated.');
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
    throw Exception(body['error']?.toString() ?? 'Subscription request failed');
  }
}
