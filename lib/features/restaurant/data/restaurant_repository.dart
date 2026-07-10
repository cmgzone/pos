import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../sales/data/held_sale_repository.dart';

const _uuid = Uuid();

class RestaurantRepository {
  static const tablesTable = 'restaurant_tables';
  static const ordersTable = 'table_orders';

  static List<dynamic> get _branchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<List<Map<String, dynamic>>> getTables() async {
    final rows = await DatabaseService.rawQuery('''
      SELECT t.*, o.id AS order_id, o.order_no, o.status AS order_status,
             o.guest_count, o.items_json, o.total, o.split_count
      FROM $tablesTable t
      LEFT JOIN $ordersTable o ON o.id = t.current_order_id AND o.deleted_at IS NULL
      WHERE t.deleted_at IS NULL AND COALESCE(t.branch_id, ?) = ?
      ORDER BY COALESCE(t.area, ''), t.name
      ''', _branchArgs);
    return rows.map(_decodeOrder).toList();
  }

  static Future<String> addTable({
    required String name,
    String? area,
    int seats = 2,
  }) async {
    await _ensureWriteAccess('manage restaurant tables');
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw Exception('Table name is required.');
    final now = DateTime.now().toIso8601String();
    final id = _uuid.v4();
    await DatabaseService.insert(tablesTable, {
      'id': id,
      'branch_id': DatabaseService.currentBranchId,
      'name': cleanName,
      'area': _clean(area),
      'seats': seats.clamp(1, 50),
      'status': 'available',
      'position_x': 0,
      'position_y': 0,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    await AuditLogService.log(
      action: 'create',
      entityTable: tablesTable,
      entityId: id,
    );
    return id;
  }

  static Future<String> openOrder({
    required String tableId,
    int guests = 1,
  }) async {
    await _ensureWriteAccess('open table orders');
    final now = DateTime.now().toIso8601String();
    final orderId = _uuid.v4();
    final orderNo =
        'T${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    await DatabaseService.db.transaction((txn) async {
      final table = await txn.query(
        tablesTable,
        where: 'id = ? AND deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
        whereArgs: [tableId, ..._branchArgs],
        limit: 1,
      );
      if (table.isEmpty) {
        throw Exception('Table not found.');
      }
      if ((table.first['current_order_id'] as String? ?? '').isNotEmpty) {
        throw Exception('This table already has an open order.');
      }
      await txn.insert(ordersTable, {
        'id': orderId,
        'branch_id': DatabaseService.currentBranchId,
        'table_id': tableId,
        'order_no': orderNo,
        'status': 'open',
        'guest_count': guests.clamp(1, 50),
        'items_json': '[]',
        'subtotal': 0,
        'tax': 0,
        'discount': 0,
        'total': 0,
        'split_count': 1,
        'opened_by': SessionService.currentUserId,
        'opened_at': now,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
      await txn.update(
        tablesTable,
        {
          'status': 'occupied',
          'current_order_id': orderId,
          'updated_at': now,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [tableId],
      );
    });
    await AuditLogService.log(
      action: 'open',
      entityTable: ordersTable,
      entityId: orderId,
    );
    return orderId;
  }

  static Future<void> addProduct({
    required String orderId,
    required Map<String, dynamic> product,
  }) async {
    await _ensureWriteAccess('edit table orders');
    final now = DateTime.now().toIso8601String();
    final rows = await DatabaseService.rawQuery(
      'SELECT * FROM $ordersTable WHERE id = ? AND deleted_at IS NULL LIMIT 1',
      [orderId],
    );
    if (rows.isEmpty) throw Exception('Table order not found.');
    final order = _decodeOrder(rows.first);
    final items = List<Map<String, dynamic>>.from(
      order['items'] as List<dynamic>,
    );
    final productId = product['id'] as String;
    final index = items.indexWhere(
      (item) => item['product_id'] == productId && item['status'] == 'pending',
    );
    if (index >= 0) {
      items[index]['quantity'] =
          ((items[index]['quantity'] as num?)?.toDouble() ?? 0) + 1;
    } else {
      items.add({
        'id': _uuid.v4(),
        'product_id': productId,
        'product_name': product['name'],
        'quantity': 1.0,
        'unit_price': (product['price'] as num? ?? 0).toDouble(),
        'cost': (product['cost'] as num? ?? 0).toDouble(),
        'unit': product['unit'] ?? 'pcs',
        'status': 'pending',
      });
    }
    await _saveItems(order, items, now);
  }

  static Future<void> updateKitchenStatus({
    required String orderId,
    required String itemId,
    required String status,
  }) async {
    const allowed = {'pending', 'preparing', 'ready', 'served'};
    if (!allowed.contains(status)) throw Exception('Invalid kitchen status.');
    final now = DateTime.now().toIso8601String();
    final rows = await DatabaseService.rawQuery(
      'SELECT * FROM $ordersTable WHERE id = ? AND deleted_at IS NULL LIMIT 1',
      [orderId],
    );
    if (rows.isEmpty) return;
    final order = _decodeOrder(rows.first);
    final items = List<Map<String, dynamic>>.from(
      order['items'] as List<dynamic>,
    );
    final index = items.indexWhere((item) => item['id'] == itemId);
    if (index < 0) return;
    items[index]['status'] = status;
    await _saveItems(order, items, now);
  }

  static Future<List<String>> sendToPos({
    required Map<String, dynamic> table,
    int splitCount = 1,
  }) async {
    await _ensureWriteAccess('send table bills to POS');
    final orderId = table['order_id'] as String? ?? '';
    final items = List<Map<String, dynamic>>.from(
      table['items'] as List<dynamic>? ?? const [],
    );
    if (orderId.isEmpty || items.isEmpty) {
      throw Exception('Add at least one item before checkout.');
    }
    final parts = splitCount.clamp(1, 20);
    final holdIds = <String>[];
    for (var part = 0; part < parts; part++) {
      final billItems = items
          .map(
            (item) => {
              ...item,
              'quantity': ((item['quantity'] as num?)?.toDouble() ?? 0) / parts,
            },
          )
          .where((item) => (item['quantity'] as num) > 0.001)
          .toList();
      final total = billItems.fold<double>(
        0,
        (sum, item) =>
            sum +
            (item['quantity'] as num).toDouble() *
                ((item['unit_price'] as num?)?.toDouble() ?? 0),
      );
      holdIds.add(
        await HeldSaleRepository.createHold(
          name: '${table['name']} · Bill ${part + 1}/$parts',
          subtotal: total,
          tax: 0,
          discount: 0,
          total: total,
          userId: SessionService.currentUserId,
          cashierName: SessionService.currentUserName,
          items: billItems,
        ),
      );
    }
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.transaction((txn) async {
      await txn.update(
        ordersTable,
        {
          'status': 'checkout',
          'split_count': parts,
          'updated_at': now,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
      await txn.update(
        tablesTable,
        {'status': 'checkout', 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [table['id']],
      );
    });
    return holdIds;
  }

  static Future<void> _saveItems(
    Map<String, dynamic> order,
    List<Map<String, dynamic>> items,
    String now,
  ) async {
    final subtotal = items.fold<double>(
      0,
      (sum, item) =>
          sum +
          ((item['quantity'] as num?)?.toDouble() ?? 0) *
              ((item['unit_price'] as num?)?.toDouble() ?? 0),
    );
    await DatabaseService.update(ordersTable, {
      'items_json': jsonEncode(items),
      'subtotal': subtotal,
      'total': subtotal,
      'updated_at': now,
      'sync_status': 'pending',
    }, order['id'] as String);
  }

  static Map<String, dynamic> _decodeOrder(Map<String, dynamic> row) {
    final raw = row['items_json']?.toString() ?? '[]';
    List<dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      decoded = const [];
    }
    return {
      ...row,
      'items': decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(),
    };
  }

  static Future<void> _ensureWriteAccess(String action) async {
    if (!SessionService.canAccessFeature(
      UserAccessProfile.featureRestaurantMode,
    )) {
      throw Exception('Your account cannot $action.');
    }
    await LicenseService.ensureWriteAccess(action: action);
    await LicenseService.ensureFeatureAccess(
      featureKey: UserAccessProfile.featureRestaurantMode,
      action: action,
    );
  }

  static String? _clean(String? value) {
    final clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }
}
