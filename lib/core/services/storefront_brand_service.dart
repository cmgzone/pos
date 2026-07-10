import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_settings_service.dart';

class StorefrontBrandSettings {
  final String businessId;
  final String businessName;
  final String branchId;
  final String logoUrl;
  final String coverUrl;
  final List<String> coverUrls;
  final String primaryColor;
  final String tagline;
  final String description;
  final DateTime? updatedAt;

  const StorefrontBrandSettings({
    required this.businessId,
    required this.businessName,
    this.branchId = 'main_branch',
    required this.logoUrl,
    required this.coverUrl,
    required this.coverUrls,
    required this.primaryColor,
    required this.tagline,
    required this.description,
    required this.updatedAt,
  });

  factory StorefrontBrandSettings.empty({String branchId = 'main_branch'}) {
    return StorefrontBrandSettings(
      businessId: '',
      businessName: ShopSettings.shopName,
      branchId: branchId,
      logoUrl: '',
      coverUrl: '',
      coverUrls: const [],
      primaryColor: '#ff2a6d',
      tagline: 'Online catalog',
      description:
          'Shop products, choose variants, and send your order directly to the store. The team will confirm availability and payment before fulfillment.',
      updatedAt: null,
    );
  }

  factory StorefrontBrandSettings.fromJson(Map<String, dynamic> json) {
    final coverUrl = json['coverUrl']?.toString() ?? '';
    final coverUrls = _readCoverUrls(json, coverUrl);
    return StorefrontBrandSettings(
      businessId: json['businessId']?.toString() ?? '',
      businessName: json['businessName']?.toString() ?? ShopSettings.shopName,
      branchId: json['branchId']?.toString() ?? 'main_branch',
      logoUrl: json['logoUrl']?.toString() ?? '',
      coverUrl: coverUrls.isNotEmpty ? coverUrls.first : coverUrl,
      coverUrls: coverUrls,
      primaryColor: json['primaryColor']?.toString() ?? '#ff2a6d',
      tagline: json['tagline']?.toString() ?? 'Online catalog',
      description:
          json['description']?.toString() ??
          StorefrontBrandSettings.empty().description,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'branchId': branchId,
      'name': businessName.trim(),
      'logoUrl': logoUrl.trim(),
      'coverUrl': coverUrls.isNotEmpty
          ? coverUrls.first.trim()
          : coverUrl.trim(),
      'coverUrls': coverUrls
          .map((url) => url.trim())
          .where((url) => url.isNotEmpty)
          .toList(),
      'primaryColor': primaryColor.trim(),
      'tagline': tagline.trim(),
      'description': description.trim(),
    };
  }

  static List<String> _readCoverUrls(
    Map<String, dynamic> json,
    String coverUrl,
  ) {
    final raw = json['coverUrls'] ?? json['cover_urls'];
    final urls = <String>[];
    if (raw is List) {
      urls.addAll(raw.map((value) => value.toString()));
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          urls.addAll(decoded.map((value) => value.toString()));
        } else {
          urls.add(raw);
        }
      } catch (_) {
        urls.add(raw);
      }
    }
    if (urls.isEmpty && coverUrl.trim().isNotEmpty) {
      urls.add(coverUrl);
    }
    final seen = <String>{};
    return urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty && seen.add(url))
        .take(8)
        .toList();
  }
}

class StorefrontBrandService {
  static const _timeout = Duration(seconds: 90);
  static const _maxClientImageBytes = 5 * 1024 * 1024;

  static Future<StorefrontBrandSettings> fetchSettings({
    String? branchId,
  }) async {
    final access = await _businessAccess();
    final client = http.Client();
    try {
      final query = {
        'deviceId': access.deviceId,
        if (branchId != null && branchId.trim().isNotEmpty)
          'branchId': branchId.trim(),
      };
      final response = await client
          .get(
            _buildUri(access.backendUrl, 'catalog/brand', query),
            headers: _authHeaders(access.license),
          )
          .timeout(_timeout);
      final body = _decodeJson(response);
      _throwIfFailed(response, body, 'Could not load storefront settings.');
      final data = body['data'];
      if (data is Map) {
        final settings =
            StorefrontBrandSettings.fromJson(Map<String, dynamic>.from(data));
        return settings;
      }
      return StorefrontBrandSettings.empty(
        branchId: branchId ?? 'main_branch',
      );
    } finally {
      client.close();
    }
  }

  static Future<StorefrontBrandSettings> saveSettings(
    StorefrontBrandSettings settings,
  ) async {
    await LicenseService.ensureWriteAccess(action: 'save storefront settings');
    final access = await _businessAccess();
    final client = http.Client();
    try {
      final query = {
        'deviceId': access.deviceId,
        if (settings.branchId.trim().isNotEmpty)
          'branchId': settings.branchId.trim(),
      };
      final response = await client
          .put(
            _buildUri(access.backendUrl, 'catalog/brand', query),
            headers: {
              ..._authHeaders(access.license),
              HttpHeaders.contentTypeHeader: 'application/json',
            },
            body: jsonEncode(settings.toJson()),
          )
          .timeout(_timeout);
      final body = _decodeJson(response);
      _throwIfFailed(response, body, 'Could not save storefront settings.');
      final data = body['data'];
      return data is Map
          ? StorefrontBrandSettings.fromJson(Map<String, dynamic>.from(data))
          : settings;
    } finally {
      client.close();
    }
  }

  static Future<String> uploadImage({
    required String imagePath,
    required String kind,
  }) async {
    final cleanPath = imagePath.trim();
    if (cleanPath.isEmpty) {
      throw Exception('Choose an image first.');
    }

    final imageDataUrl = await _fileToImageDataUrl(cleanPath);
    final access = await _businessAccess();
    final client = http.Client();
    try {
      final response = await client
          .post(
            _buildUri(access.backendUrl, 'files/storefront-images'),
            headers: {
              ..._authHeaders(access.license),
              HttpHeaders.contentTypeHeader: 'application/json',
            },
            body: jsonEncode({
              'deviceId': access.deviceId,
              'kind': kind,
              'imageDataUrl': imageDataUrl,
            }),
          )
          .timeout(_timeout);
      final body = _decodeJson(response);
      _throwIfFailed(response, body, 'Could not upload storefront image.');
      final data = body['data'];
      final imageUrl = data is Map ? data['imageUrl']?.toString() : null;
      if (imageUrl == null || imageUrl.trim().isEmpty) {
        throw Exception('Image upload did not return a public URL.');
      }
      return imageUrl.trim();
    } finally {
      client.close();
    }
  }

  static Future<_StorefrontAccess> _businessAccess() async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured.');
    }
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await LicenseService.ensureOnlineLicense(
      backendUrl: backendUrl,
      deviceId: deviceId,
      businessName: ShopSettings.shopName,
      ownerName: SessionService.currentUserName,
      ownerEmail: SessionService.currentUserEmail,
    );
    if (!license.hasBinding || license.accessToken == null) {
      throw Exception('Cloud subscription not activated.');
    }
    return _StorefrontAccess(
      backendUrl: backendUrl,
      deviceId: deviceId,
      license: license,
    );
  }

  static Future<String> _fileToImageDataUrl(String path) async {
    final file = path.startsWith('file:')
        ? File.fromUri(Uri.parse(path))
        : File(path);
    if (!await file.exists()) {
      throw Exception('Image file was not found.');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Image file is empty.');
    }
    if (bytes.length > _maxClientImageBytes) {
      throw Exception('Use an image below 5 MB.');
    }

    final mimeType = _mimeTypeForPath(path);
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  static String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  static Map<String, String> _authHeaders(LicenseSnapshot snapshot) {
    final accessToken = snapshot.accessToken;
    if (accessToken == null || accessToken.trim().isEmpty) {
      return const <String, String>{};
    }
    return {HttpHeaders.authorizationHeader: 'Bearer $accessToken'};
  }

  static Uri _buildUri(
    String backendUrl,
    String path, [
    Map<String, String>? queryParameters,
  ]) {
    return Uri.parse(
      '$backendUrl/$path',
    ).replace(queryParameters: queryParameters);
  }

  static Map<String, dynamic> _decodeJson(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const <String, dynamic>{};
    }
    return const <String, dynamic>{};
  }

  static void _throwIfFailed(
    http.Response response,
    Map<String, dynamic> body,
    String fallback,
  ) {
    final ok =
        response.statusCode >= 200 &&
        response.statusCode < 300 &&
        body['ok'] == true;
    if (ok) return;
    throw Exception(body['error']?.toString() ?? fallback);
  }
}

class _StorefrontAccess {
  final String backendUrl;
  final String deviceId;
  final LicenseSnapshot license;

  const _StorefrontAccess({
    required this.backendUrl,
    required this.deviceId,
    required this.license,
  });
}
