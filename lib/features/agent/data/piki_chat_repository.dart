import 'dart:convert';
import '../../../core/services/database_service.dart';
import 'piki_models.dart';

class PikiChatRepository {
  static const String sessionTable = 'piki_sessions';
  static const String messageTable = 'piki_messages';

  static Future<PikiSession> createSession(String title) async {
    final session = PikiSession(title: title);
    await DatabaseService.db.insert(sessionTable, {
      'id': session.id,
      'title': session.title,
      'created_at': session.createdAt.toIso8601String(),
      'updated_at': session.updatedAt.toIso8601String(),
    });
    return session;
  }

  static Future<List<PikiSession>> getAllSessions() async {
    final rows = await DatabaseService.rawQuery('SELECT * FROM $sessionTable ORDER BY updated_at DESC');
    return rows.map((row) => PikiSession.fromJson(row)).toList();
  }

  static Future<void> deleteSession(String sessionId) async {
    await DatabaseService.db.delete(sessionTable, where: 'id = ?', whereArgs: [sessionId]);
  }

  static Future<void> saveMessage(PikiMessage message) async {
    if (message.sessionId == null) return;
    
    // Update session updated_at
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.update(
      sessionTable,
      {'updated_at': now},
      where: 'id = ?',
      whereArgs: [message.sessionId],
    );

    // Save message
    final exists = await DatabaseService.rawQuery('SELECT id FROM $messageTable WHERE id = ? LIMIT 1', [message.id]);
    
    final data = {
      'id': message.id,
      'session_id': message.sessionId,
      'content': message.content,
      'sender': message.sender.name,
      'message_type': message.messageType.name,
      'attached_data_json': message.attachedData != null ? jsonEncode(message.attachedData) : null,
      'steps_json': message.steps != null ? jsonEncode(message.steps!.map((s) => s.toJson()).toList()) : null,
      'suggestions_json': message.suggestions != null ? jsonEncode(message.suggestions) : null,
      'timestamp': message.timestamp.toIso8601String(),
    };

    if (exists.isNotEmpty) {
      await DatabaseService.db.update(messageTable, data, where: 'id = ?', whereArgs: [message.id]);
    } else {
      await DatabaseService.db.insert(messageTable, data);
    }
  }

  static Future<List<PikiMessage>> getMessages(String sessionId) async {
    final rows = await DatabaseService.rawQuery(
      'SELECT * FROM $messageTable WHERE session_id = ? ORDER BY timestamp ASC',
      [sessionId],
    );

    return rows.map((row) {
      final attachedDataJson = row['attached_data_json'] as String?;
      final stepsJson = row['steps_json'] as String?;
      final suggestionsJson = row['suggestions_json'] as String?;

      return PikiMessage(
        id: row['id'] as String?,
        sessionId: row['session_id'] as String?,
        content: row['content'] as String? ?? '',
        timestamp: DateTime.tryParse(row['timestamp'] as String? ?? '') ?? DateTime.now(),
        sender: PikiSender.values.firstWhere(
          (e) => e.name == row['sender'],
          orElse: () => PikiSender.agent,
        ),
        messageType: PikiMessageType.values.firstWhere(
          (e) => e.name == row['message_type'],
          orElse: () => PikiMessageType.text,
        ),
        attachedData: attachedDataJson != null ? jsonDecode(attachedDataJson) as Map<String, dynamic> : null,
        steps: stepsJson != null ? (jsonDecode(stepsJson) as List).map((s) => PikiStep.fromJson(Map<String, dynamic>.from(s))).toList() : null,
        suggestions: suggestionsJson != null ? (jsonDecode(suggestionsJson) as List).cast<String>() : null,
      );
    }).toList();
  }
}
