import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/products/data/product_provider.dart';
import 'connectivity_service.dart';
import 'database_service.dart';
import 'license_service.dart';
import 'session_service.dart';
import 'sync_service.dart';
import 'sync_settings_service.dart';

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

enum SyncIndicatorState {
  localOnly,
  offline,
  syncing,
  error,
  issues,
  pending,
  updatesAvailable,
  synced,
}

class SyncState {
  final bool isConfigured;
  final bool autoSyncEnabled;
  final bool isOnline;
  final bool isSyncing;
  final int pendingChanges;
  final int conflictCount;
  final int errorCount;
  final int remoteChanges;
  final DateTime? lastSyncAt;
  final String cursor;
  final String? deviceId;
  final LicenseSnapshot licenseSnapshot;
  final String? lastError;
  final String? lastMessage;

  const SyncState({
    required this.isConfigured,
    required this.autoSyncEnabled,
    required this.isOnline,
    required this.isSyncing,
    required this.pendingChanges,
    required this.conflictCount,
    required this.errorCount,
    required this.remoteChanges,
    required this.lastSyncAt,
    required this.cursor,
    required this.deviceId,
    required this.licenseSnapshot,
    required this.lastError,
    required this.lastMessage,
  });

  factory SyncState.initial({required bool isOnline}) {
    return SyncState(
      isConfigured: SyncSettingsService.isConfigured,
      autoSyncEnabled: SyncSettingsService.autoSyncEnabled,
      isOnline: isOnline,
      isSyncing: false,
      pendingChanges: 0,
      conflictCount: 0,
      errorCount: 0,
      remoteChanges: 0,
      lastSyncAt: SyncSettingsService.lastSyncAt,
      cursor: SyncSettingsService.syncCursor,
      deviceId: SyncSettingsService.deviceId,
      licenseSnapshot: LicenseService.currentSnapshot,
      lastError: null,
      lastMessage: null,
    );
  }

  SyncState copyWith({
    bool? isConfigured,
    bool? autoSyncEnabled,
    bool? isOnline,
    bool? isSyncing,
    int? pendingChanges,
    int? conflictCount,
    int? errorCount,
    int? remoteChanges,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    String? cursor,
    String? deviceId,
    LicenseSnapshot? licenseSnapshot,
    String? lastError,
    bool clearLastError = false,
    String? lastMessage,
    bool clearLastMessage = false,
  }) {
    return SyncState(
      isConfigured: isConfigured ?? this.isConfigured,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      pendingChanges: pendingChanges ?? this.pendingChanges,
      conflictCount: conflictCount ?? this.conflictCount,
      errorCount: errorCount ?? this.errorCount,
      remoteChanges: remoteChanges ?? this.remoteChanges,
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      cursor: cursor ?? this.cursor,
      deviceId: deviceId ?? this.deviceId,
      licenseSnapshot: licenseSnapshot ?? this.licenseSnapshot,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastMessage: clearLastMessage ? null : (lastMessage ?? this.lastMessage),
    );
  }

  SyncIndicatorState get indicator {
    if (!isConfigured) {
      return SyncIndicatorState.localOnly;
    }
    if (!isOnline) {
      return SyncIndicatorState.offline;
    }
    if (isSyncing) {
      return SyncIndicatorState.syncing;
    }
    if (lastError != null && lastError!.trim().isNotEmpty) {
      return SyncIndicatorState.error;
    }
    if (errorCount > 0 || conflictCount > 0) {
      return SyncIndicatorState.issues;
    }
    if (pendingChanges > 0) {
      return SyncIndicatorState.pending;
    }
    if (remoteChanges > 0) {
      return SyncIndicatorState.updatesAvailable;
    }
    return SyncIndicatorState.synced;
  }

  String get shortLabel {
    switch (indicator) {
      case SyncIndicatorState.localOnly:
        return 'Local Only';
      case SyncIndicatorState.offline:
        return 'Offline';
      case SyncIndicatorState.syncing:
        return 'Syncing';
      case SyncIndicatorState.error:
        return 'Sync Error';
      case SyncIndicatorState.issues:
        return 'Needs Review';
      case SyncIndicatorState.pending:
        return 'Pending Sync';
      case SyncIndicatorState.updatesAvailable:
        return 'Updates Ready';
      case SyncIndicatorState.synced:
        return 'Synced';
    }
  }
}

class SyncController extends Notifier<SyncState> {
  Timer? _timer;
  bool _initialized = false;
  bool _busy = false;

  @override
  SyncState build() {
    ref.onDispose(() => _timer?.cancel());

    ref.listen<AsyncValue<bool>>(connectivityServiceProvider, (previous, next) {
      final isOnline = next.valueOrNull ?? false;
      state = state.copyWith(isOnline: isOnline);
      if (!_initialized) {
        return;
      }

      if (!isOnline) {
        unawaited(refreshLocalState());
        return;
      }

      if (state.autoSyncEnabled) {
        unawaited(syncNow());
      } else {
        unawaited(refreshStatus());
      }
    });

    if (!_initialized) {
      _initialized = true;
      unawaited(_initialize());
    }

    final initialOnline =
        ref.read(connectivityServiceProvider).valueOrNull ?? false;
    return SyncState.initial(isOnline: initialOnline);
  }

  Future<void> _initialize() async {
    await SyncSettingsService.init();
    await LicenseService.init();
    state = state.copyWith(
      isConfigured: SyncSettingsService.isConfigured,
      autoSyncEnabled: SyncSettingsService.autoSyncEnabled,
      cursor: SyncSettingsService.syncCursor,
      deviceId: SyncSettingsService.deviceId,
      lastSyncAt: SyncSettingsService.lastSyncAt,
      licenseSnapshot: LicenseService.currentSnapshot,
    );
    _configureTimer();
    await refreshLocalState();
    if (state.isConfigured && state.isOnline) {
      if (state.autoSyncEnabled) {
        await syncNow();
      } else {
        await refreshStatus();
      }
    }
  }

  Future<void> reloadConfiguration({bool triggerSync = false}) async {
    await SyncSettingsService.init();
    await LicenseService.init();
    state = state.copyWith(
      isConfigured: SyncSettingsService.isConfigured,
      autoSyncEnabled: SyncSettingsService.autoSyncEnabled,
      cursor: SyncSettingsService.syncCursor,
      lastSyncAt: SyncSettingsService.lastSyncAt,
      deviceId: SyncSettingsService.deviceId,
      licenseSnapshot: LicenseService.currentSnapshot,
      clearLastError: !SyncSettingsService.isConfigured,
      clearLastMessage: !SyncSettingsService.isConfigured,
    );
    _configureTimer();
    await refreshLocalState();

    if (!state.isConfigured) {
      state = state.copyWith(
        remoteChanges: 0,
        clearLastSyncAt: true,
        cursor: SyncSettingsService.syncCursor,
      );
      return;
    }

    if (!state.isOnline) {
      return;
    }

    if (triggerSync && state.autoSyncEnabled) {
      await syncNow();
      return;
    }
    await refreshStatus();
  }

  Future<void> refreshLocalState() async {
    final snapshot = await SyncService.getLocalSnapshot();
    state = state.copyWith(
      pendingChanges: snapshot.pendingCount,
      conflictCount: snapshot.conflictCount,
      errorCount: snapshot.errorCount,
      cursor: SyncSettingsService.syncCursor,
      deviceId: SyncSettingsService.deviceId,
      lastSyncAt: SyncSettingsService.lastSyncAt,
      licenseSnapshot: LicenseService.currentSnapshot,
    );
  }

  Future<void> refreshStatus() async {
    await refreshLocalState();
    if (!state.isConfigured || !state.isOnline || _busy) {
      return;
    }

    try {
      final remote = await SyncService.fetchRemoteStatus();
      state = state.copyWith(
        remoteChanges: remote.changedCount,
        licenseSnapshot: LicenseService.currentSnapshot,
        clearLastError: true,
      );
    } catch (error) {
      state = state.copyWith(
        licenseSnapshot: LicenseService.currentSnapshot,
        lastError: '$error',
      );
    }
  }

  Future<bool> syncNow() async {
    if (_busy) {
      return false;
    }
    if (!state.isConfigured) {
      state = state.copyWith(
        lastError: 'Cloud sync is not configured for this app build.',
        remoteChanges: 0,
      );
      return false;
    }
    if (!state.isOnline) {
      state = state.copyWith(lastError: 'The device is offline.');
      return false;
    }

    _busy = true;
    state = state.copyWith(
      isSyncing: true,
      clearLastError: true,
      clearLastMessage: true,
    );

    try {
      final summary = await SyncService.syncNow();
      await _refreshSessionFromDatabase();
      await _invalidateVisibleData();

      final remote = await SyncService.fetchRemoteStatus();
      state = state.copyWith(
        isSyncing: false,
        pendingChanges: summary.localSnapshot.pendingCount,
        conflictCount: summary.localSnapshot.conflictCount,
        errorCount: summary.localSnapshot.errorCount,
        remoteChanges: remote.changedCount,
        lastSyncAt: SyncSettingsService.lastSyncAt,
        cursor: summary.nextCursor,
        deviceId: SyncSettingsService.deviceId,
        licenseSnapshot: LicenseService.currentSnapshot,
        lastMessage: _buildSuccessMessage(summary),
        clearLastError: true,
      );
      return true;
    } catch (error) {
      await refreshLocalState();
      state = state.copyWith(
        isSyncing: false,
        licenseSnapshot: LicenseService.currentSnapshot,
        lastError: '$error',
      );
      return false;
    } finally {
      _busy = false;
    }
  }

  void _configureTimer() {
    _timer?.cancel();
    if (!SyncSettingsService.autoSyncEnabled) {
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (_busy || !state.isConfigured) {
        return;
      }
      if (state.isOnline) {
        unawaited(syncNow());
      }
    });
  }

  Future<void> _invalidateVisibleData() async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(filteredProductsProvider);
    ref.invalidate(lowStockProductsProvider);
  }

  Future<void> _refreshSessionFromDatabase() async {
    final userId = SessionService.currentUserId;
    if (userId.isEmpty) {
      return;
    }

    final user = await DatabaseService.queryById('users', userId);
    if (user == null) {
      return;
    }

    await SessionService.updateName(user['name'] as String? ?? '');
    await SessionService.updateRole(user['role'] as String? ?? '');
  }

  String _buildSuccessMessage(SyncRunSummary summary) {
    final parts = <String>[];
    if (summary.pushedCount > 0) {
      parts.add('Uploaded ${summary.pushedCount} change(s)');
    }
    if (summary.pulledCount > 0) {
      parts.add('Applied ${summary.pulledCount} cloud update(s)');
    }
    if (summary.resolvedConflictCount > 0) {
      parts.add('Resolved ${summary.resolvedConflictCount} conflict(s)');
    }
    if (summary.errorCount > 0) {
      parts.add('${summary.errorCount} item(s) need attention');
    }
    if (parts.isEmpty) {
      return 'Everything is already up to date.';
    }
    return '${parts.join('; ')}.';
  }
}
