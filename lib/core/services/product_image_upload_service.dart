import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'database_service.dart';
import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_settings_service.dart';

class ProductImageUploadService {
  static const _timeout = Duration(seconds: 90);
  static const _maxClientImageBytes = 5 * 1024 * 1024;

  static bool isRemoteImage(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return false;
    final uri = Uri.tryParse(text);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static Future<String> uploadProductImage({
    required String imagePath,
    String? productId,
    String? productName,
  }) async {
    final cleanPath = imagePath.trim();
    if (cleanPath.isEmpty) {
      throw Exception('Choose a product image first.');
    }
    if (isRemoteImage(cleanPath)) {
      return cleanPath;
    }

    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured.');
    }
    if (!SessionService.canAccessFeature(UserAccessProfile.featureProducts)) {
      throw Exception('Your account cannot upload product images.');
    }

    final imageDataUrl = await _fileToImageDataUrl(cleanPath);
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final client = http.Client();

    try {
      final response = await client
          .post(
            _buildUri(backendUrl, 'files/product-images'),
            headers: {
              ..._authHeaders(license),
              HttpHeaders.contentTypeHeader: 'application/json',
            },
            body: jsonEncode({
              'deviceId': deviceId,
              'branchId': DatabaseService.currentBranchId,
              'imageDataUrl': imageDataUrl,
              if (productId != null && productId.trim().isNotEmpty)
                'productId': productId.trim(),
              if (productName != null && productName.trim().isNotEmpty)
                'productName': productName.trim(),
            }),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);
      if (response.statusCode != 201 || body['ok'] != true) {
        throw Exception(
          body['error'] as String? ??
              'Product image upload failed (${response.statusCode}).',
        );
      }

      final data = body['data'] as Map?;
      final imageUrl = data?['imageUrl'] as String?;
      if (imageUrl == null || imageUrl.trim().isEmpty) {
        throw Exception('Product image upload did not return a public URL.');
      }
      return imageUrl.trim();
    } finally {
      client.close();
    }
  }

  static Future<String> _fileToImageDataUrl(String path) async {
    final file = path.startsWith('file:')
        ? File.fromUri(Uri.parse(path))
        : File(path);
    if (!await file.exists()) {
      throw Exception('Product image file was not found.');
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Product image file is empty.');
    }
    if (bytes.length > _maxClientImageBytes) {
      throw Exception('Use a product image below 5 MB.');
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

  static Future<LicenseSnapshot> _ensureAccess(
    String backendUrl,
    String deviceId,
  ) async {
    final snapshot = await LicenseService.ensureOnlineLicense(
      backendUrl: backendUrl,
      deviceId: deviceId,
      businessName: ShopSettings.shopName,
      ownerName: SessionService.currentUserName,
      ownerEmail: SessionService.currentUserEmail,
    );
    if (!snapshot.hasBinding || snapshot.accessToken == null) {
      throw Exception('Cloud subscription not activated.');
    }
    if (!snapshot.allowsFeature('products')) {
      throw Exception(
        'Your current subscription plan does not include products.',
      );
    }
    return snapshot;
  }

  static Map<String, String> _authHeaders(LicenseSnapshot snapshot) {
    final accessToken = snapshot.accessToken;
    if (accessToken == null || accessToken.trim().isEmpty) {
      return const <String, String>{};
    }
    return {HttpHeaders.authorizationHeader: 'Bearer $accessToken'};
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

  static Uri _buildUri(String backendUrl, String path) {
    return Uri.parse('$backendUrl/$path');
  }
}
