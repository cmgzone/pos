import 'dart:convert';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as edwards;
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

  test('verifies an Ed25519 license signed by the backend (Node interop)', () {
    // payloadBase64 + signature produced by backend crypto.sign(null, utf8, ed25519PrivateKey).
    const payloadBase64 = 'eyJidXNpbmVzc19pZCI6ImIxIn0';
    const signature =
        'XKgsgXEDruApexoHCq4StZSm6WJNfFb7JT-JuPGsS-p8LF7YpP-RY3WMz4cq9oE7aW9m4lhkSZaPLYnNiweLAA';
    expect(
      LicenseService.verifyEd25519Signature(payloadBase64, signature),
      isTrue,
    );
    expect(
      LicenseService.verifyEd25519Signature(
        '${payloadBase64}tampered',
        signature,
      ),
      isFalse,
    );
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

  test('marks cached license invalid when local business differs', () async {
    await prefs.setString(AppConstants.keyLocalBusinessId, 'biz-2');
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
      },
    );

    final snapshot = LicenseService.currentSnapshot;

    expect(snapshot.accessStatus, LicenseAccessStatus.invalid);
    expect(
      snapshot.detail,
      'The cached cloud license belongs to a different local business.',
    );
  });

  test(
    'trusts a recently cloud-verified license with a server signature',
    () async {
      await _storeLicense(
        prefs,
        payload: {
          'business_id': 'biz-1',
          'business_name': 'Piki Demo',
          'device_id': 'device-1',
          'plan': 'trial',
          'status': 'active',
          'expires_at': '2099-05-01T00:00:00.000Z',
          'grace_until': '2099-05-05T00:00:00.000Z',
          'issued_at': '2099-04-18T12:00:00.000Z',
        },
        signatureOverride: 'server-signature-from-production',
        lastVerifiedAt: DateTime.now().toUtc(),
      );

      final snapshot = LicenseService.currentSnapshot;

      expect(snapshot.accessStatus, LicenseAccessStatus.active);
      expect(snapshot.hasBinding, isTrue);
      expect(snapshot.allowsWrites, isTrue);
    },
  );

  test(
    'rejects a stale license when the local signature does not match',
    () async {
      await _storeLicense(
        prefs,
        payload: {
          'business_id': 'biz-1',
          'business_name': 'Piki Demo',
          'device_id': 'device-1',
          'plan': 'trial',
          'status': 'active',
          'expires_at': '2099-05-01T00:00:00.000Z',
          'grace_until': '2099-05-05T00:00:00.000Z',
          'issued_at': '2099-04-18T12:00:00.000Z',
        },
        signatureOverride: 'server-signature-from-production',
        lastVerifiedAt: DateTime.now().toUtc().subtract(
          const Duration(days: 60),
        ),
      );

      final snapshot = LicenseService.currentSnapshot;

      expect(snapshot.accessStatus, LicenseAccessStatus.invalid);
      expect(
        snapshot.detail,
        'The cached cloud license needs an online refresh before it can be trusted on this device.',
      );
    },
  );
}

Future<void> _storeLicense(
  SharedPreferences prefs, {
  required Map<String, dynamic> payload,
  String? signatureOverride,
  DateTime? lastVerifiedAt,
}) async {
  final payloadBase64 = base64Url
      .encode(utf8.encode(jsonEncode(payload)))
      .replaceAll('=', '');
  final signature = signatureOverride ?? _signEd25519(payloadBase64);

  await prefs.setString('license_business_id', payload['business_id'] as String);
  await prefs.setString(
    'license_business_name',
    payload['business_name'] as String,
  );
  await prefs.setString('license_access_token', 'token-1');
  await prefs.setString('license_plan', payload['plan'] as String);
  await prefs.setString('license_payload_base64', payloadBase64);
  await prefs.setString('license_signature', signature);
  await prefs.setString('license_alg', 'ed25519');
  await prefs.setString(
    'license_last_verified_at',
    (lastVerifiedAt ?? DateTime.now().toUtc()).toIso8601String(),
  );
}

String _signEd25519(String payloadBase64) {
  const privateKeyRaw =
      'hQO+bm/zi/2a/C+43BNRWL7jg5HPLO3syXtYTnDC1gE=';
  final privateKey = edwards.newKeyFromSeed(
    Uint8List.fromList(base64.decode(privateKeyRaw)),
  );
  final signature = edwards.sign(
    privateKey,
    Uint8List.fromList(utf8.encode(payloadBase64)),
  );
  return base64Url.encode(signature).replaceAll('=', '');
}
