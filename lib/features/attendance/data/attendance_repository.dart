import 'package:uuid/uuid.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';

const _uuid = Uuid();

class AttendanceRepository {
  static const table = 'employee_attendance';
  static List<dynamic> get _branch => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];
  static Future<Map<String, dynamic>?> current() async {
    final rows = await DatabaseService.rawQuery(
      'SELECT * FROM $table WHERE user_id = ? AND status = \'open\' AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY clock_in_at DESC LIMIT 1',
      [SessionService.currentUserId, ..._branch],
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, dynamic>>>
  getAll() => DatabaseService.rawQuery(
    'SELECT * FROM $table WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY clock_in_at DESC LIMIT 200',
    _branch,
  );
  static Future<void> clockIn({String? note}) async {
    await _write('clock in');
    final now = DateTime.now().toIso8601String();
    if (await current() != null) throw Exception('You are already clocked in.');
    await DatabaseService.insert(table, {
      'id': _uuid.v4(),
      'branch_id': DatabaseService.currentBranchId,
      'user_id': SessionService.currentUserId,
      'user_name': SessionService.currentUserName,
      'clock_in_at': now,
      'note': note?.trim(),
      'status': 'open',
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
  }

  static Future<void> clockOut({String? note}) async {
    await _write('clock out');
    final row = await current();
    if (row == null) throw Exception('You are not clocked in.');
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update(table, {
      'clock_out_at': now,
      'note': note?.trim().isNotEmpty == true ? note!.trim() : row['note'],
      'status': 'closed',
      'updated_at': now,
      'sync_status': 'pending',
    }, row['id'] as String);
  }

  static Future<void> _write(String action) async {
    if (!SessionService.canAccessFeature(UserAccessProfile.featureAttendance)) {
      throw Exception('Your account cannot $action.');
    }
    await LicenseService.ensureWriteAccess(action: action);
    await LicenseService.ensureFeatureAccess(
      featureKey: UserAccessProfile.featureAttendance,
      action: action,
    );
  }
}
