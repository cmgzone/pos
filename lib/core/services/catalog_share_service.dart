import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import 'database_service.dart';
import 'external_app_launcher.dart';
import 'license_service.dart';
import 'shop_settings.dart';
import 'sync_service.dart';
import 'sync_settings_service.dart';

enum CatalogStorefrontType { retail, services, restaurant }

extension CatalogStorefrontTypeDetails on CatalogStorefrontType {
  String get apiValue => switch (this) {
        CatalogStorefrontType.retail => 'retail',
        CatalogStorefrontType.services => 'services',
        CatalogStorefrontType.restaurant => 'restaurant',
      };

  String get label => switch (this) {
        CatalogStorefrontType.retail => 'Retail store',
        CatalogStorefrontType.services => 'Services',
        CatalogStorefrontType.restaurant => 'Restaurant menu',
      };

  String get shareDescription => switch (this) {
        CatalogStorefrontType.retail =>
          'Browse products, add to cart, and send an order for confirmation.',
        CatalogStorefrontType.services =>
          'Browse services and send a booking request for confirmation.',
        CatalogStorefrontType.restaurant =>
          'Browse the menu, add items, and send an order to the restaurant.',
      };

  static CatalogStorefrontType? fromApiValue(Object? value) {
    return switch (value?.toString().trim().toLowerCase()) {
      'retail' || 'store' || 'shop' => CatalogStorefrontType.retail,
      'services' || 'service' => CatalogStorefrontType.services,
      'restaurant' || 'menu' => CatalogStorefrontType.restaurant,
      _ => null,
    };
  }
}

class CatalogStorefrontLink {
  final CatalogStorefrontType type;
  final String url;

  const CatalogStorefrontLink({required this.type, required this.url});
}

class CatalogShareInfo {
  final String url;
  final String mainUrl;
  final String businessName;
  final CatalogStorefrontType storefrontType;
  final CatalogStorefrontType primaryStorefrontType;
  final List<CatalogStorefrontLink> storefronts;
  final SyncRunSummary? syncSummary;
  final String? syncWarning;

  const CatalogShareInfo({
    required this.url,
    String? mainUrl,
    required this.businessName,
    this.storefrontType = CatalogStorefrontType.retail,
    this.primaryStorefrontType = CatalogStorefrontType.retail,
    this.storefronts = const [],
    this.syncSummary,
    this.syncWarning,
  }) : mainUrl = mainUrl ?? url;

  CatalogShareInfo selectStorefront(CatalogStorefrontType type) {
    final selected = storefronts.where((link) => link.type == type);
    if (selected.isEmpty) return this;
    return CatalogShareInfo(
      url: type == primaryStorefrontType ? mainUrl : selected.first.url,
      mainUrl: mainUrl,
      businessName: businessName,
      storefrontType: type,
      primaryStorefrontType: primaryStorefrontType,
      storefronts: storefronts,
      syncSummary: syncSummary,
      syncWarning: syncWarning,
    );
  }
}

class CatalogShareService {
  static const _timeout = Duration(seconds: 20);

  static Future<CatalogShareInfo> prepare({
    bool syncBeforeShare = true,
    CatalogStorefrontType? storefrontType,
  }) async {
    await SyncSettingsService.init();
    await LicenseService.init();

    final snapshot = LicenseService.currentSnapshot;
    final businessId = snapshot.businessId?.trim() ?? '';
    if (!snapshot.hasBinding || businessId.isEmpty) {
      throw Exception(
        'Cloud sync is not activated yet. Activate or sign in before sharing a public catalog link.',
      );
    }

    SyncRunSummary? syncSummary;
    String? syncWarning;
    if (syncBeforeShare) {
      try {
        syncSummary = await SyncService.syncNow();
      } catch (error) {
        syncWarning = _errorMessage(error);
      }
    }

    var catalogUrl = buildCatalogUrl(businessId);
    var mainUrl = catalogUrl;
    var selectedType = storefrontType ?? CatalogStorefrontType.retail;
    var primaryType = selectedType;
    var storefronts = <CatalogStorefrontLink>[];
    try {
      final response = await _loadStorefrontLinks(
        snapshot.accessToken!,
      );
      primaryType = response.primaryType;
      selectedType = storefrontType ?? primaryType;
      storefronts = response.links
          .map(
            (link) => CatalogStorefrontLink(
              type: link.type,
              url: buildStorefrontCatalogUrl(link.url),
            ),
          )
          .toList(growable: false);
      final selected = storefronts.where((link) => link.type == selectedType);
      if (selected.isEmpty) {
        throw Exception('${selectedType.label} is not included in this plan.');
      }
      mainUrl = buildStorefrontCatalogUrl(response.rootUrl);
      catalogUrl = storefrontType == null ? mainUrl : selected.first.url;
    } catch (error) {
      final storefrontWarning =
          'Custom store link could not be refreshed, so the classic catalog link is being used: ${_errorMessage(error)}';
      syncWarning = syncWarning == null
          ? storefrontWarning
          : '$syncWarning $storefrontWarning';
    }

    return CatalogShareInfo(
      url: catalogUrl,
      mainUrl: mainUrl,
      businessName: snapshot.businessName?.trim().isNotEmpty == true
          ? snapshot.businessName!.trim()
          : 'our shop',
      storefrontType: selectedType,
      primaryStorefrontType: primaryType,
      storefronts: storefronts,
      syncSummary: syncSummary,
      syncWarning: syncWarning,
    );
  }

  static String buildCatalogUrl(String businessId) {
    final encodedBusinessId = Uri.encodeComponent(businessId.trim());
    final uri = Uri.parse(
      '${AppConstants.publicCatalogBaseUrl}/catalog/$encodedBusinessId',
    );
    final queryParameters = <String, String>{
      'branchId': DatabaseService.currentBranchId,
    };
    final currency = ShopSettings.currency.trim();
    if (currency.isNotEmpty) {
      queryParameters['currency'] = currency;
    }
    return uri.replace(queryParameters: queryParameters).toString();
  }

  static String buildStorefrontCatalogUrl(String storefrontBaseUrl) {
    final uri = Uri.parse(storefrontBaseUrl.trim());
    final queryParameters = <String, String>{
      'branchId': DatabaseService.currentBranchId,
    };
    final currency = ShopSettings.currency.trim();
    if (currency.isNotEmpty) {
      queryParameters['currency'] = currency;
    }
    return uri
        .replace(
          path: uri.path == '/' ? '' : uri.path,
          queryParameters: queryParameters,
          fragment: null,
        )
        .toString();
  }

  static String buildMessage(CatalogShareInfo info) {
    return 'Hello, you can visit ${info.businessName} online here:\n${info.url}\n\n${info.storefrontType.shareDescription}';
  }

  static Future<void> openCatalog(CatalogShareInfo info) async {
    final uri = Uri.parse(info.url);
    if (!await ExternalAppLauncher.launch(uri)) {
      throw Exception('Could not open catalog link.');
    }
  }

  static Future<void> openWhatsApp(CatalogShareInfo info) async {
    final encoded = Uri.encodeComponent(buildMessage(info));
    final uris = [
      Uri.parse('whatsapp://send?text=$encoded'),
      Uri.parse('https://wa.me/?text=$encoded'),
    ];
    if (await ExternalAppLauncher.launchFirst(uris)) {
      return;
    }
    throw Exception('Could not open WhatsApp.');
  }

  static Future<void> setPrimaryStorefront(
    CatalogStorefrontType storefrontType,
  ) async {
    await SyncSettingsService.init();
    await LicenseService.init();
    final snapshot = LicenseService.currentSnapshot;
    if (!snapshot.hasBinding || snapshot.accessToken == null) {
      throw Exception('Cloud sync is not activated yet.');
    }
    final backendUrl = SyncSettingsService.backendUrl.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    if (backendUrl.isEmpty) {
      throw Exception('Cloud backend is not configured.');
    }
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final uri = Uri.parse('$backendUrl/catalog/storefront/primary').replace(
      queryParameters: {'deviceId': deviceId},
    );
    final response = await http
        .put(
          uri,
          headers: {
            'Authorization': 'Bearer ${snapshot.accessToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'type': storefrontType.apiValue}),
        )
        .timeout(_timeout);
    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Storefront service returned an invalid response.');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['ok'] != true) {
      throw Exception(
        body['error']?.toString() ?? 'Could not set the main website.',
      );
    }
  }

  static String _errorMessage(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  static Future<_StorefrontLinksResponse> _loadStorefrontLinks(
    String accessToken,
  ) async {
    final backendUrl = SyncSettingsService.backendUrl.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    if (backendUrl.isEmpty) {
      throw Exception('Cloud backend is not configured.');
    }

    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final uri = Uri.parse(
      '$backendUrl/catalog/storefront',
    ).replace(queryParameters: {'deviceId': deviceId});
    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $accessToken'})
        .timeout(_timeout);

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Storefront service returned an invalid response.');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['ok'] != true) {
      throw Exception(
        body['error']?.toString() ?? 'Storefront link request failed.',
      );
    }

    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Storefront service did not return a valid URL.');
    }

    final selectedType =
        CatalogStorefrontTypeDetails.fromApiValue(data['type']) ??
            CatalogStorefrontType.retail;
    final primaryType =
        CatalogStorefrontTypeDetails.fromApiValue(data['primaryType']) ??
            selectedType;
    final rootUrl = data['rootUrl']?.toString().trim() ??
        data['url']?.toString().trim() ??
        '';
    final rootParsed = Uri.tryParse(rootUrl);
    if (rootParsed == null ||
        !rootParsed.hasScheme ||
        rootParsed.host.isEmpty) {
      throw Exception('Storefront service did not return a valid URL.');
    }
    final links = <_StorefrontLinkResponse>[];
    final rawStorefronts = data['storefronts'];
    if (rawStorefronts is List) {
      for (final raw in rawStorefronts) {
        if (raw is! Map) continue;
        final type = CatalogStorefrontTypeDetails.fromApiValue(raw['type']);
        final url = raw['url']?.toString().trim() ?? '';
        final parsed = Uri.tryParse(url);
        if (type != null && parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
          links.add(_StorefrontLinkResponse(type: type, url: parsed.toString()));
        }
      }
    }

    // Older cloud servers returned one URL. Keep that rollout path working.
    if (links.isEmpty) {
      final url = data['url']?.toString().trim() ?? '';
      final parsed = Uri.tryParse(url);
      if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
        throw Exception('Storefront service did not return a valid URL.');
      }
      links.add(_StorefrontLinkResponse(type: selectedType, url: parsed.toString()));
    }

    return _StorefrontLinksResponse(
      selectedType: selectedType,
      primaryType: primaryType,
      rootUrl: rootParsed.toString(),
      links: links,
    );
  }
}

class _StorefrontLinkResponse {
  final CatalogStorefrontType type;
  final String url;

  const _StorefrontLinkResponse({required this.type, required this.url});
}

class _StorefrontLinksResponse {
  final CatalogStorefrontType selectedType;
  final CatalogStorefrontType primaryType;
  final String rootUrl;
  final List<_StorefrontLinkResponse> links;

  const _StorefrontLinksResponse({
    required this.selectedType,
    required this.primaryType,
    required this.rootUrl,
    required this.links,
  });
}
