import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';

const _uuid = Uuid();

class CustomRoleRepository {
  static const _table = 'custom_roles';

  static Future<List<Map<String, dynamic>>> getAll({
    bool activeOnly = false,
  }) async {
    final where = <String>['cr.deleted_at IS NULL'];
    if (activeOnly) {
      where.add('COALESCE(cr.is_active, 1) <> 0');
    }
    return DatabaseService.rawQuery('''
      SELECT cr.*,
             COUNT(u.id) AS assigned_count
      FROM $_table cr
      LEFT JOIN users u
        ON u.custom_role_id = cr.id
       AND u.deleted_at IS NULL
      WHERE ${where.join(' AND ')}
      GROUP BY cr.id
      ORDER BY COALESCE(cr.is_active, 1) DESC,
               cr.name COLLATE NOCASE ASC
    ''');
  }

  static Future<Map<String, dynamic>?> findById(String? roleId) async {
    final cleanId = roleId?.trim() ?? '';
    if (cleanId.isEmpty) {
      return null;
    }
    final rows = await DatabaseService.queryAll(
      _table,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [cleanId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<String> create({
    required String name,
    String? description,
    String baseRole = RolePermissions.cashier,
    required List<String> featureAccess,
    List<String> allowedServiceIds = const [],
    List<String> allowedBranchIds = const [],
    String posMode = UserAccessProfile.posModeBoth,
    String serviceOrderScope =
        UserAccessProfile.serviceOrderScopeAllVisibleServices,
    bool isActive = true,
  }) async {
    await _ensureCanManageRoles();
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('Role name is required.');
    }
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    final roleColumns =
        _accessColumns(
            roleId: id,
            baseRole: baseRole,
            featureAccess: featureAccess,
            allowedServiceIds: allowedServiceIds,
            allowedBranchIds: allowedBranchIds,
            posMode: posMode,
            serviceOrderScope: serviceOrderScope,
          )
          ..remove('custom_role_id')
          ..remove('role');
    await DatabaseService.insert(_table, {
      'id': id,
      'branch_id': DatabaseService.currentBranchId,
      'name': cleanName,
      'description': _cleanText(description),
      ...roleColumns,
      'is_active': isActive ? 1 : 0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    return id;
  }

  static Future<void> update({
    required String id,
    required String name,
    String? description,
    String baseRole = RolePermissions.cashier,
    required List<String> featureAccess,
    List<String> allowedServiceIds = const [],
    List<String> allowedBranchIds = const [],
    String posMode = UserAccessProfile.posModeBoth,
    String serviceOrderScope =
        UserAccessProfile.serviceOrderScopeAllVisibleServices,
    bool isActive = true,
  }) async {
    await _ensureCanManageRoles();
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('Role name is required.');
    }
    final now = DateTime.now().toIso8601String();
    final roleColumns =
        _accessColumns(
            roleId: id,
            baseRole: baseRole,
            featureAccess: featureAccess,
            allowedServiceIds: allowedServiceIds,
            allowedBranchIds: allowedBranchIds,
            posMode: posMode,
            serviceOrderScope: serviceOrderScope,
          )
          ..remove('custom_role_id')
          ..remove('role');
    await DatabaseService.update(_table, {
      'name': cleanName,
      'description': _cleanText(description),
      ...roleColumns,
      'is_active': isActive ? 1 : 0,
      'updated_at': now,
      'sync_status': 'pending',
    }, id);
    await _propagateToAssignedUsers(id, now: now);
  }

  static Future<void> delete(String id) async {
    await _ensureCanManageRoles();
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update(_table, {
      'deleted_at': now,
      'is_active': 0,
      'updated_at': now,
      'sync_status': 'pending',
    }, id);
    await DatabaseService.db.rawUpdate(
      '''
      UPDATE users
      SET custom_role_id = NULL,
          updated_at = ?,
          sync_status = 'pending'
      WHERE custom_role_id = ?
        AND deleted_at IS NULL
      ''',
      [now, id],
    );
  }

  static Future<Map<String, dynamic>> userAccessColumnsForRole(
    String roleId,
  ) async {
    final role = await findById(roleId);
    if (role == null) {
      throw Exception('Role template was not found.');
    }
    return _accessColumnsFromRole(role);
  }

  static String roleName(Map<String, dynamic> role) {
    return (role['name'] as String?)?.trim().isNotEmpty == true
        ? (role['name'] as String).trim()
        : 'Custom role';
  }

  static List<String> featureAccessForRole(Map<String, dynamic> role) {
    final baseRole = _normalizeBaseRole(role['base_role'] as String?);
    return UserAccessProfile.resolveFeatureAccess(
      role: baseRole,
      rawFeatureAccessJson: role['feature_access_json'] as String?,
    );
  }

  static List<String> allowedServiceIdsForRole(Map<String, dynamic> role) {
    final baseRole = _normalizeBaseRole(role['base_role'] as String?);
    return UserAccessProfile.resolveAllowedServiceIds(
      role: baseRole,
      rawAllowedServiceIdsJson: role['allowed_service_ids_json'] as String?,
    );
  }

  static List<String> allowedBranchIdsForRole(Map<String, dynamic> role) {
    final baseRole = _normalizeBaseRole(role['base_role'] as String?);
    return UserAccessProfile.resolveAllowedBranchIds(
      role: baseRole,
      rawAllowedBranchIdsJson: role['allowed_branch_ids_json'] as String?,
    );
  }

  static Future<void> _propagateToAssignedUsers(
    String roleId, {
    required String now,
  }) async {
    final role = await findById(roleId);
    if (role == null) {
      return;
    }
    final accessColumns = _accessColumnsFromRole(role);
    await DatabaseService.db.rawUpdate(
      '''
      UPDATE users
      SET role = ?,
          feature_access_json = ?,
          allowed_service_ids_json = ?,
          allowed_branch_ids_json = ?,
          pos_mode = ?,
          service_order_scope = ?,
          updated_at = ?,
          sync_status = 'pending'
      WHERE custom_role_id = ?
        AND deleted_at IS NULL
      ''',
      [
        accessColumns['role'],
        accessColumns['feature_access_json'],
        accessColumns['allowed_service_ids_json'],
        accessColumns['allowed_branch_ids_json'],
        accessColumns['pos_mode'],
        accessColumns['service_order_scope'],
        now,
        roleId,
      ],
    );
    if (SessionService.currentUserId.isNotEmpty) {
      final currentUser = await DatabaseService.queryById(
        'users',
        SessionService.currentUserId,
      );
      if (currentUser?['custom_role_id'] == roleId) {
        await SessionService.updateRole(accessColumns['role'] as String);
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
    }
  }

  static Map<String, dynamic> _accessColumnsFromRole(
    Map<String, dynamic> role,
  ) {
    final baseRole = _normalizeBaseRole(role['base_role'] as String?);
    return _accessColumns(
      roleId: role['id'] as String? ?? '',
      baseRole: baseRole,
      featureAccess: featureAccessForRole(role),
      allowedServiceIds: allowedServiceIdsForRole(role),
      allowedBranchIds: allowedBranchIdsForRole(role),
      posMode: UserAccessProfile.resolvePosMode(
        role: baseRole,
        rawPosMode: role['pos_mode'] as String?,
      ),
      serviceOrderScope: UserAccessProfile.resolveServiceOrderScope(
        role: baseRole,
        rawScope: role['service_order_scope'] as String?,
      ),
    );
  }

  static Map<String, dynamic> _accessColumns({
    required String roleId,
    required String baseRole,
    required List<String> featureAccess,
    required List<String> allowedServiceIds,
    required List<String> allowedBranchIds,
    required String posMode,
    required String serviceOrderScope,
  }) {
    final normalizedRole = _normalizeBaseRole(baseRole);
    final resolvedFeatures = UserAccessProfile.resolveFeatureAccess(
      role: normalizedRole,
      rawFeatureAccessJson: UserAccessProfile.encodeStringList(featureAccess),
    );
    final nextAllowedServiceIds = normalizedRole == RolePermissions.admin
        ? const <String>[]
        : allowedServiceIds;
    final nextAllowedBranchIds = normalizedRole == RolePermissions.admin
        ? const <String>[]
        : allowedBranchIds;
    return {
      'custom_role_id': roleId,
      'base_role': normalizedRole,
      'role': normalizedRole,
      'feature_access_json': UserAccessProfile.encodeStringList(
        resolvedFeatures,
      ),
      'allowed_service_ids_json': nextAllowedServiceIds.isEmpty
          ? null
          : UserAccessProfile.encodeStringList(nextAllowedServiceIds),
      'allowed_branch_ids_json': nextAllowedBranchIds.isEmpty
          ? null
          : UserAccessProfile.encodeStringList(nextAllowedBranchIds),
      'pos_mode': UserAccessProfile.resolvePosMode(
        role: normalizedRole,
        rawPosMode: posMode,
      ),
      'service_order_scope': UserAccessProfile.resolveServiceOrderScope(
        role: normalizedRole,
        rawScope: serviceOrderScope,
      ),
    };
  }

  static String _normalizeBaseRole(String? role) {
    final normalized = RolePermissions.normalizeRole(role);
    return normalized == RolePermissions.admin
        ? RolePermissions.manager
        : normalized;
  }

  static Future<void> _ensureCanManageRoles() async {
    await LicenseService.ensureWriteAccess(action: 'manage custom roles');
    await LicenseService.ensureFeatureAccess(
      featureKey: UserAccessProfile.featureCustomRoles,
      action: 'custom roles',
    );
  }

  static String? _cleanText(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
