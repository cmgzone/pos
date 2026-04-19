import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_settings_service.dart';
import 'auth_exception.dart';
import 'auth_password_service.dart';

const _uuid = Uuid();

class UserRepository {
  static const _table = 'users';
  static const _timeout = Duration(seconds: 20);

  static Future<List<Map<String, dynamic>>> getAll() async {
    return DatabaseService.rawQuery('''
      SELECT *
      FROM $_table
      WHERE deleted_at IS NULL
      ORDER BY
        CASE WHEN role = 'ADMIN' THEN 0 WHEN role = 'MANAGER' THEN 1 ELSE 2 END,
        name COLLATE NOCASE ASC,
        email COLLATE NOCASE ASC
    ''');
  }

  static Future<int> count() async {
    final rows = await DatabaseService.rawQuery(
      'SELECT COUNT(*) as count FROM $_table WHERE deleted_at IS NULL',
    );
    if (rows.isEmpty) {
      return 0;
    }
    return (rows.first['count'] as num? ?? 0).toInt();
  }

  static Future<Map<String, dynamic>?> findById(String userId) async {
    final rows = await DatabaseService.queryAll(
      _table,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>?> findByEmail(String email) async {
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM $_table
      WHERE deleted_at IS NULL
        AND LOWER(TRIM(email)) = ?
      LIMIT 1
      ''',
      [email.trim().toLowerCase()],
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<String> createUser({
    required String name,
    required String email,
    required String password,
    String? phone,
    String role = 'CASHIER',
    String? businessNameForCloud,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password;
    final cleanPhone = phone?.trim() ?? '';
    final normalizedRole = role.trim().toUpperCase();

    await LicenseService.ensureWriteAccess(action: 'manage staff accounts');
    if (cleanName.isEmpty || cleanEmail.isEmpty || cleanPassword.isEmpty) {
      throw const AuthException('Name, email, and password are required.');
    }
    if (!cleanEmail.contains('@') || !cleanEmail.contains('.')) {
      throw const AuthException('Enter a valid email address.');
    }
    if (cleanPassword.trim().isEmpty || cleanPassword.length < 6) {
      throw const AuthException('Password must be at least 6 characters.');
    }

    final existing = await findByEmail(cleanEmail);
    if (existing != null) {
      throw const AuthException('An account with that email already exists.');
    }

    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    final userPayload = <String, dynamic>{
      'id': id,
      'name': cleanName,
      'email': cleanEmail,
      'phone': cleanPhone.isEmpty ? null : cleanPhone,
      'password': AuthPasswordService.hashPassword(cleanPassword),
      'role': normalizedRole,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    };
    await DatabaseService.insert(_table, userPayload);

    await _trySyncUserImmediately(
      userPayload,
      businessNameForCloud: businessNameForCloud,
      rollbackOnDuplicateConflict: true,
    );
    return id;
  }

  static Future<void> updateRole({
    required String userId,
    required String role,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'manage staff accounts');
    final user = await findById(userId);
    if (user == null) {
      throw const AuthException('User not found.');
    }

    final nextRole = role.trim().toUpperCase();
    final currentRole = (user['role'] as String? ?? 'CASHIER').toUpperCase();
    if (currentRole == 'ADMIN' && nextRole != 'ADMIN') {
      final adminRows = await DatabaseService.rawQuery(
        "SELECT COUNT(*) as count FROM $_table WHERE deleted_at IS NULL AND role = 'ADMIN'",
      );
      final adminCount = (adminRows.first['count'] as num? ?? 0).toInt();
      if (adminCount <= 1) {
        throw const AuthException('Keep at least one admin account active.');
      }
    }

    await DatabaseService.update(_table, {'role': nextRole}, userId);
    await _syncCurrentUserRow(userId);
  }

  static Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = await findById(userId);
    if (user == null) {
      throw const AuthException('User not found.');
    }
    final storedPassword = user['password'] as String? ?? '';
    if (!AuthPasswordService.verifyPassword(
      storedPassword: storedPassword,
      candidatePassword: currentPassword,
    )) {
      throw const AuthException('Current password is incorrect.');
    }
    if (newPassword.trim().isEmpty || newPassword.length < 6) {
      throw const AuthException('New password must be at least 6 characters.');
    }
    await DatabaseService.update(_table, {
      'password': AuthPasswordService.hashPassword(newPassword),
    }, userId);
    await _syncCurrentUserRow(userId);
  }

  static Future<void> _syncCurrentUserRow(String userId) async {
    final user = await findById(userId);
    if (user == null) {
      return;
    }
    await _trySyncUserImmediately(user);
  }

  static Future<void> _trySyncUserImmediately(
    Map<String, dynamic> localUser, {
    String? businessNameForCloud,
    bool rollbackOnDuplicateConflict = false,
  }) async {
    try {
      await SyncSettingsService.init();
      final backendUrl = SyncSettingsService.backendUrl;
      if (backendUrl.isEmpty) {
        return;
      }

      final deviceId = await SyncSettingsService.getOrCreateDeviceId();
      final access = await LicenseService.ensureOnlineLicense(
        backendUrl: backendUrl,
        deviceId: deviceId,
        businessName: (businessNameForCloud?.trim().isNotEmpty == true
            ? businessNameForCloud!.trim()
            : ShopSettings.shopName),
        ownerName: SessionService.currentUserName.isNotEmpty
            ? SessionService.currentUserName
            : (localUser['name'] as String? ?? ''),
        ownerEmail: SessionService.currentUserEmail.isNotEmpty
            ? SessionService.currentUserEmail
            : (localUser['email'] as String? ?? ''),
      );

      final accessToken = access.accessToken;
      if (accessToken == null || accessToken.trim().isEmpty) {
        return;
      }

      final response = await http
          .post(
            Uri.parse('$backendUrl/users/upsert'),
            headers: {
              'Authorization': 'Bearer $accessToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'deviceId': deviceId,
              'user': _sanitizeUserForCloud(localUser),
            }),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          body['ok'] == true) {
        await _markUserAsSynced(localUser['id'] as String? ?? '');
        return;
      }

      final message = _readText(body['error']) ?? 'Cloud user sync failed.';
      if (rollbackOnDuplicateConflict &&
          response.statusCode == 409 &&
          message.toLowerCase().contains('email')) {
        await _removeLocalUser(localUser['id'] as String? ?? '');
        throw AuthException(message);
      }
    } on AuthException {
      rethrow;
    } catch (_) {
      // Keep the local row pending so the regular sync flow can retry later.
    }
  }

  static Map<String, dynamic> _sanitizeUserForCloud(Map<String, dynamic> user) {
    final payload = <String, dynamic>{};
    for (final key in const [
      'id',
      'name',
      'email',
      'phone',
      'password',
      'role',
      'created_at',
      'updated_at',
      'deleted_at',
      'sync_status',
    ]) {
      if (user.containsKey(key)) {
        payload[key] = user[key];
      }
    }
    return payload;
  }

  static Future<void> _markUserAsSynced(String userId) async {
    if (userId.trim().isEmpty) {
      return;
    }
    await DatabaseService.db.update(
      _table,
      {'sync_status': 'synced'},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  static Future<void> _removeLocalUser(String userId) async {
    if (userId.trim().isEmpty) {
      return;
    }
    await DatabaseService.db.delete(
      _table,
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  static Map<String, dynamic> _decodeJson(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return const <String, dynamic>{};
  }

  static String? _readText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
