import 'package:uuid/uuid.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';

const _uuid = Uuid();

class CustomerGroupRepository {
  static List<dynamic> get _branch => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];
  static Future<List<Map<String, dynamic>>>
  getAll() => DatabaseService.rawQuery(
    'SELECT g.*, COUNT(m.id) AS member_count FROM customer_groups g LEFT JOIN customer_group_members m ON m.group_id = g.id AND m.deleted_at IS NULL WHERE g.deleted_at IS NULL AND COALESCE(g.branch_id, ?) = ? GROUP BY g.id ORDER BY g.name',
    _branch,
  );
  static Future<String> create({
    required String name,
    String? description,
  }) async {
    await _write('manage customer groups');
    final clean = name.trim();
    if (clean.isEmpty) throw Exception('Group name is required.');
    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    await DatabaseService.insert('customer_groups', {
      'id': id,
      'branch_id': DatabaseService.currentBranchId,
      'name': clean,
      'description': description?.trim(),
      'created_by': SessionService.currentUserId,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    return id;
  }

  static Future<void> addMember({
    required String groupId,
    required String customerId,
  }) async {
    await _write('manage customer groups');
    final now = DateTime.now().toIso8601String();
    final existing = await DatabaseService.rawQuery(
      'SELECT id FROM customer_group_members WHERE group_id = ? AND customer_id = ? AND deleted_at IS NULL LIMIT 1',
      [groupId, customerId],
    );
    if (existing.isNotEmpty) {
      return;
    }
    await DatabaseService.insert('customer_group_members', {
      'id': _uuid.v4(),
      'branch_id': DatabaseService.currentBranchId,
      'group_id': groupId,
      'customer_id': customerId,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
  }

  static Future<void> _write(String action) async {
    if (!SessionService.canAccessFeature(
      UserAccessProfile.featureCustomerSegments,
    )) {
      throw Exception('Your account cannot $action.');
    }
    await LicenseService.ensureWriteAccess(action: action);
    await LicenseService.ensureFeatureAccess(
      featureKey: UserAccessProfile.featureCustomerSegments,
      action: action,
    );
  }
}
