import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/services/database_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/sync_settings_service.dart';

/// All reporting queries that go beyond P&L.
/// Each method returns raw maps — the UI layer formats/presents them.
class ReportRepository {
  static const _requestTimeout = Duration(seconds: 15);

  // ── Top Debtors ────────────────────────────────────────────────────────────

  /// Customers sorted by outstanding Kopesha balance descending.
  static Future<List<Map<String, dynamic>>> getTopDebtors({
    int limit = 20,
  }) async {
    return DatabaseService.rawQuery('''
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
        AND s.payment_type = 'kopesha'
        AND s.balance_due > 0
        AND s.refund_sale_id IS NULL
      WHERE c.balance > 0
      GROUP BY c.id
      ORDER BY c.balance DESC
      LIMIT $limit
    ''');
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
      WHERE s.payment_type = 'kopesha'
        AND s.balance_due > 0
        AND s.refund_sale_id IS NULL
      ORDER BY s.due_date ASC
    ''');
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
      WHERE s.payment_type = 'kopesha'
        AND s.balance_due > 0
        AND s.refund_sale_id IS NULL
    ''');
    return rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : {};
  }

  // ── Best & Worst Selling Products ─────────────────────────────────────────

  /// Products ranked by quantity sold and revenue within the given period.
  static Future<List<Map<String, dynamic>>> getTopProducts({
    int daysRange = 30,
    int limit = 20,
    bool ascending = false, // false = best sellers, true = worst sellers
  }) async {
    final order = ascending ? 'ASC' : 'DESC';
    return DatabaseService.rawQuery('''
      SELECT
        p.id,
        p.name,
        p.sku,
        p.category_id,
        p.stock,
        p.unit,
        p.sale_unit,
        p.stock_unit,
        COALESCE(SUM(si.quantity), 0) as total_qty_sold,
        COALESCE(SUM(si.quantity * si.unit_price), 0) as total_revenue,
        COALESCE(SUM(si.quantity * si.unit_cost), 0) as total_cost,
        COALESCE(SUM(si.quantity * si.unit_price) - SUM(si.quantity * si.unit_cost), 0) as total_profit,
        COUNT(DISTINCT s.id) as transaction_count
      FROM products p
      LEFT JOIN sale_items si ON si.product_id = p.id
      LEFT JOIN sales s ON s.id = si.sale_id
        AND s.created_at >= datetime('now', '-$daysRange days')
        AND s.refund_sale_id IS NULL
      GROUP BY p.id
      ORDER BY total_qty_sold $order, total_revenue $order
      LIMIT $limit
    ''');
  }

  // ── Stock Movement ─────────────────────────────────────────────────────────

  /// Stock received (purchases) vs sold per product for the period.
  static Future<List<Map<String, dynamic>>> getStockMovement({
    int daysRange = 30,
    int limit = 30,
  }) async {
    return DatabaseService.rawQuery('''
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
        WHERE received_at >= datetime('now', '-$daysRange days')
        GROUP BY product_id
      ) received ON received.product_id = p.id
      LEFT JOIN (
        SELECT si.product_id, SUM(si.quantity) as qty_out
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        WHERE s.created_at >= datetime('now', '-$daysRange days')
          AND s.refund_sale_id IS NULL
        GROUP BY si.product_id
      ) sold ON sold.product_id = p.id
      WHERE COALESCE(received.qty_in, 0) > 0 OR COALESCE(sold.qty_out, 0) > 0
      ORDER BY qty_out DESC, qty_in DESC
      LIMIT $limit
    ''');
  }

  // ── Daily Cashier Summary ──────────────────────────────────────────────────

  /// Today's sales summary — totals, payment split, top products.
  static Future<Map<String, dynamic>> getDailySummary({
    String? date, // defaults to today
    String? cashierId,
  }) async {
    final d = date ?? DateTime.now().toIso8601String().substring(0, 10);
    final normalizedCashierId = cashierId?.trim();
    final summaryWhere = <String>[
      'DATE(s.created_at) = ?',
      's.refund_sale_id IS NULL',
    ];
    final summaryArgs = <dynamic>[d];
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
        SUM(CASE WHEN s.payment_type = 'cash' THEN s.total_amount ELSE 0 END) as cash_revenue,
        SUM(CASE WHEN s.payment_type = 'kopesha' THEN s.total_amount ELSE 0 END) as kopesha_revenue,
        COUNT(CASE WHEN s.payment_type = 'cash' THEN 1 END) as cash_count,
        COUNT(CASE WHEN s.payment_type = 'kopesha' THEN 1 END) as kopesha_count
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
    ];
    final profitArgs = <dynamic>[d];
    if (normalizedCashierId != null && normalizedCashierId.isNotEmpty) {
      profitWhere.add('s.user_id = ?');
      profitArgs.add(normalizedCashierId);
    }

    final profitRows = await DatabaseService.rawQuery('''
      SELECT
        COALESCE(SUM(si.quantity * (si.unit_price - si.unit_cost)), 0) as gross_profit,
        COALESCE(SUM(si.quantity * si.unit_cost), 0) as total_cost
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE ${profitWhere.join(' AND ')}
    ''', profitArgs);
    if (profitRows.isNotEmpty) {
      summary.addAll(Map<String, dynamic>.from(profitRows.first));
    }

    // Top 5 products for today
    final topProductsWhere = <String>[
      'DATE(s.created_at) = ?',
      's.refund_sale_id IS NULL',
    ];
    final topProductsArgs = <dynamic>[d];
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

    final baseWhere = <String>['DATE(s.created_at) = ?'];
    final args = <dynamic>[d];
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
        COALESCE(SUM(CASE WHEN base.payment_type = 'cash' THEN base.total_amount ELSE 0 END), 0) as cash_revenue,
        COALESCE(SUM(CASE WHEN base.payment_type = 'kopesha' THEN base.total_amount ELSE 0 END), 0) as kopesha_revenue,
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
          COALESCE((
            SELECT SUM(si.quantity * (si.unit_price - si.unit_cost))
            FROM sale_items si
            WHERE si.sale_id = s.id
          ), 0) - s.discount as sale_profit
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
