import 'package:dio/dio.dart';

import 'license_service.dart';
import 'sync_settings_service.dart';

class StorefrontCampaign {
  final String id;
  final String branchId;
  final String storefrontType;
  final String name;
  final String slug;
  final String eyebrow;
  final String title;
  final String description;
  final String badgeLabel;
  final String buttonLabel;
  final String? heroImageUrl;
  final List<String> productIds;
  final List<String> highlights;
  final String status;
  final Uri? url;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? updatedAt;

  const StorefrontCampaign({
    required this.id,
    required this.branchId,
    required this.storefrontType,
    required this.name,
    required this.slug,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.badgeLabel,
    required this.buttonLabel,
    required this.heroImageUrl,
    required this.productIds,
    required this.highlights,
    required this.status,
    required this.url,
    required this.startsAt,
    required this.endsAt,
    required this.updatedAt,
  });

  bool get isPublished => status == 'published';

  factory StorefrontCampaign.fromJson(Map<String, dynamic> json) {
    return StorefrontCampaign(
      id: json['id']?.toString() ?? '',
      branchId: json['branchId']?.toString() ?? 'main_branch',
      storefrontType: json['storefrontType']?.toString() ?? 'retail',
      name: json['name']?.toString() ?? 'Campaign',
      slug: json['slug']?.toString() ?? '',
      eyebrow: json['eyebrow']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      badgeLabel: json['badgeLabel']?.toString() ?? '',
      buttonLabel: json['buttonLabel']?.toString() ?? 'Shop the campaign',
      heroImageUrl: _optionalText(json['heroImageUrl']),
      productIds: (json['productIds'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      highlights: (json['highlights'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
      status: json['status']?.toString() ?? 'draft',
      url: Uri.tryParse(json['url']?.toString() ?? ''),
      startsAt: DateTime.tryParse(json['startsAt']?.toString() ?? ''),
      endsAt: DateTime.tryParse(json['endsAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  static String? _optionalText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class StorefrontLaunchStep {
  final String id;
  final String label;
  final bool ready;
  final String detail;

  const StorefrontLaunchStep({
    required this.id,
    required this.label,
    required this.ready,
    required this.detail,
  });

  factory StorefrontLaunchStep.fromJson(Map<String, dynamic> json) {
    return StorefrontLaunchStep(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      ready: json['ready'] == true,
      detail: json['detail']?.toString() ?? '',
    );
  }
}

class StorefrontLaunchReadiness {
  final int readyCount;
  final int totalCount;
  final List<StorefrontLaunchStep> steps;

  const StorefrontLaunchReadiness({
    required this.readyCount,
    required this.totalCount,
    required this.steps,
  });

  factory StorefrontLaunchReadiness.fromJson(Map<String, dynamic> json) {
    return StorefrontLaunchReadiness(
      readyCount: (json['readyCount'] as num?)?.toInt() ?? 0,
      totalCount: (json['totalCount'] as num?)?.toInt() ?? 0,
      steps: (json['steps'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                StorefrontLaunchStep.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
    );
  }
}

class StorefrontCampaignService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  static Future<List<StorefrontCampaign>> list({
    String branchId = 'main_branch',
    String storefrontType = 'retail',
  }) async {
    final result = await _request(
      'GET',
      'catalog/campaigns',
      query: {'branchId': branchId, 'storefrontType': storefrontType},
    );
    return (result['data'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              StorefrontCampaign.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  static Future<StorefrontCampaign> create(Map<String, dynamic> data) async {
    await LicenseService.ensureWriteAccess(action: 'create a campaign page');
    return _write('POST', 'catalog/campaigns', data);
  }

  static Future<StorefrontCampaign> update(
    String campaignId,
    Map<String, dynamic> data,
  ) async {
    await LicenseService.ensureWriteAccess(action: 'update a campaign page');
    return _write('PUT', 'catalog/campaigns/$campaignId', data);
  }

  static Future<StorefrontCampaign> publish(String campaignId) async {
    await LicenseService.ensureWriteAccess(action: 'publish a campaign page');
    return _write('POST', 'catalog/campaigns/$campaignId/publish', const {});
  }

  static Future<StorefrontCampaign> unpublish(String campaignId) async {
    await LicenseService.ensureWriteAccess(action: 'unpublish a campaign page');
    return _write('POST', 'catalog/campaigns/$campaignId/unpublish', const {});
  }

  static Future<void> delete(String campaignId) async {
    await LicenseService.ensureWriteAccess(action: 'delete a campaign page');
    await _request('DELETE', 'catalog/campaigns/$campaignId');
  }

  static Future<StorefrontLaunchReadiness> readiness({
    String branchId = 'main_branch',
    String storefrontType = 'retail',
  }) async {
    final result = await _request(
      'GET',
      'catalog/readiness',
      query: {'branchId': branchId, 'storefrontType': storefrontType},
    );
    return StorefrontLaunchReadiness.fromJson(
      Map<String, dynamic>.from(result['data'] as Map? ?? const {}),
    );
  }

  static Future<StorefrontCampaign> _write(
    String method,
    String path,
    Map<String, dynamic> data,
  ) async {
    final result = await _request(method, path, data: data);
    return StorefrontCampaign.fromJson(
      Map<String, dynamic>.from(result['data'] as Map? ?? const {}),
    );
  }

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    await LicenseService.init();
    final token = LicenseService.currentSnapshot.accessToken;
    if (token == null || token.trim().isEmpty) {
      throw Exception('Cloud storefront management is not activated.');
    }
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final base = SyncSettingsService.backendUrl.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    if (base.isEmpty) throw Exception('Cloud sync is not configured.');
    final payload = {'deviceId': deviceId, ...?data};
    final queryParameters = {'deviceId': deviceId, ...?query};
    late final Response<Map<String, dynamic>> response;
    final options = Options(headers: {'Authorization': 'Bearer $token'});
    switch (method) {
      case 'POST':
        response = await _dio.post<Map<String, dynamic>>(
          '$base/$path',
          data: payload,
          queryParameters: queryParameters,
          options: options,
        );
      case 'PUT':
        response = await _dio.put<Map<String, dynamic>>(
          '$base/$path',
          data: payload,
          queryParameters: queryParameters,
          options: options,
        );
      case 'DELETE':
        response = await _dio.delete<Map<String, dynamic>>(
          '$base/$path',
          data: payload,
          queryParameters: queryParameters,
          options: options,
        );
      default:
        response = await _dio.get<Map<String, dynamic>>(
          '$base/$path',
          queryParameters: queryParameters,
          options: options,
        );
    }
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
          'Storefront request failed.',
    );
  }
}
