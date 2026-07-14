import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';
import '../../sales/data/held_sale_repository.dart';
import '../../sales/data/sale_repository.dart';

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
             o.guest_count, o.items_json, o.subtotal, o.total, o.split_count,
             o.opened_at, o.notes AS order_notes
      FROM $tablesTable t
      LEFT JOIN $ordersTable o ON o.id = t.current_order_id AND o.deleted_at IS NULL
      WHERE t.deleted_at IS NULL AND COALESCE(t.branch_id, ?) = ?
      ORDER BY COALESCE(t.area, ''), t.name
      ''', _branchArgs);
    return rows.map(_decodeOrder).toList();
  }

  static Future<Map<String, dynamic>?> getTable(String tableId) async {
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT t.*, o.id AS order_id, o.order_no, o.status AS order_status,
             o.guest_count, o.items_json, o.subtotal, o.total, o.split_count,
             o.opened_at, o.notes AS order_notes
      FROM $tablesTable t
      LEFT JOIN $ordersTable o ON o.id = t.current_order_id AND o.deleted_at IS NULL
      WHERE t.id = ? AND t.deleted_at IS NULL
        AND COALESCE(t.branch_id, ?) = ?
      LIMIT 1
      ''',
      [tableId, ..._branchArgs],
    );
    return rows.isEmpty ? null : _decodeOrder(rows.first);
  }

  /// The restaurant has a deliberately curated menu surface. Retail catalog
  /// rows are never returned unless they were explicitly enabled for the
  /// restaurant, and variant parents are excluded until modifier support is
  /// available in the restaurant ordering flow.
  static Future<List<Map<String, dynamic>>> getMenuItems() {
    return DatabaseService.rawQuery('''
      SELECT p.*, c.name AS category_name, c.color AS category_color
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id AND c.deleted_at IS NULL
      WHERE p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND COALESCE(p.is_restaurant_menu, 0) = 1
        AND COALESCE(p.has_variants, 0) = 0
      ORDER BY
        CASE WHEN c.name IS NULL OR TRIM(c.name) = '' THEN 1 ELSE 0 END,
        c.name COLLATE NOCASE,
        p.name COLLATE NOCASE
      ''', _branchArgs);
  }

  static Future<String> createMenuItem({
    required String name,
    required double price,
    String? section,
  }) async {
    await _ensureWriteAccess('create restaurant menu items');
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw Exception('Menu item name is required.');
    if (price < 0) throw Exception('Price cannot be negative.');

    final now = DateTime.now().toIso8601String();
    final itemId = _uuid.v4();
    final cleanSection = _clean(section);
    String? categoryId;

    await DatabaseService.db.transaction((txn) async {
      if (cleanSection != null) {
        final matches = await txn.rawQuery(
          '''
          SELECT id FROM categories
          WHERE deleted_at IS NULL
            AND COALESCE(branch_id, ?) = ?
            AND LOWER(TRIM(name)) = LOWER(?)
          LIMIT 1
          ''',
          [..._branchArgs, cleanSection],
        );
        if (matches.isNotEmpty) {
          categoryId = matches.first['id'] as String?;
        } else {
          categoryId = _uuid.v4();
          await txn.insert('categories', {
            'id': categoryId,
            'branch_id': DatabaseService.currentBranchId,
            'name': cleanSection,
            'created_at': now,
            'updated_at': now,
            'sync_status': 'pending',
          });
        }
      }

      await txn.insert('products', {
        'id': itemId,
        'branch_id': DatabaseService.currentBranchId,
        'name': cleanName,
        'price': price,
        'cost': 0,
        'stock': 0,
        'low_stock': 0,
        'unit': 'item',
        'stock_unit': 'item',
        'sale_unit': 'item',
        'sale_to_stock_factor': 1,
        'purchase_unit': 'item',
        'purchase_to_stock_factor': 1,
        'show_online': 0,
        'is_featured': 0,
        'is_restaurant_menu': 1,
        'category_id': categoryId,
        'track_stock': 0,
        'has_variants': 0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
    });
    DatabaseService.notifyLocalChange();
    await AuditLogService.log(
      action: 'create',
      entityTable: 'products',
      entityId: itemId,
    );
    return itemId;
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
    DatabaseService.notifyLocalChange();
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
    final productId = product['id']?.toString() ?? '';
    final menuRows = await DatabaseService.rawQuery(
      '''
      SELECT p.*, c.name AS category_name
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id AND c.deleted_at IS NULL
      WHERE p.id = ? AND p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND COALESCE(p.is_restaurant_menu, 0) = 1
        AND COALESCE(p.has_variants, 0) = 0
      LIMIT 1
      ''',
      [productId, ..._branchArgs],
    );
    if (menuRows.isEmpty) {
      throw Exception('This item is not available on the restaurant menu.');
    }
    final menuItem = menuRows.first;
    final rows = await DatabaseService.rawQuery(
      'SELECT * FROM $ordersTable WHERE id = ? AND deleted_at IS NULL LIMIT 1',
      [orderId],
    );
    if (rows.isEmpty) throw Exception('Table order not found.');
    final order = _decodeOrder(rows.first);
    final items = List<Map<String, dynamic>>.from(
      order['items'] as List<dynamic>,
    );
    final index = items.indexWhere(
      (item) => item['product_id'] == productId && item['status'] == 'draft',
    );
    if (index >= 0) {
      items[index]['quantity'] =
          ((items[index]['quantity'] as num?)?.toDouble() ?? 0) + 1;
    } else {
      items.add({
        'id': _uuid.v4(),
        'product_id': productId,
        'product_name': menuItem['name'],
        'menu_section': menuItem['category_name'],
        'quantity': 1.0,
        'unit_price': (menuItem['price'] as num? ?? 0).toDouble(),
        'cost': (menuItem['cost'] as num? ?? 0).toDouble(),
        'unit': menuItem['unit'] ?? 'pcs',
        'status': 'draft',
      });
    }
    await _saveItems(order, items, now);
  }

  static Future<void> updateItemQuantity({
    required String orderId,
    required String itemId,
    required double quantity,
  }) async {
    await _ensureWriteAccess('edit table orders');
    final order = await _getOrder(orderId);
    final items = List<Map<String, dynamic>>.from(
      order['items'] as List<dynamic>,
    );
    final index = items.indexWhere((item) => item['id'] == itemId);
    if (index < 0) return;
    if (items[index]['status'] != 'draft') {
      throw Exception('Sent kitchen items cannot be changed.');
    }
    if (quantity <= 0) {
      items.removeAt(index);
    } else {
      items[index]['quantity'] = quantity.clamp(0.001, 999);
    }
    await _saveItems(order, items, DateTime.now().toIso8601String());
  }

  static Future<int> sendToKitchen(String orderId) async {
    await _ensureWriteAccess('send orders to the kitchen');
    final order = await _getOrder(orderId);
    final items = List<Map<String, dynamic>>.from(
      order['items'] as List<dynamic>,
    );
    var sent = 0;
    final now = DateTime.now().toIso8601String();
    for (final item in items) {
      if (item['status'] == 'draft') {
        item['status'] = 'pending';
        item['sent_at'] = now;
        sent += 1;
      }
    }
    if (sent == 0) return 0;
    await _saveItems(order, items, now);
    return sent;
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

  static Future<List<String>> prepareBill({
    required Map<String, dynamic> table,
    int splitCount = 1,
  }) async {
    await _ensureWriteAccess('prepare table bills');
    final orderId = table['order_id'] as String? ?? '';
    final tableId = table['id'] as String? ?? '';
    final items = List<Map<String, dynamic>>.from(
      table['items'] as List<dynamic>? ?? const [],
    );
    if (orderId.isEmpty || items.isEmpty) {
      throw Exception('Add at least one item before checkout.');
    }
    final parts = splitCount.clamp(1, 20);

    // Idempotency: a bill that was already prepared is returned as-is so
    // repeated taps (or retries after a transient error) never duplicate bills.
    final existing = await HeldSaleRepository.existingRestaurantHoldIds(
      orderId,
    );
    if (existing.isNotEmpty) return existing;

    final holdIds = <String>[];
    final now = DateTime.now().toIso8601String();

    await DatabaseService.db.transaction((txn) async {
      // Re-check inside the transaction so concurrent double-sends can't both
      // create bills for the same order.
      final orderRows = await txn.query(
        ordersTable,
        columns: const ['status'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [orderId],
        limit: 1,
      );
      if (orderRows.isEmpty) throw Exception('Table order not found.');
      if ((orderRows.first['status'] as String? ?? '') == 'checkout') {
        return; // another caller already prepared this order
      }

      for (var part = 0; part < parts; part++) {
        final billItems = items
            .map(
              (item) => {
                ...item,
                'quantity':
                    ((item['quantity'] as num?)?.toDouble() ?? 0) / parts,
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
        final holdId = await HeldSaleRepository.createHold(
          name: '${table['name']} · Bill ${part + 1}/$parts',
          subtotal: total,
          tax: 0,
          discount: 0,
          total: total,
          userId: SessionService.currentUserId,
          cashierName: SessionService.currentUserName,
          items: billItems,
          source: 'restaurant',
          sourceRef: orderId,
          txn: txn,
        );
        holdIds.add(holdId);
      }

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
        whereArgs: [tableId],
      );
    });

    // If the in-transaction guard bailed out (another caller won the race),
    // return the bills that caller created.
    if (holdIds.isEmpty) {
      final fallback = await HeldSaleRepository.existingRestaurantHoldIds(
        orderId,
      );
      if (fallback.isNotEmpty) return fallback;
    }
    DatabaseService.notifyLocalChange();
    return holdIds;
  }

  /// Restaurant bills waiting for payment, isolated from retail held sales.
  static Future<List<Map<String, dynamic>>> getBills() =>
      HeldSaleRepository.getRestaurantBills();

  static Future<Map<String, dynamic>?> getBill(String holdId) =>
      HeldSaleRepository.takeHold(holdId);

  static Future<String> payBill({
    required String holdId,
    required String paymentType,
    required bool isCashDrawer,
    String? shiftId,
    double? amountTendered,
    double? changeGiven,
    String? customerId,
    String? customerName,
    String? dueDate,
    String? paymentProvider,
    String? paymentReference,
    String? paymentStatus,
    Map<String, dynamic>? paymentMetadata,
  }) async {
    await _ensureWriteAccess('take restaurant payments');
    final bill = await HeldSaleRepository.takeHold(holdId);
    if (bill == null || bill['source'] != 'restaurant') {
      throw Exception('Restaurant bill not found.');
    }
    final orderId = bill['source_ref']?.toString() ?? '';
    final items = List<Map<String, dynamic>>.from(
      bill['items'] as List<dynamic>? ?? const [],
    );
    if (items.isEmpty) throw Exception('This bill has no payable items.');

    final saleItems = items
        .map(
          (item) => <String, dynamic>{
            ...item,
            'line_type': item['line_type'] ?? 'product',
            'unit_cost': item['unit_cost'] ?? item['cost'] ?? 0,
          },
        )
        .toList(growable: false);
    final saleId = await SaleRepository.createSale(
      totalAmount: (bill['total'] as num? ?? 0).toDouble(),
      tax: (bill['tax'] as num? ?? 0).toDouble(),
      discount: (bill['discount'] as num? ?? 0).toDouble(),
      paymentType: paymentType,
      isCashDrawer: isCashDrawer,
      userId: SessionService.currentUserId.isEmpty
          ? 'admin'
          : SessionService.currentUserId,
      shiftId: shiftId,
      items: saleItems,
      amountTendered: amountTendered,
      changeGiven: changeGiven,
      customerId: customerId,
      customerName: customerName,
      dueDate: dueDate,
      paymentProvider: paymentProvider,
      paymentReference: paymentReference,
      paymentStatus: paymentStatus,
      paymentMetadata: {
        if (paymentMetadata != null) ...paymentMetadata,
        'source': 'restaurant',
        'restaurantBillId': holdId,
        if (orderId.isNotEmpty) 'restaurantOrderId': orderId,
      },
    );

    await HeldSaleRepository.deleteHold(holdId);
    if (orderId.isNotEmpty) {
      final remaining = await HeldSaleRepository.existingRestaurantHoldIds(
        orderId,
      );
      if (remaining.isEmpty) {
        final now = DateTime.now().toIso8601String();
        await DatabaseService.db.transaction((txn) async {
          await txn.update(
            ordersTable,
            {
              'status': 'closed',
              'closed_at': now,
              'updated_at': now,
              'sync_status': 'pending',
            },
            where: 'id = ? AND deleted_at IS NULL',
            whereArgs: [orderId],
          );
          await txn.update(
            tablesTable,
            {
              'status': 'available',
              'current_order_id': null,
              'updated_at': now,
              'sync_status': 'pending',
            },
            where: 'current_order_id = ? AND deleted_at IS NULL',
            whereArgs: [orderId],
          );
        });
        DatabaseService.notifyLocalChange();
      }
    }
    await AuditLogService.log(
      action: 'pay',
      entityTable: ordersTable,
      entityId: orderId.isEmpty ? null : orderId,
    );
    return saleId;
  }

  static Future<Map<String, dynamic>> _getOrder(String orderId) async {
    final rows = await DatabaseService.rawQuery(
      'SELECT * FROM $ordersTable WHERE id = ? AND deleted_at IS NULL LIMIT 1',
      [orderId],
    );
    if (rows.isEmpty) throw Exception('Table order not found.');
    return _decodeOrder(rows.first);
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
