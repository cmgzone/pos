import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/core/services/database_service.dart';
import 'package:pos_app/features/auth/data/auth_password_service.dart';
import 'package:pos_app/features/auth/data/user_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await DatabaseService.overrideDatabasePathForTesting(':memory:');
    await DatabaseService.initialize();
  });

  tearDown(() async {
    await DatabaseService.overrideDatabasePathForTesting(null);
  });

  test('cloud-authenticated user is cached for offline login', () async {
    final passwordHash = AuthPasswordService.hashPassword('secret123');

    final cached = await UserRepository.upsertCloudAuthenticatedUser(
      cloudUser: const {
        'id': 'cloud-user-1',
        'name': 'Amina',
        'email': 'amina@example.com',
        'role': 'ADMIN',
      },
      fallbackEmail: 'fallback@example.com',
      passwordHash: passwordHash,
    );

    expect(cached['id'], 'cloud-user-1');
    expect(cached['email'], 'amina@example.com');
    expect(cached['cloud_verified_at'], isNotNull);
    expect(cached['sync_status'], 'synced');
    expect(
      AuthPasswordService.verifyPassword(
        storedPassword: cached['password'] as String,
        candidatePassword: 'secret123',
      ),
      isTrue,
    );
  });

  test('business switch refreshes an existing cached user', () async {
    await UserRepository.upsertCloudAuthenticatedUser(
      cloudUser: const {
        'id': 'cloud-user-2',
        'name': 'Old name',
        'email': 'owner@example.com',
        'role': 'CASHIER',
      },
      fallbackEmail: 'owner@example.com',
      passwordHash: AuthPasswordService.hashPassword('old-password'),
    );

    final refreshed = await UserRepository.upsertCloudAuthenticatedUser(
      cloudUser: const {
        'id': 'cloud-user-2',
        'name': 'Current Owner',
        'email': 'owner@example.com',
        'role': 'ADMIN',
      },
      fallbackEmail: 'owner@example.com',
      passwordHash: AuthPasswordService.hashPassword('new-password'),
    );

    expect(refreshed['name'], 'Current Owner');
    expect(refreshed['role'], 'ADMIN');
    expect(
      AuthPasswordService.verifyPassword(
        storedPassword: refreshed['password'] as String,
        candidatePassword: 'new-password',
      ),
      isTrue,
    );
  });
}
