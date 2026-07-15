import 'dart:async';

import 'package:dio/dio.dart';

import 'license_service.dart';
import 'sync_settings_service.dart';

class StorefrontThemeDesign {
  final String backgroundColor;
  final String textColor;
  final String mutedColor;
  final String surfaceColor;
  final String surfaceElevatedColor;
  final String borderColor;
  final String accentColor;
  final String fontFamily;
  final String heroStyle;
  final String cardStyle;
  final String imageRatio;
  final String density;
  final String cornerStyle;

  const StorefrontThemeDesign({
    required this.backgroundColor,
    required this.textColor,
    required this.mutedColor,
    required this.surfaceColor,
    required this.surfaceElevatedColor,
    required this.borderColor,
    required this.accentColor,
    required this.fontFamily,
    required this.heroStyle,
    required this.cardStyle,
    required this.imageRatio,
    required this.density,
    required this.cornerStyle,
  });

  factory StorefrontThemeDesign.fromJson(Map<String, dynamic> json) {
    return StorefrontThemeDesign(
      backgroundColor: json['backgroundColor']?.toString() ?? '#100f0d',
      textColor: json['textColor']?.toString() ?? '#f5f3ef',
      mutedColor: json['mutedColor']?.toString() ?? '#9a958c',
      surfaceColor: json['surfaceColor']?.toString() ?? '#181614',
      surfaceElevatedColor:
          json['surfaceElevatedColor']?.toString() ?? '#211f1c',
      borderColor: json['borderColor']?.toString() ?? '#37332f',
      accentColor: json['accentColor']?.toString() ?? '#f0ead6',
      fontFamily: json['fontFamily']?.toString() ?? 'inter',
      heroStyle: json['heroStyle']?.toString() ?? 'cover',
      cardStyle: json['cardStyle']?.toString() ?? 'bordered',
      imageRatio: json['imageRatio']?.toString() ?? 'portrait',
      density: json['density']?.toString() ?? 'comfortable',
      cornerStyle: json['cornerStyle']?.toString() ?? 'soft',
    );
  }

  Map<String, dynamic> toJson() => {
    'backgroundColor': backgroundColor,
    'textColor': textColor,
    'mutedColor': mutedColor,
    'surfaceColor': surfaceColor,
    'surfaceElevatedColor': surfaceElevatedColor,
    'borderColor': borderColor,
    'accentColor': accentColor,
    'fontFamily': fontFamily,
    'heroStyle': heroStyle,
    'cardStyle': cardStyle,
    'imageRatio': imageRatio,
    'density': density,
    'cornerStyle': cornerStyle,
  };
}

class StorefrontCheckoutSettings {
  final List<String> paymentMethods;
  final String defaultPaymentMethod;
  final List<String> fulfillmentMethods;
  final String defaultFulfillmentMethod;
  final bool showDeliveryAddress;
  final bool showOrderNote;
  final bool showOrderTracking;
  final String checkoutTitle;
  final String checkoutButtonLabel;
  final String successMessage;

  const StorefrontCheckoutSettings({
    required this.paymentMethods,
    required this.defaultPaymentMethod,
    required this.fulfillmentMethods,
    required this.defaultFulfillmentMethod,
    required this.showDeliveryAddress,
    required this.showOrderNote,
    required this.showOrderTracking,
    required this.checkoutTitle,
    required this.checkoutButtonLabel,
    required this.successMessage,
  });

  factory StorefrontCheckoutSettings.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key, List<String> fallback) {
      final value = json[key];
      if (value is! List) return fallback;
      final values = value.map((item) => item.toString()).toList();
      return values.isEmpty ? fallback : values;
    }

    return StorefrontCheckoutSettings(
      paymentMethods: strings('paymentMethods', const ['manual']),
      defaultPaymentMethod:
          json['defaultPaymentMethod']?.toString() ?? 'manual',
      fulfillmentMethods: strings('fulfillmentMethods', const [
        'pickup',
        'delivery',
      ]),
      defaultFulfillmentMethod:
          json['defaultFulfillmentMethod']?.toString() ?? 'pickup',
      showDeliveryAddress: json['showDeliveryAddress'] != false,
      showOrderNote: json['showOrderNote'] != false,
      showOrderTracking: json['showOrderTracking'] != false,
      checkoutTitle: json['checkoutTitle']?.toString() ?? 'Checkout',
      checkoutButtonLabel:
          json['checkoutButtonLabel']?.toString() ?? 'Place order',
      successMessage:
          json['successMessage']?.toString() ?? 'Your order has been received.',
    );
  }

  Map<String, dynamic> toJson() => {
    'paymentMethods': paymentMethods,
    'defaultPaymentMethod': defaultPaymentMethod,
    'fulfillmentMethods': fulfillmentMethods,
    'defaultFulfillmentMethod': defaultFulfillmentMethod,
    'showDeliveryAddress': showDeliveryAddress,
    'showOrderNote': showOrderNote,
    'showOrderTracking': showOrderTracking,
    'checkoutTitle': checkoutTitle,
    'checkoutButtonLabel': checkoutButtonLabel,
    'successMessage': successMessage,
  };
}

class StorefrontThemePreset {
  final String id;
  final String label;
  final String description;
  final StorefrontThemeDesign design;

  const StorefrontThemePreset({
    required this.id,
    required this.label,
    required this.description,
    required this.design,
  });

  factory StorefrontThemePreset.fromJson(Map<String, dynamic> json) {
    return StorefrontThemePreset(
      id: json['id']?.toString() ?? 'studio',
      label: json['label']?.toString() ?? 'Studio',
      description: json['description']?.toString() ?? '',
      design: StorefrontThemeDesign.fromJson(
        Map<String, dynamic>.from(json['design'] as Map? ?? const {}),
      ),
    );
  }
}

class StorefrontThemeSection {
  final String id;
  final String type;
  final String title;
  final bool enabled;
  final Map<String, dynamic> data;

  const StorefrontThemeSection({
    required this.id,
    required this.type,
    required this.title,
    required this.enabled,
    required this.data,
  });

  factory StorefrontThemeSection.fromJson(Map<String, dynamic> json) {
    final data = Map<String, dynamic>.from(json);
    return StorefrontThemeSection(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'catalog',
      title: json['title']?.toString() ?? json['text']?.toString() ?? 'Section',
      enabled: json['enabled'] != false,
      data: data,
    );
  }

  Map<String, dynamic> toJson() => {
    ...data,
    'id': id,
    'type': type,
    'enabled': enabled,
  };

  StorefrontThemeSection copyWith({
    String? id,
    String? type,
    String? title,
    bool? enabled,
    Map<String, dynamic>? data,
  }) {
    final nextData = Map<String, dynamic>.from(data ?? this.data);
    final nextTitle = title ?? this.title;
    if (type == 'announcement' || this.type == 'announcement') {
      nextData['text'] = nextTitle;
    } else {
      nextData['title'] = nextTitle;
    }
    return StorefrontThemeSection(
      id: id ?? this.id,
      type: type ?? this.type,
      title: nextTitle,
      enabled: enabled ?? this.enabled,
      data: nextData,
    );
  }
}

class StorefrontTheme {
  final String id;
  final String branchId;
  final String storefrontType;
  final String name;
  final String preset;
  final StorefrontThemeDesign design;
  final List<StorefrontThemeSection> sections;
  final StorefrontCheckoutSettings checkout;
  final String source;
  final bool isPublished;
  final DateTime? updatedAt;

  const StorefrontTheme({
    required this.id,
    required this.branchId,
    required this.storefrontType,
    required this.name,
    required this.preset,
    required this.design,
    required this.sections,
    required this.checkout,
    required this.source,
    required this.isPublished,
    required this.updatedAt,
  });

  factory StorefrontTheme.fromJson(Map<String, dynamic> json) {
    return StorefrontTheme(
      id: json['id']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? 'main_branch',
      storefrontType: json['storefrontType']?.toString() ?? 'retail',
      name: json['name']?.toString() ?? 'Storefront theme',
      preset: json['preset']?.toString() ?? 'studio',
      design: StorefrontThemeDesign.fromJson(
        Map<String, dynamic>.from(json['design'] as Map? ?? const {}),
      ),
      sections: (json['sections'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (section) => StorefrontThemeSection.fromJson(
              Map<String, dynamic>.from(section),
            ),
          )
          .toList(),
      checkout: StorefrontCheckoutSettings.fromJson(
        Map<String, dynamic>.from(json['checkout'] as Map? ?? const {}),
      ),
      source: json['source']?.toString() ?? 'manual',
      isPublished: json['isPublished'] == true,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

class StorefrontThemeCollection {
  final List<StorefrontTheme> themes;
  final List<StorefrontThemePreset> presets;
  final String branchId;
  final String storefrontType;

  const StorefrontThemeCollection({
    required this.themes,
    required this.presets,
    required this.branchId,
    required this.storefrontType,
  });
}

enum StorefrontThemeChangeKind { upsert, delete }

class StorefrontThemeChange {
  final StorefrontTheme theme;
  final StorefrontThemeChangeKind kind;

  const StorefrontThemeChange({required this.theme, required this.kind});
}

class StorefrontPreviewUnavailableException implements Exception {
  final String message;

  const StorefrontPreviewUnavailableException(this.message);

  @override
  String toString() => message;
}

class StorefrontThemeService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 30),
    ),
  );
  static final StreamController<StorefrontThemeChange> _changes =
      StreamController<StorefrontThemeChange>.broadcast(sync: true);
  static Stream<StorefrontThemeChange> get changes => _changes.stream;

  static Future<StorefrontThemeCollection> list({
    required String branchId,
    required String storefrontType,
  }) async {
    final context = await _requestContext();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('catalog/themes'),
      queryParameters: {
        'deviceId': context.deviceId,
        'branchId': branchId,
        'storefrontType': storefrontType,
      },
      options: Options(headers: context.headers),
    );
    final data = Map<String, dynamic>.from(
      _requireOk(response)['data'] as Map? ?? const {},
    );
    return StorefrontThemeCollection(
      themes: (data['themes'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => StorefrontTheme.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      presets: (data['presets'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                StorefrontThemePreset.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      branchId: data['branchId']?.toString() ?? branchId,
      storefrontType: data['storefrontType']?.toString() ?? storefrontType,
    );
  }

  static Future<StorefrontTheme> create({
    required String branchId,
    required String storefrontType,
    required String name,
    String preset = 'studio',
    Map<String, dynamic>? design,
    Map<String, dynamic>? checkout,
    String source = 'manual',
  }) {
    return _write(
      method: 'POST',
      path: 'catalog/themes',
      data: {
        'branchId': branchId,
        'storefrontType': storefrontType,
        'name': name,
        'preset': preset,
        ...design == null ? const {} : {'design': design},
        ...checkout == null ? const {} : {'checkout': checkout},
        'source': source,
      },
      action: 'create a storefront theme',
    );
  }

  static Future<StorefrontTheme> update(
    String themeId,
    Map<String, dynamic> changes,
  ) {
    return _write(
      method: 'PUT',
      path: 'catalog/themes/$themeId',
      data: changes,
      action: 'update a storefront theme',
    );
  }

  static Future<StorefrontTheme> duplicate(
    String themeId, {
    String? name,
    String source = 'duplicate',
  }) {
    return _write(
      method: 'POST',
      path: 'catalog/themes/$themeId/duplicate',
      data: {
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        'source': source,
      },
      action: 'duplicate a storefront theme',
    );
  }

  static Future<StorefrontTheme> publish(String themeId) {
    return _write(
      method: 'POST',
      path: 'catalog/themes/$themeId/publish',
      data: const {},
      action: 'publish a storefront theme',
    );
  }

  static Future<StorefrontTheme> aiCustomize(
    String themeId,
    String instruction, {
    bool fromScratch = false,
  }) {
    return _write(
      method: 'POST',
      path: 'catalog/themes/$themeId/ai-customize',
      data: {
        'instruction': instruction.trim(),
        'mode': fromScratch ? 'build' : 'refine',
        'fromScratch': fromScratch,
      },
      action: 'create an AI storefront theme draft',
    );
  }

  static Future<Uri> previewUrl(StorefrontTheme theme) async {
    final context = await _requestContext();
    late final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.get<Map<String, dynamic>>(
        _url('catalog/themes/${theme.id}/preview'),
        queryParameters: {'deviceId': context.deviceId},
        options: Options(headers: context.headers),
      );
    } on DioException catch (error) {
      if (!_isMissingPreviewRoute(error)) rethrow;
      if (theme.isPublished) {
        return _liveStorefrontUrl(
          context: context,
          storefrontType: theme.storefrontType,
        );
      }
      throw const StorefrontPreviewUnavailableException(
        'Draft preview is temporarily unavailable. Your theme is saved; try again after the website service has been updated.',
      );
    }
    final body = _requireOk(response);
    final data = Map<String, dynamic>.from(
      body['data'] as Map? ?? const <String, dynamic>{},
    );
    final uri = Uri.tryParse(data['url']?.toString() ?? '');
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw Exception('The exact storefront preview link is unavailable.');
    }
    return uri;
  }

  static Future<Uri> _liveStorefrontUrl({
    required _ThemeRequestContext context,
    required String storefrontType,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _url('catalog/storefront'),
      queryParameters: {'deviceId': context.deviceId, 'type': storefrontType},
      options: Options(headers: context.headers),
    );
    final data = Map<String, dynamic>.from(
      _requireOk(response)['data'] as Map? ?? const <String, dynamic>{},
    );
    final uri = Uri.tryParse(data['url']?.toString() ?? '');
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const StorefrontPreviewUnavailableException(
        'The live storefront link is temporarily unavailable.',
      );
    }
    return uri;
  }

  static bool _isMissingPreviewRoute(DioException error) {
    if (error.response?.statusCode != 404) return false;
    final data = error.response?.data;
    if (data is Map) {
      final message =
          (data['message'] ?? data['error'])?.toString().trim().toLowerCase() ??
          '';
      if (message.contains('theme was not found')) return false;
      if (message.isNotEmpty && !message.contains('cannot get')) return false;
    }
    return true;
  }

  static Future<void> delete(String themeId) async {
    await LicenseService.ensureWriteAccess(action: 'delete a storefront theme');
    final context = await _requestContext();
    final response = await _dio.delete<Map<String, dynamic>>(
      _url('catalog/themes/$themeId'),
      queryParameters: {'deviceId': context.deviceId},
      options: Options(headers: context.headers),
    );
    final body = _requireOk(response);
    final theme = StorefrontTheme.fromJson(
      Map<String, dynamic>.from(body['data'] as Map? ?? const {}),
    );
    _changes.add(
      StorefrontThemeChange(
        theme: theme,
        kind: StorefrontThemeChangeKind.delete,
      ),
    );
  }

  static Future<StorefrontTheme> _write({
    required String method,
    required String path,
    required Map<String, dynamic> data,
    required String action,
  }) async {
    await LicenseService.ensureWriteAccess(action: action);
    final context = await _requestContext();
    final payload = {'deviceId': context.deviceId, ...data};
    late final Response<Map<String, dynamic>> response;
    if (method == 'PUT') {
      response = await _dio.put<Map<String, dynamic>>(
        _url(path),
        data: payload,
        options: Options(headers: context.headers),
      );
    } else {
      response = await _dio.post<Map<String, dynamic>>(
        _url(path),
        data: payload,
        options: Options(headers: context.headers),
      );
    }
    final body = _requireOk(response);
    final theme = StorefrontTheme.fromJson(
      Map<String, dynamic>.from(body['data'] as Map? ?? const {}),
    );
    _changes.add(
      StorefrontThemeChange(
        theme: theme,
        kind: StorefrontThemeChangeKind.upsert,
      ),
    );
    return theme;
  }

  static String _url(String path) {
    final base = SyncSettingsService.backendUrl.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    if (base.isEmpty) throw Exception('Cloud sync is not configured.');
    return '$base/$path';
  }

  static Future<_ThemeRequestContext> _requestContext() async {
    await LicenseService.init();
    final token = LicenseService.currentSnapshot.accessToken;
    if (token == null || token.trim().isEmpty) {
      throw Exception('Cloud storefront management is not activated.');
    }
    return _ThemeRequestContext(
      deviceId: await SyncSettingsService.getOrCreateDeviceId(),
      headers: {'Authorization': 'Bearer $token'},
    );
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
    throw Exception(
      body['message']?.toString() ??
          body['error']?.toString() ??
          'Storefront theme request failed.',
    );
  }
}

class _ThemeRequestContext {
  final String deviceId;
  final Map<String, String> headers;

  const _ThemeRequestContext({required this.deviceId, required this.headers});
}
