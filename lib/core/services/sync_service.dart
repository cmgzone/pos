import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import 'branch_service.dart';
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

class SyncProgress {
  final String message;
  final double? value;
  final String? table;
  final int completedTables;
  final int totalTables;
  final int pulledCount;

  const SyncProgress({
    required this.message,
    this.value,
    this.table,
    this.completedTables = 0,
    this.totalTables = 0,
    this.pulledCount = 0,
  });
}

typedef SyncProgressCallback = void Function(SyncProgress progress);

class SyncRunSummary {
  final int pushedCount;
  final int pulledCount;
  final int resolvedConflictCount;
  final int errorCount;
  final List<String> issueMessages;
  final String nextCursor;
  final LocalSyncSnapshot localSnapshot;
  final bool uploadBlocked;

  const SyncRunSummary({
    required this.pushedCount,
    required this.pulledCount,
    required this.resolvedConflictCount,
    required this.errorCount,
    this.issueMessages = const <String>[],
    required this.nextCursor,
    required this.localSnapshot,
    this.uploadBlocked = false,
  });
}

class SyncService {
  static const _timeout = Duration(seconds: 20);
  static const _pullTimeout = Duration(seconds: 90);
  static const _localSnapshotMarkerKey = 'cloud_snapshot_v1';

  static const List<String> _pushTableOrder = [
    'branches',
    'categories',
    'expense_categories',
    'payment_methods',
    'custom_roles',
    'customer_groups',
    'users',
    'customers',
    'customer_group_members',
    'suppliers',
    'products',
    'product_variants',
    'product_variant_colors',
    'purchase_invoices',
    'supplier_payments',
    'purchase_orders',
    'purchase_order_items',
    'shifts',
    'stock_batches',
    'product_serials',
    'wastage_logs',
    'stock_transfers',
    'stocktake_sessions',
    'stocktake_items',
    'sms_campaigns',
    'exchange_rates',
    'customer_invoices',
    'customer_invoice_items',
    'quotations',
    'quotation_items',
    'sales',
    'sale_items',
    'cash_movements',
    'credit_payments',
    'loyalty_rules',
    'loyalty_ledger',
    'gift_cards',
    'gift_card_transactions',
    'promotions',
    'promotion_rules',
    'expenses',
    'services',
    'service_fields',
    'service_orders',
    'service_field_values',
    'service_sale_items',
    'restaurant_tables',
    'table_orders',
    'employee_attendance',
    'delivery_zones',
    'deliveries',
    'audit_logs',
  ];

  static const List<String> _pullTableOrder = [
    'branches',
    'categories',
    'expense_categories',
    'payment_methods',
    'custom_roles',
    'customer_groups',
    'users',
    'customers',
    'customer_group_members',
    'suppliers',
    'products',
    'product_variants',
    'product_variant_colors',
    'purchase_invoices',
    'supplier_payments',
    'purchase_orders',
    'purchase_order_items',
    'shifts',
    'sales',
    'services',
    'customer_invoices',
    'customer_invoice_items',
    'quotations',
    'quotation_items',
    'stock_batches',
    'product_serials',
    'wastage_logs',
    'stock_transfers',
    'stocktake_sessions',
    'stocktake_items',
    'sms_campaigns',
    'exchange_rates',
    'sale_items',
    'cash_movements',
    'credit_payments',
    'loyalty_rules',
    'loyalty_ledger',
    'gift_cards',
    'gift_card_transactions',
    'promotions',
    'promotion_rules',
    'expenses',
    'service_fields',
    'service_orders',
    'service_field_values',
    'service_sale_items',
    'restaurant_tables',
    'table_orders',
    'employee_attendance',
    'delivery_zones',
    'deliveries',
    'audit_logs',
  ];

  @visibleForTesting
  static List<String> get pullTableOrderForTesting =>
      List<String>.unmodifiable(_pullTableOrder);

  @visibleForTesting
  static Future<void> normalizeLocalSystemRowsForTesting() =>
      _normalizeLocalSystemRowsForRole();

  @visibleForTesting
  static Future<void> applyRemoteRowForTesting(
    Transaction txn,
    String table,
    Map<String, dynamic> remoteRow,
  ) => _applyRemoteRow(txn, table, remoteRow);

  @visibleForTesting
  static Future<bool> localSnapshotNeedsRecoveryForTesting({
    required String cursor,
    required String businessId,
  }) => _localSnapshotNeedsRecovery(cursor: cursor, businessId: businessId);

  @visibleForTesting
  static Future<void> writeLocalSnapshotMarkerForTesting({
    required String businessId,
    required String cursor,
    String scopeKey = '',
  }) => _writeLocalSnapshotMarker(
    businessId: businessId,
    cursor: cursor,
    scopeKey: scopeKey,
  );

  static Future<LocalSyncSnapshot> getLocalSnapshot() async {
    final pendingChanges = <String, List<Map<String, dynamic>>>{};
    var pendingCount = 0;
    var conflictCount = 0;
    var errorCount = 0;

    for (final table in _pushTableOrder) {
      final pendingRows = await DatabaseService.queryAll(
        table,
        where: 'sync_status IN (?, ?)',
        whereArgs: ['pending', 'error'],
        orderBy:
            "CASE sync_status WHEN 'pending' THEN 0 ELSE 1 END, updated_at ASC, id ASC",
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
      allowReadOnly: true,
    );
    final cursor = _cursorForBusiness(license);
    final userId = SessionService.currentUserId;
    final client = http.Client();
    try {
      final params = {'cursor': cursor, 'deviceId': deviceId};
      final scopeKey = SyncSettingsService.syncScopeKey;
      if (scopeKey.isNotEmpty) {
        params['scopeKey'] = scopeKey;
      }
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

  static Future<SyncRunSummary> syncNow({
    SyncProgressCallback? onProgress,
    bool forceFullPull = false,
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud sync is not configured for this app build');
    }

    onProgress?.call(
      const SyncProgress(message: 'Preparing cloud sync...', value: 0.04),
    );
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final license = await _ensureBusinessAccess(
      backendUrl: backendUrl,
      deviceId: deviceId,
      forceRefresh: true,
      allowReadOnly: true,
    );
    await _normalizeLocalSystemRowsForRole();
    final savedCursor = _cursorForBusiness(license);
    final recoverLocalSnapshot = await _localSnapshotNeedsRecovery(
      cursor: savedCursor,
      businessId: license.businessId?.trim() ?? '',
    );
    final initialCursor = forceFullPull || recoverLocalSnapshot
        ? '0'
        : savedCursor;
    final localSnapshot = await getLocalSnapshot();

    var pushedCount = 0;
    var resolvedConflictCount = 0;
    var errorCount = 0;
    var issueMessages = const <String>[];
    final uploadBlocked =
        localSnapshot.pendingCount > 0 && !license.allowsWrites;

    if (localSnapshot.pendingCount > 0 && license.allowsWrites) {
      onProgress?.call(
        const SyncProgress(message: 'Uploading local changes...', value: 0.14),
      );
      final pushSummary = await _pushChanges(
        backendUrl: backendUrl,
        deviceId: deviceId,
        pendingChanges: localSnapshot.pendingChanges,
      );
      pushedCount = pushSummary.pushedCount;
      resolvedConflictCount += pushSummary.resolvedConflictCount;
      errorCount += pushSummary.errorCount;
      issueMessages = pushSummary.issueMessages;
    }

    onProgress?.call(
      const SyncProgress(message: 'Downloading business data...', value: 0.30),
    );
    final pullSummary = await _pullChanges(
      backendUrl: backendUrl,
      deviceId: deviceId,
      cursor: initialCursor,
      allowReadOnly: true,
      onProgress: onProgress,
    );

    onProgress?.call(
      const SyncProgress(message: 'Finalizing downloaded data...', value: 0.94),
    );
    await SyncSettingsService.setSyncCursor(pullSummary.nextCursor);
    await SyncSettingsService.setSyncScopeKey(pullSummary.scopeKey);
    await SyncSettingsService.setLastSyncAt(DateTime.now());
    await _markBusinessPulled(license);
    await _writeLocalSnapshotMarker(
      businessId: license.businessId?.trim() ?? '',
      cursor: pullSummary.nextCursor,
      scopeKey: pullSummary.scopeKey,
    );

    final updatedLocalSnapshot = await getLocalSnapshot();

    return SyncRunSummary(
      pushedCount: pushedCount,
      pulledCount: pullSummary.pulledCount,
      resolvedConflictCount:
          resolvedConflictCount + pullSummary.resolvedConflictCount,
      errorCount: errorCount,
      issueMessages: issueMessages,
      nextCursor: pullSummary.nextCursor,
      localSnapshot: updatedLocalSnapshot,
      uploadBlocked: uploadBlocked,
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
        issueMessages: <String>[],
      );
    }

    final client = http.Client();
    try {
      // Push all pending local rows for the business. Rows carry their own
      // branch_id where the table supports branches.
      final bodyPayload = {'deviceId': deviceId, 'changes': payload};
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
      final issueMessages = _readIssueMessages(body['invalidRows']);

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
        issueMessages: issueMessages,
      );
    } finally {
      client.close();
    }
  }

  static Future<_PullSummary> _pullChanges({
    required String backendUrl,
    required String deviceId,
    required String cursor,
    bool allowReadOnly = false,
    SyncProgressCallback? onProgress,
  }) async {
    final license = await _ensureBusinessAccess(
      backendUrl: backendUrl,
      deviceId: deviceId,
      allowReadOnly: allowReadOnly,
    );
    final userId = SessionService.currentUserId;
    final client = http.Client();
    try {
      final params = {'cursor': cursor, 'deviceId': deviceId};
      final previousScopeKey = SyncSettingsService.syncScopeKey;
      if (previousScopeKey.isNotEmpty) {
        params['scopeKey'] = previousScopeKey;
      }
      if (userId.isNotEmpty) {
        params['userId'] = userId;
      }

      final response = await client
          .get(
            _buildUri(backendUrl, 'sync/pull', params),
            headers: _authHeaders(license),
          )
          .timeout(_pullTimeout);

      final body = _decodeJson(response);
      _throwIfRequestFailed(response, body);

      final nextCursor =
          _readString(body['nextCursor'])?.trim().isNotEmpty == true
          ? _readString(body['nextCursor'])!.trim()
          : cursor;
      final scopeKey = _readString(body['scopeKey'])?.trim() ?? '';
      final data = body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : const <String, dynamic>{};

      var pulledCount = 0;
      var resolvedConflictCount = 0;
      String? preservedUserPassword;

      final scopeChanged =
          scopeKey.isNotEmpty &&
          scopeKey != previousScopeKey &&
          (previousScopeKey.isNotEmpty ||
              RolePermissions.normalizeRole(SessionService.currentUserRole) !=
                  RolePermissions.admin);
      if (scopeChanged) {
        final localSnapshot = await getLocalSnapshot();
        if (localSnapshot.pendingCount > 0) {
          throw Exception(
            'Employee access changed while local updates are still pending. Sync those updates before refreshing access.',
          );
        }
        final currentUser = await DatabaseService.queryById(
          'users',
          SessionService.currentUserId,
        );
        preservedUserPassword = _readString(currentUser?['password']);
        await DatabaseService.wipeAndReinitialize();
      }

      await DatabaseService.db.transaction((txn) async {
        final totalTables = _pullTableOrder.length;
        for (var tableIndex = 0; tableIndex < totalTables; tableIndex += 1) {
          final table = _pullTableOrder[tableIndex];
          final rawRows = data[table] is List<dynamic>
              ? data[table] as List<dynamic>
              : [];
          onProgress?.call(
            SyncProgress(
              message: _downloadMessageForTable(table, rawRows.length),
              value: _pullProgressValue(tableIndex, totalTables),
              table: table,
              completedTables: tableIndex,
              totalTables: totalTables,
              pulledCount: pulledCount,
            ),
          );
          for (final rawRow in rawRows) {
            if (rawRow is! Map) {
              continue;
            }
            final row = Map<String, dynamic>.from(rawRow);
            final rowId = _readString(row['id']) ?? '';
            final outcome = await _applyRemoteRowWithDiagnostics(
              txn,
              table,
              row,
              rowId: rowId,
            );
            if (outcome.applied) {
              pulledCount += 1;
            }
            if (outcome.resolvedConflict) {
              resolvedConflictCount += 1;
            }
          }
          onProgress?.call(
            SyncProgress(
              message: _downloadMessageForTable(table, rawRows.length),
              value: _pullProgressValue(tableIndex + 1, totalTables),
              table: table,
              completedTables: tableIndex + 1,
              totalTables: totalTables,
              pulledCount: pulledCount,
            ),
          );
        }
      });

      if (preservedUserPassword?.isNotEmpty == true) {
        await DatabaseService.db.update(
          'users',
          {'password': preservedUserPassword},
          where: 'id = ?',
          whereArgs: [SessionService.currentUserId],
        );
      }
      await _normalizeLocalSystemRowsForRole();
      await _refreshCurrentUserSession();

      return _PullSummary(
        pulledCount: pulledCount,
        resolvedConflictCount: resolvedConflictCount,
        nextCursor: nextCursor,
        scopeKey: scopeKey,
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

    final localRow = await _getRowById(txn, table, id);
    final normalizedRemote = _canonicalizeForLocalStore(remoteRow, 'synced');
    if (table == 'users' && !normalizedRemote.containsKey('password')) {
      normalizedRemote['password'] = localRow?['password'] ?? '';
    }
    if (localRow == null) {
      // A fresh device does not need cloud tombstones for rows it never held.
      // Skipping them also avoids legacy deleted rows whose parent/category
      // was already purged from the server from breaking the entire restore.
      if (_readString(normalizedRemote['deleted_at'])?.isNotEmpty == true) {
        return const _ApplyOutcome(applied: false, resolvedConflict: false);
      }

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

    if (hasLocalUnsynced && updatedComparison > 0) {
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

  static Future<void> _refreshCurrentUserSession() async {
    final userId = SessionService.currentUserId;
    if (userId.isEmpty) return;
    final user = await DatabaseService.queryById('users', userId);
    if (user == null || user['deleted_at'] != null) return;

    await SessionService.signIn(user);
    final allowedBranchIds = SessionService.currentAllowedBranchIds;
    if (allowedBranchIds.isNotEmpty &&
        !allowedBranchIds.contains(BranchService.currentBranchId)) {
      await BranchService.setCurrentBranch(allowedBranchIds.first);
    }
  }

  static Future<void> _normalizeLocalSystemRowsForRole() async {
    if (RolePermissions.normalizeRole(SessionService.currentUserRole) ==
        RolePermissions.admin) {
      return;
    }

    await DatabaseService.db.update(
      'branches',
      {'sync_status': 'synced'},
      where: 'id = ? AND sync_status IN (?, ?, ?)',
      whereArgs: [
        DatabaseService.defaultBranchId,
        'pending',
        'error',
        'conflict',
      ],
    );
  }

  static Future<_ApplyOutcome> _applyRemoteRowWithDiagnostics(
    Transaction txn,
    String table,
    Map<String, dynamic> remoteRow, {
    required String rowId,
  }) async {
    try {
      return await _applyRemoteRow(txn, table, remoteRow);
    } catch (error, stackTrace) {
      debugPrint(
        'Sync apply failed for table=$table id=${rowId.isEmpty ? '<unknown>' : rowId}: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      throw Exception(
        'Failed applying remote change for table "$table"'
        '${rowId.isEmpty ? '' : ' with id "$rowId"'}: $error',
      );
    }
  }

  static double _pullProgressValue(int completedTables, int totalTables) {
    if (totalTables <= 0) {
      return 0.90;
    }
    final fraction = completedTables / totalTables;
    return 0.30 + (fraction * 0.60);
  }

  static String _downloadMessageForTable(String table, int rowCount) {
    final countText = rowCount > 0 ? ' ($rowCount)' : '';
    switch (table) {
      case 'products':
        return rowCount > 0
            ? 'Downloading products$countText...'
            : 'Checking products...';
      case 'product_variants':
        return rowCount > 0
            ? 'Downloading product variants$countText...'
            : 'Checking product variants...';
      case 'product_variant_colors':
        return rowCount > 0
            ? 'Downloading product colors$countText...'
            : 'Checking product colors...';
      case 'categories':
        return rowCount > 0
            ? 'Downloading categories$countText...'
            : 'Checking categories...';
      case 'payment_methods':
        return 'Downloading payment methods$countText...';
      case 'custom_roles':
        return 'Downloading role templates$countText...';
      case 'users':
        return 'Downloading team access$countText...';
      case 'sales':
        return 'Downloading sales history$countText...';
      case 'stock_batches':
      case 'stock_transfers':
        return 'Downloading stock data$countText...';
      case 'product_serials':
        return 'Downloading serial numbers$countText...';
      case 'stocktake_sessions':
      case 'stocktake_items':
        return 'Downloading stocktake data$countText...';
      case 'sms_campaigns':
        return 'Downloading SMS campaigns$countText...';
      case 'exchange_rates':
        return 'Downloading exchange rates$countText...';
      case 'gift_cards':
      case 'gift_card_transactions':
        return 'Downloading gift cards$countText...';
      case 'promotions':
      case 'promotion_rules':
        return 'Downloading promotions$countText...';
      case 'loyalty_rules':
      case 'loyalty_ledger':
        return 'Downloading loyalty data$countText...';
      default:
        return 'Downloading business data$countText...';
    }
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

      // PostgreSQL exposes boolean columns as true/false, while sqflite only
      // accepts num, String, and Uint8List values. SQLite stores booleans as
      // INTEGER, so normalize them at the cloud/local boundary for every
      // synced table.
      if (value is bool) {
        normalized[key] = value ? 1 : 0;
        continue;
      }

      normalized[key] = value is Map || value is List
          ? jsonEncode(value)
          : value;
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
    bool allowReadOnly = false,
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
    final readOnlyAccessAllowed =
        allowReadOnly && snapshot.accessStatus == LicenseAccessStatus.expired;
    if (!snapshot.allowsWrites && !readOnlyAccessAllowed) {
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

  static String _cursorForBusiness(LicenseSnapshot snapshot) {
    final businessId = snapshot.businessId?.trim() ?? '';
    if (businessId.isEmpty) {
      return SyncSettingsService.syncCursor;
    }

    final localBusinessId = SyncSettingsService.localBusinessId.trim();
    if (localBusinessId.isEmpty || localBusinessId != businessId) {
      return '0';
    }
    return SyncSettingsService.syncCursor;
  }

  static Future<bool> _localSnapshotNeedsRecovery({
    required String cursor,
    required String businessId,
  }) async {
    final normalizedCursor = cursor.trim();
    if (normalizedCursor.isEmpty || normalizedCursor == '0') {
      return false;
    }

    final rows = await DatabaseService.rawQuery(
      'SELECT value FROM sync_metadata WHERE key = ? LIMIT 1',
      [_localSnapshotMarkerKey],
    );
    if (rows.isEmpty) {
      return true;
    }

    try {
      final decoded = jsonDecode(rows.first['value']?.toString() ?? '');
      if (decoded is! Map) {
        return true;
      }
      final markerBusinessId =
          _readString(decoded['business_id'])?.trim() ?? '';
      return businessId.isNotEmpty && markerBusinessId != businessId;
    } catch (_) {
      return true;
    }
  }

  static Future<void> _writeLocalSnapshotMarker({
    required String businessId,
    required String cursor,
    required String scopeKey,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await DatabaseService.db.insert('sync_metadata', {
      'key': _localSnapshotMarkerKey,
      'value': jsonEncode({
        'business_id': businessId.trim(),
        'cursor': cursor.trim(),
        'scope_key': scopeKey.trim(),
      }),
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> _markBusinessPulled(LicenseSnapshot snapshot) async {
    final businessId = snapshot.businessId?.trim() ?? '';
    if (businessId.isNotEmpty) {
      await SyncSettingsService.setLocalBusinessId(businessId);
    }
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

  static List<String> _readIssueMessages(Object? rawIssues) {
    final messages = <String>[];
    if (rawIssues is! Map) {
      return messages;
    }

    for (final entry in rawIssues.entries) {
      final table = entry.key.toString();
      final rows = entry.value is List ? entry.value as List : const [];
      for (final row in rows) {
        if (row is! Map) {
          continue;
        }
        final id = _readString(row['id'])?.trim();
        final code = _readString(row['code'])?.trim();
        final message = _readString(row['message'])?.trim();
        final field = _readString(row['field'])?.trim();
        final parts = <String>[
          table,
          if (id != null && id.isNotEmpty) id,
          if (code != null && code.isNotEmpty) code,
          if (field != null && field.isNotEmpty) field,
          if (message != null && message.isNotEmpty) message,
        ];
        if (parts.length > 1) {
          messages.add(parts.join(': '));
        }
      }
    }

    return messages;
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
  final List<String> issueMessages;

  const _PushSummary({
    required this.pushedCount,
    required this.resolvedConflictCount,
    required this.errorCount,
    required this.issueMessages,
  });
}

class _PullSummary {
  final int pulledCount;
  final int resolvedConflictCount;
  final String nextCursor;
  final String scopeKey;

  const _PullSummary({
    required this.pulledCount,
    required this.resolvedConflictCount,
    required this.nextCursor,
    required this.scopeKey,
  });
}

class _ApplyOutcome {
  final bool applied;
  final bool resolvedConflict;

  const _ApplyOutcome({required this.applied, required this.resolvedConflict});
}
