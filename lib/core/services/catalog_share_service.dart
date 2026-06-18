import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/app_constants.dart';
import 'database_service.dart';
import 'external_app_launcher.dart';
import 'license_service.dart';
import 'shop_settings.dart';
import 'sync_service.dart';
import 'sync_settings_service.dart';

class CatalogShareInfo {
  final String url;
  final String businessName;
  final SyncRunSummary? syncSummary;
  final String? syncWarning;

  const CatalogShareInfo({
    required this.url,
    required this.businessName,
    this.syncSummary,
    this.syncWarning,
  });
}

class CatalogShareService {
  static const _timeout = Duration(seconds: 20);

  static Future<CatalogShareInfo> prepare({bool syncBeforeShare = true}) async {
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
    try {
      final storefrontBaseUrl = await _loadStorefrontBaseUrl(
        snapshot.accessToken!,
      );
      catalogUrl = buildStorefrontCatalogUrl(storefrontBaseUrl);
    } catch (error) {
      final storefrontWarning =
          'Custom store link could not be refreshed, so the classic catalog link is being used: ${_errorMessage(error)}';
      syncWarning = syncWarning == null
          ? storefrontWarning
          : '$syncWarning $storefrontWarning';
    }

    return CatalogShareInfo(
      url: catalogUrl,
      businessName: snapshot.businessName?.trim().isNotEmpty == true
          ? snapshot.businessName!.trim()
          : 'our shop',
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
    return 'Hello, you can shop ${info.businessName} online here:\n${info.url}\n\nBrowse products, add to cart, and send your order for confirmation.';
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

  static String _errorMessage(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }

  static Future<String> _loadStorefrontBaseUrl(String accessToken) async {
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
    final url = data is Map<String, dynamic>
        ? data['url']?.toString().trim() ?? ''
        : '';
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      throw Exception('Storefront service did not return a valid URL.');
    }
    return parsed.toString();
  }
}
