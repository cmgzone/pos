import '../../../core/services/database_service.dart';
import 'auth_exception.dart';
import 'auth_password_service.dart';
import 'user_repository.dart';

class AuthService {
  static Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw const AuthException('Enter both email and password.');
    }

    final user = await UserRepository.findByEmail(normalizedEmail);
    if (user == null) {
      throw const AuthException('Invalid email or password.');
    }

    final userId = user['id'] as String? ?? '';
    final storedPassword = user['password'] as String? ?? '';
    if (userId.isEmpty) {
      throw const AuthException(
        'This account is incomplete and cannot sign in.',
      );
    }
    if (!AuthPasswordService.verifyPassword(
      storedPassword: storedPassword,
      candidatePassword: password,
    )) {
      throw const AuthException('Invalid email or password.');
    }

    final currentEmail = (user['email'] as String? ?? '').trim().toLowerCase();
    final needsEmailNormalization = currentEmail != normalizedEmail;
    final needsPasswordMigration = AuthPasswordService.needsMigration(
      storedPassword,
    );

    if (!needsEmailNormalization && !needsPasswordMigration) {
      return user;
    }

    final updates = <String, dynamic>{};
    if (needsEmailNormalization) {
      updates['email'] = normalizedEmail;
    }
    if (needsPasswordMigration) {
      updates['password'] = AuthPasswordService.hashPassword(password);
    }

    await DatabaseService.update('users', updates, userId);
    return await UserRepository.findById(userId) ?? {...user, ...updates};
  }
}
