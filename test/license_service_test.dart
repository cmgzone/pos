import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/constants/app_constants.dart';
import 'package:pos_app/core/services/license_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LicenseService.init();
    prefs = await SharedPreferences.getInstance();
  });

  setUp(() async {
    await prefs.clear();
  });

  test('returns local-only snapshot when no binding is stored', () {
    final snapshot = LicenseService.currentSnapshot;

    expect(snapshot.accessStatus, LicenseAccessStatus.localOnly);
    expect(snapshot.hasBinding, isFalse);
    expect(snapshot.allowsWrites, isTrue);
  });

  test('recognizes an active cached license', () async {
    await _storeLicense(
      prefs,
      payload: {
        'business_id': 'biz-1',
        'business_name': 'Velora Demo',
        'device_id': 'device-1',
        'plan': 'trial',
        'status': 'active',
        'expires_at': '2099-05-01T00:00:00.000Z',
        'grace_until': '2099-05-05T00:00:00.000Z',
        'issued_at': '2099-04-18T12:00:00.000Z',
        'entitlements': {
          'features': ['pos', 'agent'],
          'maxBranches': 1,
          'maxEmployees': 2,
          'maxAiAgents': 1,
          'aiRateLimits': {'hourly': 20, 'weekly': 200, 'monthly': 500},
        },
      },
    );

    final snapshot = LicenseService.currentSnapshot;

    expect(snapshot.accessStatus, LicenseAccessStatus.active);
    expect(snapshot.hasBinding, isTrue);
    expect(snapshot.allowsWrites, isTrue);
    expect(snapshot.businessId, 'biz-1');
    expect(snapshot.allowsFeature('agent'), isTrue);
    expect(snapshot.allowsFeature('branches'), isFalse);
    expect(snapshot.allowsFeature('settings'), isTrue);
    expect(snapshot.entitlements.maxBranches, 1);
  });

  test('blocks writes when the cached license is expired', () async {
    await _storeLicense(
      prefs,
      payload: {
        'business_id': 'biz-1',
        'business_name': 'Velora Demo',
        'device_id': 'device-1',
        'plan': 'trial',
        'status': 'active',
        'expires_at': '2020-05-01T00:00:00.000Z',
        'grace_until': '2020-05-05T00:00:00.000Z',
        'issued_at': '2020-04-18T12:00:00.000Z',
      },
    );

    await expectLater(
      LicenseService.ensureWriteAccess(action: 'record sales'),
      throwsException,
    );
  });
}

Future<void> _storeLicense(
  SharedPreferences prefs, {
  required Map<String, dynamic> payload,
}) async {
  final payloadBase64 = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  final signature = base64Url
      .encode(
        Hmac(
          sha256,
          utf8.encode(AppConstants.licenseSigningSecret),
        ).convert(utf8.encode(payloadBase64)).bytes,
      )
      .replaceAll('=', '');

  await prefs.setString(
    'license_business_id',
    payload['business_id'] as String,
  );
  await prefs.setString(
    'license_business_name',
    payload['business_name'] as String,
  );
  await prefs.setString('license_access_token', 'token-1');
  await prefs.setString('license_plan', payload['plan'] as String);
  await prefs.setString('license_payload_base64', payloadBase64);
  await prefs.setString('license_signature', signature);
  await prefs.setString(
    'license_last_verified_at',
    DateTime.now().toUtc().toIso8601String(),
  );
}
