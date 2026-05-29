import 'package:url_launcher/url_launcher.dart';

import 'license_service.dart';
import 'shop_settings.dart';
import 'sync_service.dart';
import 'sync_settings_service.dart';

class CatalogShareInfo {
  final String url;
  final String businessName;
  final SyncRunSummary? syncSummary;

  const CatalogShareInfo({
    required this.url,
    required this.businessName,
    this.syncSummary,
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
    if (syncBeforeShare) {
      syncSummary = await SyncService.syncNow();
    }

    return CatalogShareInfo(
      url: buildCatalogUrl(businessId),
      businessName: snapshot.businessName?.trim().isNotEmpty == true
          ? snapshot.businessName!.trim()
          : 'our shop',
      syncSummary: syncSummary,
    );
  }

  static String buildCatalogUrl(String businessId) {
    final base = _publicBackendBaseUrl();
    final encodedBusinessId = Uri.encodeComponent(businessId.trim());
    final uri = Uri.parse('$base/catalog/$encodedBusinessId');
    final currency = ShopSettings.currency.trim();
    if (currency.isEmpty) {
      return uri.toString();
    }
    return uri.replace(queryParameters: {'currency': currency}).toString();
  }

  static String buildMessage(CatalogShareInfo info) {
    return 'Hello, you can view ${info.businessName} product catalog here:\n${info.url}';
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

  static String _publicBackendBaseUrl() {
    final backendUrl = SyncSettingsService.backendUrl.trim();
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync backend is not configured.');
    }
    final trimmed = backendUrl.replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/api')) {
      return trimmed.substring(0, trimmed.length - 4);
    }
    return trimmed;
  }
}
