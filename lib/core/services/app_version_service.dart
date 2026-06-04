import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import 'sync_settings_service.dart';

class AppVersionInfo {
  final String latestVersion;
  final String minimumVersion;
  final String apkUrl;
  final String releaseNotes;

  const AppVersionInfo({
    required this.latestVersion,
    required this.minimumVersion,
    required this.apkUrl,
    required this.releaseNotes,
  });

  factory AppVersionInfo.fromJson(Map<String, dynamic> json) {
    return AppVersionInfo(
      latestVersion: json['latestVersion']?.toString() ?? '',
      minimumVersion: json['minimumVersion']?.toString() ?? '',
      apkUrl: json['apkUrl']?.toString() ?? '',
      releaseNotes: json['releaseNotes']?.toString() ?? '',
    );
  }

  bool get hasRelease =>
      latestVersion.trim().isNotEmpty && apkUrl.trim().isNotEmpty;

  bool get hasUpdate =>
      hasRelease && latestVersion.trim() != AppConstants.appVersion;
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
    final response = await _dio.get<Map<String, dynamic>>(_url('app/version'));
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
}
