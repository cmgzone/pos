import 'dart:io';

import 'package:dio/dio.dart';

import 'license_service.dart';
import 'shop_settings.dart';
import 'sync_settings_service.dart';

class SubscriptionPlanPrice {
  final String id;
  final String planCode;
  final String countryCode;
  final String currency;
  final int amountMinor;
  final String billingPeriod;
  final String provider;
  final String? storeProductId;

  const SubscriptionPlanPrice({
    required this.id,
    required this.planCode,
    required this.countryCode,
    required this.currency,
    required this.amountMinor,
    required this.billingPeriod,
    required this.provider,
    this.storeProductId,
  });

  factory SubscriptionPlanPrice.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlanPrice(
      id: json['id']?.toString() ?? '',
      planCode: json['planCode']?.toString() ?? '',
      countryCode: json['countryCode']?.toString() ?? 'GLOBAL',
      currency: json['currency']?.toString() ?? 'USD',
      amountMinor: (json['amountMinor'] as num? ?? 0).toInt(),
      billingPeriod: json['billingPeriod']?.toString() ?? 'monthly',
      provider: json['provider']?.toString() ?? 'google_play',
      storeProductId: _readText(json['storeProductId']),
    );
  }

  String get displayAmount {
    final major = amountMinor / 100;
    final decimals = currency == 'KES' ? 0 : 2;
    final value = major.toStringAsFixed(decimals);
    final parts = value.split('.');
    final whole = _withThousands(parts.first);
    final body = '$whole${parts.length > 1 ? '.${parts.last}' : ''}';
    final symbol = ShopSettings.currencySymbolFor(currency);
    final separator = ShopSettings.currencySymbolUsesSpace(symbol) ? ' ' : '';
    return '$symbol$separator$body';
  }

  /// Same amount as [displayAmount] but with the ISO currency code appended in
  /// parentheses, e.g. `$15.00 (USD)` or `KSh 1,500 (KES)`.
  String get displayAmountWithCode {
    final amount = displayAmount;
    final code = currency.trim().toUpperCase();
    return code.isEmpty ? amount : '$amount ($code)';
  }

  static String _withThousands(String value) {
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final remaining = value.length - i;
      buffer.write(value[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}

class SubscriptionMarket {
  final String countryCode;
  final String label;
  final String currency;
  final String provider;
  final String providerLabel;
  final bool paymentActive;

  const SubscriptionMarket({
    required this.countryCode,
    required this.label,
    required this.currency,
    required this.provider,
    required this.providerLabel,
    this.paymentActive = true,
  });

  factory SubscriptionMarket.fromJson(Map<String, dynamic> json) {
    return SubscriptionMarket(
      countryCode: json['countryCode']?.toString() ?? 'GLOBAL',
      label: json['label']?.toString() ?? 'Other Countries',
      currency: json['currency']?.toString() ?? 'USD',
      provider: json['provider']?.toString() ?? 'google_play',
      providerLabel: json['providerLabel']?.toString() ?? 'Google Play',
      paymentActive: json['paymentActive'] == null
          ? true
          : json['paymentActive'] == true,
    );
  }

  String get key => '$countryCode:$provider';

  String get displayLabel => '$label - $providerLabel';
}

class SubscriptionCountry {
  final String countryCode;
  final String label;
  final String currency;

  const SubscriptionCountry({
    required this.countryCode,
    required this.label,
    required this.currency,
  });

  factory SubscriptionCountry.fromJson(Map<String, dynamic> json) {
    return SubscriptionCountry(
      countryCode: json['countryCode']?.toString() ?? 'GLOBAL',
      label: json['label']?.toString() ?? 'Other Countries',
      currency: json['currency']?.toString() ?? 'USD',
    );
  }
}

class SubscriptionPlanSummary {
  final String code;
  final String name;
  final String description;
  final List<String> features;
  final List<String> sellingModes;
  final SubscriptionEntitlements entitlements;
  final List<SubscriptionPlanPrice> prices;
  final SubscriptionPlanPrice? price;

  const SubscriptionPlanSummary({
    required this.code,
    required this.name,
    required this.description,
    required this.features,
    required this.sellingModes,
    required this.entitlements,
    required this.prices,
    required this.price,
  });

  factory SubscriptionPlanSummary.fromJson(Map<String, dynamic> json) {
    final rawFeatures = json['features'];
    final rawSellingModes =
        json['sellingModes'] ?? json['availableSellingModes'];
    final parsedPrice = json['price'] is Map<String, dynamic>
        ? SubscriptionPlanPrice.fromJson(json['price'] as Map<String, dynamic>)
        : null;
    return SubscriptionPlanSummary(
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      features: rawFeatures is List
          ? rawFeatures.map((item) => item.toString()).toList()
          : const [],
      sellingModes: rawSellingModes is List
          ? rawSellingModes.map((item) => item.toString()).toList()
          : const [],
      entitlements: SubscriptionEntitlements.fromJson(json['entitlements']),
      prices: json['prices'] is List
          ? (json['prices'] as List)
                .whereType<Map<String, dynamic>>()
                .map(SubscriptionPlanPrice.fromJson)
                .where(
                  (price) =>
                      price.provider != 'mpesa' &&
                      price.provider != 'google_pay',
                )
                .toList()
          : const [],
      price:
          parsedPrice?.provider == 'mpesa' ||
              parsedPrice?.provider == 'google_pay'
          ? null
          : parsedPrice,
    );
  }

  SubscriptionPlanPrice? priceFor(
    SubscriptionMarket market, {
    String? billingPeriod,
  }) {
    bool matches(SubscriptionPlanPrice price, String countryCode) {
      return price.countryCode == countryCode &&
          price.provider == market.provider &&
          (billingPeriod == null || price.billingPeriod == billingPeriod);
    }

    return prices
            .where((price) => matches(price, market.countryCode))
            .firstOrNull ??
        prices.where((price) => matches(price, 'GLOBAL')).firstOrNull ??
        (billingPeriod == null || price?.billingPeriod == billingPeriod
            ? price
            : null);
  }

  List<String> billingPeriodsFor(SubscriptionMarket market) {
    final periods = <String>[];
    for (final item in prices) {
      final matchesMarket =
          item.provider == market.provider &&
          (item.countryCode == market.countryCode ||
              item.countryCode == 'GLOBAL');
      if (matchesMarket && !periods.contains(item.billingPeriod)) {
        periods.add(item.billingPeriod);
      }
    }
    if (periods.isEmpty &&
        price != null &&
        price!.provider == market.provider) {
      periods.add(price!.billingPeriod);
    }
    periods.sort((a, b) {
      const order = {'monthly': 0, 'yearly': 1, 'weekly': 2};
      return (order[a] ?? 99).compareTo(order[b] ?? 99);
    });
    return periods;
  }
}

class SubscriptionCatalog {
  final String backendUrl;
  final String? countryCode;
  final String? provider;
  final SubscriptionMarket? selectedMarket;
  final List<SubscriptionMarket> markets;
  final List<SubscriptionCountry> availableCountries;
  final List<SubscriptionPlanSummary> plans;
  final String platform;

  const SubscriptionCatalog({
    required this.backendUrl,
    required this.countryCode,
    required this.provider,
    required this.selectedMarket,
    required this.markets,
    required this.availableCountries,
    required this.plans,
    required this.platform,
  });
}

class SubscriptionCheckoutResult {
  final String? backendUrl;
  final String paymentId;
  final String provider;
  final String status;
  final String? message;
  final String? checkoutUrl;
  final String? storeProductId;
  final String? checkoutMode;
  final String? nextActionType;
  final bool requiresCard;
  final bool requiresPin;
  final bool requiresOtp;
  final bool requiresAvs;

  const SubscriptionCheckoutResult({
    required this.backendUrl,
    required this.paymentId,
    required this.provider,
    required this.status,
    required this.message,
    required this.checkoutUrl,
    required this.storeProductId,
    required this.checkoutMode,
    required this.nextActionType,
    required this.requiresCard,
    required this.requiresPin,
    required this.requiresOtp,
    required this.requiresAvs,
  });

  factory SubscriptionCheckoutResult.fromJson(
    Map<String, dynamic> json, {
    String? backendUrl,
  }) {
    final nextAction = json['nextAction'];
    final nextActionMap = nextAction is Map
        ? Map<String, dynamic>.from(nextAction)
        : const <String, dynamic>{};
    final nextActionType =
        _readText(json['nextActionType']) ??
        _readText(nextActionMap['type']) ??
        _readText(nextAction);
    final normalizedAction = nextActionType?.trim().toLowerCase() ?? '';
    return SubscriptionCheckoutResult(
      backendUrl: _readText(backendUrl),
      paymentId: _readText(json['id']) ?? _readText(json['paymentId']) ?? '',
      provider: json['provider']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      message: json['message']?.toString(),
      checkoutUrl:
          _readText(json['checkoutUrl']) ??
          _readText(json['redirectUrl']) ??
          _readText(nextActionMap['url']),
      storeProductId: _readText(json['storeProductId']),
      checkoutMode: _readText(json['checkoutMode']),
      nextActionType: nextActionType,
      requiresCard:
          json['requiresCard'] == true || normalizedAction.contains('card'),
      requiresPin:
          json['requiresPin'] == true || normalizedAction.contains('pin'),
      requiresOtp:
          json['requiresOtp'] == true || normalizedAction.contains('otp'),
      requiresAvs:
          json['requiresAvs'] == true ||
          json['requiresAdditionalFields'] == true ||
          normalizedAction.contains('additional_fields') ||
          normalizedAction.contains('avs'),
    );
  }

  bool get isFlutterwaveV4 =>
      provider.trim().toLowerCase() == 'flutterwave' &&
      checkoutMode?.trim().toLowerCase() == 'flutterwave_v4';

  String get normalizedStatus => status.trim().toLowerCase();

  bool get isPaid => normalizedStatus == 'paid';

  bool get isCancelled =>
      normalizedStatus == 'cancelled' || normalizedStatus == 'canceled';

  bool get isTerminalFailure =>
      isCancelled ||
      normalizedStatus == 'failed' ||
      normalizedStatus == 'declined';
}

class SubscriptionService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 75),
      receiveTimeout: const Duration(seconds: 75),
      sendTimeout: const Duration(seconds: 75),
    ),
  );

  static Future<SubscriptionCatalog> fetchPlans({
    String? countryCode,
    String? provider,
  }) async {
    await SyncSettingsService.init();
    final queryParameters = {
      if (countryCode != null && countryCode.trim().isNotEmpty)
        'countryCode': countryCode,
      if (provider != null && provider.trim().isNotEmpty) 'provider': provider,
      'platform': currentPlatform,
    };
    final response = await _getWithFallback(
      'subscription/plans',
      queryParameters: queryParameters,
    );
    final body = _requireOk(response);
    final rawPlans = body['plans'];
    final rawMarkets = body['markets'];
    final markets = rawMarkets is List
        ? rawMarkets
              .whereType<Map<String, dynamic>>()
              .map(SubscriptionMarket.fromJson)
              .where(
                (market) =>
                    market.provider != 'mpesa' &&
                    market.provider != 'google_pay',
              )
              .toList()
        : <SubscriptionMarket>[];
    final parsedSelectedMarket = body['selectedMarket'] is Map<String, dynamic>
        ? SubscriptionMarket.fromJson(
            body['selectedMarket'] as Map<String, dynamic>,
          )
        : null;
    final rawCountries = body['availableCountries'];
    final availableCountries = rawCountries is List
        ? rawCountries
              .whereType<Map<String, dynamic>>()
              .map(SubscriptionCountry.fromJson)
              .toList()
        : <SubscriptionCountry>[];
    return SubscriptionCatalog(
      backendUrl: _sourceBackendUrl(response),
      countryCode: body['countryCode']?.toString(),
      provider: body['provider']?.toString(),
      selectedMarket:
          parsedSelectedMarket?.provider == 'mpesa' ||
              parsedSelectedMarket?.provider == 'google_pay'
          ? (markets.isEmpty ? null : markets.first)
          : parsedSelectedMarket,
      markets: markets,
      availableCountries: availableCountries,
      plans: rawPlans is List
          ? rawPlans
                .whereType<Map<String, dynamic>>()
                .map(SubscriptionPlanSummary.fromJson)
                .toList()
          : const [],
      platform: body['platform']?.toString() ?? currentPlatform,
    );
  }

  static Future<Map<String, dynamic>> fetchCurrent({
    String? countryCode,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _getWithFallback(
      'subscription/current',
      queryParameters: {
        if (countryCode != null && countryCode.trim().isNotEmpty)
          'countryCode': countryCode,
        'deviceId': deviceId,
        'platform': currentPlatform,
      },
      options: Options(headers: headers),
    );
    return _requireOk(response)['data'] as Map<String, dynamic>;
  }

  static Future<SubscriptionCheckoutResult> startCheckout({
    required String planCode,
    required String countryCode,
    required String provider,
    required String billingPeriod,
    required String sellingMode,
  }) async {
    if (const {'mpesa', 'google_pay'}.contains(provider.trim().toLowerCase())) {
      throw UnsupportedError(
        'M-Pesa is available only for customer sales configured by the business.',
      );
    }
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _postWithFallback(
      'subscription/checkout',
      data: {
        'deviceId': deviceId,
        'planCode': planCode,
        'countryCode': countryCode,
        'provider': provider,
        'billingPeriod': billingPeriod,
        'sellingMode': sellingMode,
        'platform': currentPlatform,
      },
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    return SubscriptionCheckoutResult.fromJson(
      data,
      backendUrl: _sourceBackendUrl(response),
    );
  }

  static Future<Map<String, dynamic>> confirmGooglePlay({
    required String paymentId,
    required String productId,
    required String purchaseToken,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _postWithFallback(
      'subscription/google-play/confirm',
      data: {
        'deviceId': deviceId,
        'paymentId': paymentId,
        'productId': productId,
        'purchaseToken': purchaseToken,
      },
      options: Options(headers: headers),
    );
    return _requireOk(response)['data'] as Map<String, dynamic>;
  }

  static Future<SubscriptionCheckoutResult> submitFlutterwaveV4Card({
    required String backendUrl,
    required String paymentId,
    required String cardNumber,
    required String expiryMonth,
    required String expiryYear,
    required String cvv,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _postToPaymentBackend(
      backendUrl,
      'subscription/flutterwave/v4/card',
      data: {
        'deviceId': deviceId,
        'paymentId': paymentId,
        'cardNumber': cardNumber,
        'expiryMonth': expiryMonth,
        'expiryYear': expiryYear,
        'cvv': cvv,
      },
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    return SubscriptionCheckoutResult.fromJson(data, backendUrl: backendUrl);
  }

  static Future<SubscriptionCheckoutResult> authorizeFlutterwaveV4({
    required String backendUrl,
    required String paymentId,
    required String type,
    String? value,
    Map<String, String>? address,
  }) async {
    final authorizationType = type.trim().toLowerCase();
    if (!const {'pin', 'otp', 'avs'}.contains(authorizationType)) {
      throw ArgumentError.value(type, 'type', 'Must be pin, otp, or avs.');
    }
    final authorizationValue = value?.trim() ?? '';
    if (authorizationType != 'avs' && authorizationValue.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Authorization is required.');
    }
    if (authorizationType == 'avs' && (address == null || address.isEmpty)) {
      throw ArgumentError.value(address, 'address', 'Address is required.');
    }
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = await _postToPaymentBackend(
      backendUrl,
      'subscription/flutterwave/v4/authorize',
      data: {
        'deviceId': deviceId,
        'paymentId': paymentId,
        'type': authorizationType,
        if (authorizationType == 'avs') 'address': address,
        if (authorizationType != 'avs') 'value': authorizationValue,
      },
      options: Options(headers: headers),
    );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    return SubscriptionCheckoutResult.fromJson(data, backendUrl: backendUrl);
  }

  static Future<SubscriptionCheckoutResult> fetchPayment({
    required String paymentId,
    String? backendUrl,
  }) async {
    final headers = await _authHeaders();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final response = backendUrl == null
        ? await _getWithFallback(
            'subscription/payments/${Uri.encodeComponent(paymentId)}',
            queryParameters: {'deviceId': deviceId},
            options: Options(headers: headers),
          )
        : await _getFromPaymentBackend(
            backendUrl,
            'subscription/payments/${Uri.encodeComponent(paymentId)}',
            queryParameters: {'deviceId': deviceId},
            options: Options(headers: headers),
          );
    final data = _requireOk(response)['data'] as Map<String, dynamic>;
    return SubscriptionCheckoutResult.fromJson(
      data,
      backendUrl: backendUrl ?? _sourceBackendUrl(response),
    );
  }

  static String get currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return Platform.operatingSystem.toLowerCase();
  }

  static Future<String> resolveReachableBackendUrl() async {
    final catalog = await fetchPlans();
    return catalog.backendUrl;
  }

  static String _urlFor(String backendUrl, String path) {
    final base = backendUrl.replaceFirst(RegExp(r'/+$'), '');
    return '$base/$path';
  }

  static Future<Response<Map<String, dynamic>>> _getWithFallback(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return _requestWithFallback(
      (backendUrl) => _dio.get<Map<String, dynamic>>(
        _urlFor(backendUrl, path),
        queryParameters: queryParameters,
        options: _withSourceBackend(options, backendUrl),
      ),
    );
  }

  static Future<Response<Map<String, dynamic>>> _postWithFallback(
    String path, {
    Object? data,
    Options? options,
  }) async {
    return _requestWithFallback(
      (backendUrl) => _dio.post<Map<String, dynamic>>(
        _urlFor(backendUrl, path),
        data: data,
        options: _withSourceBackend(options, backendUrl),
      ),
    );
  }

  static Future<Response<Map<String, dynamic>>> _postToPaymentBackend(
    String backendUrl,
    String path, {
    Object? data,
    Options? options,
  }) {
    final secureBackendUrl = _securePaymentBackendUrl(backendUrl);
    return _requestPaymentBackend(
      secureBackendUrl,
      () => _dio.post<Map<String, dynamic>>(
        _urlFor(secureBackendUrl, path),
        data: data,
        options: _withSourceBackend(options, secureBackendUrl),
      ),
    );
  }

  static Future<Response<Map<String, dynamic>>> _getFromPaymentBackend(
    String backendUrl,
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    final secureBackendUrl = _securePaymentBackendUrl(backendUrl);
    return _requestPaymentBackend(
      secureBackendUrl,
      () => _dio.get<Map<String, dynamic>>(
        _urlFor(secureBackendUrl, path),
        queryParameters: queryParameters,
        options: _withSourceBackend(options, secureBackendUrl),
      ),
    );
  }

  static Future<Response<Map<String, dynamic>>> _requestPaymentBackend(
    String backendUrl,
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    try {
      return await request();
    } catch (error) {
      final responseError = _responseErrorMessage(error);
      if (responseError != null) {
        throw Exception(responseError);
      }
      if (_isRetryableConnectionError(error)) {
        throw Exception(_connectionErrorMessage(error, [backendUrl]));
      }
      rethrow;
    }
  }

  static String _securePaymentBackendUrl(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw Exception(
        'Flutterwave v4 checkout requires the same secure HTTPS backend that created the payment.',
      );
    }
    return normalized;
  }

  static Future<Response<Map<String, dynamic>>> _requestWithFallback(
    Future<Response<Map<String, dynamic>>> Function(String backendUrl) request,
  ) async {
    Object? lastError;
    final candidates = SyncSettingsService.backendUrlCandidates;
    for (final backendUrl in candidates) {
      try {
        return await request(backendUrl);
      } catch (error) {
        lastError = error;
        final responseError = _responseErrorMessage(error);
        if (responseError != null) {
          throw Exception(responseError);
        }
        if (!_isRetryableConnectionError(error)) {
          rethrow;
        }
      }
    }
    throw Exception(_connectionErrorMessage(lastError, candidates));
  }

  static Options _withSourceBackend(Options? options, String backendUrl) {
    final base = options ?? Options();
    final extra = Map<String, dynamic>.from(base.extra ?? const {});
    extra['sourceBackendUrl'] = backendUrl;
    return base.copyWith(extra: extra);
  }

  static String _sourceBackendUrl(Response response) {
    return response.requestOptions.extra['sourceBackendUrl']?.toString() ??
        SyncSettingsService.backendUrl;
  }

  static String? _responseErrorMessage(Object error) {
    if (error is! DioException) {
      return null;
    }
    final data = error.response?.data;
    if (data is Map) {
      final message = data['error'] ?? data['message'];
      final text = message?.toString().trim();
      return text == null || text.isEmpty ? null : text;
    }
    if (data is String) {
      final text = data.trim();
      return text.isEmpty ? null : text;
    }
    return null;
  }

  static bool _isRetryableConnectionError(Object error) {
    if (error is! DioException) {
      return false;
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        return error.response == null;
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.cancel:
        return false;
    }
  }

  static String _connectionErrorMessage(Object? error, List<String> urls) {
    final tried = urls.isEmpty ? '' : ' Tried: ${urls.join(', ')}.';
    if (error is DioException) {
      final message = error.message?.trim();
      return 'Could not reach the subscription backend.${message == null || message.isEmpty ? '' : ' $message'}$tried';
    }
    return 'Could not reach the subscription backend.$tried';
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

String? _readText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
