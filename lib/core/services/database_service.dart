import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  static const String _databaseName = 'velora_pos.db';
  static const int _databaseVersion = 7;

  static Database? _database;
  static String? _databasePath;

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

  static Future<void> initialize() async {
    if (_database != null) {
      return;
    }

    _configureDatabaseFactory();

    final databasesDirectory = await getDatabasesPath();
    await Directory(databasesDirectory).create(recursive: true);
    _databasePath =
        '$databasesDirectory${Platform.pathSeparator}$_databaseName';

    _database = await openDatabase(
      _databasePath!,
      version: _databaseVersion,
      onConfigure: _onConfigure,
      onCreate: (database, version) async {
        await _createTables(database);
        await _createIndexes(database);
        await _runMigrations(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        await _createTables(database);
        await _createIndexes(database);
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

    return database.insert(table, payload);
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

    return database.update(table, payload, where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> delete(String table, String id) async {
    final database = await _ensureDatabase();
    final columns = await _getColumnNames(database, table);
    if (columns.contains('deleted_at')) {
      final now = DateTime.now().toIso8601String();
      return database.update(
        table,
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    return database.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  static Future<Database> _ensureDatabase() async {
    await initialize();
    return db;
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
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
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
        category_id TEXT,
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
      CREATE TABLE IF NOT EXISTS sales (
        id TEXT PRIMARY KEY,
        total_amount REAL NOT NULL DEFAULT 0,
        tax REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        payment_type TEXT NOT NULL,
        user_id TEXT,
        customer_id TEXT,
        customer_name TEXT,
        due_date TEXT,
        amount_paid REAL NOT NULL DEFAULT 0,
        amount_tendered REAL NOT NULL DEFAULT 0,
        change_given REAL NOT NULL DEFAULT 0,
        balance_due REAL NOT NULL DEFAULT 0,
        refund_sale_id TEXT,
        refund_for_sale_id TEXT,
        refund_note TEXT,
        refunded_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
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
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY,
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
        supplier_id TEXT,
        supplier_name TEXT,
        invoice_number TEXT,
        total_amount REAL NOT NULL DEFAULT 0,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS stock_batches (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        quantity_received REAL NOT NULL DEFAULT 0,
        quantity_remaining REAL NOT NULL DEFAULT 0,
        unit_cost REAL NOT NULL DEFAULT 0,
        purchase_id TEXT,
        supplier_id TEXT,
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
      CREATE TABLE IF NOT EXISTS credit_payments (
        id TEXT PRIMARY KEY,
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
  }

  static Future<void> _createIndexes(DatabaseExecutor database) async {
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_customer_id ON sales(customer_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_user_id ON sales(user_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_refund_sale_id ON sales(refund_sale_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_refund_for_sale_id ON sales(refund_for_sale_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON sale_items(product_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_batches_product_id ON stock_batches(product_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_batches_purchase_id ON stock_batches(purchase_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_stock_batches_received_at ON stock_batches(received_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_credit_payments_customer_id ON credit_payments(customer_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_credit_payments_group_id ON credit_payments(payment_group_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_purchase_invoices_supplier_id ON purchase_invoices(supplier_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_incurred_on ON expenses(incurred_on)',
    );
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique ON users(email)',
    );
  }

  static Future<void> _runMigrations(DatabaseExecutor database) async {
    await _createTables(database);
    await _createIndexes(database);
    await _ensureProductUnitConversionSchema(database);
    await _ensureUserProfileSchema(database);
    await _ensureSalesPaymentSchema(database);
    await _ensureSalesRefundSchema(database);
    await _ensurePurchaseSchema(database);
    await _ensureCreditPaymentSchema(database);
    await _ensureExpenseSchema(database);
    await _ensureSyncMetadataSchema(database);
    await _ensureCloudAuthSchema(database);
    await _ensureUserLastSeenSchema(database);
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
      column: 'category_id',
      definition: 'TEXT',
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

  static Future<void> _ensureSyncMetadataSchema(
    DatabaseExecutor database,
  ) async {
    for (final table in const [
      'categories',
      'products',
      'users',
      'customers',
      'sales',
      'sale_items',
      'suppliers',
      'purchase_invoices',
      'stock_batches',
      'credit_payments',
      'expense_categories',
      'expenses',
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
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor database, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final columns = await _getColumnNames(database, table);
    if (columns.contains(column)) {
      return;
    }
    await database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
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

  static Future<void> _ensureCloudAuthSchema(
    DatabaseExecutor database,
  ) async {
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
}
