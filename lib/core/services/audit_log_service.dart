import 'dart:developer' as developer;

import 'package:uuid/uuid.dart';

import 'database_service.dart';
import 'session_service.dart';

const _auditUuid = Uuid();

class AuditLogService {
  static Future<void> log({
    required String action,
    required String entityTable,
    String? entityId,
    String? branchId,
  }) async {
    try {
      await DatabaseService.insert('audit_logs', {
        'id': _auditUuid.v4(),
        'branch_id': branchId ?? DatabaseService.currentBranchId,
        'user_id': SessionService.currentUserId.trim().isEmpty
            ? null
            : SessionService.currentUserId,
        'user_name': SessionService.currentUserName,
        'user_role': SessionService.currentUserRole,
        'action': action,
        'entity_table': entityTable,
        'entity_id': entityId,
      });
    } catch (e, st) {
      developer.log(
        'Failed to write audit log',
        error: e,
        stackTrace: st,
        name: 'AuditLogService',
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getRecent({
    String? branchId,
    String? tableName,
    int limit = 100,
  }) {
    final clauses = <String>['deleted_at IS NULL'];
    final args = <dynamic>[];

    final cleanBranchId = branchId?.trim() ?? '';
    if (cleanBranchId.isNotEmpty) {
      clauses.add('branch_id = ?');
      args.add(cleanBranchId);
    }

    final cleanTableName = tableName?.trim() ?? '';
    if (cleanTableName.isNotEmpty) {
      clauses.add('entity_table = ?');
      args.add(cleanTableName);
    }

    args.add(limit);
    return DatabaseService.rawQuery('''
      SELECT *
      FROM audit_logs
      WHERE ${clauses.join(' AND ')}
      ORDER BY created_at DESC
      LIMIT ?
      ''', args);
  }
}
