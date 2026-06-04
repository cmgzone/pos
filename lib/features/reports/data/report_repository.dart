import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/services/database_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/sync_settings_service.dart';

enum ReportBranchScope { current, all, compare }

/// All reporting queries that go beyond P&L.
/// Each method returns raw maps — the UI layer formats/presents them.
class ReportRepository {
  static const _requestTimeout = Duration(seconds: 15);

  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static bool get _canUseAllBranchReports {
    final role = RolePermissions.normalizeRole(SessionService.currentUserRole);
    return role == RolePermissions.admin || role == RolePermissions.manager;
  }

  static ReportBranchScope _effectiveScope(ReportBranchScope scope) {
    return scope == ReportBranchScope.all && _canUseAllBranchReports
        ? ReportBranchScope.all
        : ReportBranchScope.current;
  }

  static void _addBranchFilter(
    List<String> clauses,
    List<dynamic> args,
    String alias,
    ReportBranchScope scope,
  ) {
    if (_effectiveScope(scope) == ReportBranchScope.all) {
      return;
    }
    clauses.add('COALESCE($alias.branch_id, ?) = ?');
    args.addAll(_currentBranchArgs);
  }

  static Future<Map<String, dynamic>> getZReport({
    DateTime? day,
    ReportBranchScope branchScope = ReportBranchScope.current,
  }) async {
    final target = day ?? DateTime.now();
    final date = _dateOnly(target);
    final clauses = <String>[
      'date(s.created_at) = ?',
      's.deleted_at IS NULL',
      's.refund_sale_id IS NULL',
    ];
    final args = <dynamic>[date];
    _addBranchFilter(clauses, args, 's', branchScope);

    final rows = await DatabaseService.rawQuery('''
      SELECT
        COUNT(s.id) as sale_count,
        COALESCE(SUM(s.total_amount), 0) as total_sales,
        COALESCE(SUM(s.tax), 0) as total_tax,
        COALESCE(SUM(s.discount), 0) as total_discount,
        COALESCE(SUM(s.amount_paid), 0) as amount_paid,
        COALESCE(SUM(s.balance_due), 0) as balance_due,
        COALESCE(SUM(CASE WHEN s.payment_type = 'cash' THEN s.total_amount ELSE 0 END), 0) as cash_sales,
        COALESCE(SUM(CASE WHEN s.payment_type LIKE '%mpesa%' THEN s.total_amount ELSE 0 END), 0) as mpesa_sales,
        COALESCE(SUM(CASE WHEN s.payment_type NOT IN ('cash') AND s.payment_type NOT LIKE '%mpesa%' THEN s.total_amount ELSE 0 END), 0) as other_sales
      FROM sales s
      WHERE ${clauses.join(' AND ')}
      ''', args);
    return {
      'date': date,
      ...Map<String, dynamic>.from(rows.isEmpty ? const {} : rows.first),
    };
  }

  static Future<Map<String, dynamic>> getKenyaVatSummary({
    DateTime? from,
    DateTime? to,
    ReportBranchScope branchScope = ReportBranchScope.current,
  }) async {
    final start = from ?? DateTime(DateTime.now().year, DateTime.now().month);
    final end = to ?? DateTime.now();
    final clauses = <String>[
      'date(s.created_at) BETWEEN ? AND ?',
      's.deleted_at IS NULL',
      's.refund_sale_id IS NULL',
    ];
    final args = <dynamic>[_dateOnly(start), _dateOnly(end)];
    _addBranchFilter(clauses, args, 's', branchScope);

    final rows = await DatabaseService.rawQuery('''
      SELECT
        COALESCE(SUM(s.total_amount), 0) as gross_sales,
        COALESCE(SUM(s.tax), 0) as output_vat,
        COALESCE(SUM(s.total_amount - s.tax), 0) as net_sales,
        COALESCE(SUM(s.discount), 0) as discounts,
        COUNT(s.id) as receipt_count
      FROM sales s
      WHERE ${clauses.join(' AND ')}
      ''', args);
    return {
      'from': _dateOnly(start),
      'to': _dateOnly(end),
      'country': 'KE',
      'currency': 'KES',
      ...Map<String, dynamic>.from(rows.isEmpty ? const {} : rows.first),
    };
  }

  static Future<List<Map<String, dynamic>>> getAccountantExportRows({
    DateTime? from,
    DateTime? to,
    ReportBranchScope branchScope = ReportBranchScope.current,
  }) async {
    final start = from ?? DateTime(DateTime.now().year, DateTime.now().month);
    final end = to ?? DateTime.now();
    final clauses = <String>[
      'date(s.created_at) BETWEEN ? AND ?',
      's.deleted_at IS NULL',
    ];
    final args = <dynamic>[_dateOnly(start), _dateOnly(end)];
    _addBranchFilter(clauses, args, 's', branchScope);
    return DatabaseService.rawQuery('''
      SELECT
        s.id,
        s.created_at,
        s.customer_name,
        s.payment_type,
        s.total_amount,
        s.tax,
        s.discount,
        s.amount_paid,
        s.balance_due,
        s.payment_reference,
        s.etims_status,
        s.etims_invoice_number,
        s.etims_control_unit_invoice_number,
        s.etims_control_unit_serial,
        s.etims_submitted_at,
        s.etims_error,
        s.refund_for_sale_id,
        s.refund_note
      FROM sales s
      WHERE ${clauses.join(' AND ')}
      ORDER BY s.created_at ASC
      ''', args);
  }

  static Future<Map<String, dynamic>> getEtimsSummary({
    DateTime? from,
    DateTime? to,
    ReportBranchScope branchScope = ReportBranchScope.current,
  }) async {
    final start = from ?? DateTime(DateTime.now().year, DateTime.now().month);
    final end = to ?? DateTime.now();
    final clauses = <String>[
      'date(s.created_at) BETWEEN ? AND ?',
      's.deleted_at IS NULL',
      's.refund_sale_id IS NULL',
    ];
    final args = <dynamic>[_dateOnly(start), _dateOnly(end)];
    _addBranchFilter(clauses, args, 's', branchScope);

    final rows = await DatabaseService.rawQuery('''
      SELECT
        COUNT(s.id) as receipt_count,
        COALESCE(SUM(CASE WHEN s.etims_status = 'submitted' THEN 1 ELSE 0 END), 0) as submitted_count,
        COALESCE(SUM(CASE WHEN s.etims_status IN ('pending_sync', 'pending_configuration', 'not_submitted') OR s.etims_status IS NULL THEN 1 ELSE 0 END), 0) as pending_count,
        COALESCE(SUM(CASE WHEN s.etims_status = 'failed' THEN 1 ELSE 0 END), 0) as failed_count
      FROM sales s
      WHERE ${clauses.join(' AND ')}
      ''', args);
    return {
      'from': _dateOnly(start),
      'to': _dateOnly(end),
      ...Map<String, dynamic>.from(rows.isEmpty ? const {} : rows.first),
    };
  }

  static String _dateOnly(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // ── Top Debtors ────────────────────────────────────────────────────────────

  /// Customers sorted by outstanding Kopesha balance descending.
  static Future<List<Map<String, dynamic>>> getTopDebtors({
    int limit = 20,
  }) async {
    return DatabaseService.rawQuery(
      '''
      SELECT
        c.id,
        c.name,
        c.phone,
        c.email,
        c.balance,
        COUNT(s.id) as open_sales,
        MIN(s.due_date) as earliest_due,
        MAX(s.due_date) as latest_due
      FROM customers c
      LEFT JOIN sales s ON s.customer_id = c.id
        AND s.balance_due > 0
        AND s.customer_id IS NOT NULL
        AND s.refund_sale_id IS NULL
        AND s.deleted_at IS NULL
        AND COALESCE(s.branch_id, ?) = ?
      WHERE c.balance > 0
        AND c.deleted_at IS NULL
        AND COALESCE(c.branch_id, ?) = ?
      GROUP BY c.id
      ORDER BY c.balance DESC
      LIMIT $limit
    ''',
      [..._currentBranchArgs, ..._currentBranchArgs],
    );
  }

  // ── Overdue Aging ──────────────────────────────────────────────────────────

  /// Kopesha sales grouped into aging buckets:
  /// current (not yet due), 1-7 days, 8-30 days, 31-60 days, 60+ days.
  static Future<List<Map<String, dynamic>>> getOverdueAging() async {
    return DatabaseService.rawQuery('''
      SELECT
        s.id,
        s.customer_name,
        s.customer_id,
        s.balance_due,
        s.due_date,
        s.created_at,
        CASE
          WHEN s.due_date >= date('now') THEN 'current'
          WHEN julianday('now') - julianday(s.due_date) <= 7  THEN '1_7'
          WHEN julianday('now') - julianday(s.due_date) <= 30 THEN '8_30'
          WHEN julianday('now') - julianday(s.due_date) <= 60 THEN '31_60'
          ELSE 'over_60'
        END as age_bucket,
        CAST(julianday('now') - julianday(s.due_date) AS INTEGER) as days_overdue
      FROM sales s
      WHERE s.balance_due > 0
        AND s.customer_id IS NOT NULL
        AND s.refund_sale_id IS NULL
        AND s.deleted_at IS NULL
        AND COALESCE(s.branch_id, ?) = ?
      ORDER BY s.due_date ASC
    ''', _currentBranchArgs);
  }

  /// Aggregate totals per aging bucket.
  static Future<Map<String, dynamic>> getOverdueAgingSummary() async {
    final rows = await DatabaseService.rawQuery('''
      SELECT
        SUM(CASE WHEN s.due_date >= date('now') THEN s.balance_due ELSE 0 END) as current_amount,
        COUNT(CASE WHEN s.due_date >= date('now') THEN 1 END) as current_count,

        SUM(CASE WHEN julianday('now') - julianday(s.due_date) BETWEEN 0 AND 7
          AND s.due_date < date('now') THEN s.balance_due ELSE 0 END) as d1_7_amount,
        COUNT(CASE WHEN julianday('now') - julianday(s.due_date) BETWEEN 0 AND 7
          AND s.due_date < date('now') THEN 1 END) as d1_7_count,

        SUM(CASE WHEN julianday('now') - julianday(s.due_date) BETWEEN 8 AND 30 THEN s.balance_due ELSE 0 END) as d8_30_amount,
        COUNT(CASE WHEN julianday('now') - julianday(s.due_date) BETWEEN 8 AND 30 THEN 1 END) as d8_30_count,

        SUM(CASE WHEN julianday('now') - julianday(s.due_date) BETWEEN 31 AND 60 THEN s.balance_due ELSE 0 END) as d31_60_amount,
        COUNT(CASE WHEN julianday('now') - julianday(s.due_date) BETWEEN 31 AND 60 THEN 1 END) as d31_60_count,

        SUM(CASE WHEN julianday('now') - julianday(s.due_date) > 60 THEN s.balance_due ELSE 0 END) as over60_amount,
        COUNT(CASE WHEN julianday('now') - julianday(s.due_date) > 60 THEN 1 END) as over60_count,

        SUM(s.balance_due) as total_outstanding,
        COUNT(s.id) as total_count
      FROM sales s
      WHERE s.balance_due > 0
        AND s.customer_id IS NOT NULL
        AND s.refund_sale_id IS NULL
        AND s.deleted_at IS NULL
        AND COALESCE(s.branch_id, ?) = ?
    ''', _currentBranchArgs);
    return rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : {};
  }

  // ── Best & Worst Selling Products ─────────────────────────────────────────

  /// Products ranked by quantity sold and revenue within the given period.
  static Future<List<Map<String, dynamic>>> getTopProducts({
    int daysRange = 30,
    int limit = 20,
    bool ascending = false, // false = best sellers, true = worst sellers
    ReportBranchScope branchScope = ReportBranchScope.current,
  }) async {
    final order = ascending ? 'ASC' : 'DESC';
    final clauses = <String>['p.deleted_at IS NULL'];
    final args = <dynamic>[];
    final salesClauses = <String>[
      's.created_at >= datetime(\'now\', \'-$daysRange days\')',
      's.refund_sale_id IS NULL',
      's.deleted_at IS NULL',
    ];
    final salesArgs = <dynamic>[];
    _addBranchFilter(salesClauses, salesArgs, 's', branchScope);
    _addBranchFilter(clauses, args, 'p', branchScope);

    return DatabaseService.rawQuery(
      '''
      SELECT
        p.id,
        p.name,
        p.sku,
        p.category_id,
        p.image_url,
        p.stock,
        p.unit,
        p.sale_unit,
        p.stock_unit,
        COALESCE(SUM(CASE WHEN s.id IS NOT NULL THEN si.quantity ELSE 0 END), 0) as total_qty_sold,
        COALESCE(SUM(CASE WHEN s.id IS NOT NULL THEN si.quantity * si.unit_price ELSE 0 END), 0) as total_revenue,
        COALESCE(SUM(CASE WHEN s.id IS NOT NULL THEN si.quantity * si.unit_cost ELSE 0 END), 0) as total_cost,
        COALESCE(SUM(CASE WHEN s.id IS NOT NULL THEN si.quantity * (si.unit_price - si.unit_cost) ELSE 0 END), 0) as total_profit,
        COUNT(DISTINCT s.id) as transaction_count
      FROM products p
      LEFT JOIN sale_items si ON si.product_id = p.id
      LEFT JOIN sales s ON s.id = si.sale_id
        AND ${salesClauses.join(' AND ')}
      WHERE ${clauses.join(' AND ')}
      GROUP BY p.id
      ORDER BY total_qty_sold $order, total_revenue $order
      LIMIT $limit
    ''',
      [...salesArgs, ...args],
    );
  }

  /// Stock received (purchases) vs sold per product for the period.
  static Future<List<Map<String, dynamic>>> getStockMovement({
    int daysRange = 30,
    int limit = 30,
    ReportBranchScope branchScope = ReportBranchScope.current,
  }) async {
    final receivedClauses = <String>[
      'received_at >= datetime(\'now\', \'-$daysRange days\')',
      'deleted_at IS NULL',
    ];
    final receivedArgs = <dynamic>[];
    _addBranchFilter(
      receivedClauses,
      receivedArgs,
      'stock_batches',
      branchScope,
    );

    final soldClauses = <String>[
      's.created_at >= datetime(\'now\', \'-$daysRange days\')',
      's.refund_sale_id IS NULL',
      's.deleted_at IS NULL',
    ];
    final soldArgs = <dynamic>[];
    _addBranchFilter(soldClauses, soldArgs, 's', branchScope);

    final productClauses = <String>['p.deleted_at IS NULL'];
    final productArgs = <dynamic>[];
    _addBranchFilter(productClauses, productArgs, 'p', branchScope);

    return DatabaseService.rawQuery(
      '''
      SELECT
        p.id,
        p.name,
        p.sku,
        p.stock as current_stock,
        p.low_stock,
        p.stock_unit,
        p.unit,
        COALESCE(received.qty_in, 0) as qty_in,
        COALESCE(sold.qty_out, 0) as qty_out,
        COALESCE(received.qty_in, 0) - COALESCE(sold.qty_out, 0) as net_movement,
        CASE
          WHEN p.stock <= 0 THEN 'out'
          WHEN p.stock <= p.low_stock THEN 'low'
          ELSE 'ok'
        END as stock_status
      FROM products p
      LEFT JOIN (
        SELECT product_id, SUM(quantity_received) as qty_in
        FROM stock_batches
        WHERE ${receivedClauses.join(' AND ')}
        GROUP BY product_id
      ) received ON received.product_id = p.id
      LEFT JOIN (
        SELECT si.product_id, SUM(si.quantity) as qty_out
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        WHERE ${soldClauses.join(' AND ')}
        GROUP BY si.product_id
      ) sold ON sold.product_id = p.id
      WHERE ${productClauses.join(' AND ')}
        AND (COALESCE(received.qty_in, 0) > 0 OR COALESCE(sold.qty_out, 0) > 0)
      ORDER BY qty_out DESC, qty_in DESC
      LIMIT $limit
    ''',
      [...receivedArgs, ...soldArgs, ...productArgs],
    );
  }

  // ── Branch Comparison ──────────────────────────────────────────────────────

  /// Per-branch aggregates: revenue, profit, expenses, product/service
  /// revenue, sales count, and refund totals for a given date range.
  /// Only available for managers and admins.
  static Future<List<Map<String, dynamic>>> getBranchComparison({
    int daysRange = 30,
  }) async {
    if (!_canUseAllBranchReports) {
      return const [];
    }
    return DatabaseService.rawQuery('''
      SELECT
        b.id                as branch_id,
        b.name              as branch_name,
        COALESCE(agg.revenue, 0)          as revenue,
        COALESCE(agg.gross_profit, 0)     as gross_profit,
        COALESCE(agg.product_revenue, 0)  as product_revenue,
        COALESCE(agg.service_revenue, 0)  as service_revenue,
        COALESCE(agg.sale_count, 0)       as sale_count,
        COALESCE(agg.refund_total, 0)     as refund_total,
        COALESCE(agg.refund_count, 0)     as refund_count,
        COALESCE(exp.total_expenses, 0)   as total_expenses,
        COALESCE(agg.gross_profit, 0) - COALESCE(exp.total_expenses, 0) as net_profit
      FROM branches b
      LEFT JOIN (
        SELECT
          COALESCE(s.branch_id, '${DatabaseService.defaultBranchId}') as bid,
          SUM(CASE WHEN s.refund_sale_id IS NULL THEN s.total_amount ELSE 0 END) as revenue,
          SUM(CASE WHEN s.refund_sale_id IS NULL THEN
            COALESCE((SELECT SUM(si.quantity * (si.unit_price - si.unit_cost)) FROM sale_items si WHERE si.sale_id = s.id), 0)
            + COALESCE((SELECT SUM(ssi.quantity * ssi.unit_price) FROM service_sale_items ssi WHERE ssi.sale_id = s.id), 0)
          ELSE 0 END) as gross_profit,
          SUM(CASE WHEN s.refund_sale_id IS NULL THEN
            COALESCE((SELECT SUM(si.quantity * si.unit_price) FROM sale_items si WHERE si.sale_id = s.id), 0)
          ELSE 0 END) as product_revenue,
          SUM(CASE WHEN s.refund_sale_id IS NULL THEN
            COALESCE((SELECT SUM(ssi.quantity * ssi.unit_price) FROM service_sale_items ssi WHERE ssi.sale_id = s.id), 0)
          ELSE 0 END) as service_revenue,
          COUNT(CASE WHEN s.refund_sale_id IS NULL THEN 1 END) as sale_count,
          SUM(CASE WHEN s.refund_sale_id IS NOT NULL THEN ABS(s.total_amount) ELSE 0 END) as refund_total,
          COUNT(CASE WHEN s.refund_sale_id IS NOT NULL THEN 1 END) as refund_count
        FROM sales s
        WHERE s.deleted_at IS NULL
          AND s.created_at >= datetime('now', '-$daysRange days')
        GROUP BY bid
      ) agg ON agg.bid = b.id
      LEFT JOIN (
        SELECT
          COALESCE(e.branch_id, '${DatabaseService.defaultBranchId}') as bid,
          SUM(e.amount) as total_expenses
        FROM expenses e
        WHERE e.incurred_on >= date('now', '-$daysRange days')
          AND e.deleted_at IS NULL
        GROUP BY bid
      ) exp ON exp.bid = b.id
      WHERE b.deleted_at IS NULL
      ORDER BY COALESCE(agg.revenue, 0) DESC, b.name COLLATE NOCASE ASC
    ''');
  }

  // ── Daily Cashier Summary ──────────────────────────────────────────────────

  /// Today's sales summary — totals, payment split, top products.
  static Future<Map<String, dynamic>> getDailySummary({
    String? date, // defaults to today
    String? cashierId,
    ReportBranchScope branchScope = ReportBranchScope.current,
  }) async {
    final d = date ?? DateTime.now().toIso8601String().substring(0, 10);
    final normalizedCashierId = cashierId?.trim();
    final summaryWhere = <String>[
      'DATE(s.created_at) = ?',
      's.refund_sale_id IS NULL',
      's.deleted_at IS NULL',
    ];
    final summaryArgs = <dynamic>[d];
    _addBranchFilter(summaryWhere, summaryArgs, 's', branchScope);
    if (normalizedCashierId != null && normalizedCashierId.isNotEmpty) {
      summaryWhere.add('s.user_id = ?');
      summaryArgs.add(normalizedCashierId);
    }

    final rows = await DatabaseService.rawQuery('''
      SELECT
        COUNT(*) as total_sales,
        COALESCE(SUM(s.total_amount), 0) as total_revenue,
        COALESCE(SUM(s.tax), 0) as total_tax,
        COALESCE(SUM(s.discount), 0) as total_discount,
        SUM(CASE WHEN s.is_cash_drawer = 1 THEN s.total_amount ELSE 0 END) as cash_revenue,
        SUM(CASE WHEN s.balance_due > 0 THEN s.total_amount ELSE 0 END) as kopesha_revenue,
        COUNT(CASE WHEN s.is_cash_drawer = 1 THEN 1 END) as cash_count,
        COUNT(CASE WHEN s.balance_due > 0 THEN 1 END) as kopesha_count,
        COALESCE(SUM((SELECT COALESCE(SUM(si.quantity * si.unit_price), 0) FROM sale_items si WHERE si.sale_id = s.id)), 0) as product_revenue,
        COALESCE(SUM((SELECT COALESCE(SUM(ssi.quantity * ssi.unit_price), 0) FROM service_sale_items ssi WHERE ssi.sale_id = s.id)), 0) as service_revenue,
        COUNT(CASE WHEN EXISTS (SELECT 1 FROM sale_items si WHERE si.sale_id = s.id) THEN 1 END) as product_sales,
        COUNT(CASE WHEN EXISTS (SELECT 1 FROM service_sale_items ssi WHERE ssi.sale_id = s.id) THEN 1 END) as service_sales
      FROM sales s
      WHERE ${summaryWhere.join(' AND ')}
    ''', summaryArgs);

    final summary = rows.isNotEmpty
        ? Map<String, dynamic>.from(rows.first)
        : <String, dynamic>{};
    summary['date'] = d;
    final profitWhere = <String>[
      'DATE(s.created_at) = ?',
      's.refund_sale_id IS NULL',
      's.deleted_at IS NULL',
    ];
    final profitArgs = <dynamic>[d];
    _addBranchFilter(profitWhere, profitArgs, 's', branchScope);
    if (normalizedCashierId != null && normalizedCashierId.isNotEmpty) {
      profitWhere.add('s.user_id = ?');
      profitArgs.add(normalizedCashierId);
    }

    final profitRows = await DatabaseService.rawQuery('''
      SELECT
        COALESCE(SUM(
          COALESCE((
            SELECT SUM(si.quantity * (si.unit_price - si.unit_cost))
            FROM sale_items si
            WHERE si.sale_id = s.id
          ), 0)
          + COALESCE((
            SELECT SUM(ssi.quantity * ssi.unit_price)
            FROM service_sale_items ssi
            WHERE ssi.sale_id = s.id
          ), 0)
        ), 0) as gross_profit,
        COALESCE(SUM((
          SELECT COALESCE(SUM(si.quantity * si.unit_cost), 0)
          FROM sale_items si
          WHERE si.sale_id = s.id
        )), 0) as total_cost
      FROM sales s
      WHERE ${profitWhere.join(' AND ')}
    ''', profitArgs);
    if (profitRows.isNotEmpty) {
      summary.addAll(Map<String, dynamic>.from(profitRows.first));
    }

    // Top 5 products for today
    final topProductsWhere = <String>[
      'DATE(s.created_at) = ?',
      's.refund_sale_id IS NULL',
      's.deleted_at IS NULL',
    ];
    final topProductsArgs = <dynamic>[d];
    _addBranchFilter(topProductsWhere, topProductsArgs, 's', branchScope);
    if (normalizedCashierId != null && normalizedCashierId.isNotEmpty) {
      topProductsWhere.add('s.user_id = ?');
      topProductsArgs.add(normalizedCashierId);
    }

    final topProducts = await DatabaseService.rawQuery('''
      SELECT
        p.name,
        p.sale_unit,
        SUM(si.quantity) as qty_sold,
        SUM(si.quantity * si.unit_price) as revenue
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      JOIN products p ON p.id = si.product_id
      WHERE ${topProductsWhere.join(' AND ')}
      GROUP BY si.product_id
      ORDER BY qty_sold DESC
      LIMIT 5
    ''', topProductsArgs);
    summary['top_products'] = topProducts;

    final topServicesWhere = <String>[
      'DATE(s.created_at) = ?',
      's.refund_sale_id IS NULL',
      's.deleted_at IS NULL',
    ];
    final topServicesArgs = <dynamic>[d];
    _addBranchFilter(topServicesWhere, topServicesArgs, 's', branchScope);
    if (normalizedCashierId != null && normalizedCashierId.isNotEmpty) {
      topServicesWhere.add('s.user_id = ?');
      topServicesArgs.add(normalizedCashierId);
    }

    final topServices = await DatabaseService.rawQuery('''
      SELECT
        ssi.service_name as name,
        SUM(ssi.quantity) as qty_sold,
        SUM(ssi.quantity * ssi.unit_price) as revenue
      FROM service_sale_items ssi
      JOIN sales s ON s.id = ssi.sale_id
      WHERE ${topServicesWhere.join(' AND ')}
      GROUP BY ssi.service_id, ssi.service_name
      ORDER BY revenue DESC, qty_sold DESC
      LIMIT 5
    ''', topServicesArgs);
    summary['top_services'] = topServices;

    return summary;
  }

  static Future<List<Map<String, dynamic>>> getDailyCashierSummary({
    String? date,
    String? cashierId,
  }) async {
    final d = date ?? DateTime.now().toIso8601String().substring(0, 10);
    final normalizedCashierId = cashierId?.trim();
    final remoteRows = await _fetchRemoteDailyCashierSummary(
      date: d,
      cashierId: normalizedCashierId,
    );
    if (remoteRows != null) {
      return remoteRows;
    }

    final baseWhere = <String>[
      'DATE(s.created_at) = ?',
      's.deleted_at IS NULL',
      'COALESCE(s.branch_id, ?) = ?',
    ];
    final args = <dynamic>[d, ..._currentBranchArgs];
    if (normalizedCashierId != null && normalizedCashierId.isNotEmpty) {
      baseWhere.add('s.user_id = ?');
      args.add(normalizedCashierId);
    }

    return DatabaseService.rawQuery('''
      SELECT
        base.cashier_id,
        COALESCE(
          NULLIF(TRIM(u.name), ''),
          CASE
            WHEN base.cashier_id = 'admin' THEN 'Admin'
            WHEN COALESCE(base.cashier_id, '') = '' THEN 'Unknown Cashier'
            ELSE base.cashier_id
          END
        ) as cashier_name,
        COALESCE(u.role, 'CASHIER') as cashier_role,
        COUNT(CASE WHEN base.payment_type NOT LIKE 'refund%' THEN 1 END) as total_sales,
        COALESCE(SUM(CASE WHEN base.payment_type NOT LIKE 'refund%' THEN base.total_amount ELSE 0 END), 0) as total_revenue,
        COALESCE(SUM(CASE WHEN base.is_cash_drawer = 1 THEN base.total_amount ELSE 0 END), 0) as cash_revenue,
        COALESCE(SUM(CASE WHEN base.balance_due > 0 THEN base.total_amount ELSE 0 END), 0) as kopesha_revenue,
        COALESCE(SUM(CASE WHEN base.payment_type NOT LIKE 'refund%' THEN base.product_line_revenue ELSE 0 END), 0) as product_revenue,
        COALESCE(SUM(CASE WHEN base.payment_type NOT LIKE 'refund%' THEN base.service_line_revenue ELSE 0 END), 0) as service_revenue,
        COUNT(CASE WHEN base.has_product_items = 1 AND base.payment_type NOT LIKE 'refund%' THEN 1 END) as product_sales,
        COUNT(CASE WHEN base.has_service_items = 1 AND base.payment_type NOT LIKE 'refund%' THEN 1 END) as service_sales,
        COALESCE(SUM(CASE WHEN base.payment_type NOT LIKE 'refund%' THEN base.sale_profit ELSE 0 END), 0) as gross_profit,
        COALESCE(SUM(CASE WHEN base.payment_type LIKE 'refund%' THEN ABS(base.total_amount) ELSE 0 END), 0) as refunds_issued,
        COUNT(CASE WHEN base.payment_type LIKE 'refund%' THEN 1 END) as refund_count,
        MIN(CASE WHEN base.payment_type NOT LIKE 'refund%' THEN base.created_at END) as first_sale_at,
        MAX(CASE WHEN base.payment_type NOT LIKE 'refund%' THEN base.created_at END) as last_sale_at
      FROM (
        SELECT
          COALESCE(s.user_id, '') as cashier_id,
          s.payment_type,
          s.total_amount,
          s.created_at,
          s.is_cash_drawer,
          s.balance_due,
          CASE WHEN EXISTS (SELECT 1 FROM sale_items si WHERE si.sale_id = s.id) THEN 1 ELSE 0 END as has_product_items,
          CASE WHEN EXISTS (SELECT 1 FROM service_sale_items ssi WHERE ssi.sale_id = s.id) THEN 1 ELSE 0 END as has_service_items,
          COALESCE((SELECT SUM(si.quantity * si.unit_price) FROM sale_items si WHERE si.sale_id = s.id), 0) as product_line_revenue,
          COALESCE((SELECT SUM(ssi.quantity * ssi.unit_price) FROM service_sale_items ssi WHERE ssi.sale_id = s.id), 0) as service_line_revenue,
          (
            COALESCE((
              SELECT SUM(si.quantity * (si.unit_price - si.unit_cost))
              FROM sale_items si
              WHERE si.sale_id = s.id
            ), 0)
            + COALESCE((
              SELECT SUM(ssi.quantity * ssi.unit_price)
              FROM service_sale_items ssi
              WHERE ssi.sale_id = s.id
            ), 0)
            - s.discount
          ) as sale_profit
        FROM sales s
        WHERE ${baseWhere.join(' AND ')}
      ) base
      LEFT JOIN users u ON u.id = base.cashier_id
      GROUP BY base.cashier_id, cashier_name, cashier_role
      ORDER BY total_revenue DESC, total_sales DESC, cashier_name COLLATE NOCASE ASC
    ''', args);
  }

  static Future<List<Map<String, dynamic>>?> _fetchRemoteDailyCashierSummary({
    required String date,
    String? cashierId,
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      return null;
    }

    final queryParameters = <String, String>{'date': date};
    final currentUserId = SessionService.currentUserId;
    if (currentUserId.isNotEmpty) {
      queryParameters['userId'] = currentUserId;
    }
    queryParameters['branchId'] = DatabaseService.currentBranchId;
    if (cashierId != null && cashierId.isNotEmpty) {
      queryParameters['cashierId'] = cashierId;
    }

    final uri = Uri.parse(
      '$backendUrl/api/reports/daily-cashier-summary',
    ).replace(queryParameters: queryParameters);
    final client = http.Client();
    try {
      final response = await client.get(uri).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        return null;
      }

      final cashiers = body['cashiers'];
      if (cashiers is! List) {
        return null;
      }

      return cashiers
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
