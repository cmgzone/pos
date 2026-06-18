import 'dart:io';

import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import 'sync_settings_service.dart';

class AppVersionInfo {
  final String platform;
  final String latestVersion;
  final String minimumVersion;
  final String apkUrl;
  final String downloadUrl;
  final String androidUrl;
  final String windowsUrl;
  final String releaseNotes;

  const AppVersionInfo({
    required this.platform,
    required this.latestVersion,
    required this.minimumVersion,
    required this.apkUrl,
    required this.downloadUrl,
    required this.androidUrl,
    required this.windowsUrl,
    required this.releaseNotes,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      platform: json['platform']?.toString() ?? '',
      latestVersion: json['latestVersion']?.toString() ?? '',
      minimumVersion: json['minimumVersion']?.toString() ?? '',
      apkUrl: json['apkUrl']?.toString() ?? '',
      downloadUrl:
          json['downloadUrl']?.toString() ?? json['apkUrl']?.toString() ?? '',
      androidUrl: json['androidUrl']?.toString() ?? '',
      windowsUrl: json['windowsUrl']?.toString() ?? '',
      releaseNotes: json['releaseNotes']?.toString() ?? '',
    );
  }

  bool get hasRelease =>
      latestVersion.trim().isNotEmpty && resolvedDownloadUrl.trim().isNotEmpty;

  bool get hasUpdate =>
      hasRelease &&
      AppVersionService.compareVersions(
            AppConstants.appVersion,
            latestVersion.trim(),
          ) <
          0;

  bool get isRequiredUpdate {
    final minimum = minimumVersion.trim();
    return minimum.isNotEmpty &&
        AppVersionService.compareVersions(AppConstants.appVersion, minimum) < 0;
  }

  String get resolvedDownloadUrl {
    if (downloadUrl.trim().isNotEmpty) return downloadUrl.trim();
    if (platform == 'android' && androidUrl.trim().isNotEmpty) {
      return androidUrl.trim();
    }
    if (platform == 'windows' && windowsUrl.trim().isNotEmpty) {
      return windowsUrl.trim();
    }
    return apkUrl.trim();
  }

  Uri? get downloadUri {
    final value = resolvedDownloadUrl;
    if (value.isEmpty) return null;
    final parsed = Uri.tryParse(value);
    if (parsed == null) return null;
    if (parsed.hasScheme) return parsed;
    if (!value.startsWith('/')) return null;
    final origin = AppVersionService.backendOrigin;
    if (origin.isEmpty) return null;
    return Uri.tryParse('$origin$value');
  }
}

class AppVersionService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );

  static Future<AppVersionInfo?> fetch() async {
    await SyncSettingsService.init();
    final response = await _dio.get<Map<String, dynamic>>(
      _url('app/version'),
      queryParameters: {'platform': currentPlatform},
    );
    final body = response.data ?? const <String, dynamic>{};
    if (body['ok'] != true || body['data'] is! Map<String, dynamic>) {
      return null;
    }
    return AppVersionInfo.fromJson(body['data'] as Map<String, dynamic>);
  }

  static String _url(String path) {
    final base = SyncSettingsService.backendUrl.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    return '$base/$path';
  }

  static String get currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return 'windows';
  }

  static String get backendOrigin {
    final base = SyncSettingsService.backendUrl.replaceFirst(
      RegExp(r'/+$'),
      '',
    );
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasScheme) return '';
    return uri
        .replace(path: '', query: null, fragment: null)
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }

  static int compareVersions(String current, String target) {
    final currentParts = _versionParts(current);
    final targetParts = _versionParts(target);
    final maxLength = currentParts.length > targetParts.length
        ? currentParts.length
        : targetParts.length;
    for (var index = 0; index < maxLength; index += 1) {
      final left = index < currentParts.length ? currentParts[index] : 0;
      final right = index < targetParts.length ? targetParts[index] : 0;
      if (left != right) return left.compareTo(right);
    }
    return 0;
  }

  static List<int> _versionParts(String value) {
    return RegExp(r'\d+')
        .allMatches(value)
        .map((match) => int.tryParse(match.group(0) ?? '') ?? 0)
        .toList(growable: false);
  }
}
