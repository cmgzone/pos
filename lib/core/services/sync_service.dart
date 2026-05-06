import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import 'license_service.dart';
import 'session_service.dart';
import 'shop_settings.dart';
import 'sync_settings_service.dart';

class LocalSyncSnapshot {
  final Map<String, List<Map<String, dynamic>>> pendingChanges;
  final int pendingCount;
  final int conflictCount;
  final int errorCount;

  const LocalSyncSnapshot({
    required this.pendingChanges,
    required this.pendingCount,
    required this.conflictCount,
    required this.errorCount,
  });
}

class RemoteSyncStatus {
  final int changedCount;
  final String snapshotCursor;

  const RemoteSyncStatus({
    required this.changedCount,
    required this.snapshotCursor,
  });
}

class SyncRunSummary {
  final int pushedCount;
  final int pulledCount;
  final int resolvedConflictCount;
  final int errorCount;
  final String nextCursor;
  final LocalSyncSnapshot localSnapshot;

  const SyncRunSummary({
    required this.pushedCount,
    required this.pulledCount,
    required this.resolvedConflictCount,
    required this.errorCount,
    required this.nextCursor,
    required this.localSnapshot,
  });
}

class SyncService {
  static const _timeout = Duration(seconds: 20);

  static const List<String> _pushTableOrder = [
    'branches',
    'categories',
    'expense_categories',
    'payment_methods',
    'users',
    'customers',
    'suppliers',
    'products',
    'product_variants',
    'purchase_invoices',
    'shifts',
    'stock_batches',
    'stock_transfers',
    'sales',
    'sale_items',
    'cash_movements',
    'credit_payments',
    'expenses',
    'services',
    'service_fields',
    'service_orders',
    'service_field_values',
    'service_sale_items',
    'audit_logs',
  ];

  static const List<String> _pullTableOrder = [
    'branches',
    'categories',
    'expense_categories',
    'payment_methods',
    'users',
    'customers',
    'suppliers',
    'products',
    'product_variants',
    'purchase_invoices',
    'shifts',
    'sales',
    'stock_batches',
    'stock_transfers',
    'sale_items',
    'cash_movements',
    'credit_payments',
    'expenses',
    'services',
    'service_fields',
    'service_orders',
    'service_field_values',
    'service_sale_items',
    'audit_logs',
  ];

  static Future<LocalSyncSnapshot> getLocalSnapshot() async {
    final pendingChanges = <String, List<Map<String, dynamic>>>{};
    var pendingCount = 0;
    var conflictCount = 0;
    var errorCount = 0;

    for (final table in _pushTableOrder) {
      final pendingRows = await DatabaseService.queryAll(
        table,
        where: 'sync_status = ?',
        whereArgs: ['pending'],
        orderBy: 'updated_at ASC, id ASC',
      );
      pendingChanges[table] = pendingRows;
      pendingCount += pendingRows.length;

      conflictCount += await _countRowsByStatus(table, 'conflict');
      errorCount += await _countRowsByStatus(table, 'error');
    }

    return LocalSyncSnapshot(
      pendingChanges: pendingChanges,
      pendingCount: pendingCount,
      conflictCount: conflictCount,
      errorCount: errorCount,
    );
  }

  static Future<RemoteSyncStatus> fetchRemoteStatus() async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      return const RemoteSyncStatus(changedCount: 0, snapshotCursor: '0');
    }

    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureBusinessAccess(
      backendUrl: backendUrl,
      deviceId: deviceId,
    );
    final cursor = SyncSettingsService.syncCursor;
    final userId = SessionService.currentUserId;
    final client = http.Client();
    try {
      final params = {
        'cursor': cursor,
        'deviceId': deviceId,
        'branchId': DatabaseService.currentBranchId,
      };
      if (userId.isNotEmpty) {
        params['userId'] = userId;
      }

      final response = await client
          .get(
            _buildUri(backendUrl, 'sync/status', params),
            headers: _authHeaders(license),
          )
          .timeout(_timeout);
      final body = _decodeJson(response);
      _throwIfRequestFailed(response, body);

      final tables = body['tables'] is Map<String, dynamic>
          ? body['tables'] as Map<String, dynamic>
          : const <String, dynamic>{};
      var changedCount = 0;
      for (final value in tables.values) {
        if (value is Map<String, dynamic>) {
          changedCount += _asInt(value['changed_since']);
        }
      }

      return RemoteSyncStatus(
        changedCount: changedCount,
        snapshotCursor:
            _readString(body['snapshotCursor'])?.trim().isNotEmpty == true
            ? _readString(body['snapshotCursor'])!.trim()
            : cursor,
      );
    } finally {
      client.close();
    }
  }

  static Future<SyncRunSummary> syncNow() async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured for this app build');
    }

    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    await _ensureBusinessAccess(
      backendUrl: backendUrl,
      deviceId: deviceId,
      forceRefresh: true,
    );
    final initialCursor = SyncSettingsService.syncCursor;
    final localSnapshot = await getLocalSnapshot();

    var pushedCount = 0;
    var resolvedConflictCount = 0;
    var errorCount = 0;

    if (localSnapshot.pendingCount > 0) {
      final pushSummary = await _pushChanges(
        backendUrl: backendUrl,
        deviceId: deviceId,
        pendingChanges: localSnapshot.pendingChanges,
      );
      pushedCount = pushSummary.pushedCount;
      resolvedConflictCount += pushSummary.resolvedConflictCount;
      errorCount += pushSummary.errorCount;
    }

    final pullSummary = await _pullChanges(
      backendUrl: backendUrl,
      deviceId: deviceId,
      cursor: initialCursor,
    );

    await SyncSettingsService.setSyncCursor(pullSummary.nextCursor);
    await SyncSettingsService.setLastSyncAt(DateTime.now());

    final updatedLocalSnapshot = await getLocalSnapshot();

    return SyncRunSummary(
      pushedCount: pushedCount,
      pulledCount: pullSummary.pulledCount,
      resolvedConflictCount:
          resolvedConflictCount + pullSummary.resolvedConflictCount,
      errorCount: errorCount,
      nextCursor: pullSummary.nextCursor,
      localSnapshot: updatedLocalSnapshot,
    );
  }

  static Future<_PushSummary> _pushChanges({
    required String backendUrl,
    required String deviceId,
    required Map<String, List<Map<String, dynamic>>> pendingChanges,
  }) async {
    final license = await _ensureBusinessAccess(
      backendUrl: backendUrl,
      deviceId: deviceId,
    );
    final userId = SessionService.currentUserId;
    final payload = <String, dynamic>{};
    for (final table in _pushTableOrder) {
      final rows = pendingChanges[table] ?? const <Map<String, dynamic>>[];
      if (rows.isEmpty) {
        continue;
      }
      payload[table] = rows.map(_sanitizeRowForPayload).toList();
    }

    if (payload.isEmpty && userId.isEmpty) {
      return const _PushSummary(
        pushedCount: 0,
        resolvedConflictCount: 0,
        errorCount: 0,
      );
    }

    final client = http.Client();
    try {
      final bodyPayload = {
        'deviceId': deviceId,
        'branchId': DatabaseService.currentBranchId,
        'changes': payload,
      };
      if (userId.isNotEmpty) {
        bodyPayload['userId'] = userId;
      }

      final response = await client
          .post(
            _buildUri(backendUrl, 'sync/push'),
            headers: {
              ..._authHeaders(license),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(bodyPayload),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);
      _throwIfRequestFailed(response, body);

      final conflictsByTable = _readConflictRows(body['conflicts']);
      final invalidIdsByTable = _readIssueIds(body['invalidRows']);

      var pushedCount = 0;
      var resolvedConflictCount = 0;
      var errorCount = 0;

      await DatabaseService.db.transaction((txn) async {
        for (final table in _pushTableOrder) {
          final rows = pendingChanges[table] ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            continue;
          }

          final tableConflicts =
              conflictsByTable[table] ?? const <String, Map<String, dynamic>>{};
          final tableInvalidIds = invalidIdsByTable[table] ?? const <String>{};

          for (final row in rows) {
            final id = _readString(row['id']);
            if (id == null || id.isEmpty) {
              continue;
            }

            final currentRow = await _getRowById(txn, table, id);
            if (!_matchesSnapshot(currentRow, row)) {
              continue;
            }

            final conflictServerRow = tableConflicts[id];
            if (conflictServerRow != null) {
              await _upsertRow(
                txn,
                table,
                _canonicalizeForLocalStore(conflictServerRow, 'synced'),
              );
              resolvedConflictCount += 1;
              continue;
            }

            if (tableInvalidIds.contains(id)) {
              await txn.update(
                table,
                {'sync_status': 'error'},
                where: 'id = ? AND updated_at = ?',
                whereArgs: [id, row['updated_at']],
              );
              errorCount += 1;
              continue;
            }

            final successPayload = Map<String, dynamic>.from(
              _canonicalizeForLocalStore(row, 'synced'),
            )..remove('id');

            await txn.update(
              table,
              successPayload,
              where: 'id = ? AND updated_at = ?',
              whereArgs: [id, row['updated_at']],
            );
            pushedCount += 1;
          }
        }
      });

      return _PushSummary(
        pushedCount: pushedCount,
        resolvedConflictCount: resolvedConflictCount,
        errorCount: errorCount,
      );
    } finally {
      client.close();
    }
  }

  static Future<_PullSummary> _pullChanges({
    required String backendUrl,
    required String deviceId,
    required String cursor,
  }) async {
    final license = await _ensureBusinessAccess(
      backendUrl: backendUrl,
      deviceId: deviceId,
    );
    final userId = SessionService.currentUserId;
    final client = http.Client();
    try {
      final params = {
        'cursor': cursor,
        'deviceId': deviceId,
        'branchId': DatabaseService.currentBranchId,
      };
      if (userId.isNotEmpty) {
        params['userId'] = userId;
      }

      final response = await client
          .get(
            _buildUri(backendUrl, 'sync/pull', params),
            headers: _authHeaders(license),
          )
          .timeout(_timeout);

      final body = _decodeJson(response);
      _throwIfRequestFailed(response, body);

      final nextCursor =
          _readString(body['nextCursor'])?.trim().isNotEmpty == true
          ? _readString(body['nextCursor'])!.trim()
          : cursor;
      final data = body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : const <String, dynamic>{};

      var pulledCount = 0;
      var resolvedConflictCount = 0;

      await DatabaseService.db.transaction((txn) async {
        for (final table in _pullTableOrder) {
          final rawRows = data[table] is List<dynamic>
              ? data[table] as List<dynamic>
              : [];
          for (final rawRow in rawRows) {
            if (rawRow is! Map) {
              continue;
            }
            final row = Map<String, dynamic>.from(rawRow);
            final outcome = await _applyRemoteRow(txn, table, row);
            if (outcome.applied) {
              pulledCount += 1;
            }
            if (outcome.resolvedConflict) {
              resolvedConflictCount += 1;
            }
          }
        }
      });

      return _PullSummary(
        pulledCount: pulledCount,
        resolvedConflictCount: resolvedConflictCount,
        nextCursor: nextCursor,
      );
    } finally {
      client.close();
    }
  }

  static Future<_ApplyOutcome> _applyRemoteRow(
    Transaction txn,
    String table,
    Map<String, dynamic> remoteRow,
  ) async {
    final id = _readString(remoteRow['id']);
    if (id == null || id.isEmpty) {
      return const _ApplyOutcome(applied: false, resolvedConflict: false);
    }

    final normalizedRemote = _canonicalizeForLocalStore(remoteRow, 'synced');
    final localRow = await _getRowById(txn, table, id);
    if (localRow == null) {
      // Before inserting, check for unique-key conflicts on non-PK columns
      // (e.g., users.email). If a local row already holds this unique value
      // under a different id, update it in-place to keep FK references intact.
      final conflictRow = await _findUniqueConflict(
        txn,
        table,
        normalizedRemote,
      );
      if (conflictRow != null) {
        final updatePayload = Map<String, dynamic>.from(normalizedRemote)
          ..remove('id');
        await txn.update(
          table,
          updatePayload,
          where: 'id = ?',
          whereArgs: [conflictRow['id']],
        );
        return const _ApplyOutcome(applied: true, resolvedConflict: true);
      }
      await txn.insert(table, normalizedRemote);
      return const _ApplyOutcome(applied: true, resolvedConflict: false);
    }

    final localStatus = _readString(localRow['sync_status'])?.toLowerCase();
    final hasLocalUnsynced =
        localStatus == 'pending' ||
        localStatus == 'conflict' ||
        localStatus == 'error';
    final sameRecord = _recordsEquivalent(localRow, normalizedRemote);
    final updatedComparison = _compareTimestampValues(
      localRow['updated_at'],
      normalizedRemote['updated_at'],
    );

    if (sameRecord) {
      if (localStatus == 'synced') {
        return const _ApplyOutcome(applied: false, resolvedConflict: false);
      }

      await txn.update(
        table,
        Map<String, dynamic>.from(normalizedRemote)..remove('id'),
        where: 'id = ?',
        whereArgs: [id],
      );
      return const _ApplyOutcome(applied: false, resolvedConflict: true);
    }

    if (updatedComparison > 0) {
      return const _ApplyOutcome(applied: false, resolvedConflict: false);
    }

    await txn.update(
      table,
      Map<String, dynamic>.from(normalizedRemote)..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
    return _ApplyOutcome(applied: true, resolvedConflict: hasLocalUnsynced);
  }

  static Map<String, dynamic> _sanitizeRowForPayload(Map<String, dynamic> row) {
    final sanitized = Map<String, dynamic>.from(row);
    sanitized.remove('business_id');
    sanitized.remove('server_revision');
    return sanitized;
  }

  static Map<String, dynamic> _canonicalizeForLocalStore(
    Map<String, dynamic> row,
    String syncStatus,
  ) {
    final normalized = <String, dynamic>{};
    for (final entry in row.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key == 'business_id' || key == 'server_revision') {
        continue;
      }

      if (key.endsWith('_at')) {
        normalized[key] = _normalizeTimestamp(value);
        continue;
      }

      normalized[key] = value;
    }
    normalized['sync_status'] = syncStatus;
    return normalized;
  }

  static bool _matchesSnapshot(
    Map<String, dynamic>? currentRow,
    Map<String, dynamic> snapshotRow,
  ) {
    if (currentRow == null) {
      return false;
    }

    return _compareTimestampValues(
          currentRow['updated_at'],
          snapshotRow['updated_at'],
        ) ==
        0;
  }

  static bool _recordsEquivalent(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final normalizedLeft = _normalizeForComparison(left);
    final normalizedRight = _normalizeForComparison(right);
    final keys = <String>{...normalizedLeft.keys, ...normalizedRight.keys};

    for (final key in keys) {
      if (!_sameValue(normalizedLeft[key], normalizedRight[key])) {
        return false;
      }
    }
    return true;
  }

  static Map<String, dynamic> _normalizeForComparison(
    Map<String, dynamic> row,
  ) {
    final normalized = <String, dynamic>{};
    for (final entry in row.entries) {
      if (entry.key == 'sync_status') {
        continue;
      }

      if (entry.key.endsWith('_at')) {
        normalized[entry.key] = _normalizeTimestamp(entry.value);
      } else {
        normalized[entry.key] = entry.value;
      }
    }
    return normalized;
  }

  static bool _sameValue(Object? left, Object? right) {
    if (left == right) {
      return true;
    }
    if (left == null && right == null) {
      return true;
    }
    if (left is num && right is num) {
      return left.toDouble() == right.toDouble();
    }
    return false;
  }

  static String? _normalizeTimestamp(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }

    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return text;
    }
    return parsed.toUtc().toIso8601String();
  }

  static int _compareTimestampValues(Object? left, Object? right) {
    final leftText = _normalizeTimestamp(left);
    final rightText = _normalizeTimestamp(right);
    if (leftText == null && rightText == null) {
      return 0;
    }
    if (leftText == null) {
      return -1;
    }
    if (rightText == null) {
      return 1;
    }
    if (leftText == rightText) {
      return 0;
    }

    final leftDate = DateTime.tryParse(leftText);
    final rightDate = DateTime.tryParse(rightText);
    if (leftDate == null || rightDate == null) {
      return leftText.compareTo(rightText);
    }
    return leftDate.compareTo(rightDate);
  }

  static Future<Map<String, dynamic>?> _getRowById(
    Transaction txn,
    String table,
    String id,
  ) async {
    final rows = await txn.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, dynamic>.from(rows.first);
  }

  static Future<void> _upsertRow(
    Transaction txn,
    String table,
    Map<String, dynamic> row,
  ) async {
    final id = _readString(row['id']);
    if (id == null || id.isEmpty) {
      return;
    }

    final existing = await _getRowById(txn, table, id);
    if (existing == null) {
      // Guard against unique-key conflicts (e.g., users.email) the same way
      // _applyRemoteRow does: update in-place rather than inserting a duplicate.
      final conflictRow = await _findUniqueConflict(txn, table, row);
      if (conflictRow != null) {
        await txn.update(
          table,
          Map<String, dynamic>.from(row)..remove('id'),
          where: 'id = ?',
          whereArgs: [conflictRow['id']],
        );
        return;
      }
      await txn.insert(table, row);
      return;
    }

    await txn.update(
      table,
      Map<String, dynamic>.from(row)..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Returns an existing local row that would violate a unique constraint other
  /// than the primary key, or `null` if no such conflict exists.
  ///
  /// Currently handles:
  /// - `users.email` (UNIQUE INDEX idx_users_email_unique)
  static Future<Map<String, dynamic>?> _findUniqueConflict(
    Transaction txn,
    String table,
    Map<String, dynamic> row,
  ) async {
    if (table == 'users') {
      final email = _readString(row['email']);
      final rowId = _readString(row['id']) ?? '';
      if (email != null && email.isNotEmpty) {
        final rows = await txn.query(
          table,
          where: 'email = ? AND id != ?',
          whereArgs: [email, rowId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          return Map<String, dynamic>.from(rows.first);
        }
      }
    }
    return null;
  }

  static Future<int> _countRowsByStatus(String table, String status) async {
    final rows = await DatabaseService.rawQuery(
      'SELECT COUNT(*) AS count FROM $table WHERE sync_status = ?',
      [status],
    );
    if (rows.isEmpty) {
      return 0;
    }
    return _asInt(rows.first['count']);
  }

  static Future<LicenseSnapshot> _ensureBusinessAccess({
    required String backendUrl,
    required String deviceId,
    bool forceRefresh = false,
  }) async {
    final snapshot = await LicenseService.ensureOnlineLicense(
      backendUrl: backendUrl,
      deviceId: deviceId,
      businessName: ShopSettings.shopName,
      ownerName: SessionService.currentUserName,
      ownerEmail: SessionService.currentUserEmail,
      forceRefresh: forceRefresh,
    );

    if (!snapshot.hasBinding || snapshot.accessToken == null) {
      throw Exception(
        'Cloud subscription could not be activated for this device.',
      );
    }
    if (!snapshot.allowsWrites) {
      throw Exception(snapshot.buildActionMessage('continue syncing'));
    }
    return snapshot;
  }

  static Map<String, String> _authHeaders(LicenseSnapshot snapshot) {
    final accessToken = snapshot.accessToken;
    if (accessToken == null || accessToken.trim().isEmpty) {
      return const <String, String>{};
    }
    return {'Authorization': 'Bearer $accessToken'};
  }

  static Uri _buildUri(
    String backendUrl,
    String path, [
    Map<String, String>? queryParameters,
  ]) {
    return Uri.parse(
      '$backendUrl/$path',
    ).replace(queryParameters: queryParameters);
  }

  static Map<String, dynamic> _decodeJson(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return const <String, dynamic>{};
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception('Unexpected sync response format');
  }

  static void _throwIfRequestFailed(
    http.Response response,
    Map<String, dynamic> body,
  ) {
    final ok = body['ok'] == true;
    if (response.statusCode >= 200 && response.statusCode < 300 && ok) {
      return;
    }

    final message =
        _readString(body['error']) ??
        'Sync request failed with status ${response.statusCode}';
    throw Exception(message);
  }

  static Map<String, Map<String, Map<String, dynamic>>> _readConflictRows(
    Object? rawConflicts,
  ) {
    final conflictsByTable = <String, Map<String, Map<String, dynamic>>>{};
    if (rawConflicts is! Map) {
      return conflictsByTable;
    }

    for (final entry in rawConflicts.entries) {
      final table = entry.key.toString();
      final rows = entry.value is List ? entry.value as List : const [];
      final mapped = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        if (row is! Map) {
          continue;
        }
        final record = Map<String, dynamic>.from(row);
        final id = _readString(record['id']);
        final serverRow = record['serverRow'] is Map
            ? Map<String, dynamic>.from(record['serverRow'] as Map)
            : null;
        if (id == null || serverRow == null) {
          continue;
        }
        mapped[id] = serverRow;
      }
      if (mapped.isNotEmpty) {
        conflictsByTable[table] = mapped;
      }
    }

    return conflictsByTable;
  }

  static Map<String, Set<String>> _readIssueIds(Object? rawIssues) {
    final issuesByTable = <String, Set<String>>{};
    if (rawIssues is! Map) {
      return issuesByTable;
    }

    for (final entry in rawIssues.entries) {
      final table = entry.key.toString();
      final rows = entry.value is List ? entry.value as List : const [];
      final ids = <String>{};
      for (final row in rows) {
        if (row is! Map) {
          continue;
        }
        final id = _readString(row['id']);
        if (id != null && id.isNotEmpty) {
          ids.add(id);
        }
      }
      if (ids.isNotEmpty) {
        issuesByTable[table] = ids;
      }
    }

    return issuesByTable;
  }

  static int _asInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _readString(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString();
    return text;
  }
}

class _PushSummary {
  final int pushedCount;
  final int resolvedConflictCount;
  final int errorCount;

  const _PushSummary({
    required this.pushedCount,
    required this.resolvedConflictCount,
    required this.errorCount,
  });
}

class _PullSummary {
  final int pulledCount;
  final int resolvedConflictCount;
  final String nextCursor;

  const _PullSummary({
    required this.pulledCount,
    required this.resolvedConflictCount,
    required this.nextCursor,
  });
}

class _ApplyOutcome {
  final bool applied;
  final bool resolvedConflict;

  const _ApplyOutcome({required this.applied, required this.resolvedConflict});
}
