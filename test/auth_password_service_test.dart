import 'package:flutter_test/flutter_test.dart';
import 'package:pos_app/features/auth/data/auth_password_service.dart';

void main() {
  test('hashPassword produces a verifiable non-plaintext value', () {
    final hashedPassword = AuthPasswordService.hashPassword('admin123');

    expect(hashedPassword, isNot('admin123'));
    expect(
      AuthPasswordService.verifyPassword(
        storedPassword: hashedPassword,
        candidatePassword: 'admin123',
      ),
      isTrue,
    );
    expect(AuthPasswordService.needsMigration(hashedPassword), isFalse);
  });

  test('verifyPassword still supports legacy plaintext values', () {
    expect(
      AuthPasswordService.verifyPassword(
        storedPassword: 'legacy-pass',
        candidatePassword: 'legacy-pass',
      ),
      isTrue,
    );
    expect(AuthPasswordService.needsMigration('legacy-pass'), isTrue);
  });

  test('verifyPassword rejects incorrect passwords', () {
    final hashedPassword = AuthPasswordService.hashPassword('correct-pass');

    expect(
      AuthPasswordService.verifyPassword(
        storedPassword: hashedPassword,
        candidatePassword: 'wrong-pass',
      ),
      isFalse,
    );
  });
}
