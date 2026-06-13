import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import 'database_service.dart';
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

    return CatalogShareInfo(
      url: buildCatalogUrl(businessId),
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

  static String buildMessage(CatalogShareInfo info) {
    return 'Hello, you can shop ${info.businessName} online here:\n${info.url}\n\nBrowse products, add to cart, and send your order for confirmation.';
  }

  static Future<void> openCatalog(CatalogShareInfo info) async {
    final uri = Uri.parse(info.url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open catalog link.');
    }
  }

  static Future<void> openWhatsApp(CatalogShareInfo info) async {
    final encoded = Uri.encodeComponent(buildMessage(info));
    final appUri = Uri.parse('whatsapp://send?text=$encoded');
    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri, mode: LaunchMode.externalApplication);
      return;
    }

    final webUri = Uri.parse('https://wa.me/?text=$encoded');
    if (!await launchUrl(webUri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open WhatsApp.');
    }
  }

  static String _errorMessage(Object error) {
    return error.toString().replaceFirst('Exception: ', '');
  }
}
