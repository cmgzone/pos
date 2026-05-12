import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'database_service.dart';
import 'license_service.dart';
import 'session_service.dart';

const _branchUuid = Uuid();

class BranchService {
  static const _keyCurrentBranchId = 'current_branch_id';
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    final branchId = currentBranchId;
    DatabaseService.setCurrentBranchId(branchId);
  }

  static String get currentBranchId {
    final value = _prefs?.getString(_keyCurrentBranchId)?.trim() ?? '';
    return value.isEmpty ? DatabaseService.defaultBranchId : value;
  }

  static Future<void> setCurrentBranch(String branchId) async {
    await init();
    final cleanBranchId = branchId.trim().isEmpty
        ? DatabaseService.defaultBranchId
        : branchId.trim();
    if (!SessionService.canAccessBranchId(cleanBranchId)) {
      throw Exception('This user is not allowed to use that branch');
    }
    await _prefs!.setString(_keyCurrentBranchId, cleanBranchId);
    DatabaseService.setCurrentBranchId(cleanBranchId);
  }

  static Future<List<Map<String, dynamic>>> getBranches({
    bool activeOnly = false,
  }) {
    return DatabaseService.rawQuery(
      '''
      SELECT *
      FROM branches
      WHERE deleted_at IS NULL
        ${activeOnly ? 'AND is_active = 1' : ''}
      ORDER BY CASE WHEN id = ? THEN 0 ELSE 1 END, name COLLATE NOCASE ASC
      ''',
      [DatabaseService.defaultBranchId],
    );
  }

  static Future<String> createBranch({
    required String name,
    String? code,
    String? phone,
    String? address,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'create branches');
    await LicenseService.ensureFeatureAccess(
      featureKey: 'branches',
      action: 'branch management',
    );
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('Branch name is required');
    }
    final branches = await getBranches(activeOnly: true);
    await LicenseService.ensureLimitAvailable(
      limit: SubscriptionLimit.branches,
      currentCount: branches.length,
      label: 'active branch(es)',
    );

    final id = _branchUuid.v4();
    await DatabaseService.insert('branches', {
      'id': id,
      'name': cleanName,
      'code': code?.trim(),
      'phone': phone?.trim(),
      'address': address?.trim(),
      'is_active': 1,
    });
    return id;
  }

  static Future<void> updateBranch(
    String id, {
    required String name,
    String? code,
    String? phone,
    String? address,
    required bool isActive,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'update branches');
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw Exception('Branch name is required');
    }

    await DatabaseService.update('branches', {
      'name': cleanName,
      'code': code?.trim(),
      'phone': phone?.trim(),
      'address': address?.trim(),
      'is_active': isActive ? 1 : 0,
    }, id);
  }
}
