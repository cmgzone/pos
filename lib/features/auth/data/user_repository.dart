import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_settings_service.dart';
import '../../settings/data/custom_role_repository.dart';
import 'auth_exception.dart';
import 'auth_password_service.dart';

const _uuid = Uuid();

class UserRepository {
  static const _table = 'users';
  static const _timeout = Duration(seconds: 20);

  static Future<List<Map<String, dynamic>>> getAll() async {
    return DatabaseService.rawQuery('''
      SELECT u.*,
             cr.name AS custom_role_name,
             cr.is_active AS custom_role_active
      FROM $_table u
      LEFT JOIN custom_roles cr
        ON cr.id = u.custom_role_id
       AND cr.deleted_at IS NULL
      WHERE u.deleted_at IS NULL
      ORDER BY
        CASE WHEN u.role = 'ADMIN' THEN 0 WHEN u.role = 'MANAGER' THEN 1 ELSE 2 END,
        u.name COLLATE NOCASE ASC,
        u.email COLLATE NOCASE ASC
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

  static Future<int> countAiEnabledUsers({String? excludeUserId}) async {
    final users = await getAll();
    return users
        .where((user) => user['id'] != excludeUserId && _isAiEnabledUser(user))
        .length;
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
    String? customRoleId,
    String? businessNameForCloud,
  }) async {
    final cleanName = name.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanPassword = password;
    final cleanPhone = phone?.trim() ?? '';
    var normalizedRole = role.trim().toUpperCase();
    final cleanCustomRoleId = customRoleId?.trim() ?? '';
    Map<String, dynamic>? customRoleAccess;
    if (cleanCustomRoleId.isNotEmpty) {
      customRoleAccess = await CustomRoleRepository.userAccessColumnsForRole(
        cleanCustomRoleId,
      );
      normalizedRole =
          customRoleAccess['role'] as String? ?? RolePermissions.cashier;
    }

    await LicenseService.ensureWriteAccess(action: 'manage staff accounts');
    await LicenseService.ensureLimitAvailable(
      limit: SubscriptionLimit.employees,
      currentCount: await count(),
      label: 'employee account(s)',
    );
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
    final defaultFeatures = customRoleAccess == null
        ? UserAccessProfile.defaultFeatureAccessForRole(normalizedRole).toList()
        : UserAccessProfile.resolveFeatureAccess(
            role: normalizedRole,
            rawFeatureAccessJson:
                customRoleAccess['feature_access_json'] as String?,
          ).toList();
    if (defaultFeatures.contains(UserAccessProfile.featureAgent) &&
        !(await _canGrantAdditionalAiSeat())) {
      defaultFeatures.remove(UserAccessProfile.featureAgent);
    }
    final featureAccessJson = UserAccessProfile.encodeStringList(
      defaultFeatures,
    );
    final userPayload = <String, dynamic>{
      'id': id,
      'name': cleanName,
      'email': cleanEmail,
      'phone': cleanPhone.isEmpty ? null : cleanPhone,
      'password': AuthPasswordService.hashPassword(cleanPassword),
      'role': normalizedRole,
      'custom_role_id': cleanCustomRoleId.isEmpty ? null : cleanCustomRoleId,
      'feature_access_json': featureAccessJson,
      'allowed_service_ids_json': customRoleAccess == null
          ? null
          : customRoleAccess['allowed_service_ids_json'] as String?,
      'allowed_branch_ids_json': customRoleAccess == null
          ? null
          : customRoleAccess['allowed_branch_ids_json'] as String?,
      'pos_mode': customRoleAccess == null
          ? UserAccessProfile.posModeBoth
          : customRoleAccess['pos_mode'] as String?,
      'service_order_scope': customRoleAccess == null
          ? UserAccessProfile.serviceOrderScopeAllVisibleServices
          : customRoleAccess['service_order_scope'] as String?,
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

    final defaultFeatureAccessJson = _defaultFeatureAccessJsonForRole(nextRole);
    await DatabaseService.update(_table, {
      'role': nextRole,
      'custom_role_id': null,
      'feature_access_json': defaultFeatureAccessJson,
      'allowed_service_ids_json': null,
      'allowed_branch_ids_json': null,
      'pos_mode': UserAccessProfile.posModeBoth,
      'service_order_scope':
          UserAccessProfile.serviceOrderScopeAllVisibleServices,
      'updated_at': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
    }, userId);
    if (userId == SessionService.currentUserId) {
      await SessionService.updateRole(nextRole);
      await SessionService.updateAccess(
        featureAccessJson: defaultFeatureAccessJson,
        allowedServiceIdsJson: null,
        allowedBranchIdsJson: null,
        posMode: UserAccessProfile.posModeBoth,
        serviceOrderScope:
            UserAccessProfile.serviceOrderScopeAllVisibleServices,
      );
    }
    await _syncCurrentUserRow(userId);
  }

  static Future<void> updateAccess({
    required String userId,
    required List<String> featureAccess,
    required List<String> allowedServiceIds,
    List<String> allowedBranchIds = const [],
    required String posMode,
    required String serviceOrderScope,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'manage staff accounts');
    final user = await findById(userId);
    if (user == null) {
      throw const AuthException('User not found.');
    }

    final normalizedRole = RolePermissions.normalizeRole(
      user['role'] as String?,
    );
    final hadAiAccess = _isAiEnabledUser(user);
    final wantsAiAccess =
        normalizedRole == RolePermissions.admin ||
        featureAccess.contains(UserAccessProfile.featureAgent);
    if (!hadAiAccess && wantsAiAccess) {
      await LicenseService.ensureLimitAvailable(
        limit: SubscriptionLimit.aiAgents,
        currentCount: await countAiEnabledUsers(),
        label: 'Piki AI-enabled employee(s)',
      );
    }
    final nextFeatureAccessJson = normalizedRole == RolePermissions.admin
        ? _defaultFeatureAccessJsonForRole(normalizedRole)
        : UserAccessProfile.encodeStringList(featureAccess);
    final nextAllowedServiceIdsJson =
        normalizedRole == RolePermissions.admin || allowedServiceIds.isEmpty
        ? null
        : UserAccessProfile.encodeStringList(allowedServiceIds);
    final nextAllowedBranchIdsJson =
        normalizedRole == RolePermissions.admin || allowedBranchIds.isEmpty
        ? null
        : UserAccessProfile.encodeStringList(allowedBranchIds);
    final nextPosMode = UserAccessProfile.resolvePosMode(
      role: normalizedRole,
      rawPosMode: posMode,
    );
    final nextServiceOrderScope = UserAccessProfile.resolveServiceOrderScope(
      role: normalizedRole,
      rawScope: serviceOrderScope,
    );
    final now = DateTime.now().toIso8601String();

    await DatabaseService.update(_table, {
      'feature_access_json': nextFeatureAccessJson,
      'custom_role_id': null,
      'allowed_service_ids_json': nextAllowedServiceIdsJson,
      'allowed_branch_ids_json': nextAllowedBranchIdsJson,
      'pos_mode': nextPosMode,
      'service_order_scope': nextServiceOrderScope,
      'updated_at': now,
      'sync_status': 'pending',
    }, userId);

    if (userId == SessionService.currentUserId) {
      await SessionService.updateAccess(
        featureAccessJson: nextFeatureAccessJson,
        allowedServiceIdsJson: nextAllowedServiceIdsJson,
        allowedBranchIdsJson: nextAllowedBranchIdsJson,
        posMode: nextPosMode,
        serviceOrderScope: nextServiceOrderScope,
      );
    }
    await _syncCurrentUserRow(userId);
  }

  static Future<void> assignCustomRole({
    required String userId,
    String? customRoleId,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'assign custom roles');
    await LicenseService.ensureFeatureAccess(
      featureKey: UserAccessProfile.featureCustomRoles,
      action: 'custom roles',
    );
    final cleanRoleId = customRoleId?.trim() ?? '';
    final user = await findById(userId);
    if (user == null) {
      throw const AuthException('User not found.');
    }
    if (cleanRoleId.isEmpty) {
      final currentRole = RolePermissions.normalizeRole(
        user['role'] as String?,
      );
      await updateRole(userId: userId, role: currentRole);
      return;
    }

    final accessColumns = await CustomRoleRepository.userAccessColumnsForRole(
      cleanRoleId,
    );
    final nextRole = RolePermissions.normalizeRole(
      accessColumns['role'] as String?,
    );
    final currentRole = RolePermissions.normalizeRole(user['role'] as String?);
    if (currentRole == RolePermissions.admin &&
        nextRole != RolePermissions.admin) {
      final adminRows = await DatabaseService.rawQuery(
        "SELECT COUNT(*) as count FROM $_table WHERE deleted_at IS NULL AND role = 'ADMIN'",
      );
      final adminCount = (adminRows.first['count'] as num? ?? 0).toInt();
      if (adminCount <= 1) {
        throw const AuthException('Keep at least one admin account active.');
      }
    }

    final hadAiAccess = _isAiEnabledUser(user);
    final wantsAiAccess =
        nextRole == RolePermissions.admin ||
        UserAccessProfile.resolveFeatureAccess(
          role: nextRole,
          rawFeatureAccessJson: accessColumns['feature_access_json'] as String?,
        ).contains(UserAccessProfile.featureAgent);
    if (!hadAiAccess && wantsAiAccess) {
      await LicenseService.ensureLimitAvailable(
        limit: SubscriptionLimit.aiAgents,
        currentCount: await countAiEnabledUsers(),
        label: 'Piki AI-enabled employee(s)',
      );
    }

    final now = DateTime.now().toIso8601String();
    await DatabaseService.update(_table, {
      'role': nextRole,
      'custom_role_id': cleanRoleId,
      'feature_access_json': accessColumns['feature_access_json'],
      'allowed_service_ids_json': accessColumns['allowed_service_ids_json'],
      'allowed_branch_ids_json': accessColumns['allowed_branch_ids_json'],
      'pos_mode': accessColumns['pos_mode'],
      'service_order_scope': accessColumns['service_order_scope'],
      'updated_at': now,
      'sync_status': 'pending',
    }, userId);

    if (userId == SessionService.currentUserId) {
      await SessionService.updateRole(nextRole);
      await SessionService.updateAccess(
        featureAccessJson: accessColumns['feature_access_json'] as String?,
        allowedServiceIdsJson:
            accessColumns['allowed_service_ids_json'] as String?,
        allowedBranchIdsJson:
            accessColumns['allowed_branch_ids_json'] as String?,
        posMode: accessColumns['pos_mode'] as String?,
        serviceOrderScope: accessColumns['service_order_scope'] as String?,
      );
    }
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
      'custom_role_id',
      'feature_access_json',
      'allowed_service_ids_json',
      'allowed_branch_ids_json',
      'pos_mode',
      'service_order_scope',
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

  static Future<bool> _canGrantAdditionalAiSeat() async {
    return LicenseService.canAddWithinLimit(
      limit: SubscriptionLimit.aiAgents,
      currentCount: await countAiEnabledUsers(),
    );
  }

  static bool _isAiEnabledUser(Map<String, dynamic> user) {
    final role = RolePermissions.normalizeRole(user['role'] as String?);
    if (role == RolePermissions.admin) {
      return true;
    }
    final features = UserAccessProfile.resolveFeatureAccess(
      role: role,
      rawFeatureAccessJson: user['feature_access_json'] as String?,
    );
    return features.contains(UserAccessProfile.featureAgent);
  }

  static String _defaultFeatureAccessJsonForRole(String role) {
    return UserAccessProfile.encodeStringList(
      UserAccessProfile.defaultFeatureAccessForRole(role),
    );
  }
}
