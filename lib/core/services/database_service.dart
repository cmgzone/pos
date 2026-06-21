import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'session_service.dart';

class DatabaseService {
  static const String _databaseName = 'velora_pos.db';
  static const int _databaseVersion = 21;
  static const String defaultBranchId = 'main_branch';
  static const _uuid = Uuid();

  static const Set<String> _branchAwareTables = {
    'categories',
    'products',
    'product_variants',
    'product_variant_colors',
    'customers',
    'shifts',
    'sales',
    'customer_invoices',
    'customer_invoice_items',
    'quotations',
    'quotation_items',
    'cash_movements',
    'held_sales',
    'suppliers',
    'purchase_invoices',
    'supplier_payments',
    'purchase_orders',
    'purchase_order_items',
    'stock_batches',
    'stock_transfers',
    'credit_payments',
    'expense_categories',
    'expenses',
    'services',
    'service_orders',
    'audit_logs',
  };

  static Database? _database;
  static String? _databasePath;
  static String? _databasePathOverride;
  static String _currentBranchId = defaultBranchId;
  static final StreamController<void> _localChangeController =
      StreamController<void>.broadcast();

  static Stream<void> get localChanges => _localChangeController.stream;

  static void notifyLocalChange() {
    if (!_localChangeController.isClosed) {
      _localChangeController.add(null);
    }
  }

  static Database get db {
    final database = _database;
    if (database == null) {
      throw StateError('Database has not been initialized');
    }
    return database;
  }

  static String get databasePath {
    final path = _databasePath;
    if (path == null) {
      throw StateError('Database path is not available before initialization');
    }
    return path;
  }

  static String get currentBranchId => _currentBranchId;

  static Future<void> initialize() async {
    if (_database != null) {
      return;
    }

    _configureDatabaseFactory();

    _databasePath = _databasePathOverride ?? await _resolveDatabasePath();
    await File(_databasePath!).parent.create(recursive: true);

    _database = await openDatabase(
      _databasePath!,
      version: _databaseVersion,
      onConfigure: _onConfigure,
      onCreate: (database, version) async {
        await _runMigrations(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 16) {
          // Drop barcode indexes to recreate them with the deleted_at IS NULL partial index condition
          await database.execute('DROP INDEX IF EXISTS idx_products_barcode');
          await database.execute(
            'DROP INDEX IF EXISTS idx_product_variants_barcode',
          );
        }
        await _runMigrations(database);
      },
      onOpen: (database) async {
        await _runMigrations(database);
      },
    );
  }

  static Future<void> close() async {
    final database = _database;
    if (database == null) {
      return;
    }
    await database.close();
    _database = null;
  }

  /// Closes the current database connection, deletes the database file from
  /// disk, then re-opens and re-creates it from scratch.
  ///
  /// Call this when a different business account logs in on the same device so
  /// that stale data from the previous business is not visible.
  static Future<void> wipeAndReinitialize() async {
    await close();
    final path = _databasePath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      _databasePath = null;
    }
    await initialize();
  }

  @visibleForTesting
  static Future<void> overrideDatabasePathForTesting(String? path) async {
    await close();
    _databasePathOverride = path;
    _databasePath = null;
  }

  static Future<List<Map<String, dynamic>>> queryAll(
    String table, {
    String? where,
    List<dynamic>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final database = await _ensureDatabase();
    final rows = await database.query(
      table,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: limit,
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static Future<Map<String, dynamic>?> queryById(
    String table,
    String id,
  ) async {
    final rows = await queryAll(
      table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<List<Map<String, dynamic>>> rawQuery(
    String sql, [
    List<dynamic>? arguments,
  ]) async {
    final database = await _ensureDatabase();
    final rows = await database.rawQuery(sql, arguments);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static Future<int> insert(String table, Map<String, dynamic> data) async {
    final database = await _ensureDatabase();
    final payload = Map<String, dynamic>.from(data);
    final now = DateTime.now().toIso8601String();
    payload.putIfAbsent('created_at', () => now);
    payload.putIfAbsent('updated_at', () => now);
    payload.putIfAbsent('sync_status', () => 'pending');
    await _applyDefaultBranch(database, table, payload);

    final result = await database.insert(table, payload);
    await _writeAuditLog(
      database,
      action: 'create',
      tableName: table,
      entityId: payload['id']?.toString(),
      after: payload,
      branchId: payload['branch_id']?.toString(),
    );
    notifyLocalChange();
    return result;
  }

  static Future<int> update(
    String table,
    Map<String, dynamic> data,
    String id,
  ) async {
    final database = await _ensureDatabase();
    final payload = Map<String, dynamic>.from(data);
    payload.putIfAbsent('updated_at', () => DateTime.now().toIso8601String());
    payload.putIfAbsent('sync_status', () => 'pending');
    await _applyDefaultBranch(database, table, payload);

    final before = await _queryById(database, table, id);
    final result = await database.update(
      table,
      payload,
      where: 'id = ?',
      whereArgs: [id],
    );
    await _writeAuditLog(
      database,
      action: 'update',
      tableName: table,
      entityId: id,
      before: before,
      after: payload,
      branchId:
          payload['branch_id']?.toString() ?? before?['branch_id']?.toString(),
    );
    if (result > 0) {
      notifyLocalChange();
    }
    return result;
  }

  static Future<int> delete(String table, String id) async {
    final database = await _ensureDatabase();
    final columns = await _getColumnNames(database, table);
    final before = await _queryById(database, table, id);
    if (columns.contains('deleted_at')) {
      final now = DateTime.now().toIso8601String();
      final result = await database.update(
        table,
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _writeAuditLog(
        database,
        action: 'delete',
        tableName: table,
        entityId: id,
        before: before,
        after: {'deleted_at': now},
        branchId: before?['branch_id']?.toString(),
      );
      if (result > 0) {
        notifyLocalChange();
      }
      return result;
    }
    final result = await database.delete(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );
    await _writeAuditLog(
      database,
      action: 'delete',
      tableName: table,
      entityId: id,
      before: before,
      branchId: before?['branch_id']?.toString(),
    );
    if (result > 0) {
      notifyLocalChange();
    }
    return result;
  }

  static void setCurrentBranchId(String? branchId) {
    final cleanBranchId = branchId?.trim() ?? '';
    _currentBranchId = cleanBranchId.isEmpty ? defaultBranchId : cleanBranchId;
  }

  static Future<Database> _ensureDatabase() async {
    await initialize();
    return db;
  }

  static Future<void> _applyDefaultBranch(
    DatabaseExecutor database,
    String table,
    Map<String, dynamic> payload,
  ) async {
    if (!_branchAwareTables.contains(table) || table == 'branches') {
      return;
    }
    if (payload.containsKey('branch_id')) {
      return;
    }
    final columns = await _getColumnNames(database, table);
    if (columns.contains('branch_id')) {
      payload['branch_id'] = _currentBranchId;
    }
  }

  static Future<Map<String, dynamic>?> _queryById(
    DatabaseExecutor database,
    String table,
    String id,
  ) async {
    try {
      final rows = await database.query(
        table,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      return Map<String, dynamic>.from(rows.first);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeAuditLog(
    DatabaseExecutor database, {
    required String action,
    required String tableName,
    String? entityId,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    String? branchId,
  }) async {
    if (tableName == 'audit_logs') {
      return;
    }
    try {
      final now = DateTime.now().toIso8601String();
      await database.insert('audit_logs', {
        'id': _uuid.v4(),
        'branch_id': branchId?.trim().isNotEmpty == true
            ? branchId!.trim()
            : _currentBranchId,
        'user_id': SessionService.currentUserId.trim().isEmpty
            ? null
            : SessionService.currentUserId,
        'user_name': SessionService.currentUserName,
        'user_role': SessionService.currentUserRole,
        'action': action,
        'entity_table': tableName,
        'entity_id': entityId,
        'before_json': before == null ? null : jsonEncode(before),
        'after_json': after == null ? null : jsonEncode(after),
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      });
    } catch (_) {
      // Audit logging should never block the sale or stock operation itself.
    }
  }

  static void _configureDatabaseFactory() {
    if (kIsWeb) {
      return;
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  static Future<String> _resolveDatabasePath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final appSupportDirectory = await getApplicationSupportDirectory();
      final databaseDirectory = Directory(
        '${appSupportDirectory.path}${Platform.pathSeparator}Velora POS',
      );
      return '${databaseDirectory.path}${Platform.pathSeparator}$_databaseName';
    }

    final databasesDirectory = await getDatabasesPath();
    return '$databasesDirectory${Platform.pathSeparator}$_databaseName';
  }

  static Future<void> _onConfigure(Database database) async {
    await database.execute('PRAGMA foreign_keys = ON');
    try {
      await database.execute('PRAGMA journal_mode = WAL');
    } catch (_) {
      // Some embedded engines can reject WAL; the app still works without it.
    }
  }

  static Future<void> _createTables(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS branches (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT,
        phone TEXT,
        address TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        name TEXT NOT NULL,
        color TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        cost REAL,
        stock REAL NOT NULL DEFAULT 0,
        low_stock REAL NOT NULL DEFAULT 0,
        unit TEXT NOT NULL DEFAULT 'pcs',
        stock_unit TEXT NOT NULL DEFAULT 'pcs',
        sale_unit TEXT NOT NULL DEFAULT 'pcs',
        sale_to_stock_factor REAL NOT NULL DEFAULT 1,
        purchase_unit TEXT NOT NULL DEFAULT 'pcs',
        purchase_to_stock_factor REAL NOT NULL DEFAULT 1,
        sku TEXT,
        barcode TEXT,
        image_url TEXT,
        brand TEXT,
        description TEXT,
        image_urls_json TEXT,
        show_online INTEGER NOT NULL DEFAULT 1,
        is_featured INTEGER NOT NULL DEFAULT 0,
        category_id TEXT,
        track_stock INTEGER NOT NULL DEFAULT 1,
        has_variants INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        phone TEXT,
        password TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'CASHIER',
        feature_access_json TEXT,
        allowed_service_ids_json TEXT,
        allowed_branch_ids_json TEXT,
        pos_mode TEXT NOT NULL DEFAULT 'both',
        service_order_scope TEXT NOT NULL DEFAULT 'all_visible_services',
        last_seen_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        balance REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS shifts (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        user_id TEXT,
        cashier_name TEXT,
        status TEXT NOT NULL DEFAULT 'open',
        opening_cash REAL NOT NULL DEFAULT 0,
        closing_cash_counted REAL NOT NULL DEFAULT 0,
        expected_cash REAL NOT NULL DEFAULT 0,
        cash_sales_total REAL NOT NULL DEFAULT 0,
        cash_refunds_total REAL NOT NULL DEFAULT 0,
        cash_in_total REAL NOT NULL DEFAULT 0,
        cash_out_total REAL NOT NULL DEFAULT 0,
        difference REAL NOT NULL DEFAULT 0,
        note TEXT,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        total_amount REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        payment_type TEXT NOT NULL,
        is_cash_drawer INTEGER NOT NULL DEFAULT 0,
        user_id TEXT,
        shift_id TEXT,
        customer_id TEXT,
        customer_name TEXT,
        due_date TEXT,
        amount_paid REAL NOT NULL DEFAULT 0,
        amount_tendered REAL NOT NULL DEFAULT 0,
        change_given REAL NOT NULL DEFAULT 0,
        balance_due REAL NOT NULL DEFAULT 0,
        payment_provider TEXT,
        payment_reference TEXT,
        payment_status TEXT,
        payment_metadata_json TEXT,
        etims_status TEXT,
        etims_invoice_number TEXT,
        etims_control_unit_invoice_number TEXT,
        etims_control_unit_serial TEXT,
        etims_verification_url TEXT,
        etims_qr_code TEXT,
        etims_submitted_at TEXT,
        etims_error TEXT,
        etims_response_json TEXT,
        refund_sale_id TEXT,
        refund_for_sale_id TEXT,
        refund_note TEXT,
        refunded_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
        FOREIGN KEY (shift_id) REFERENCES shifts(id) ON DELETE SET NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL,
        FOREIGN KEY (refund_sale_id) REFERENCES sales(id) ON DELETE SET NULL,
        FOREIGN KEY (refund_for_sale_id) REFERENCES sales(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id TEXT PRIMARY KEY,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        unit TEXT NOT NULL DEFAULT 'pcs',
        sale_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        variant_id TEXT,
        variant_color_id TEXT,
        variant_color_name TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id),
        FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS customer_invoices (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        invoice_number TEXT NOT NULL,
        customer_id TEXT,
        customer_name TEXT NOT NULL,
        customer_phone TEXT,
        customer_email TEXT,
        customer_kra_pin TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        issue_date TEXT NOT NULL,
        due_date TEXT,
        subtotal REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        amount_paid REAL NOT NULL DEFAULT 0,
        balance_due REAL NOT NULL DEFAULT 0,
        payment_method TEXT,
        payment_reference TEXT,
        note TEXT,
        sale_id TEXT,
        sent_at TEXT,
        paid_at TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS customer_invoice_items (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        invoice_id TEXT NOT NULL,
        line_type TEXT NOT NULL DEFAULT 'product',
        product_id TEXT,
        variant_id TEXT,
        service_id TEXT,
        description TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1,
        unit TEXT NOT NULL DEFAULT 'pcs',
        unit_price REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        sale_to_stock_factor REAL NOT NULL DEFAULT 1,
        stock_unit TEXT NOT NULL DEFAULT 'pcs',
        track_stock INTEGER NOT NULL DEFAULT 1,
        line_total REAL NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (invoice_id) REFERENCES customer_invoices(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL,
        FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE SET NULL,
        FOREIGN KEY (service_id) REFERENCES services(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS cash_movements (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        shift_id TEXT NOT NULL,
        user_id TEXT,
        type TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (shift_id) REFERENCES shifts(id) ON DELETE CASCADE,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS held_sales (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        name TEXT NOT NULL,
        subtotal REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        item_count INTEGER NOT NULL DEFAULT 0,
        user_id TEXT,
        cashier_name TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS held_sale_items (
        id TEXT PRIMARY KEY,
        held_sale_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 0,
        unit_price REAL NOT NULL DEFAULT 0,
        cost REAL NOT NULL DEFAULT 0,
        max_stock REAL NOT NULL DEFAULT 0,
        stock_on_hand REAL NOT NULL DEFAULT 0,
        sale_to_stock_factor REAL NOT NULL DEFAULT 1,
        line_type TEXT NOT NULL DEFAULT 'product',
        service_order_id TEXT,
        service_id TEXT,
        variant_id TEXT,
        variant_name TEXT,
        variant_color_id TEXT,
        variant_color_name TEXT,
        unit TEXT NOT NULL DEFAULT 'pcs',
        stock_unit TEXT NOT NULL DEFAULT 'pcs',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (held_sale_id) REFERENCES held_sales(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS purchase_invoices (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        supplier_id TEXT,
        supplier_name TEXT,
        invoice_number TEXT,
        total_amount REAL NOT NULL DEFAULT 0,
        amount_paid REAL NOT NULL DEFAULT 0,
        balance_due REAL NOT NULL DEFAULT 0,
        due_date TEXT,
        status TEXT NOT NULL DEFAULT 'unpaid',
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS supplier_payments (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        supplier_id TEXT NOT NULL,
        purchase_id TEXT,
        amount REAL NOT NULL DEFAULT 0,
        payment_method TEXT,
        reference TEXT,
        note TEXT,
        paid_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE,
        FOREIGN KEY (purchase_id) REFERENCES purchase_invoices(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        supplier_id TEXT,
        supplier_name TEXT,
        order_number TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        total_amount REAL NOT NULL DEFAULT 0,
        expected_on TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_items (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        purchase_order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 0,
        unit TEXT NOT NULL DEFAULT 'pcs',
        unit_cost REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS stock_batches (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        product_id TEXT NOT NULL,
        batch_number TEXT,
        quantity_received REAL NOT NULL DEFAULT 0,
        quantity_remaining REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        purchase_id TEXT,
        supplier_id TEXT,
        expiry_date TEXT,
        received_at TEXT NOT NULL,
        finished_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
        FOREIGN KEY (purchase_id) REFERENCES purchase_invoices(id) ON DELETE SET NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS stock_transfers (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        from_branch_id TEXT NOT NULL,
        to_branch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 0,
        unit TEXT,
        status TEXT NOT NULL DEFAULT 'requested',
        requested_by TEXT,
        approved_by TEXT,
        received_by TEXT,
        note TEXT,
        requested_at TEXT NOT NULL,
        approved_at TEXT,
        received_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS credit_payments (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        payment_group_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        sale_id TEXT,
        user_id TEXT,
        amount REAL NOT NULL DEFAULT 0,
        note TEXT,
        received_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS expense_categories (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        name TEXT NOT NULL,
        color TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        category_id TEXT,
        category_name TEXT,
        title TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        note TEXT,
        incurred_on TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (category_id) REFERENCES expense_categories(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS services (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        name TEXT NOT NULL,
        category TEXT,
        description TEXT,
        base_price REAL NOT NULL DEFAULT 0,
        duration_minutes INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS service_fields (
        id TEXT PRIMARY KEY,
        service_id TEXT NOT NULL,
        label TEXT NOT NULL,
        field_type TEXT NOT NULL,
        options_json TEXT,
        price_map_json TEXT,
        is_required INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (service_id) REFERENCES services(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS service_orders (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        service_id TEXT NOT NULL,
        service_name TEXT NOT NULL,
        customer_id TEXT,
        customer_name TEXT,
        entry_mode TEXT NOT NULL DEFAULT 'walk_in',
        scheduled_at TEXT,
        checked_in_at TEXT,
        status TEXT NOT NULL DEFAULT 'booked',
        assigned_staff TEXT,
        assigned_staff_user_id TEXT,
        bay_number TEXT,
        price REAL NOT NULL DEFAULT 0,
        note TEXT,
        sale_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (service_id) REFERENCES services(id),
        FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE SET NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS service_field_values (
        id TEXT PRIMARY KEY,
        service_order_id TEXT NOT NULL,
        field_id TEXT,
        field_label TEXT NOT NULL,
        field_type TEXT NOT NULL,
        value_text TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (service_order_id) REFERENCES service_orders(id) ON DELETE CASCADE,
        FOREIGN KEY (field_id) REFERENCES service_fields(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS service_sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        service_order_id TEXT,
        service_id TEXT,
        service_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (service_order_id) REFERENCES service_orders(id) ON DELETE SET NULL,
        FOREIGN KEY (service_id) REFERENCES services(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS product_variants (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        product_id TEXT NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        cost REAL,
        sku TEXT,
        barcode TEXT,
        stock REAL NOT NULL DEFAULT 0,
        low_stock REAL NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS product_variant_colors (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        product_id TEXT NOT NULL,
        variant_id TEXT NOT NULL,
        name TEXT NOT NULL,
        hex_color TEXT,
        stock REAL NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
        FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS payment_methods (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        provider_key TEXT,
        is_cash_drawer INTEGER NOT NULL DEFAULT 0,
        is_credit INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        user_id TEXT,
        user_name TEXT,
        user_role TEXT,
        action TEXT NOT NULL,
        entity_table TEXT NOT NULL,
        entity_id TEXT,
        before_json TEXT,
        after_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
  }

  static Future<void> _createIndexes(DatabaseExecutor database) async {
    await _createIndexIfColumnsExist(
      database,
      table: 'products',
      indexName: 'idx_products_category_id',
      columns: ['category_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'products',
      indexName: 'idx_products_name',
      columns: ['name'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'products',
      indexName: 'idx_products_barcode',
      columns: ['barcode'],
      whereClause: 'deleted_at IS NULL',
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'shifts',
      indexName: 'idx_shifts_user_id',
      columns: ['user_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'shifts',
      indexName: 'idx_shifts_status',
      columns: ['status'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'shifts',
      indexName: 'idx_shifts_opened_at',
      columns: ['opened_at'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'sales',
      indexName: 'idx_sales_created_at',
      columns: ['created_at'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'sales',
      indexName: 'idx_sales_customer_id',
      columns: ['customer_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'sales',
      indexName: 'idx_sales_user_id',
      columns: ['user_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'sales',
      indexName: 'idx_sales_shift_id',
      columns: ['shift_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'sales',
      indexName: 'idx_sales_refund_sale_id',
      columns: ['refund_sale_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'sales',
      indexName: 'idx_sales_refund_for_sale_id',
      columns: ['refund_for_sale_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'sale_items',
      indexName: 'idx_sale_items_sale_id',
      columns: ['sale_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'sale_items',
      indexName: 'idx_sale_items_product_id',
      columns: ['product_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'cash_movements',
      indexName: 'idx_cash_movements_shift_id',
      columns: ['shift_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'cash_movements',
      indexName: 'idx_cash_movements_created_at',
      columns: ['created_at'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'held_sales',
      indexName: 'idx_held_sales_updated_at',
      columns: ['updated_at'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'held_sale_items',
      indexName: 'idx_held_sale_items_hold_id',
      columns: ['held_sale_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'stock_batches',
      indexName: 'idx_stock_batches_product_id',
      columns: ['product_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'stock_batches',
      indexName: 'idx_stock_batches_purchase_id',
      columns: ['purchase_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'stock_batches',
      indexName: 'idx_stock_batches_received_at',
      columns: ['received_at'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'stock_batches',
      indexName: 'idx_stock_batches_expiry_date',
      columns: ['expiry_date'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'credit_payments',
      indexName: 'idx_credit_payments_customer_id',
      columns: ['customer_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'credit_payments',
      indexName: 'idx_credit_payments_group_id',
      columns: ['payment_group_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'purchase_invoices',
      indexName: 'idx_purchase_invoices_supplier_id',
      columns: ['supplier_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'supplier_payments',
      indexName: 'idx_supplier_payments_supplier_id',
      columns: ['supplier_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'supplier_payments',
      indexName: 'idx_supplier_payments_purchase_id',
      columns: ['purchase_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'purchase_orders',
      indexName: 'idx_purchase_orders_supplier_id',
      columns: ['supplier_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'purchase_order_items',
      indexName: 'idx_purchase_order_items_order_id',
      columns: ['purchase_order_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'expenses',
      indexName: 'idx_expenses_incurred_on',
      columns: ['incurred_on'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'users',
      indexName: 'idx_users_email_unique',
      columns: ['email'],
      unique: true,
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'services',
      indexName: 'idx_services_name',
      columns: ['name'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'service_fields',
      indexName: 'idx_service_fields_service_id',
      columns: ['service_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'service_orders',
      indexName: 'idx_service_orders_service_id',
      columns: ['service_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'service_orders',
      indexName: 'idx_service_orders_status',
      columns: ['status'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'service_orders',
      indexName: 'idx_service_orders_scheduled_at',
      columns: ['scheduled_at'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'service_field_values',
      indexName: 'idx_service_field_values_order_id',
      columns: ['service_order_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'service_sale_items',
      indexName: 'idx_service_sale_items_sale_id',
      columns: ['sale_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'product_variants',
      indexName: 'idx_product_variants_product_id',
      columns: ['product_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'product_variants',
      indexName: 'idx_product_variants_barcode',
      columns: ['barcode'],
      whereClause: 'deleted_at IS NULL',
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'product_variant_colors',
      indexName: 'idx_product_variant_colors_variant_id',
      columns: ['variant_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'sale_items',
      indexName: 'idx_sale_items_variant_id',
      columns: ['variant_id'],
    );
    for (final table in _branchAwareTables) {
      await _createIndexIfColumnsExist(
        database,
        table: table,
        indexName: 'idx_${table}_branch_id',
        columns: ['branch_id'],
      );
    }
    await _createIndexIfColumnsExist(
      database,
      table: 'stock_transfers',
      indexName: 'idx_stock_transfers_from_to_status',
      columns: ['from_branch_id', 'to_branch_id', 'status'],
    );
    // Optimization indexes added in v16
    await _createIndexIfColumnsExist(
      database,
      table: 'product_variants',
      indexName: 'idx_product_variants_product',
      columns: ['product_id', 'deleted_at'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'sale_items',
      indexName: 'idx_sale_items_lookup',
      columns: ['sale_id', 'product_id'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'sales',
      indexName: 'idx_sales_sync_branch',
      columns: ['branch_id', 'deleted_at', 'created_at'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'stock_batches',
      indexName: 'idx_stock_batches_fifo',
      columns: [
        'product_id',
        'quantity_remaining',
        'expiry_date',
        'received_at',
      ],
      whereClause: 'deleted_at IS NULL',
    );
    // Optimization indexes added in v19
    await _createIndexIfColumnsExist(
      database,
      table: 'products',
      indexName: 'idx_products_branch_deleted',
      columns: ['branch_id', 'deleted_at'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'product_variants',
      indexName: 'idx_product_variants_branch_deleted',
      columns: ['branch_id', 'deleted_at'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'product_variant_colors',
      indexName: 'idx_product_variant_colors_branch_deleted',
      columns: ['branch_id', 'deleted_at'],
    );
  }

  static Future<void> _createIndexIfColumnsExist(
    DatabaseExecutor database, {
    required String table,
    required String indexName,
    required List<String> columns,
    bool unique = false,
    String? whereClause,
  }) async {
    final availableColumns = await _getColumnNames(database, table);
    if (!columns.every(availableColumns.contains)) {
      return;
    }

    final uniqueSql = unique ? 'UNIQUE ' : '';
    final columnSql = columns.join(', ');
    final whereSql = whereClause != null ? ' WHERE $whereClause' : '';
    await database.execute(
      'CREATE ${uniqueSql}INDEX IF NOT EXISTS $indexName ON $table($columnSql)$whereSql',
    );
  }

  static Future<void> _runMigrations(DatabaseExecutor database) async {
    await _createTables(database);
    await _ensureProductUnitConversionSchema(database);
    await _ensureUserProfileSchema(database);
    await _ensureSalesPaymentSchema(database);
    await _ensureEtimsSalesSchema(database);
    await _ensureSalesCashDrawerSchema(database);
    await _ensureSalesRefundSchema(database);
    await _ensurePurchaseSchema(database);
    await _ensureCreditPaymentSchema(database);
    await _ensureExpenseSchema(database);
    await _ensureShiftSchema(database);
    await _ensureSyncMetadataSchema(database);
    await _ensureSaleItemsSchema(database);
    await _ensureCustomerInvoiceSchema(database);
    await _ensureQuotationSchema(database);
    await _ensureServicesSchema(database);
    await _ensureCarWashSchema(database);
    await _promoteLegacyServiceSyncStatuses(database);
    await _ensureCloudAuthSchema(database);
    await _ensureUserLastSeenSchema(database);
    await _ensureUserAccessSchema(database);
    await _ensureProductVariantsSchema(database);
    await _ensureProductVariantColorsSchema(database);
    await _ensureBrandColumn(database);
    await _ensureProductStorefrontSchema(database);
    await _ensurePaymentMethodsSchema(database);
    await _ensureEnterpriseSchema(database);
    await _ensureStockTransferSchema(database);
    await _ensurePublicCatalogOrderSchema(database);
    await _ensureAgentMemorySchema(database);
    await _ensureAgentChatSchema(database);
    // Indexes must be created last because some of them target columns that
    // are added by the schema repair helpers above on older local databases.
    await _createIndexes(database);
  }

  static Future<void> _ensureAgentChatSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS piki_sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS piki_messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        content TEXT NOT NULL,
        sender TEXT NOT NULL,
        message_type TEXT NOT NULL,
        attached_data_json TEXT,
        steps_json TEXT,
        suggestions_json TEXT,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES piki_sessions(id) ON DELETE CASCADE
      )
    ''');
    await _createIndexIfColumnsExist(
      database,
      table: 'piki_messages',
      indexName: 'idx_piki_messages_session_id',
      columns: ['session_id'],
    );
  }

  static Future<void> _ensureAgentMemorySchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS piki_memory (
        id TEXT PRIMARY KEY,
        key TEXT NOT NULL,
        value_json TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await _createIndexIfColumnsExist(
      database,
      table: 'piki_memory',
      indexName: 'idx_piki_memory_key',
      columns: ['key'],
    );
  }

  static Future<void> _ensureEnterpriseSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS branches (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        code TEXT,
        phone TEXT,
        address TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        user_id TEXT,
        user_name TEXT,
        user_role TEXT,
        action TEXT NOT NULL,
        entity_table TEXT NOT NULL,
        entity_id TEXT,
        before_json TEXT,
        after_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS stock_transfers (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        from_branch_id TEXT NOT NULL,
        to_branch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 0,
        unit TEXT,
        status TEXT NOT NULL DEFAULT 'requested',
        requested_by TEXT,
        approved_by TEXT,
        received_by TEXT,
        note TEXT,
        requested_at TEXT NOT NULL,
        approved_at TEXT,
        received_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    for (final table in _branchAwareTables) {
      await _ensureColumn(
        database,
        table: table,
        column: 'branch_id',
        definition: "TEXT DEFAULT '$defaultBranchId'",
      );
    }

    final now = DateTime.now().toIso8601String();
    await database.insert('branches', {
      'id': defaultBranchId,
      'name': 'Main Branch',
      'code': 'MAIN',
      'is_active': 1,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _ensureStockTransferSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS stock_transfers (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        from_branch_id TEXT NOT NULL,
        to_branch_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 0,
        unit TEXT,
        status TEXT NOT NULL DEFAULT 'requested',
        requested_by TEXT,
        approved_by TEXT,
        received_by TEXT,
        note TEXT,
        requested_at TEXT NOT NULL,
        approved_at TEXT,
        received_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'branch_id',
      definition: "TEXT DEFAULT '$defaultBranchId'",
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'from_branch_id',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'to_branch_id',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'product_id',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'product_name',
      definition: "TEXT NOT NULL DEFAULT 'Product'",
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'quantity',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'unit',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'status',
      definition: "TEXT NOT NULL DEFAULT 'requested'",
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'requested_by',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'approved_by',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'received_by',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'note',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'requested_at',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'approved_at',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'received_at',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'created_at',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'updated_at',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'deleted_at',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_transfers',
      column: 'sync_status',
      definition: "TEXT NOT NULL DEFAULT 'pending'",
    );
  }

  static Future<void> _ensurePublicCatalogOrderSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS public_catalog_orders (
        id TEXT PRIMARY KEY,
        business_id TEXT,
        branch_id TEXT NOT NULL DEFAULT 'main_branch',
        customer_name TEXT NOT NULL,
        phone TEXT NOT NULL,
        fulfillment_method TEXT NOT NULL DEFAULT 'delivery',
        delivery_address TEXT,
        note TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        subtotal REAL NOT NULL DEFAULT 0,
        item_count REAL NOT NULL DEFAULT 0,
        source TEXT NOT NULL DEFAULT 'catalog_link',
        payment_requested_at TEXT,
        fulfilled_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS public_catalog_order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        business_id TEXT,
        product_id TEXT NOT NULL,
        variant_id TEXT,
        product_name TEXT NOT NULL,
        variant_name TEXT,
        quantity REAL NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (order_id) REFERENCES public_catalog_orders(id) ON DELETE CASCADE
      )
    ''');
    await _ensureColumn(
      database,
      table: 'public_catalog_orders',
      column: 'branch_id',
      definition: "TEXT NOT NULL DEFAULT 'main_branch'",
    );
    await _ensureColumn(
      database,
      table: 'public_catalog_orders',
      column: 'fulfillment_method',
      definition: "TEXT NOT NULL DEFAULT 'delivery'",
    );
    await _ensureColumn(
      database,
      table: 'public_catalog_orders',
      column: 'payment_requested_at',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'public_catalog_orders',
      column: 'fulfilled_at',
      definition: 'TEXT',
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'public_catalog_orders',
      indexName: 'idx_public_catalog_orders_status',
      columns: ['status', 'created_at'],
    );
  }

  /// Ensures variant tables and columns exist on databases created before
  /// version 12. Safe to run on fresh databases (CREATE IF NOT EXISTS).
  static Future<void> _ensureProductVariantsSchema(
    DatabaseExecutor database,
  ) async {
    // product_variants table is created by _createTables; make sure it exists
    // on databases that were opened before version 12.
    await database.execute('''
      CREATE TABLE IF NOT EXISTS product_variants (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        branch_id TEXT,
        name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        cost REAL,
        sku TEXT,
        barcode TEXT,
        stock REAL NOT NULL DEFAULT 0,
        low_stock REAL NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');
    await _ensureColumn(
      database,
      table: 'products',
      column: 'has_variants',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'sale_items',
      column: 'variant_id',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensureProductVariantColorsSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS product_variant_colors (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        product_id TEXT NOT NULL,
        variant_id TEXT NOT NULL,
        name TEXT NOT NULL,
        hex_color TEXT,
        stock REAL NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
        FOREIGN KEY (variant_id) REFERENCES product_variants(id) ON DELETE CASCADE
      )
    ''');
    await _ensureColumn(
      database,
      table: 'sale_items',
      column: 'variant_color_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sale_items',
      column: 'variant_color_name',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'held_sale_items',
      column: 'variant_color_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'held_sale_items',
      column: 'variant_color_name',
      definition: 'TEXT',
    );
  }

  /// Adds the brand column to products if it doesn't exist (v13+).
  static Future<void> _ensureBrandColumn(DatabaseExecutor database) async {
    await _ensureColumn(
      database,
      table: 'products',
      column: 'brand',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensureProductStorefrontSchema(
    DatabaseExecutor database,
  ) async {
    await _ensureColumn(
      database,
      table: 'products',
      column: 'description',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'image_urls_json',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'show_online',
      definition: 'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'is_featured',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// Ensures that columns added to sale_items after initial release exist.
  /// Without these, any P&L query referencing si.unit_cost throws a silent
  /// exception and the screen falls back to showing all-zero profit.
  static Future<void> _ensureSaleItemsSchema(DatabaseExecutor database) async {
    await _ensureColumn(
      database,
      table: 'sale_items',
      column: 'unit_cost',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'sale_items',
      column: 'unit',
      definition: "TEXT NOT NULL DEFAULT 'pcs'",
    );
    await _ensureColumn(
      database,
      table: 'held_sale_items',
      column: 'line_type',
      definition: "TEXT NOT NULL DEFAULT 'product'",
    );
    await _ensureColumn(
      database,
      table: 'held_sale_items',
      column: 'service_order_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'held_sale_items',
      column: 'service_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'held_sale_items',
      column: 'variant_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'held_sale_items',
      column: 'variant_name',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensureCustomerInvoiceSchema(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS customer_invoices (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        invoice_number TEXT NOT NULL,
        customer_id TEXT,
        customer_name TEXT NOT NULL,
        customer_phone TEXT,
        customer_email TEXT,
        customer_kra_pin TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        issue_date TEXT NOT NULL,
        due_date TEXT,
        subtotal REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        amount_paid REAL NOT NULL DEFAULT 0,
        balance_due REAL NOT NULL DEFAULT 0,
        payment_method TEXT,
        payment_reference TEXT,
        note TEXT,
        sale_id TEXT,
        sent_at TEXT,
        paid_at TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS customer_invoice_items (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        invoice_id TEXT NOT NULL,
        line_type TEXT NOT NULL DEFAULT 'product',
        product_id TEXT,
        variant_id TEXT,
        service_id TEXT,
        description TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 1,
        unit TEXT NOT NULL DEFAULT 'pcs',
        unit_price REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        sale_to_stock_factor REAL NOT NULL DEFAULT 1,
        stock_unit TEXT NOT NULL DEFAULT 'pcs',
        track_stock INTEGER NOT NULL DEFAULT 1,
        line_total REAL NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    for (final table in const ['customer_invoices', 'customer_invoice_items']) {
      await _ensureColumn(
        database,
        table: table,
        column: 'branch_id',
        definition: "TEXT DEFAULT '$defaultBranchId'",
      );
      await _ensureColumn(
        database,
        table: table,
        column: 'deleted_at',
        definition: 'TEXT',
      );
      await _ensureColumn(
        database,
        table: table,
        column: 'sync_status',
        definition: "TEXT NOT NULL DEFAULT 'pending'",
      );
    }

    for (final spec in const [
      ['customer_invoices', 'invoice_number', "TEXT NOT NULL DEFAULT ''"],
      ['customer_invoices', 'customer_id', 'TEXT'],
      ['customer_invoices', 'customer_name', "TEXT NOT NULL DEFAULT ''"],
      ['customer_invoices', 'customer_phone', 'TEXT'],
      ['customer_invoices', 'customer_email', 'TEXT'],
      ['customer_invoices', 'customer_kra_pin', 'TEXT'],
      ['customer_invoices', 'status', "TEXT NOT NULL DEFAULT 'draft'"],
      ['customer_invoices', 'issue_date', "TEXT NOT NULL DEFAULT ''"],
      ['customer_invoices', 'due_date', 'TEXT'],
      ['customer_invoices', 'subtotal', 'REAL NOT NULL DEFAULT 0'],
      ['customer_invoices', 'tax', 'REAL NOT NULL DEFAULT 0'],
      ['customer_invoices', 'discount', 'REAL NOT NULL DEFAULT 0'],
      ['customer_invoices', 'total_amount', 'REAL NOT NULL DEFAULT 0'],
      ['customer_invoices', 'amount_paid', 'REAL NOT NULL DEFAULT 0'],
      ['customer_invoices', 'balance_due', 'REAL NOT NULL DEFAULT 0'],
      ['customer_invoices', 'payment_method', 'TEXT'],
      ['customer_invoices', 'payment_reference', 'TEXT'],
      ['customer_invoices', 'note', 'TEXT'],
      ['customer_invoices', 'sale_id', 'TEXT'],
      ['customer_invoices', 'sent_at', 'TEXT'],
      ['customer_invoices', 'paid_at', 'TEXT'],
      ['customer_invoices', 'created_by', 'TEXT'],
      ['customer_invoice_items', 'invoice_id', "TEXT NOT NULL DEFAULT ''"],
      [
        'customer_invoice_items',
        'line_type',
        "TEXT NOT NULL DEFAULT 'product'",
      ],
      ['customer_invoice_items', 'product_id', 'TEXT'],
      ['customer_invoice_items', 'variant_id', 'TEXT'],
      ['customer_invoice_items', 'service_id', 'TEXT'],
      ['customer_invoice_items', 'description', "TEXT NOT NULL DEFAULT ''"],
      ['customer_invoice_items', 'quantity', 'REAL NOT NULL DEFAULT 1'],
      ['customer_invoice_items', 'unit', "TEXT NOT NULL DEFAULT 'pcs'"],
      ['customer_invoice_items', 'unit_price', 'REAL NOT NULL DEFAULT 0'],
      ['customer_invoice_items', 'unit_cost', 'REAL NOT NULL DEFAULT 0'],
      [
        'customer_invoice_items',
        'sale_to_stock_factor',
        'REAL NOT NULL DEFAULT 1',
      ],
      ['customer_invoice_items', 'stock_unit', "TEXT NOT NULL DEFAULT 'pcs'"],
      ['customer_invoice_items', 'track_stock', 'INTEGER NOT NULL DEFAULT 1'],
      ['customer_invoice_items', 'line_total', 'REAL NOT NULL DEFAULT 0'],
      ['customer_invoice_items', 'sort_order', 'INTEGER NOT NULL DEFAULT 0'],
    ]) {
      await _ensureColumn(
        database,
        table: spec[0],
        column: spec[1],
        definition: spec[2],
      );
    }

    await _createIndexIfColumnsExist(
      database,
      table: 'customer_invoices',
      indexName: 'idx_customer_invoices_status',
      columns: ['branch_id', 'status', 'due_date'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'customer_invoice_items',
      indexName: 'idx_customer_invoice_items_invoice_id',
      columns: ['invoice_id'],
    );
  }

  static Future<void> _ensureQuotationSchema(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS quotation_sequences (
        branch_id TEXT PRIMARY KEY,
        next_number INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS quotations (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        quotation_no TEXT NOT NULL,
        customer_id TEXT,
        customer_name TEXT,
        subtotal REAL NOT NULL DEFAULT 0,
        discount_total REAL NOT NULL DEFAULT 0,
        tax_total REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        expiry_date TEXT,
        notes TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        created_by TEXT,
        converted_sale_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS quotation_items (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        quotation_id TEXT NOT NULL,
        product_id TEXT,
        variant_id TEXT,
        variant_color_id TEXT,
        variant_color_name TEXT,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 0,
        unit TEXT NOT NULL DEFAULT 'pcs',
        unit_price REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');

    for (final table in const ['quotations', 'quotation_items']) {
      await _ensureColumn(
        database,
        table: table,
        column: 'branch_id',
        definition: "TEXT DEFAULT '$defaultBranchId'",
      );
      await _ensureColumn(
        database,
        table: table,
        column: 'deleted_at',
        definition: 'TEXT',
      );
      await _ensureColumn(
        database,
        table: table,
        column: 'sync_status',
        definition: "TEXT NOT NULL DEFAULT 'pending'",
      );
    }

    for (final spec in const [
      ['quotations', 'quotation_no', "TEXT NOT NULL DEFAULT ''"],
      ['quotations', 'customer_id', 'TEXT'],
      ['quotations', 'customer_name', 'TEXT'],
      ['quotations', 'subtotal', 'REAL NOT NULL DEFAULT 0'],
      ['quotations', 'discount_total', 'REAL NOT NULL DEFAULT 0'],
      ['quotations', 'tax_total', 'REAL NOT NULL DEFAULT 0'],
      ['quotations', 'total', 'REAL NOT NULL DEFAULT 0'],
      ['quotations', 'expiry_date', 'TEXT'],
      ['quotations', 'notes', 'TEXT'],
      ['quotations', 'status', "TEXT NOT NULL DEFAULT 'draft'"],
      ['quotations', 'created_by', 'TEXT'],
      ['quotations', 'converted_sale_id', 'TEXT'],
      ['quotation_items', 'quotation_id', "TEXT NOT NULL DEFAULT ''"],
      ['quotation_items', 'product_id', 'TEXT'],
      ['quotation_items', 'variant_id', 'TEXT'],
      ['quotation_items', 'variant_color_id', 'TEXT'],
      ['quotation_items', 'variant_color_name', 'TEXT'],
      ['quotation_items', 'product_name', "TEXT NOT NULL DEFAULT ''"],
      ['quotation_items', 'quantity', 'REAL NOT NULL DEFAULT 0'],
      ['quotation_items', 'unit', "TEXT NOT NULL DEFAULT 'pcs'"],
      ['quotation_items', 'unit_price', 'REAL NOT NULL DEFAULT 0'],
      ['quotation_items', 'discount', 'REAL NOT NULL DEFAULT 0'],
      ['quotation_items', 'tax', 'REAL NOT NULL DEFAULT 0'],
      ['quotation_items', 'line_total', 'REAL NOT NULL DEFAULT 0'],
    ]) {
      await _ensureColumn(
        database,
        table: spec[0],
        column: spec[1],
        definition: spec[2],
      );
    }

    await _createIndexIfColumnsExist(
      database,
      table: 'quotations',
      indexName: 'idx_quotations_branch_status',
      columns: ['branch_id', 'status', 'expiry_date'],
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'quotations',
      indexName: 'idx_quotations_quotation_no',
      columns: ['branch_id', 'quotation_no'],
      unique: true,
      whereClause: 'deleted_at IS NULL',
    );
    await _createIndexIfColumnsExist(
      database,
      table: 'quotation_items',
      indexName: 'idx_quotation_items_quotation_id',
      columns: ['quotation_id'],
    );
  }

  static Future<void> _ensureProductUnitConversionSchema(
    DatabaseExecutor database,
  ) async {
    await _ensureColumn(
      database,
      table: 'products',
      column: 'low_stock',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'unit',
      definition: "TEXT NOT NULL DEFAULT 'pcs'",
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'stock_unit',
      definition: "TEXT NOT NULL DEFAULT 'pcs'",
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'sale_unit',
      definition: "TEXT NOT NULL DEFAULT 'pcs'",
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'sale_to_stock_factor',
      definition: 'REAL NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'purchase_unit',
      definition: "TEXT NOT NULL DEFAULT 'pcs'",
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'purchase_to_stock_factor',
      definition: 'REAL NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'sku',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'barcode',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'image_url',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'description',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'image_urls_json',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'show_online',
      definition: 'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'is_featured',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'category_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'products',
      column: 'track_stock',
      definition: 'INTEGER NOT NULL DEFAULT 1',
    );
  }

  static Future<void> _ensureUserProfileSchema(
    DatabaseExecutor database,
  ) async {
    await _ensureColumn(
      database,
      table: 'users',
      column: 'phone',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensureSalesPaymentSchema(
    DatabaseExecutor database,
  ) async {
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'amount_paid',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'amount_tendered',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'change_given',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'balance_due',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'customer_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'customer_name',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'due_date',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'payment_provider',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'payment_reference',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'payment_status',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'payment_metadata_json',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensureSalesCashDrawerSchema(
    DatabaseExecutor database,
  ) async {
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'is_cash_drawer',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
  }

  static Future<void> _ensureEtimsSalesSchema(DatabaseExecutor database) async {
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'etims_status',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'etims_invoice_number',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'etims_control_unit_invoice_number',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'etims_control_unit_serial',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'etims_verification_url',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'etims_qr_code',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'etims_submitted_at',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'etims_error',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'etims_response_json',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensureSalesRefundSchema(
    DatabaseExecutor database,
  ) async {
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'refund_sale_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'refund_for_sale_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'refund_note',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'refunded_at',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensurePurchaseSchema(DatabaseExecutor database) async {
    await _ensureColumn(
      database,
      table: 'stock_batches',
      column: 'batch_number',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_batches',
      column: 'purchase_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_batches',
      column: 'supplier_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_batches',
      column: 'finished_at',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'stock_batches',
      column: 'expiry_date',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'purchase_invoices',
      column: 'supplier_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'purchase_invoices',
      column: 'supplier_name',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'purchase_invoices',
      column: 'invoice_number',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'purchase_invoices',
      column: 'total_amount',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'purchase_invoices',
      column: 'amount_paid',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'purchase_invoices',
      column: 'balance_due',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'purchase_invoices',
      column: 'due_date',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'purchase_invoices',
      column: 'status',
      definition: "TEXT NOT NULL DEFAULT 'unpaid'",
    );
    await _ensureColumn(
      database,
      table: 'purchase_invoices',
      column: 'note',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'suppliers',
      column: 'phone',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'suppliers',
      column: 'email',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'suppliers',
      column: 'address',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'suppliers',
      column: 'note',
      definition: 'TEXT',
    );
    await database.execute('''
      CREATE TABLE IF NOT EXISTS supplier_payments (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        supplier_id TEXT NOT NULL,
        purchase_id TEXT,
        amount REAL NOT NULL DEFAULT 0,
        payment_method TEXT,
        reference TEXT,
        note TEXT,
        paid_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS purchase_orders (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        supplier_id TEXT,
        supplier_name TEXT,
        order_number TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        total_amount REAL NOT NULL DEFAULT 0,
        expected_on TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS purchase_order_items (
        id TEXT PRIMARY KEY,
        branch_id TEXT,
        purchase_order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL DEFAULT 0,
        unit TEXT NOT NULL DEFAULT 'pcs',
        unit_cost REAL NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
  }

  static Future<void> _ensureCreditPaymentSchema(
    DatabaseExecutor database,
  ) async {
    await _ensureColumn(
      database,
      table: 'credit_payments',
      column: 'payment_group_id',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      database,
      table: 'credit_payments',
      column: 'updated_at',
      definition: 'TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
    );
  }

  static Future<void> _ensureExpenseSchema(DatabaseExecutor database) async {
    await _ensureColumn(
      database,
      table: 'expense_categories',
      column: 'color',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'expenses',
      column: 'category_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'expenses',
      column: 'category_name',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'expenses',
      column: 'note',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensureShiftSchema(DatabaseExecutor database) async {
    await _ensureColumn(
      database,
      table: 'sales',
      column: 'shift_id',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensureSyncMetadataSchema(
    DatabaseExecutor database,
  ) async {
    for (final table in const [
      'categories',
      'products',
      'users',
      'customers',
      'shifts',
      'sales',
      'sale_items',
      'customer_invoices',
      'customer_invoice_items',
      'quotations',
      'quotation_items',
      'cash_movements',
      'suppliers',
      'purchase_invoices',
      'supplier_payments',
      'purchase_orders',
      'purchase_order_items',
      'stock_batches',
      'stock_transfers',
      'credit_payments',
      'expense_categories',
      'expenses',
      'services',
      'service_fields',
      'service_orders',
      'service_field_values',
      'service_sale_items',
    ]) {
      await _ensureColumn(
        database,
        table: table,
        column: 'created_at',
        definition: "TEXT NOT NULL DEFAULT ''",
      );
      await _ensureColumn(
        database,
        table: table,
        column: 'updated_at',
        definition: "TEXT NOT NULL DEFAULT ''",
      );
      await _ensureColumn(
        database,
        table: table,
        column: 'deleted_at',
        definition: 'TEXT',
      );
    }
    await _ensureColumn(
      database,
      table: 'quotation_items',
      column: 'variant_color_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'quotation_items',
      column: 'variant_color_name',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensureServicesSchema(DatabaseExecutor database) async {
    await _ensureColumn(
      database,
      table: 'services',
      column: 'category',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'services',
      column: 'description',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'services',
      column: 'base_price',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'services',
      column: 'duration_minutes',
      definition: 'INTEGER',
    );
    await _ensureColumn(
      database,
      table: 'services',
      column: 'is_active',
      definition: 'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      database,
      table: 'service_fields',
      column: 'options_json',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_fields',
      column: 'is_required',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'service_fields',
      column: 'sort_order',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'customer_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'customer_name',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'entry_mode',
      definition: "TEXT NOT NULL DEFAULT 'walk_in'",
    );
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'scheduled_at',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'checked_in_at',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'status',
      definition: "TEXT NOT NULL DEFAULT 'booked'",
    );
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'assigned_staff',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'assigned_staff_user_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'price',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'note',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'sale_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_field_values',
      column: 'field_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_field_values',
      column: 'field_label',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      database,
      table: 'service_field_values',
      column: 'field_type',
      definition: "TEXT NOT NULL DEFAULT 'text'",
    );
    await _ensureColumn(
      database,
      table: 'service_field_values',
      column: 'value_text',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_sale_items',
      column: 'service_order_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_sale_items',
      column: 'service_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_sale_items',
      column: 'service_name',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      database,
      table: 'service_sale_items',
      column: 'quantity',
      definition: 'REAL NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      database,
      table: 'service_sale_items',
      column: 'unit_price',
      definition: 'REAL NOT NULL DEFAULT 0',
    );
  }

  static Future<void> _ensureCarWashSchema(DatabaseExecutor database) async {
    await _ensureColumn(
      database,
      table: 'service_orders',
      column: 'bay_number',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'service_fields',
      column: 'price_map_json',
      definition: 'TEXT',
    );
  }

  static Future<void> _promoteLegacyServiceSyncStatuses(
    DatabaseExecutor database,
  ) async {
    for (final table in const [
      'services',
      'service_fields',
      'service_orders',
      'service_field_values',
      'service_sale_items',
    ]) {
      try {
        await database.rawUpdate(
          "UPDATE $table SET sync_status = 'pending' WHERE sync_status = 'local_only'",
        );
      } catch (_) {
        // Ignore until the table exists on the local device schema.
      }
    }
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor database, {
    required String table,
    required String column,
    required String definition,
  }) async {
    if (!await _tableExists(database, table)) {
      return;
    }
    final columns = await _getColumnNames(database, table);
    if (columns.contains(column)) {
      return;
    }
    await database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  static Future<bool> _tableExists(
    DatabaseExecutor database,
    String table,
  ) async {
    final rows = await database.rawQuery(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<Set<String>> _getColumnNames(
    DatabaseExecutor database,
    String table,
  ) async {
    final rows = await database.rawQuery("PRAGMA table_info('$table')");
    return rows
        .map((row) => (row['name'] as String?) ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();
  }

  static Future<void> _ensureCloudAuthSchema(DatabaseExecutor database) async {
    await _ensureColumn(
      database,
      table: 'users',
      column: 'cloud_verified_at',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensureUserLastSeenSchema(
    DatabaseExecutor database,
  ) async {
    await _ensureColumn(
      database,
      table: 'users',
      column: 'last_seen_at',
      definition: 'TEXT',
    );
  }

  static Future<void> _ensureUserAccessSchema(DatabaseExecutor database) async {
    await _ensureColumn(
      database,
      table: 'users',
      column: 'feature_access_json',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'users',
      column: 'allowed_service_ids_json',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'users',
      column: 'allowed_branch_ids_json',
      definition: 'TEXT',
    );
    await _ensureColumn(
      database,
      table: 'users',
      column: 'pos_mode',
      definition: "TEXT NOT NULL DEFAULT 'both'",
    );
    await _ensureColumn(
      database,
      table: 'users',
      column: 'service_order_scope',
      definition: "TEXT NOT NULL DEFAULT 'all_visible_services'",
    );
  }

  /// Ensures payment_methods table has is_credit column for credit/kopesha payments.
  static Future<void> _ensurePaymentMethodsSchema(
    DatabaseExecutor database,
  ) async {
    await _ensureColumn(
      database,
      table: 'payment_methods',
      column: 'is_credit',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      database,
      table: 'payment_methods',
      column: 'provider_key',
      definition: 'TEXT',
    );
    await database.rawUpdate('''
      UPDATE payment_methods
      SET provider_key = CASE
        WHEN is_cash_drawer = 1 THEN 'cash'
        WHEN is_credit = 1 OR LOWER(name) LIKE '%kopesha%' THEN 'kopesha'
        WHEN LOWER(name) LIKE '%mpesa%' OR LOWER(name) LIKE '%m-pesa%' THEN 'mpesa'
        WHEN LOWER(name) LIKE '%card%' THEN 'card'
        WHEN LOWER(name) LIKE '%bank%' OR LOWER(name) LIKE '%transfer%' THEN 'bank_transfer'
        ELSE 'other'
      END
      WHERE provider_key IS NULL OR TRIM(provider_key) = ''
    ''');
  }
}
