import 'package:uuid/uuid.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';

const _uuid = Uuid();

class DeliveryRepository {
  static List<dynamic> get _branch => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];
  static Future<List<Map<String, dynamic>>> zones() => DatabaseService.rawQuery(
    'SELECT * FROM delivery_zones WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY name',
    _branch,
  );
  static Future<List<Map<String, dynamic>>>
  deliveries() => DatabaseService.rawQuery(
    'SELECT * FROM deliveries WHERE deleted_at IS NULL AND COALESCE(branch_id, ?) = ? ORDER BY updated_at DESC',
    _branch,
  );
  static Future<void> addZone({required String name, double fee = 0}) async {
    await _write('manage delivery zones');
    final now = DateTime.now().toIso8601String();
    await DatabaseService.insert('delivery_zones', {
      'id': _uuid.v4(),
      'branch_id': DatabaseService.currentBranchId,
      'name': name.trim(),
      'fee': fee,
      'minimum_order': 0,
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
  }

  static Future<void> updateStatus(String id, String status) async {
    await _write('update deliveries');
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update('deliveries', {
      'status': status,
      'delivered_at': status == 'delivered' ? now : null,
      'updated_at': now,
      'sync_status': 'pending',
    }, id);
  }

  static Future<void> _write(String action) async {
    if (!SessionService.canAccessFeature(UserAccessProfile.featureDelivery)) {
      throw Exception('Your account cannot $action.');
    }
    await LicenseService.ensureWriteAccess(action: action);
    await LicenseService.ensureFeatureAccess(
      featureKey: UserAccessProfile.featureDelivery,
      action: action,
    );
  }
}
