import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/spreadsheet_import_reader.dart';
import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_settings_service.dart';

class PikiAiJob {
  final String id;
  final String? branchId;
  final String jobType;
  final String status;
  final String? title;
  final String? sourceFileName;
  final int progress;
  final int totalSteps;
  final int completedSteps;
  final String? currentStep;
  final Map<String, dynamic>? result;
  final Map<String, dynamic>? payload;
  final String? errorMessage;
  final DateTime? createdAt;
  final DateTime? completedAt;

  const PikiAiJob({
    required this.id,
    required this.jobType,
    required this.status,
    required this.progress,
    required this.totalSteps,
    required this.completedSteps,
    this.branchId,
    this.title,
    this.sourceFileName,
    this.currentStep,
    this.result,
    this.payload,
    this.errorMessage,
    this.createdAt,
    this.completedAt,
  });

  bool get isRunning => status == 'queued' || status == 'running';
  bool get isWaitingForReview => status == 'waiting_for_review';
  bool get isFailed => status == 'failed';
  bool get isDone =>
      status == 'waiting_for_review' ||
      status == 'completed' ||
      status == 'failed' ||
      status == 'cancelled';

  factory PikiAiJob.fromJson(Map<String, dynamic> json) {
    return PikiAiJob(
      id: json['id']?.toString() ?? '',
      branchId: json['branchId']?.toString(),
      jobType: json['jobType']?.toString() ?? '',
      status: json['status']?.toString() ?? 'queued',
      title: json['title']?.toString(),
      sourceFileName: json['sourceFileName']?.toString(),
      progress: _readInt(json['progress']),
      totalSteps: _readInt(json['totalSteps']),
      completedSteps: _readInt(json['completedSteps']),
      currentStep: json['currentStep']?.toString(),
      result: json['result'] is Map
          ? Map<String, dynamic>.from(json['result'] as Map)
          : null,
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : null,
      errorMessage: json['errorMessage']?.toString(),
      createdAt: _readDate(json['createdAt']),
      completedAt: _readDate(json['completedAt']),
    );
  }
}

class PikiAiJobEvent {
  final String id;
  final String eventType;
  final String level;
  final String title;
  final String? message;
  final String? toolName;
  final String? entityType;
  final String? entityName;
  final int? progress;
  final DateTime? createdAt;

  const PikiAiJobEvent({
    required this.id,
    required this.eventType,
    required this.level,
    required this.title,
    this.message,
    this.toolName,
    this.entityType,
    this.entityName,
    this.progress,
    this.createdAt,
  });

  bool get isError => level == 'error';
  bool get isWarning => level == 'warning';

  factory PikiAiJobEvent.fromJson(Map<String, dynamic> json) {
    return PikiAiJobEvent(
      id: json['id']?.toString() ?? '',
      eventType: json['eventType']?.toString() ?? '',
      level: json['level']?.toString() ?? 'info',
      title: json['title']?.toString() ?? 'Piki activity',
      message: json['message']?.toString(),
      toolName: json['toolName']?.toString(),
      entityType: json['entityType']?.toString(),
      entityName: json['entityName']?.toString(),
      progress: json['progress'] == null ? null : _readInt(json['progress']),
      createdAt: _readDate(json['createdAt']),
    );
  }
}

class PikiImportDraftItem {
  final String id;
  final String status;
  final String? productName;
  final String? categoryName;
  final String? sku;
  final String? barcode;
  final double? costPrice;
  final double? sellingPrice;
  final double? stockQuantity;
  final String? imageUrl;
  final String? imageMatchStatus;
  final String? acceptedProductId;
  final String? sourceRowKey;
  final Map<String, dynamic> row;

  const PikiImportDraftItem({
    required this.id,
    required this.status,
    required this.row,
    this.productName,
    this.categoryName,
    this.sku,
    this.barcode,
    this.costPrice,
    this.sellingPrice,
    this.stockQuantity,
    this.imageUrl,
    this.imageMatchStatus,
    this.acceptedProductId,
    this.sourceRowKey,
  });

  factory PikiImportDraftItem.fromJson(Map<String, dynamic> json) {
    return PikiImportDraftItem(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'needs_review',
      productName: json['productName']?.toString(),
      categoryName: json['categoryName']?.toString(),
      sku: json['sku']?.toString(),
      barcode: json['barcode']?.toString(),
      costPrice: _readDouble(json['costPrice']),
      sellingPrice: _readDouble(json['sellingPrice']),
      stockQuantity: _readDouble(json['stockQuantity']),
      imageUrl: json['imageUrl']?.toString(),
      imageMatchStatus: json['imageMatchStatus']?.toString(),
      acceptedProductId: json['acceptedProductId']?.toString(),
      sourceRowKey: json['sourceRowKey']?.toString(),
      row: json['row'] is Map
          ? Map<String, dynamic>.from(json['row'] as Map)
          : const <String, dynamic>{},
    );
  }
}

class PikiAiJobUpdate {
  final PikiAiJob? job;
  final PikiAiJobEvent? event;

  const PikiAiJobUpdate.job(this.job) : event = null;
  const PikiAiJobUpdate.event(this.event) : job = null;
}

class PikiAiJobService {
  static const _timeout = Duration(seconds: 45);

  static Future<PikiAiJob> createStorefrontThemeJob(
    String themeId,
    String instruction, {
    bool fromScratch = false,
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured');
    }
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final response = await http
        .post(
          _buildUri(backendUrl, 'catalog/themes/$themeId/ai-jobs'),
          headers: {
            ..._authHeaders(license),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'deviceId': deviceId,
            'instruction': instruction.trim(),
            'mode': fromScratch ? 'build' : 'refine',
            'fromScratch': fromScratch,
          }),
        )
        .timeout(_timeout);
    final body = _decodeBody(response);
    if (response.statusCode != 202 ||
        body['ok'] != true ||
        body['job'] is! Map) {
      throw Exception(
        body['error']?.toString() ??
            'Piki could not start the storefront job (${response.statusCode}).',
      );
    }
    return PikiAiJob.fromJson(Map<String, dynamic>.from(body['job'] as Map));
  }

  static Future<PikiAiJob> createStorefrontPageJob(
    String pageId,
    String instruction,
  ) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) throw Exception('Cloud sync is not configured');
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final response = await http
        .post(
          _buildUri(backendUrl, 'catalog/pages/$pageId/ai-jobs'),
          headers: {
            ..._authHeaders(license),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'deviceId': deviceId,
            'instruction': instruction.trim(),
          }),
        )
        .timeout(_timeout);
    final body = _decodeBody(response);
    if (response.statusCode != 202 ||
        body['ok'] != true ||
        body['job'] is! Map) {
      throw Exception(
        body['error']?.toString() ??
            'Piki could not start the page design job (${response.statusCode}).',
      );
    }
    return PikiAiJob.fromJson(Map<String, dynamic>.from(body['job'] as Map));
  }

  static Future<PikiAiJob> createStorefrontSiteJob(
    String instruction, {
    String branchId = 'main_branch',
    String storefrontType = 'retail',
    String? parentBuildId,
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) throw Exception('Cloud sync is not configured');
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final response = await http
        .post(
          _buildUri(backendUrl, 'catalog/site-builds/ai-jobs'),
          headers: {
            ..._authHeaders(license),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'deviceId': deviceId,
            'instruction': instruction.trim(),
            'branchId': branchId,
            'storefrontType': storefrontType,
            if (parentBuildId?.trim().isNotEmpty == true)
              'parentBuildId': parentBuildId!.trim(),
          }),
        )
        .timeout(_timeout);
    final body = _decodeBody(response);
    if (response.statusCode != 202 ||
        body['ok'] != true ||
        body['job'] is! Map) {
      throw Exception(
        body['error']?.toString() ??
            'Piki could not start the site compiler (${response.statusCode}).',
      );
    }
    return PikiAiJob.fromJson(Map<String, dynamic>.from(body['job'] as Map));
  }

  static Future<PikiAiJob> createMarketingContentJob(
    String instruction, {
    String branchId = 'main_branch',
    String storefrontType = 'retail',
    List<String> productIds = const [],
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) throw Exception('Cloud sync is not configured');
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final response = await http
        .post(
          _buildUri(backendUrl, 'catalog/marketing/ai-jobs'),
          headers: {
            ..._authHeaders(license),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'deviceId': deviceId,
            'instruction': instruction.trim(),
            'branchId': branchId,
            'storefrontType': storefrontType,
            'productIds': productIds,
          }),
        )
        .timeout(_timeout);
    final body = _decodeBody(response);
    if (response.statusCode != 202 ||
        body['ok'] != true ||
        body['job'] is! Map) {
      throw Exception(
        body['error']?.toString() ??
            'Piki could not start the marketing job (${response.statusCode}).',
      );
    }
    return PikiAiJob.fromJson(Map<String, dynamic>.from(body['job'] as Map));
  }

  static Future<PikiAiJob> createProductImportJob(
    SpreadsheetFileRows file, {
    String? branchId,
    String? instruction,
  }) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Could not read the selected file.');
    }
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured');
    }
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final response = await http
        .post(
          _buildUri(backendUrl, 'ai/imports'),
          headers: {
            ..._authHeaders(license),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'deviceId': deviceId,
            'importType': 'products',
            if (branchId != null && branchId.trim().isNotEmpty)
              'branchId': branchId.trim(),
            if (instruction != null && instruction.trim().isNotEmpty)
              'instruction': instruction.trim(),
            'fileName': file.fileName,
            'mimeType': file.mimeType,
            'extension': file.extension,
            'sourceText': file.extractedText,
            'fileBase64': base64Encode(bytes),
          }),
        )
        .timeout(_timeout);
    final body = _decodeBody(response);
    if (response.statusCode != 202 || body['ok'] != true) {
      throw Exception(
        body['error']?.toString() ??
            'Piki could not start the import job (${response.statusCode}).',
      );
    }
    return PikiAiJob.fromJson(Map<String, dynamic>.from(body['job'] as Map));
  }

  static Future<List<PikiAiJob>> listActiveJobs() async {
    final body = await _getJson('ai/jobs', {'status': 'active'});
    final jobs = body['jobs'];
    if (jobs is! List) return const [];
    return jobs
        .whereType<Map>()
        .map((item) => PikiAiJob.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<List<PikiAiJob>> listStorefrontThemeJobs() async {
    final body = await _getJson('ai/jobs', {
      'status': 'queued,running,completed,failed',
      'jobType': 'storefront_theme',
      'limit': '20',
    });
    final jobs = body['jobs'];
    if (jobs is! List) return const [];
    return jobs
        .whereType<Map>()
        .map((item) => PikiAiJob.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<List<PikiAiJob>> listStorefrontSiteJobs() async {
    final body = await _getJson('ai/jobs', {
      'status': 'queued,running,completed,failed',
      'jobType': 'storefront_site',
      'limit': '20',
    });
    final jobs = body['jobs'];
    if (jobs is! List) return const [];
    return jobs
        .whereType<Map>()
        .map((item) => PikiAiJob.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<List<PikiAiJob>> listMarketingContentJobs() async {
    final body = await _getJson('ai/jobs', {
      'status': 'queued,running,completed,failed',
      'jobType': 'marketing_content',
      'limit': '20',
    });
    final jobs = body['jobs'];
    if (jobs is! List) return const [];
    return jobs
        .whereType<Map>()
        .map((item) => PikiAiJob.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<PikiAiJob> getJob(String jobId) async {
    final body = await _getJson('ai/jobs/$jobId');
    return PikiAiJob.fromJson(Map<String, dynamic>.from(body['job'] as Map));
  }

  static Future<List<PikiAiJobEvent>> getEvents(String jobId) async {
    final body = await _getJson('ai/jobs/$jobId/events');
    final events = body['events'];
    if (events is! List) return const [];
    return events
        .whereType<Map>()
        .map((item) => PikiAiJobEvent.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<List<PikiImportDraftItem>> getDraftItems(String jobId) async {
    final body = await _getJson('ai/imports/$jobId/draft-items');
    final items = body['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              PikiImportDraftItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  static Future<PikiAiJob> markImportCompleted(
    String jobId, {
    required int created,
    required int updated,
    required int stockBatches,
    required int skipped,
  }) async {
    final body = await _postJson('ai/imports/$jobId/confirm', {
      'created': created,
      'updated': updated,
      'stockBatches': stockBatches,
      'skipped': skipped,
    });
    return PikiAiJob.fromJson(Map<String, dynamic>.from(body['job'] as Map));
  }

  static Future<PikiAiJob> cancelJob(String jobId) async {
    final body = await _postJson('ai/jobs/$jobId/cancel', const {});
    return PikiAiJob.fromJson(Map<String, dynamic>.from(body['job'] as Map));
  }

  static Future<PikiAiJob> retryImportJob(String jobId) async {
    final body = await _postJson('ai/imports/$jobId/retry', const {});
    return PikiAiJob.fromJson(Map<String, dynamic>.from(body['job'] as Map));
  }

  static Future<PikiAiJob> retryJob(String jobId) async {
    final body = await _postJson('ai/jobs/$jobId/retry', const {});
    return PikiAiJob.fromJson(Map<String, dynamic>.from(body['job'] as Map));
  }

  static Future<PikiAiJob> waitForCompletion(
    String jobId, {
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final job = await getJob(jobId);
      if (job.isDone) return job;
      if (DateTime.now().isAfter(deadline)) {
        throw Exception(
          'Piki is still working in the background. Open Online Store to see its progress.',
        );
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  static Stream<PikiAiJobUpdate> streamJob(String jobId) async* {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured');
    }
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final client = http.Client();
    try {
      final request = http.Request(
        'GET',
        _buildUri(backendUrl, 'ai/jobs/$jobId/events/stream', {
          'deviceId': deviceId,
        }),
      );
      request.headers.addAll(_authHeaders(license));
      final response = await client.send(request).timeout(_timeout);
      if (response.statusCode != 200) {
        throw Exception(
          'Piki activity stream failed (${response.statusCode}).',
        );
      }

      final data = StringBuffer();
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.isEmpty) {
          final update = _parseSseData(data.toString());
          data.clear();
          if (update != null) {
            yield update;
          }
          continue;
        }
        if (line.startsWith('data:')) {
          data.writeln(line.substring(5).trimLeft());
        }
      }
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured');
    }
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final response = await http
        .post(
          _buildUri(backendUrl, path),
          headers: {
            ..._authHeaders(license),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'deviceId': deviceId, ...payload}),
        )
        .timeout(_timeout);
    final body = _decodeBody(response);
    if (response.statusCode != 200 || body['ok'] != true) {
      throw Exception(
        body['error']?.toString() ??
            'Piki job request failed (${response.statusCode}).',
      );
    }
    return body;
  }

  static Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured');
    }
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureAccess(backendUrl, deviceId);
    final response = await http
        .get(
          _buildUri(backendUrl, path, {'deviceId': deviceId, ...?query}),
          headers: _authHeaders(license),
        )
        .timeout(_timeout);
    final body = _decodeBody(response);
    if (response.statusCode != 200 || body['ok'] != true) {
      throw Exception(
        body['error']?.toString() ??
            'Piki job request failed (${response.statusCode}).',
      );
    }
    return body;
  }

  static PikiAiJobUpdate? _parseSseData(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final payload = Map<String, dynamic>.from(decoded);
      if (payload['type'] == 'job' && payload['job'] is Map) {
        return PikiAiJobUpdate.job(
          PikiAiJob.fromJson(Map<String, dynamic>.from(payload['job'] as Map)),
        );
      }
      if (payload['type'] == 'event' && payload['event'] is Map) {
        return PikiAiJobUpdate.event(
          PikiAiJobEvent.fromJson(
            Map<String, dynamic>.from(payload['event'] as Map),
          ),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Map<String, dynamic> _decodeBody(http.Response response) {
    return decodePikiCloudJsonResponse(response);
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
    if (!snapshot.allowsFeature('agent')) {
      throw Exception(
        'Your current subscription plan does not include Piki AI.',
      );
    }
    return snapshot;
  }

  static Map<String, String> _authHeaders(LicenseSnapshot snapshot) {
    final accessToken = snapshot.accessToken;
    if (accessToken == null || accessToken.trim().isEmpty) {
      return const <String, String>{};
    }
    return {'Authorization': 'Bearer $accessToken'};
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
}

Map<String, dynamic> decodePikiCloudJsonResponse(http.Response response) {
  final text = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
  if (text.isEmpty) return const {};
  try {
    final decoded = jsonDecode(text);
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : const <String, dynamic>{};
  } on FormatException {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final looksLikeHtml =
        contentType.contains('text/html') ||
        text.startsWith('<!DOCTYPE') ||
        text.startsWith('<html');
    if (looksLikeHtml) {
      throw Exception(
        response.statusCode == 404
            ? 'This Piki Cloud feature is not available on the current server deployment. Please redeploy the backend and try again.'
            : 'Piki Cloud returned a website page instead of API data. Please check the backend routing and try again.',
      );
    }
    throw Exception(
      'Piki Cloud returned invalid data (${response.statusCode}). Please try again.',
    );
  }
}

int _readInt(Object? value) {
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _readDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? _readDate(Object? value) {
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) return null;
  return DateTime.tryParse(text)?.toLocal();
}
