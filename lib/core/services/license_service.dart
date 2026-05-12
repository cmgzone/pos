import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

enum LicenseAccessStatus { localOnly, active, grace, expired, invalid }

enum SubscriptionLimit { branches, employees, aiAgents }

class SubscriptionEntitlements {
  final List<String> features;
  final int maxBranches;
  final int maxEmployees;
  final int maxAiAgents;
  final Map<String, int> aiRateLimits;

  const SubscriptionEntitlements({
    required this.features,
    required this.maxBranches,
    required this.maxEmployees,
    required this.maxAiAgents,
    required this.aiRateLimits,
  });

  const SubscriptionEntitlements.empty()
    : features = const [],
      maxBranches = 0,
      maxEmployees = 0,
      maxAiAgents = 0,
      aiRateLimits = const {};

  factory SubscriptionEntitlements.fromJson(Object? value) {
    if (value is! Map) {
      return const SubscriptionEntitlements.empty();
    }
    final rawFeatures = value['features'];
    final features = <String>[];
    if (rawFeatures is List) {
      for (final feature in rawFeatures) {
        final clean = feature?.toString().trim() ?? '';
        if (clean.isNotEmpty && !features.contains(clean)) {
          features.add(clean);
        }
      }
    }
    final rawRates = value['aiRateLimits'];
    final rates = <String, int>{};
    if (rawRates is Map) {
      for (final entry in rawRates.entries) {
        rates[entry.key.toString()] = _readInt(entry.value);
      }
    }
    return SubscriptionEntitlements(
      features: features,
      maxBranches: _readInt(value['maxBranches']),
      maxEmployees: _readInt(value['maxEmployees']),
      maxAiAgents: _readInt(value['maxAiAgents']),
      aiRateLimits: rates,
    );
  }

  bool get isEmpty =>
      features.isEmpty &&
      maxBranches == 0 &&
      maxEmployees == 0 &&
      maxAiAgents == 0 &&
      aiRateLimits.isEmpty;

  int limitFor(SubscriptionLimit limit) {
    switch (limit) {
      case SubscriptionLimit.branches:
        return maxBranches;
      case SubscriptionLimit.employees:
        return maxEmployees;
      case SubscriptionLimit.aiAgents:
        return maxAiAgents;
    }
  }

  static int _readInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class LicenseSnapshot {
  final String? businessId;
  final String? businessName;
  final String? accessToken;
  final String? plan;
  final DateTime? expiresAt;
  final DateTime? graceUntil;
  final DateTime? lastVerifiedAt;
  final LicenseAccessStatus accessStatus;
  final String? detail;
  final SubscriptionEntitlements entitlements;

  const LicenseSnapshot({
    required this.businessId,
    required this.businessName,
    required this.accessToken,
    required this.plan,
    required this.expiresAt,
    required this.graceUntil,
    required this.lastVerifiedAt,
    required this.accessStatus,
    required this.detail,
    required this.entitlements,
  });

  const LicenseSnapshot.localOnly()
    : businessId = null,
      businessName = null,
      accessToken = null,
      plan = null,
      expiresAt = null,
      graceUntil = null,
      lastVerifiedAt = null,
      accessStatus = LicenseAccessStatus.localOnly,
      detail = 'Cloud subscription is not activated on this device yet.',
      entitlements = const SubscriptionEntitlements.empty();

  bool get hasBinding =>
      (businessId?.trim().isNotEmpty ?? false) &&
      (accessToken?.trim().isNotEmpty ?? false);

  bool get allowsWrites =>
      accessStatus == LicenseAccessStatus.localOnly ||
      accessStatus == LicenseAccessStatus.active ||
      accessStatus == LicenseAccessStatus.grace;

  bool allowsFeature(String featureKey) {
    if (accessStatus == LicenseAccessStatus.localOnly) {
      return true;
    }
    if (entitlements.features.isEmpty) {
      return true;
    }
    return entitlements.features.contains(featureKey);
  }

  String get shortLabel {
    switch (accessStatus) {
      case LicenseAccessStatus.localOnly:
        return 'Local Only';
      case LicenseAccessStatus.active:
        return 'Subscription Active';
      case LicenseAccessStatus.grace:
        return 'Grace Period';
      case LicenseAccessStatus.expired:
        return 'Subscription Expired';
      case LicenseAccessStatus.invalid:
        return 'License Error';
    }
  }

  String buildActionMessage(String action) {
    switch (accessStatus) {
      case LicenseAccessStatus.localOnly:
        return 'Cloud subscription is not activated yet, so $action still works locally on this device.';
      case LicenseAccessStatus.active:
        return 'Subscription active.';
      case LicenseAccessStatus.grace:
        final until = _formatDate(graceUntil);
        return until == null
            ? 'This device is in its offline grace period. Reconnect soon to keep $action available.'
            : 'This device is in its offline grace period until $until. Reconnect soon to keep $action available.';
      case LicenseAccessStatus.expired:
        final until = _formatDate(graceUntil);
        if (until != null) {
          return 'The cached subscription grace period ended on $until. Reconnect and renew the subscription to $action.';
        }
        return 'The cached subscription has expired. Reconnect and renew the subscription to $action.';
      case LicenseAccessStatus.invalid:
        return 'The cached cloud license is invalid or corrupted. Reconnect to refresh the license before trying to $action.';
    }
  }

  static String? _formatDate(DateTime? value) {
    if (value == null) {
      return null;
    }
    final local = value.toLocal();
    final month = _monthNames[local.month - 1];
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month $day, ${local.year} $hour:$minute';
  }

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class LicenseService {
  static SharedPreferences? _prefs;
  static const _timeout = Duration(seconds: 20);

  static const _keyBusinessId = 'license_business_id';
  static const _keyBusinessName = 'license_business_name';
  static const _keyAccessToken = 'license_access_token';
  static const _keyPlan = 'license_plan';
  static const _keyPayloadBase64 = 'license_payload_base64';
  static const _keySignature = 'license_signature';
  static const _keyLastVerifiedAt = 'license_last_verified_at';

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static LicenseSnapshot get currentSnapshot {
    final prefs = _prefs;
    if (prefs == null) {
      return const LicenseSnapshot.localOnly();
    }

    final businessId = _readTrimmed(prefs.getString(_keyBusinessId));
    final businessName = _readTrimmed(prefs.getString(_keyBusinessName));
    final accessToken = _readTrimmed(prefs.getString(_keyAccessToken));
    final plan = _readTrimmed(prefs.getString(_keyPlan));
    final payloadBase64 = _readTrimmed(prefs.getString(_keyPayloadBase64));
    final signature = _readTrimmed(prefs.getString(_keySignature));
    final lastVerifiedAt = _parseDate(
      _readTrimmed(prefs.getString(_keyLastVerifiedAt)),
    );

    if (businessId == null && accessToken == null) {
      return const LicenseSnapshot.localOnly();
    }

    if (payloadBase64 == null || signature == null) {
      return LicenseSnapshot(
        businessId: businessId,
        businessName: businessName,
        accessToken: accessToken,
        plan: plan,
        expiresAt: null,
        graceUntil: null,
        lastVerifiedAt: lastVerifiedAt,
        accessStatus: LicenseAccessStatus.invalid,
        detail: 'The cached cloud license is incomplete.',
        entitlements: const SubscriptionEntitlements.empty(),
      );
    }

    if (!_matchesSignature(payloadBase64, signature)) {
      return LicenseSnapshot(
        businessId: businessId,
        businessName: businessName,
        accessToken: accessToken,
        plan: plan,
        expiresAt: null,
        graceUntil: null,
        lastVerifiedAt: lastVerifiedAt,
        accessStatus: LicenseAccessStatus.invalid,
        detail: 'The cached cloud license signature does not match.',
        entitlements: const SubscriptionEntitlements.empty(),
      );
    }

    final payload = _decodePayload(payloadBase64);
    if (payload == null) {
      return LicenseSnapshot(
        businessId: businessId,
        businessName: businessName,
        accessToken: accessToken,
        plan: plan,
        expiresAt: null,
        graceUntil: null,
        lastVerifiedAt: lastVerifiedAt,
        accessStatus: LicenseAccessStatus.invalid,
        detail: 'The cached cloud license could not be decoded.',
        entitlements: const SubscriptionEntitlements.empty(),
      );
    }

    final payloadBusinessId = _readTrimmed(payload['business_id']?.toString());
    final expiresAt = _parseDate(payload['expires_at']?.toString());
    final graceUntil = _parseDate(payload['grace_until']?.toString());
    final payloadStatus =
        _readTrimmed(payload['status']?.toString()) ?? 'active';
    if (payloadBusinessId == null ||
        businessId == null ||
        payloadBusinessId != businessId ||
        expiresAt == null ||
        graceUntil == null) {
      return LicenseSnapshot(
        businessId: businessId,
        businessName: businessName,
        accessToken: accessToken,
        plan: plan,
        expiresAt: expiresAt,
        graceUntil: graceUntil,
        lastVerifiedAt: lastVerifiedAt,
        accessStatus: LicenseAccessStatus.invalid,
        detail: 'The cached cloud license does not match this device binding.',
        entitlements: const SubscriptionEntitlements.empty(),
      );
    }

    final now = DateTime.now().toUtc();
    final accessStatus = _resolveAccessStatus(
      payloadStatus: payloadStatus,
      expiresAt: expiresAt,
      graceUntil: graceUntil,
      now: now,
    );

    return LicenseSnapshot(
      businessId: businessId,
      businessName:
          _readTrimmed(payload['business_name']?.toString()) ?? businessName,
      accessToken: accessToken,
      plan: _readTrimmed(payload['plan']?.toString()) ?? plan,
      expiresAt: expiresAt,
      graceUntil: graceUntil,
      lastVerifiedAt: lastVerifiedAt,
      accessStatus: accessStatus,
      detail: _buildSnapshotDetail(
        accessStatus: accessStatus,
        expiresAt: expiresAt,
        graceUntil: graceUntil,
      ),
      entitlements: SubscriptionEntitlements.fromJson(payload['entitlements']),
    );
  }

  static Future<LicenseSnapshot> ensureOnlineLicense({
    required String backendUrl,
    required String deviceId,
    required String businessName,
    required String ownerName,
    required String ownerEmail,
    bool forceRefresh = false,
  }) async {
    await init();

    final normalizedBackendUrl = backendUrl.trim();
    if (normalizedBackendUrl.isEmpty) {
      return currentSnapshot;
    }

    final snapshot = currentSnapshot;
    if (!snapshot.hasBinding) {
      return _activate(
        backendUrl: normalizedBackendUrl,
        deviceId: deviceId,
        businessName: businessName,
        ownerName: ownerName,
        ownerEmail: ownerEmail,
      );
    }

    if (forceRefresh || _shouldRefresh(snapshot)) {
      return refreshOnline(
        backendUrl: normalizedBackendUrl,
        deviceId: deviceId,
      );
    }

    return snapshot;
  }

  static Future<LicenseSnapshot> refreshOnline({
    required String backendUrl,
    required String deviceId,
  }) async {
    await init();
    final snapshot = currentSnapshot;
    final accessToken = snapshot.accessToken;
    if (accessToken == null || accessToken.trim().isEmpty) {
      throw Exception('Cloud subscription is not activated on this device.');
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            _buildUri(backendUrl, 'license/refresh'),
            headers: {
              HttpHeaders.authorizationHeader: 'Bearer $accessToken',
              HttpHeaders.contentTypeHeader: 'application/json',
            },
            body: jsonEncode({'deviceId': deviceId}),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);
      _throwIfRequestFailed(response, body);
      await _storeAccessResponse(body);
      return currentSnapshot;
    } finally {
      client.close();
    }
  }

  static Future<void> storeAccessResponse(Map<String, dynamic> body) async {
    await init();
    await _storeAccessResponse(body);
  }

  static Future<void> ensureWriteAccess({required String action}) async {
    await init();
    final snapshot = currentSnapshot;
    if (!snapshot.hasBinding) {
      return;
    }
    if (snapshot.allowsWrites) {
      return;
    }
    throw Exception(snapshot.buildActionMessage(action));
  }

  static Future<void> ensureFeatureAccess({
    required String featureKey,
    required String action,
  }) async {
    await init();
    final snapshot = currentSnapshot;
    if (!snapshot.hasBinding || snapshot.allowsFeature(featureKey)) {
      return;
    }
    throw Exception('Your current subscription plan does not include $action.');
  }

  static Future<void> ensureLimitAvailable({
    required SubscriptionLimit limit,
    required int currentCount,
    required String label,
  }) async {
    await init();
    final snapshot = currentSnapshot;
    if (!snapshot.hasBinding || snapshot.entitlements.isEmpty) {
      return;
    }
    final max = snapshot.entitlements.limitFor(limit);
    if (max <= 0 || currentCount < max) {
      return;
    }
    throw Exception('Your current subscription plan allows $max $label.');
  }

  static bool canAddWithinLimit({
    required SubscriptionLimit limit,
    required int currentCount,
  }) {
    final snapshot = currentSnapshot;
    if (!snapshot.hasBinding || snapshot.entitlements.isEmpty) {
      return true;
    }
    final max = snapshot.entitlements.limitFor(limit);
    return max <= 0 || currentCount < max;
  }

  static Future<void> clearBinding() async {
    await init();
    await _prefs!.remove(_keyBusinessId);
    await _prefs!.remove(_keyBusinessName);
    await _prefs!.remove(_keyAccessToken);
    await _prefs!.remove(_keyPlan);
    await _prefs!.remove(_keyPayloadBase64);
    await _prefs!.remove(_keySignature);
    await _prefs!.remove(_keyLastVerifiedAt);
  }

  static Future<LicenseSnapshot> _activate({
    required String backendUrl,
    required String deviceId,
    required String businessName,
    required String ownerName,
    required String ownerEmail,
  }) async {
    final normalizedBusinessName = businessName.trim();
    if (normalizedBusinessName.isEmpty) {
      throw Exception('Enter a business name before activating cloud sync.');
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            _buildUri(backendUrl, 'license/activate'),
            headers: const {HttpHeaders.contentTypeHeader: 'application/json'},
            body: jsonEncode({
              'deviceId': deviceId,
              'deviceName': _deviceName,
              'businessName': normalizedBusinessName,
              'ownerName': ownerName.trim(),
              'ownerEmail': ownerEmail.trim(),
            }),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);
      _throwIfRequestFailed(response, body);
      await _storeAccessResponse(body);
      return currentSnapshot;
    } finally {
      client.close();
    }
  }

  static Future<void> _storeAccessResponse(Map<String, dynamic> body) async {
    final business = body['business'] is Map<String, dynamic>
        ? body['business'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final license = body['license'] is Map<String, dynamic>
        ? body['license'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final subscription = body['subscription'] is Map<String, dynamic>
        ? body['subscription'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final businessId = _readTrimmed(business['id']?.toString());
    final businessName = _readTrimmed(business['name']?.toString());
    final accessToken = _readTrimmed(body['accessToken']?.toString());
    final plan = _readTrimmed(subscription['plan']?.toString());
    final payloadBase64 = _readTrimmed(license['payloadBase64']?.toString());
    final signature = _readTrimmed(license['signature']?.toString());
    final lastVerifiedAt = _readTrimmed(
      subscription['lastVerifiedAt']?.toString(),
    );

    if (businessId == null ||
        accessToken == null ||
        payloadBase64 == null ||
        signature == null) {
      throw Exception('The cloud subscription response was incomplete.');
    }

    await _prefs!.setString(_keyBusinessId, businessId);
    if (businessName != null) {
      await _prefs!.setString(_keyBusinessName, businessName);
    }
    await _prefs!.setString(_keyAccessToken, accessToken);
    if (plan != null) {
      await _prefs!.setString(_keyPlan, plan);
    }
    await _prefs!.setString(_keyPayloadBase64, payloadBase64);
    await _prefs!.setString(_keySignature, signature);
    if (lastVerifiedAt != null) {
      await _prefs!.setString(_keyLastVerifiedAt, lastVerifiedAt);
    }
  }

  static bool _shouldRefresh(LicenseSnapshot snapshot) {
    if (!snapshot.hasBinding) {
      return true;
    }
    if (snapshot.accessStatus == LicenseAccessStatus.invalid ||
        snapshot.accessStatus == LicenseAccessStatus.expired) {
      return true;
    }
    if (snapshot.lastVerifiedAt == null) {
      return true;
    }

    final now = DateTime.now().toUtc();
    if (now.difference(snapshot.lastVerifiedAt!).inHours >= 12) {
      return true;
    }

    final expiresAt = snapshot.expiresAt;
    if (expiresAt == null) {
      return true;
    }

    return expiresAt.difference(now).inHours <= 48;
  }

  static LicenseAccessStatus _resolveAccessStatus({
    required String payloadStatus,
    required DateTime expiresAt,
    required DateTime graceUntil,
    required DateTime now,
  }) {
    final normalizedStatus = payloadStatus.trim().toLowerCase();
    if (normalizedStatus != 'active' && normalizedStatus != 'grace') {
      return LicenseAccessStatus.expired;
    }
    if (now.isAfter(graceUntil)) {
      return LicenseAccessStatus.expired;
    }
    if (now.isAfter(expiresAt)) {
      return LicenseAccessStatus.grace;
    }
    return LicenseAccessStatus.active;
  }

  static String _buildSnapshotDetail({
    required LicenseAccessStatus accessStatus,
    required DateTime? expiresAt,
    required DateTime? graceUntil,
  }) {
    switch (accessStatus) {
      case LicenseAccessStatus.localOnly:
        return 'Cloud subscription is not activated on this device yet.';
      case LicenseAccessStatus.active:
        final expiresText = LicenseSnapshot._formatDate(expiresAt);
        return expiresText == null
            ? 'Subscription is active.'
            : 'Subscription is active until $expiresText.';
      case LicenseAccessStatus.grace:
        final graceText = LicenseSnapshot._formatDate(graceUntil);
        return graceText == null
            ? 'Subscription is in its offline grace period.'
            : 'Subscription is in its offline grace period until $graceText.';
      case LicenseAccessStatus.expired:
        final graceText = LicenseSnapshot._formatDate(graceUntil);
        return graceText == null
            ? 'Subscription has expired.'
            : 'Subscription expired after the grace period ended on $graceText.';
      case LicenseAccessStatus.invalid:
        return 'The cached cloud license is invalid or corrupted.';
    }
  }

  static Map<String, dynamic>? _decodePayload(String payloadBase64) {
    try {
      final decoded = utf8.decode(_decodeBase64Url(payloadBase64));
      final value = jsonDecode(decoded);
      if (value is Map<String, dynamic>) {
        return value;
      }
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic> _decodeJson(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return const <String, dynamic>{};
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception('Unexpected cloud license response format');
  }

  static void _throwIfRequestFailed(
    http.Response response,
    Map<String, dynamic> body,
  ) {
    final ok = body['ok'] == true;
    if (response.statusCode >= 200 && response.statusCode < 300 && ok) {
      return;
    }

    final message =
        _readTrimmed(body['error']?.toString()) ??
        'Cloud license request failed with status ${response.statusCode}';
    throw Exception(message);
  }

  static bool _matchesSignature(String payloadBase64, String signature) {
    final expected = _signatureFor(payloadBase64);
    return expected == signature;
  }

  static String _signatureFor(String payloadBase64) {
    final digest = Hmac(
      sha256,
      utf8.encode(AppConstants.licenseSigningSecret),
    ).convert(utf8.encode(payloadBase64));
    return _encodeBase64Url(digest.bytes);
  }

  static Uri _buildUri(String backendUrl, String path) {
    return Uri.parse('$backendUrl/$path');
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  static String? _readTrimmed(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static String _encodeBase64Url(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static List<int> _decodeBase64Url(String value) {
    final normalized = value.padRight(
      value.length + ((4 - value.length % 4) % 4),
      '=',
    );
    return base64Url.decode(normalized);
  }

  static String get _deviceName {
    try {
      return 'Velora ${Platform.operatingSystem}';
    } catch (_) {
      return 'Velora device';
    }
  }
}
