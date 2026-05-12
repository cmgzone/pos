import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../../core/services/database_service.dart';

class PikiMemoryService {
  static const _uuid = Uuid();
  static const table = 'piki_memory';

  static Future<void> saveMemory(String key, dynamic value) async {
    final now = DateTime.now().toIso8601String();
    final valueJson = jsonEncode(value);

    // Try to find existing entry
    final existing = await DatabaseService.rawQuery(
      'SELECT id FROM $table WHERE key = ? LIMIT 1',
      [key],
    );

    if (existing.isNotEmpty) {
      await DatabaseService.db.update(
        table,
        {
          'value_json': valueJson,
          'updated_at': now,
        },
        where: 'key = ?',
        whereArgs: [key],
      );
    } else {
      await DatabaseService.db.insert(table, {
        'id': _uuid.v4(),
        'key': key,
        'value_json': valueJson,
        'updated_at': now,
      });
    }
  }

  static Future<dynamic> getMemory(String key) async {
    final rows = await DatabaseService.rawQuery(
      'SELECT value_json FROM $table WHERE key = ? LIMIT 1',
      [key],
    );

    if (rows.isEmpty) return null;
    final valueJson = rows.first['value_json'] as String?;
    if (valueJson == null) return null;
    return jsonDecode(valueJson);
  }

  static Future<void> clearMemory(String key) async {
    await DatabaseService.db.delete(
      table,
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  static Future<void> wipeAll() async {
    await DatabaseService.db.delete(table);
  }
}
