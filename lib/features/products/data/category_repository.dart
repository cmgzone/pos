import 'package:uuid/uuid.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';

const _uuid = Uuid();

class CategoryRepository {
  static const _table = 'categories';

  /// Get all categories
  static Future<List<Map<String, dynamic>>> getAll() async {
    return DatabaseService.queryAll(_table, orderBy: 'name ASC');
  }

  /// Get a single category by ID
  static Future<Map<String, dynamic>?> getById(String id) async {
    return DatabaseService.queryById(_table, id);
  }

  /// Create a new category
  static Future<String> create({required String name, String? color}) async {
    await LicenseService.ensureWriteAccess(action: 'create categories');
    final id = _uuid.v4();
    await DatabaseService.insert(_table, {
      'id': id,
      'name': name,
      'color': color,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
    });
    return id;
  }

  /// Update a category
  static Future<void> update(String id, Map<String, dynamic> data) async {
    await LicenseService.ensureWriteAccess(action: 'update categories');
    await DatabaseService.update(_table, data, id);
  }

  /// Delete a category
  static Future<void> delete(String id) async {
    await LicenseService.ensureWriteAccess(action: 'delete categories');
    await DatabaseService.delete(_table, id);
  }
}
