import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/messaging_service.dart';
import '../../../core/services/session_service.dart';

const _uuid = Uuid();

class SmsCampaignRepository {
  static const table = 'sms_campaigns';

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<List<Map<String, dynamic>>> getAll() {
    return DatabaseService.rawQuery('''
      SELECT *
      FROM $table
      WHERE deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY updated_at DESC, created_at DESC
      ''', _currentBranchArgs);
  }

  static Future<List<Map<String, dynamic>>> previewRecipients(String segment) {
    final where = <String>[
      'deleted_at IS NULL',
      'COALESCE(branch_id, ?) = ?',
      "COALESCE(phone, '') <> ''",
    ];
    final args = <dynamic>[..._currentBranchArgs];
    final groupId = _groupId(segment);
    if (groupId != null) {
      where.add('''
        id IN (
          SELECT customer_id FROM customer_group_members
          WHERE group_id = ? AND deleted_at IS NULL
            AND COALESCE(branch_id, ?) = ?
        )
        ''');
      args.addAll([groupId, ..._currentBranchArgs]);
    }
    switch (_normalizeSegment(segment)) {
      case 'debtors':
        where.add('COALESCE(balance, 0) > 0');
        break;
      case 'loyalty':
        where.add('COALESCE(loyalty_points, 0) > 0');
        break;
      case 'inactive':
        where.add('''
          id NOT IN (
            SELECT DISTINCT customer_id
            FROM sales
            WHERE customer_id IS NOT NULL
              AND deleted_at IS NULL
              AND COALESCE(branch_id, ?) = ?
              AND date(created_at) >= date('now', '-60 day', 'localtime')
          )
          ''');
        args.addAll(_currentBranchArgs);
        break;
    }
    return DatabaseService.rawQuery('''
      SELECT id, name, phone
      FROM customers
      WHERE ${where.join(' AND ')}
      ORDER BY name COLLATE NOCASE ASC
      ''', args);
  }

  static Future<String> createDraft({
    required String name,
    required String segment,
    required String message,
  }) async {
    await _ensureWriteAccess('create SMS campaigns');
    final cleanName = name.trim();
    final cleanMessage = message.trim();
    if (cleanName.isEmpty) {
      throw Exception('Campaign name is required.');
    }
    if (cleanMessage.isEmpty) {
      throw Exception('Campaign message is required.');
    }
    final recipients = await previewRecipients(segment);
    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    await DatabaseService.insert(table, {
      'id': id,
      'branch_id': DatabaseService.currentBranchId,
      'name': cleanName,
      'segment': _normalizeSegment(segment),
      'message': cleanMessage,
      'recipient_count': recipients.length,
      'sent_count': 0,
      'failed_count': 0,
      'status': 'draft',
      'recipient_snapshot_json': jsonEncode(recipients),
      'created_by': SessionService.currentUserId,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    await AuditLogService.log(
      action: 'create',
      entityTable: table,
      entityId: id,
    );
    return id;
  }

  static Future<Map<String, int>> sendCampaign(String campaignId) async {
    await _ensureWriteAccess('send SMS campaigns');
    await _ensureApiMessagingEnabled();
    final campaign = await DatabaseService.queryById(table, campaignId);
    if (campaign == null || campaign['deleted_at'] != null) {
      throw Exception('Campaign not found.');
    }
    final recipients = _decodeRecipients(campaign['recipient_snapshot_json']);
    final targetRecipients = recipients.isEmpty
        ? await previewRecipients(campaign['segment'] as String? ?? 'all')
        : recipients;
    if (targetRecipients.isEmpty) {
      throw Exception('No customers with phone numbers match this segment.');
    }

    var sent = 0;
    var failed = 0;
    String? lastError;
    for (final recipient in targetRecipients) {
      final phone = recipient['phone']?.toString().trim() ?? '';
      if (phone.isEmpty) {
        failed += 1;
        continue;
      }
      try {
        await MessagingService.sendApi(
          channel: CustomerMessageChannel.sms,
          phoneNumber: phone,
          message: _personalize(
            campaign['message'] as String? ?? '',
            recipient['name'] as String? ?? 'Customer',
          ),
          metadata: {
            'campaignId': campaignId,
            'campaignName': campaign['name'],
            'customerId': recipient['id'],
          },
        );
        sent += 1;
      } catch (error) {
        failed += 1;
        lastError = error.toString().replaceFirst('Exception: ', '');
      }
    }

    final now = DateTime.now().toIso8601String();
    await DatabaseService.update(table, {
      'recipient_count': targetRecipients.length,
      'sent_count': sent,
      'failed_count': failed,
      'status': sent == 0 && failed > 0 ? 'failed' : 'sent',
      'recipient_snapshot_json': jsonEncode(targetRecipients),
      'last_error': lastError,
      'sent_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    }, campaignId);
    await AuditLogService.log(
      action: 'send',
      entityTable: table,
      entityId: campaignId,
    );
    return {'sent': sent, 'failed': failed};
  }

  static List<Map<String, dynamic>> _decodeRecipients(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }
    } catch (_) {
      return const [];
    }
    return const [];
  }

  static Future<void> _ensureApiMessagingEnabled() async {
    if (!MessagingService.allowApiSend) {
      try {
        await MessagingService.fetchSettings();
      } catch (_) {
        // The explicit error below is clearer for the campaign workflow.
      }
    }
    if (!MessagingService.allowApiSend) {
      throw Exception('Enable WhatsApp/SMS API sending in Messaging Settings.');
    }
  }

  static Future<void> _ensureWriteAccess(String action) async {
    if (!SessionService.canAccessFeature(
      UserAccessProfile.featureSmsCampaigns,
    )) {
      throw Exception('Your account cannot access SMS campaigns.');
    }
    await LicenseService.ensureWriteAccess(action: action);
    await LicenseService.ensureFeatureAccess(
      featureKey: UserAccessProfile.featureSmsCampaigns,
      action: action,
    );
  }

  static String _normalizeSegment(String value) {
    final clean = value.trim().toLowerCase();
    if (_groupId(clean) != null) return clean;
    if (clean == 'debtors' || clean == 'loyalty' || clean == 'inactive') {
      return clean;
    }
    return 'all';
  }

  static String? _groupId(String value) {
    final clean = value.trim();
    if (!clean.startsWith('group:')) return null;
    final id = clean.substring('group:'.length).trim();
    return id.isEmpty ? null : id;
  }

  static String _personalize(String message, String name) {
    return message.replaceAll(RegExp(r'\{name\}', caseSensitive: false), name);
  }
}
