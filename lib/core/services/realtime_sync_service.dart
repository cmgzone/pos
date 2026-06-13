import 'package:socket_io_client/socket_io_client.dart' as socket_io;

import 'license_service.dart';

class RealtimeSyncChange {
  final String? sourceDeviceId;
  final String reason;
  final List<String> tables;
  final DateTime? serverTime;

  const RealtimeSyncChange({
    required this.sourceDeviceId,
    required this.reason,
    required this.tables,
    required this.serverTime,
  });

  factory RealtimeSyncChange.fromPayload(Object? payload) {
    if (payload is! Map) {
      return const RealtimeSyncChange(
        sourceDeviceId: null,
        reason: 'sync',
        tables: <String>[],
        serverTime: null,
      );
    }

    final tables = <String>[];
    final rawTables = payload['tables'];
    if (rawTables is List) {
      for (final table in rawTables) {
        final clean = table?.toString().trim();
        if (clean != null && clean.isNotEmpty && !tables.contains(clean)) {
          tables.add(clean);
        }
      }
    }

    return RealtimeSyncChange(
      sourceDeviceId: _readText(payload['sourceDeviceId']),
      reason: _readText(payload['reason']) ?? 'sync',
      tables: tables,
      serverTime: DateTime.tryParse(_readText(payload['serverTime']) ?? ''),
    );
  }

  bool get affectsCatalogOrders => tables.contains('public_catalog_orders');

  static String? _readText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

class RealtimeSyncService {
  static socket_io.Socket? _socket;
  static String? _connectionKey;
  static void Function(RealtimeSyncChange change)? _onRemoteChange;

  static bool get isConnected => _socket?.connected == true;

  static void configure({
    required String backendUrl,
    required String? deviceId,
    required LicenseSnapshot licenseSnapshot,
    required void Function(RealtimeSyncChange change) onRemoteChange,
  }) {
    final accessToken = licenseSnapshot.accessToken?.trim() ?? '';
    final cleanDeviceId = deviceId?.trim() ?? '';
    final realtimeUrl = _realtimeBaseUrl(backendUrl);
    if (realtimeUrl.isEmpty || accessToken.isEmpty || cleanDeviceId.isEmpty) {
      disconnect();
      return;
    }

    _onRemoteChange = onRemoteChange;
    final nextKey =
        '$realtimeUrl|${licenseSnapshot.businessId ?? ''}|$cleanDeviceId|$accessToken';
    final existing = _socket;
    if (existing != null && _connectionKey == nextKey) {
      if (!existing.connected) {
        existing.connect();
      }
      return;
    }

    disconnect();
    _connectionKey = nextKey;
    final socket = socket_io.io(realtimeUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionDelay': 2000,
      'auth': <String, dynamic>{
        'accessToken': accessToken,
        'deviceId': cleanDeviceId,
      },
      'query': <String, dynamic>{'deviceId': cleanDeviceId},
    });

    socket.on('sync:changed', (payload) {
      _onRemoteChange?.call(RealtimeSyncChange.fromPayload(payload));
    });
    socket.connect();
    _socket = socket;
  }

  static void disconnect() {
    final socket = _socket;
    _socket = null;
    _connectionKey = null;
    _onRemoteChange = null;
    if (socket == null) {
      return;
    }
    socket
      ..clearListeners()
      ..disconnect()
      ..dispose();
  }

  static String _realtimeBaseUrl(String backendUrl) {
    final trimmed = backendUrl.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return trimmed.replaceFirst(RegExp(r'/api/?$'), '');
    }

    final segments = uri.pathSegments
        .where((segment) => segment.trim().isNotEmpty)
        .toList();
    if (segments.isNotEmpty && segments.last.toLowerCase() == 'api') {
      segments.removeLast();
    }

    return uri
        .replace(
          path: segments.isEmpty ? '' : '/${segments.join('/')}',
          query: null,
          fragment: null,
        )
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }
}
