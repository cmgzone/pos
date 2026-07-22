import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../../core/services/database_service.dart';

class PikiMemoryService {
  static const _uuid = Uuid();
  static const table = 'piki_memory';

  static Future<void> saveMemory(String key, dynamic value) async {
    final now = DateTime.now().toIso8601String();
    final valueJson = jsonEncode(value);

    await DatabaseService.db.rawInsert(
      '''
      INSERT INTO $table (id, key, value_json, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        value_json = excluded.value_json,
        updated_at = excluded.updated_at
      ''',
      [_uuid.v4(), key, valueJson, now],
    );
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
