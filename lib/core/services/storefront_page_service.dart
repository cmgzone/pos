import 'package:dio/dio.dart';

import 'license_service.dart';
import 'storefront_theme_service.dart';
import 'sync_settings_service.dart';

class StorefrontPage {
  final String id;
  final String branchId;
  final String storefrontType;
  final String pageType;
  final String title;
  final String slug;
  final String navigationLabel;
  final bool showInNavigation;
  final String seoTitle;
  final String seoDescription;
  final List<StorefrontThemeSection> sections;
  final String status;
  final String source;
  final Uri? url;

  const StorefrontPage({
    required this.id,
    required this.branchId,
    required this.storefrontType,
    required this.pageType,
    required this.title,
    required this.slug,
    required this.navigationLabel,
    required this.showInNavigation,
    required this.seoTitle,
    required this.seoDescription,
    required this.sections,
    required this.status,
    required this.source,
    required this.url,
  });

  bool get isPublished => status == 'published';

  factory StorefrontPage.fromJson(Map<String, dynamic> json) {
    return StorefrontPage(
      id: json['id']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? 'main_branch',
      storefrontType: json['storefrontType']?.toString() ?? 'retail',
      pageType: json['pageType']?.toString() ?? 'custom',
      title: json['title']?.toString() ?? 'Untitled page',
      slug: json['slug']?.toString() ?? '',
      navigationLabel:
          json['navigationLabel']?.toString() ??
          json['title']?.toString() ??
          '',
      showInNavigation: json['showInNavigation'] != false,
      seoTitle: json['seoTitle']?.toString() ?? json['title']?.toString() ?? '',
      seoDescription: json['seoDescription']?.toString() ?? '',
      sections: (json['sections'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => StorefrontThemeSection.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      status: json['status']?.toString() ?? 'draft',
      source: json['source']?.toString() ?? 'manual',
      url: Uri.tryParse(json['url']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
    'branchId': branchId,
    'storefrontType': storefrontType,
    'pageType': pageType,
    'title': title,
    'slug': slug,
    'navigationLabel': navigationLabel,
    'showInNavigation': showInNavigation,
    'seoTitle': seoTitle,
    'seoDescription': seoDescription,
    'sections': sections.map((item) => item.toJson()).toList(),
    'source': source,
  };
}

class StorefrontConnection {
  final String id;
  final String name;
  final String endpointUrl;
  final String authType;
  final String apiKeyHeader;
  final String dataPath;
  final Map<String, String> fieldMappings;
  final bool isEnabled;
  final bool hasSecret;
  final String? lastTestStatus;
  final String? lastTestMessage;

  const StorefrontConnection({
    required this.id,
    required this.name,
    required this.endpointUrl,
    required this.authType,
    required this.apiKeyHeader,
    required this.dataPath,
    required this.fieldMappings,
    required this.isEnabled,
    required this.hasSecret,
    required this.lastTestStatus,
    required this.lastTestMessage,
  });

  factory StorefrontConnection.fromJson(Map<String, dynamic> json) {
    final rawMappings = Map<String, dynamic>.from(
      json['fieldMappings'] as Map? ?? const {},
    );
    return StorefrontConnection(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Store product API',
      endpointUrl: json['endpointUrl']?.toString() ?? '',
      authType: json['authType']?.toString() ?? 'none',
      apiKeyHeader: json['apiKeyHeader']?.toString() ?? 'X-API-Key',
      dataPath: json['dataPath']?.toString() ?? '',
      fieldMappings: rawMappings.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      isEnabled: json['isEnabled'] == true,
      hasSecret: json['hasSecret'] == true,
      lastTestStatus: json['lastTestStatus']?.toString(),
      lastTestMessage: json['lastTestMessage']?.toString(),
    );
  }
}

class StorefrontSiteBuild {
  final String id;
  final String branchId;
  final String storefrontType;
  final int version;
  final String name;
  final String summary;
  final String status;
  final String compilerVersion;
  final String codeHash;
  final List<String> slots;
  final String? singleProductId;
  final bool securityPassed;
  final DateTime? updatedAt;

  const StorefrontSiteBuild({
    required this.id,
    required this.branchId,
    required this.storefrontType,
    required this.version,
    required this.name,
    required this.summary,
    required this.status,
    required this.compilerVersion,
    required this.codeHash,
    required this.slots,
    required this.singleProductId,
    required this.securityPassed,
    required this.updatedAt,
  });

  bool get isPublished => status == 'published';
  bool get isDraft => status == 'draft';

  factory StorefrontSiteBuild.fromJson(Map<String, dynamic> json) {
    final security = Map<String, dynamic>.from(
      json['security'] as Map? ?? const {},
    );
    return StorefrontSiteBuild(
      id: json['id']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? 'main_branch',
      storefrontType: json['storefrontType']?.toString() ?? 'retail',
      version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
      name: json['name']?.toString() ?? 'Piki generated storefront',
      summary: json['summary']?.toString() ?? '',
      status: json['status']?.toString() ?? 'draft',
      compilerVersion: json['compilerVersion']?.toString() ?? '',
      codeHash: json['codeHash']?.toString() ?? '',
      slots: (json['slots'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      singleProductId: json['singleProductId']?.toString(),
      securityPassed: security['passed'] == true,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

class StorefrontBuilderItem {
  final String id;
  final String name;
  final String? category;
  final String source;
  final Uri? imageUrl;

  const StorefrontBuilderItem({
    required this.id,
    required this.name,
    required this.category,
    required this.source,
    required this.imageUrl,
  });

  bool get isConnected => source == 'connected_store_api';

  factory StorefrontBuilderItem.fromJson(Map<String, dynamic> json) {
    return StorefrontBuilderItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled item',
      category: json['category']?.toString(),
      source: json['source']?.toString() ?? 'piki_pos',
      imageUrl: Uri.tryParse(json['imageUrl']?.toString() ?? ''),
    );
  }
}

class StorefrontPageService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 90),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<List<StorefrontPage>> list({
    required String branchId,
    required String storefrontType,
  }) async {
    final context = await _requestContext();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('catalog/pages'),
      queryParameters: {
        'deviceId': context.deviceId,
        'branchId': branchId,
        'storefrontType': storefrontType,
      },
      options: Options(headers: context.headers),
    );
    final data = _requireOk(response)['data'] as List? ?? const [];
    return data
        .whereType<Map>()
        .map((item) => StorefrontPage.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<List<StorefrontSiteBuild>> listSiteBuilds({
    required String branchId,
    required String storefrontType,
  }) async {
    final context = await _requestContext();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('catalog/site-builds'),
      queryParameters: {
        'deviceId': context.deviceId,
        'branchId': branchId,
        'storefrontType': storefrontType,
      },
      options: Options(headers: context.headers),
    );
    final data = _requireOk(response)['data'] as List? ?? const [];
    return data
        .whereType<Map>()
        .map(
          (item) =>
              StorefrontSiteBuild.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  static Future<List<StorefrontBuilderItem>> listSiteBuilderItems({
    required String branchId,
    required String storefrontType,
  }) async {
    final context = await _requestContext();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('catalog/site-builder/items'),
      queryParameters: {
        'deviceId': context.deviceId,
        'branchId': branchId,
        'storefrontType': storefrontType,
      },
      options: Options(headers: context.headers),
    );
    final data = _requireOk(response)['data'] as List? ?? const [];
    return data
        .whereType<Map>()
        .map(
          (item) =>
              StorefrontBuilderItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  static Future<StorefrontSiteBuild> createStarterSite({
    required String branchId,
    required String storefrontType,
  }) => _siteBuildWrite('POST', 'catalog/site-builds/starter', {
    'branchId': branchId,
    'storefrontType': storefrontType,
  }, 'create a generated storefront starter');

  static Future<StorefrontSiteBuild> publishSiteBuild(String buildId) =>
      _siteBuildWrite(
        'POST',
        'catalog/site-builds/$buildId/publish',
        const {},
        'publish generated storefront code',
      );

  static Future<Uri> siteBuildPreviewUrl(String buildId) async {
    final context = await _requestContext();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('catalog/site-builds/$buildId/preview'),
      queryParameters: {'deviceId': context.deviceId},
      options: Options(headers: context.headers),
    );
    final data = Map<String, dynamic>.from(
      _requireOk(response)['data'] as Map? ?? const {},
    );
    final uri = Uri.tryParse(data['url']?.toString() ?? '');
    if (uri == null || !uri.hasScheme) {
      throw Exception('The generated site preview is unavailable.');
    }
    return uri;
  }

  static Future<void> deleteSiteBuild(String buildId) async {
    await LicenseService.ensureWriteAccess(
      action: 'delete a generated storefront build',
    );
    final context = await _requestContext();
    final response = await _dio.delete<Map<String, dynamic>>(
      _url('catalog/site-builds/$buildId'),
      queryParameters: {'deviceId': context.deviceId},
      options: Options(headers: context.headers),
    );
    _requireOk(response);
  }

  static Future<StorefrontPage> create(Map<String, dynamic> data) =>
      _pageWrite('POST', 'catalog/pages', data, 'create a storefront page');

  static Future<StorefrontPage> update(
    String pageId,
    Map<String, dynamic> data,
  ) => _pageWrite(
    'PUT',
    'catalog/pages/$pageId',
    data,
    'update a storefront page',
  );

  static Future<StorefrontPage> publish(String pageId) => _pageWrite(
    'POST',
    'catalog/pages/$pageId/publish',
    const {},
    'publish a storefront page',
  );

  static Future<StorefrontPage> unpublish(String pageId) => _pageWrite(
    'POST',
    'catalog/pages/$pageId/unpublish',
    const {},
    'unpublish a storefront page',
  );

  static Future<StorefrontPage> designWithPiki(
    String pageId,
    String instruction,
  ) => _pageWrite(
    'POST',
    'catalog/pages/$pageId/piki-design',
    {'instruction': instruction},
    'design a storefront page with Piki',
  );

  static Future<Uri> previewUrl(String pageId) async {
    final context = await _requestContext();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('catalog/pages/$pageId/preview'),
      queryParameters: {'deviceId': context.deviceId},
      options: Options(headers: context.headers),
    );
    final data = Map<String, dynamic>.from(
      _requireOk(response)['data'] as Map? ?? const {},
    );
    final uri = Uri.tryParse(data['url']?.toString() ?? '');
    if (uri == null || !uri.hasScheme) {
      throw Exception('The exact page preview is unavailable.');
    }
    return uri;
  }

  static Future<void> delete(String pageId) async {
    await LicenseService.ensureWriteAccess(action: 'delete a storefront page');
    final context = await _requestContext();
    final response = await _dio.delete<Map<String, dynamic>>(
      _url('catalog/pages/$pageId'),
      queryParameters: {'deviceId': context.deviceId},
      options: Options(headers: context.headers),
    );
    _requireOk(response);
  }

  static Future<StorefrontConnection?> connection({
    String branchId = 'main_branch',
  }) async {
    final context = await _requestContext();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('catalog/connection'),
      queryParameters: {'deviceId': context.deviceId, 'branchId': branchId},
      options: Options(headers: context.headers),
    );
    final data = _requireOk(response)['data'];
    if (data is! Map) return null;
    return StorefrontConnection.fromJson(Map<String, dynamic>.from(data));
  }

  static Future<StorefrontConnection> saveConnection(
    Map<String, dynamic> data,
  ) async {
    await LicenseService.ensureWriteAccess(action: 'connect a store API');
    final context = await _requestContext();
    final response = await _dio.put<Map<String, dynamic>>(
      _url('catalog/connection'),
      data: {'deviceId': context.deviceId, ...data},
      options: Options(headers: context.headers),
    );
    return StorefrontConnection.fromJson(
      Map<String, dynamic>.from(
        _requireOk(response)['data'] as Map? ?? const {},
      ),
    );
  }

  static Future<String> testConnection({
    String branchId = 'main_branch',
  }) async {
    final context = await _requestContext();
    final response = await _dio.post<Map<String, dynamic>>(
      _url('catalog/connection/test'),
      data: {'deviceId': context.deviceId, 'branchId': branchId},
      options: Options(headers: context.headers),
    );
    final data = Map<String, dynamic>.from(
      _requireOk(response)['data'] as Map? ?? const {},
    );
    return data['message']?.toString() ?? 'Connection works.';
  }

  static Future<StorefrontPage> _pageWrite(
    String method,
    String path,
    Map<String, dynamic> data,
    String action,
  ) async {
    await LicenseService.ensureWriteAccess(action: action);
    final context = await _requestContext();
    final payload = {'deviceId': context.deviceId, ...data};
    final response = method == 'PUT'
        ? await _dio.put<Map<String, dynamic>>(
            _url(path),
            data: payload,
            options: Options(headers: context.headers),
          )
        : await _dio.post<Map<String, dynamic>>(
            _url(path),
            data: payload,
            options: Options(headers: context.headers),
          );
    return StorefrontPage.fromJson(
      Map<String, dynamic>.from(
        _requireOk(response)['data'] as Map? ?? const {},
      ),
    );
  }

  static Future<StorefrontSiteBuild> _siteBuildWrite(
    String method,
    String path,
    Map<String, dynamic> data,
    String action,
  ) async {
    await LicenseService.ensureWriteAccess(action: action);
    final context = await _requestContext();
    final payload = {'deviceId': context.deviceId, ...data};
    final response = method == 'PUT'
        ? await _dio.put<Map<String, dynamic>>(
            _url(path),
            data: payload,
            options: Options(headers: context.headers),
          )
        : await _dio.post<Map<String, dynamic>>(
            _url(path),
            data: payload,
            options: Options(headers: context.headers),
          );
    return StorefrontSiteBuild.fromJson(
      Map<String, dynamic>.from(
        _requireOk(response)['data'] as Map? ?? const {},
      ),
    );
  }

  static String _url(String path) {
    final base = SyncSettingsService.backendUrl.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    if (base.isEmpty) throw Exception('Cloud sync is not configured.');
    return '$base/$path';
  }

  static Future<_PageRequestContext> _requestContext() async {
    await LicenseService.init();
    final token = LicenseService.currentSnapshot.accessToken;
    if (token == null || token.trim().isEmpty) {
      throw Exception('Cloud storefront management is not activated.');
    }
    return _PageRequestContext(
      deviceId: await SyncSettingsService.getOrCreateDeviceId(),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  static Map<String, dynamic> _requireOk(
    Response<Map<String, dynamic>> response,
  ) {
    final body = response.data ?? const <String, dynamic>{};
    if ((response.statusCode ?? 500) >= 200 &&
        (response.statusCode ?? 500) < 300 &&
        body['ok'] == true) {
      return body;
    }
    throw Exception(
      body['message']?.toString() ??
          body['error']?.toString() ??
          'Storefront request failed.',
    );
  }
}

class _PageRequestContext {
  final String deviceId;
  final Map<String, String> headers;

  const _PageRequestContext({required this.deviceId, required this.headers});
}
