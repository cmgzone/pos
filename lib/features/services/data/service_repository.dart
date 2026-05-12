import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/services/audit_log_service.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';
import '../../../core/services/session_service.dart';

const _uuid = Uuid();

class ServiceRepository {
  static const _servicesTable = 'services';
  static const _fieldsTable = 'service_fields';
  static const _ordersTable = 'service_orders';
  static const _valuesTable = 'service_field_values';

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<void> _ensureServiceWriteAccess(String action) async {
    await LicenseService.ensureWriteAccess(action: action);
    await LicenseService.ensureFeatureAccess(
      featureKey: 'services',
      action: action,
    );
  }

  static Future<List<Map<String, dynamic>>> getServices({
    bool activeOnly = false,
    String query = '',
  }) async {
    final clauses = <String>[
      "deleted_at IS NULL",
      'COALESCE(branch_id, ?) = ?',
    ];
    final args = <dynamic>[..._currentBranchArgs];
    if (activeOnly) {
      clauses.add('is_active = 1');
    }
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      clauses.add('(name LIKE ? OR category LIKE ? OR description LIKE ?)');
      final pattern = '%$trimmed%';
      args.addAll([pattern, pattern, pattern]);
    }
    final accessClause = _serviceAccessClause('id', args);
    if (accessClause != null) {
      clauses.add(accessClause);
    }

    return DatabaseService.rawQuery('''
      SELECT *
      FROM $_servicesTable
      WHERE ${clauses.join(' AND ')}
      ORDER BY is_active DESC, name COLLATE NOCASE ASC
      ''', args);
  }

  static Future<Map<String, dynamic>?> getServiceById(String id) async {
    if (!SessionService.canAccessServiceId(id)) {
      return null;
    }
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM $_servicesTable
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [id, ..._currentBranchArgs],
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, dynamic>>> getFieldsForService(
    String serviceId,
  ) async {
    if (!SessionService.canAccessServiceId(serviceId)) {
      return const [];
    }
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM $_fieldsTable
      WHERE service_id = ? AND deleted_at IS NULL
      ORDER BY sort_order ASC, created_at ASC
      ''',
      [serviceId],
    );

    return rows.map(_decodeFieldOptions).toList();
  }

  static Future<String> createService({
    required String name,
    String? category,
    String? description,
    double basePrice = 0,
    int? durationMinutes,
    bool isActive = true,
    List<Map<String, dynamic>> fields = const [],
  }) async {
    await _ensureServiceWriteAccess('create services');
    final serviceId = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    await DatabaseService.db.transaction((txn) async {
      await txn.insert(_servicesTable, {
        'id': serviceId,
        'branch_id': DatabaseService.currentBranchId,
        'name': name.trim(),
        'category': _clean(category),
        'description': _clean(description),
        'base_price': basePrice,
        'duration_minutes': durationMinutes,
        'is_active': isActive ? 1 : 0,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      for (var index = 0; index < fields.length; index++) {
        final field = fields[index];
        await txn.insert(_fieldsTable, {
          'id': _uuid.v4(),
          'service_id': serviceId,
          'label': (field['label'] as String? ?? '').trim(),
          'field_type': (field['field_type'] as String? ?? 'text').trim(),
          'options_json': _encodeOptions(field['options']),
          'price_map_json': _buildPriceMapJson(field),
          'is_required': _asBool(field['is_required']) ? 1 : 0,
          'sort_order': field['sort_order'] ?? index,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });
      }
    });

    await AuditLogService.log(
      action: 'create',
      entityTable: _servicesTable,
      entityId: serviceId,
    );
    return serviceId;
  }

  static Future<void> updateService({
    required String id,
    required String name,
    String? category,
    String? description,
    double basePrice = 0,
    int? durationMinutes,
    bool isActive = true,
    List<Map<String, dynamic>> fields = const [],
  }) async {
    await _ensureServiceWriteAccess('update services');
    final now = DateTime.now().toIso8601String();

    await DatabaseService.db.transaction((txn) async {
      await txn.update(
        _servicesTable,
        {
          'name': name.trim(),
          'category': _clean(category),
          'description': _clean(description),
          'base_price': basePrice,
          'duration_minutes': durationMinutes,
          'is_active': isActive ? 1 : 0,
          'updated_at': now,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      await txn.update(
        _fieldsTable,
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'service_id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );

      for (var index = 0; index < fields.length; index++) {
        final field = fields[index];
        await txn.insert(_fieldsTable, {
          'id': _uuid.v4(),
          'service_id': id,
          'label': (field['label'] as String? ?? '').trim(),
          'field_type': (field['field_type'] as String? ?? 'text').trim(),
          'options_json': _encodeOptions(field['options']),
          'price_map_json': _buildPriceMapJson(field),
          'is_required': _asBool(field['is_required']) ? 1 : 0,
          'sort_order': field['sort_order'] ?? index,
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });
      }
    });
    await AuditLogService.log(
      action: 'update',
      entityTable: _servicesTable,
      entityId: id,
    );
  }

  static Future<void> deleteService(String id) async {
    await _ensureServiceWriteAccess('delete services');
    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.transaction((txn) async {
      await txn.update(
        _servicesTable,
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        _fieldsTable,
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'service_id = ? AND deleted_at IS NULL',
        whereArgs: [id],
      );
    });
    await AuditLogService.log(
      action: 'delete',
      entityTable: _servicesTable,
      entityId: id,
    );
  }

  static Future<List<Map<String, dynamic>>> getOrders({
    String filter = 'active',
  }) async {
    final clauses = <String>[
      'so.deleted_at IS NULL',
      'COALESCE(so.branch_id, ?) = ?',
    ];
    final args = <dynamic>[..._currentBranchArgs];
    switch (filter) {
      case 'today':
        clauses.add("so.status NOT IN ('paid', 'cancelled')");
        clauses.add('''
          (
            so.entry_mode <> 'appointment'
            OR date(so.scheduled_at) <= date('now', 'localtime')
            OR so.status IN ('checked_in', 'in_progress', 'ready', 'completed')
            OR date(COALESCE(so.checked_in_at, so.created_at)) = date('now', 'localtime')
            OR (so.entry_mode = 'appointment' AND date(so.scheduled_at) = date('now', 'localtime'))
          )
          ''');
        break;
      case 'active':
        clauses.add("so.status NOT IN ('paid', 'cancelled')");
        break;
      case 'appointments':
        clauses.add("so.entry_mode = 'appointment'");
        break;
      case 'walk_in':
        clauses.add("so.entry_mode = 'walk_in'");
        break;
    }
    final accessClause = _serviceAccessClause('so.service_id', args);
    if (accessClause != null) {
      clauses.add(accessClause);
    }
    final assignmentClause = _serviceOrderAssignmentClause('so', args);
    if (assignmentClause != null) {
      clauses.add(assignmentClause);
    }

    return DatabaseService.rawQuery('''
      SELECT
        so.*,
        s.category AS service_category,
        s.duration_minutes AS service_duration_minutes
      FROM $_ordersTable so
      LEFT JOIN $_servicesTable s ON s.id = so.service_id
      WHERE ${clauses.join(' AND ')}
      ORDER BY
        CASE so.status
          WHEN 'booked' THEN 0
          WHEN 'checked_in' THEN 1
          WHEN 'in_progress' THEN 2
          WHEN 'ready' THEN 3
          WHEN 'completed' THEN 4
          WHEN 'paid' THEN 5
          ELSE 6
        END,
        CASE
          WHEN so.scheduled_at IS NULL OR TRIM(so.scheduled_at) = '' THEN 1
          ELSE 0
        END ASC,
        so.scheduled_at ASC,
        so.created_at DESC
      ''', args);
  }

  static Future<Map<String, dynamic>?> getOrderById(String orderId) async {
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM $_ordersTable
      WHERE id = ?
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      LIMIT 1
      ''',
      [orderId, ..._currentBranchArgs],
    );
    if (rows.isEmpty) {
      return null;
    }

    final order = rows.first;
    if (!_canAccessServiceOrder(order)) {
      return null;
    }
    final values = await DatabaseService.rawQuery(
      '''
      SELECT *
      FROM $_valuesTable
      WHERE service_order_id = ? AND deleted_at IS NULL
      ORDER BY created_at ASC
      ''',
      [orderId],
    );
    return {...order, 'field_values': values};
  }

  static Future<String> createOrder({
    required String serviceId,
    required String serviceName,
    String? customerId,
    String? customerName,
    required String entryMode,
    String? scheduledAt,
    String? checkedInAt,
    String status = 'booked',
    String? assignedStaff,
    String? assignedStaffUserId,
    String? bayNumber,
    double? price,
    String? note,
    List<Map<String, dynamic>> fieldValues = const [],
  }) async {
    await _ensureServiceWriteAccess('create service orders');
    if (!SessionService.canAccessServiceId(serviceId)) {
      throw Exception(
        'This account is not allowed to create orders for that service.',
      );
    }
    final orderId = _uuid.v4();
    final now = DateTime.now().toIso8601String();

    final service = await getServiceById(serviceId);
    final effectivePrice =
        price ?? (service?['base_price'] as num? ?? 0).toDouble();

    await DatabaseService.db.transaction((txn) async {
      await txn.insert(_ordersTable, {
        'id': orderId,
        'branch_id': DatabaseService.currentBranchId,
        'service_id': serviceId,
        'service_name': serviceName.trim(),
        'customer_id': _clean(customerId),
        'customer_name': _clean(customerName),
        'entry_mode': entryMode,
        'scheduled_at': _clean(scheduledAt),
        'checked_in_at': _clean(checkedInAt),
        'status': status,
        'assigned_staff': _clean(assignedStaff),
        'assigned_staff_user_id': _clean(assignedStaffUserId),
        'bay_number': _clean(bayNumber),
        'price': effectivePrice,
        'note': _clean(note),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });

      for (final field in fieldValues) {
        await txn.insert(_valuesTable, {
          'id': _uuid.v4(),
          'service_order_id': orderId,
          'field_id': field['field_id'],
          'field_label': field['field_label'],
          'field_type': field['field_type'],
          'value_text': _clean(field['value_text']),
          'created_at': now,
          'updated_at': now,
          'sync_status': 'pending',
        });
      }
    });

    await AuditLogService.log(
      action: 'create',
      entityTable: _ordersTable,
      entityId: orderId,
    );
    return orderId;
  }

  static Future<void> updateOrderBay(String orderId, String? bayNumber) async {
    await _ensureServiceWriteAccess('update service orders');
    final order = await getOrderById(orderId);
    if (order == null) {
      throw Exception('Service order not found or access denied.');
    }
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update(_ordersTable, {
      'bay_number': bayNumber,
      'updated_at': now,
      'sync_status': 'pending',
    }, orderId);
  }

  static Future<void> updateOrderStatus(String orderId, String status) async {
    await _ensureServiceWriteAccess('update service orders');
    final order = await getOrderById(orderId);
    if (order == null) {
      throw Exception('Service order not found or access denied.');
    }
    final now = DateTime.now().toIso8601String();
    final payload = <String, dynamic>{
      'status': status,
      'updated_at': now,
      'sync_status': 'pending',
    };
    if (status == 'checked_in') {
      payload['checked_in_at'] = now;
    }
    await DatabaseService.update(_ordersTable, payload, orderId);
  }

  static Future<void> deleteOrder(String orderId) async {
    await _ensureServiceWriteAccess('delete service orders');
    final order = await getOrderById(orderId);
    if (order == null) {
      throw Exception('Service order not found or access denied.');
    }
    final saleId = _clean(order['sale_id'] as String?);
    if (saleId != null) {
      throw Exception('Delete the linked sale before deleting this order.');
    }

    final now = DateTime.now().toIso8601String();
    await DatabaseService.db.transaction((txn) async {
      await txn.update(
        _ordersTable,
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [orderId],
      );
      await txn.update(
        _valuesTable,
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'service_order_id = ? AND deleted_at IS NULL',
        whereArgs: [orderId],
      );
    });
    await AuditLogService.log(
      action: 'delete',
      entityTable: _ordersTable,
      entityId: orderId,
      branchId: order['branch_id'] as String?,
    );
  }

  static Future<void> attachSaleToOrder(String orderId, String saleId) async {
    final order = await getOrderById(orderId);
    if (order == null) {
      throw Exception('Service order not found or access denied.');
    }
    final now = DateTime.now().toIso8601String();
    await DatabaseService.update(_ordersTable, {
      'sale_id': saleId,
      'status': 'paid',
      'updated_at': now,
      'sync_status': 'pending',
    }, orderId);
  }

  static Map<String, dynamic> _decodeFieldOptions(Map<String, dynamic> row) {
    final optionsRaw = row['options_json'] as String?;
    final options = <String>[];
    if (optionsRaw != null && optionsRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(optionsRaw);
        if (decoded is List) {
          for (final value in decoded) {
            final text = value?.toString().trim() ?? '';
            if (text.isNotEmpty) {
              options.add(text);
            }
          }
        }
      } catch (_) {}
    }

    // Decode price_map_json → Map<String, double>
    final priceMapRaw = row['price_map_json'] as String?;
    final priceMap = <String, double>{};
    if (priceMapRaw != null && priceMapRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(priceMapRaw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final key = entry.key?.toString() ?? '';
            final val = (entry.value as num?)?.toDouble();
            if (key.isNotEmpty && val != null && val > 0) {
              priceMap[key] = val;
            }
          }
        }
      } catch (_) {}
    }

    return {...row, 'options': options, 'price_map': priceMap};
  }

  static String? _encodeOptions(Object? rawOptions) {
    if (rawOptions is! List) {
      return null;
    }
    final options = rawOptions
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
    if (options.isEmpty) {
      return null;
    }
    return jsonEncode(options);
  }

  /// Builds the price_map_json string from parallel options + prices lists.
  /// e.g. options=[Sedan,SUV], prices=[300,500] → '{"Sedan":300.0,"SUV":500.0}'
  static String? _buildPriceMapJson(Map<String, dynamic> field) {
    final options = (field['options'] as List<dynamic>? ?? [])
        .map((o) => o.toString().trim())
        .where((o) => o.isNotEmpty)
        .toList();
    final rawPrices = field['prices'] as List<dynamic>? ?? [];
    if (options.isEmpty) return null;
    final map = <String, dynamic>{};
    for (var i = 0; i < options.length; i++) {
      final raw = i < rawPrices.length ? rawPrices[i] : null;
      final price = raw is num
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '');
      if (price != null && price > 0) {
        map[options[i]] = price;
      }
    }
    return map.isEmpty ? null : jsonEncode(map);
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static String defaultAssignedStaffName() {
    return _clean(SessionService.currentUserName) ?? 'Cashier';
  }

  static String? currentAssignedStaffUserIdFor(String? assignedStaff) {
    final currentName = _clean(SessionService.currentUserName);
    final enteredStaff = _clean(assignedStaff);
    if (currentName == null ||
        enteredStaff == null ||
        currentName.toLowerCase() != enteredStaff.toLowerCase()) {
      return null;
    }
    return _clean(SessionService.currentUserId);
  }

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return value?.toString().toLowerCase() == 'true';
  }

  static Future<Map<String, dynamic>> getServiceStats() async {
    final summaryArgs = <dynamic>[..._currentBranchArgs];
    final summaryClauses = <String>[
      'deleted_at IS NULL',
      'COALESCE(branch_id, ?) = ?',
    ];
    final summaryAccessClause = _serviceAccessClause('service_id', summaryArgs);
    if (summaryAccessClause != null) {
      summaryClauses.add(summaryAccessClause);
    }

    final rows = await DatabaseService.rawQuery('''
      SELECT
        COUNT(*) as total_orders,
        SUM(CASE WHEN status NOT IN ('paid','cancelled') THEN 1 ELSE 0 END) as active_count,
        SUM(CASE WHEN date(created_at) = date('now','localtime') THEN 1 ELSE 0 END) as today_count,
        SUM(CASE WHEN date(created_at) = date('now','localtime') AND status = 'paid' THEN price ELSE 0 END) as today_revenue,
        SUM(CASE WHEN status = 'paid' THEN price ELSE 0 END) as total_revenue,
        SUM(CASE WHEN status = 'booked' THEN 1 ELSE 0 END) as booked_count,
        SUM(CASE WHEN status = 'checked_in' THEN 1 ELSE 0 END) as checked_in_count,
        SUM(CASE WHEN status = 'in_progress' THEN 1 ELSE 0 END) as in_progress_count,
        SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as completed_count,
        SUM(CASE WHEN entry_mode = 'appointment' AND status NOT IN ('completed','paid','cancelled') THEN 1 ELSE 0 END) as upcoming_appointments
      FROM $_ordersTable
      WHERE ${summaryClauses.join(' AND ')}
    ''', summaryArgs);

    final topServiceArgs = <dynamic>[..._currentBranchArgs];
    final topServiceClauses = <String>[
      'deleted_at IS NULL',
      'COALESCE(branch_id, ?) = ?',
    ];
    final topServiceAccessClause = _serviceAccessClause(
      'service_id',
      topServiceArgs,
    );
    if (topServiceAccessClause != null) {
      topServiceClauses.add(topServiceAccessClause);
    }

    final topServices = await DatabaseService.rawQuery('''
      SELECT service_name, COUNT(*) as order_count, SUM(price) as revenue
      FROM $_ordersTable
      WHERE ${topServiceClauses.join(' AND ')}
      GROUP BY service_name
      ORDER BY order_count DESC
      LIMIT 6
    ''', topServiceArgs);

    final recentOrderArgs = <dynamic>[..._currentBranchArgs];
    final recentOrderClauses = <String>[
      'so.deleted_at IS NULL',
      'COALESCE(so.branch_id, ?) = ?',
    ];
    final recentOrderAccessClause = _serviceAccessClause(
      'so.service_id',
      recentOrderArgs,
    );
    if (recentOrderAccessClause != null) {
      recentOrderClauses.add(recentOrderAccessClause);
    }

    final recentOrders = await DatabaseService.rawQuery('''
      SELECT so.*, s.category as service_category
      FROM $_ordersTable so
      LEFT JOIN $_servicesTable s ON s.id = so.service_id
      WHERE ${recentOrderClauses.join(' AND ')}
      ORDER BY so.created_at DESC
      LIMIT 8
    ''', recentOrderArgs);

    final result = rows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(rows.first);
    result['top_services'] = topServices;
    result['recent_orders'] = recentOrders;
    return result;
  }

  static Future<Map<String, dynamic>> getServiceSalesByDate(String date) async {
    final accessArgs = <dynamic>[];
    final accessClause = _serviceAccessClause('ssi.service_id', accessArgs);
    final where = [
      'date(s.created_at) = date(?)',
      'COALESCE(s.branch_id, ?) = ?',
      ?accessClause,
    ].join(' AND ');
    final args = <dynamic>[date, ..._currentBranchArgs, ...accessArgs];

    final summaryRows = await DatabaseService.rawQuery('''
      SELECT
        COUNT(DISTINCT s.id) as sale_count,
        COALESCE(SUM(ssi.quantity * ssi.unit_price), 0) as revenue,
        COALESCE(SUM(CASE WHEN s.payment_type = 'kopesha' THEN ssi.quantity * ssi.unit_price ELSE 0 END), 0) as credit_revenue,
        COALESCE(SUM(CASE WHEN s.is_cash_drawer = 1 THEN ssi.quantity * ssi.unit_price ELSE 0 END), 0) as cash_drawer_revenue
      FROM service_sale_items ssi
      JOIN sales s ON s.id = ssi.sale_id
      WHERE $where AND s.deleted_at IS NULL
    ''', args);

    final paymentRows = await DatabaseService.rawQuery('''
      SELECT
        s.payment_type,
        COUNT(DISTINCT s.id) as sale_count,
        COALESCE(SUM(ssi.quantity * ssi.unit_price), 0) as revenue
      FROM service_sale_items ssi
      JOIN sales s ON s.id = ssi.sale_id
      WHERE $where AND s.deleted_at IS NULL
      GROUP BY s.payment_type
      ORDER BY revenue DESC
    ''', args);

    final serviceRows = await DatabaseService.rawQuery('''
      SELECT
        ssi.service_name,
        COUNT(DISTINCT s.id) as sale_count,
        COALESCE(SUM(ssi.quantity * ssi.unit_price), 0) as revenue
      FROM service_sale_items ssi
      JOIN sales s ON s.id = ssi.sale_id
      WHERE $where AND s.deleted_at IS NULL
      GROUP BY ssi.service_name
      ORDER BY revenue DESC
      LIMIT 8
    ''', args);

    final recentRows = await DatabaseService.rawQuery('''
      SELECT
        s.id as sale_id,
        s.payment_type,
        s.customer_name,
        s.created_at,
        ssi.service_order_id,
        ssi.service_id,
        ssi.service_name,
        ssi.quantity,
        ssi.unit_price
      FROM service_sale_items ssi
      JOIN sales s ON s.id = ssi.sale_id
      WHERE $where AND s.deleted_at IS NULL
      ORDER BY s.created_at DESC
      LIMIT 12
    ''', args);

    final summary = summaryRows.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(summaryRows.first);
    summary['payment_methods'] = paymentRows;
    summary['services'] = serviceRows;
    summary['recent_sales'] = recentRows;
    summary['date'] = date;
    return summary;
  }

  static String? _serviceAccessClause(String columnName, List<dynamic> args) {
    final allowedServiceIds = SessionService.currentAllowedServiceIds;
    if (allowedServiceIds.isEmpty) {
      return null;
    }
    final placeholders = List.filled(allowedServiceIds.length, '?').join(',');
    args.addAll(allowedServiceIds);
    return '$columnName IN ($placeholders)';
  }

  static String? _serviceOrderAssignmentClause(
    String tableAlias,
    List<dynamic> args,
  ) {
    if (!SessionService.limitsServiceOrdersToAssigned) {
      return null;
    }

    final clauses = <String>[];
    final currentUserId = _clean(SessionService.currentUserId);
    if (currentUserId != null) {
      clauses.add('$tableAlias.assigned_staff_user_id = ?');
      args.add(currentUserId);
    }

    final currentUserName = _clean(SessionService.currentUserName);
    if (currentUserName != null) {
      clauses.add('LOWER(TRIM($tableAlias.assigned_staff)) = LOWER(?)');
      args.add(currentUserName);
    }

    if (clauses.isEmpty) {
      return '1 = 0';
    }
    return '(${clauses.join(' OR ')})';
  }

  static bool _canAccessServiceOrder(Map<String, dynamic> order) {
    if (!SessionService.canAccessServiceId(order['service_id'] as String?)) {
      return false;
    }
    if (!SessionService.limitsServiceOrdersToAssigned) {
      return true;
    }

    final currentUserId = _clean(SessionService.currentUserId);
    final assignedStaffUserId = _clean(
      order['assigned_staff_user_id'] as String?,
    );
    if (currentUserId != null && assignedStaffUserId == currentUserId) {
      return true;
    }

    final currentUserName = _clean(SessionService.currentUserName);
    final assignedStaff = _clean(order['assigned_staff'] as String?);
    return currentUserName != null &&
        assignedStaff != null &&
        currentUserName.toLowerCase() == assignedStaff.toLowerCase();
  }
}
