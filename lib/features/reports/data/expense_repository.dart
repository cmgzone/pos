import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';

const _uuid = Uuid();

class ExpenseRepository {
  static List<dynamic> get _currentBranchArgs => [
    DatabaseService.defaultBranchId,
    DatabaseService.currentBranchId,
  ];

  static Future<List<Map<String, dynamic>>> getCategories() async {
    return DatabaseService.queryAll(
      'expense_categories',
      where: 'deleted_at IS NULL AND COALESCE(branch_id, ?) = ?',
      whereArgs: _currentBranchArgs,
      orderBy: 'name ASC',
    );
  }

  static Future<String> createCategory({
    required String name,
    String? color,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'create expense categories');
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Category name is required');
    }

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await DatabaseService.insert('expense_categories', {
      'id': id,
      'name': trimmedName,
      'color': color,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    return id;
  }

  static Future<String> createExpense({
    required String title,
    required double amount,
    required String incurredOn,
    String? categoryId,
    String? categoryName,
    String? note,
  }) async {
    await LicenseService.ensureWriteAccess(action: 'record expenses');
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw Exception('Expense title is required');
    }
    if (amount <= 0) {
      throw Exception('Expense amount must be greater than zero');
    }

    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await DatabaseService.insert('expenses', {
      'id': id,
      'category_id': categoryId,
      'category_name': categoryName,
      'title': trimmedTitle,
      'amount': amount,
      'note': note?.trim(),
      'incurred_on': incurredOn,
      'created_at': now,
      'updated_at': now,
      'sync_status': 'pending',
    });
    return id;
  }

  static Future<List<Map<String, dynamic>>> getRecentExpenses({
    int daysRange = 30,
    int limit = 10,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final range = _resolveDateRange(
      daysRange: daysRange,
      startDate: startDate,
      endDate: endDate,
    );
    return DatabaseService.rawQuery(
      '''
      SELECT *
      FROM expenses
      WHERE DATE(incurred_on) BETWEEN DATE(?) AND DATE(?)
        AND COALESCE(branch_id, ?) = ?
      ORDER BY incurred_on DESC, created_at DESC
      LIMIT $limit
      ''',
      [range.start, range.end, ..._currentBranchArgs],
    );
  }

  static Future<List<Map<String, dynamic>>> getDailyProfitLoss({
    required int daysRange,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final range = _resolveDateRange(
      daysRange: daysRange,
      startDate: startDate,
      endDate: endDate,
    );
    return DatabaseService.rawQuery(
      '''
      WITH daily_sales AS (
        SELECT
          DATE(s.created_at) as day_key,
          COUNT(*) as sale_count,
          COALESCE(SUM(
            COALESCE((
              SELECT SUM(si.quantity * si.unit_price)
              FROM sale_items si
              WHERE si.sale_id = s.id
            ), 0)
            + COALESCE((
              SELECT SUM(ssi.quantity * ssi.unit_price)
              FROM service_sale_items ssi
              WHERE ssi.sale_id = s.id
            ), 0)
          ), 0) as revenue,
          COALESCE(SUM((
            SELECT COALESCE(SUM(si.quantity * si.unit_cost), 0)
            FROM sale_items si
            WHERE si.sale_id = s.id
          )), 0) as total_cost,
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
          COALESCE(SUM(s.tax), 0) as tax,
          COALESCE(SUM(s.discount), 0) as discount
        FROM sales s
        WHERE DATE(s.created_at) BETWEEN DATE(?) AND DATE(?)
          AND s.deleted_at IS NULL
          AND s.refund_for_sale_id IS NULL
          AND COALESCE(s.branch_id, ?) = ?
        GROUP BY DATE(s.created_at)
      ),
      daily_expenses AS (
        SELECT
          DATE(e.incurred_on) as day_key,
          COALESCE(SUM(e.amount), 0) as total_expenses
        FROM expenses e
        WHERE DATE(e.incurred_on) BETWEEN DATE(?) AND DATE(?)
          AND COALESCE(e.branch_id, ?) = ?
        GROUP BY DATE(e.incurred_on)
      ),
      all_days AS (
        SELECT day_key FROM daily_sales
        UNION
        SELECT day_key FROM daily_expenses
      )
      SELECT
        all_days.day_key as sale_date,
        COALESCE(ds.sale_count, 0) as sale_count,
        COALESCE(ds.revenue, 0) as revenue,
        COALESCE(ds.total_cost, 0) as total_cost,
        COALESCE(ds.gross_profit, 0) as gross_profit,
        COALESCE(de.total_expenses, 0) as total_expenses,
        COALESCE(ds.gross_profit, 0) - COALESCE(de.total_expenses, 0) as net_profit,
        COALESCE(ds.tax, 0) as tax,
        COALESCE(ds.discount, 0) as discount
      FROM all_days
      LEFT JOIN daily_sales ds ON ds.day_key = all_days.day_key
      LEFT JOIN daily_expenses de ON de.day_key = all_days.day_key
      ORDER BY all_days.day_key DESC
      ''',
      [
        range.start,
        range.end,
        ..._currentBranchArgs,
        range.start,
        range.end,
        ..._currentBranchArgs,
      ],
    );
  }

  static Future<Map<String, dynamic>> getProfitLossTotals({
    required int daysRange,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final range = _resolveDateRange(
      daysRange: daysRange,
      startDate: startDate,
      endDate: endDate,
    );
    final rows = await DatabaseService.rawQuery(
      '''
      WITH sales_totals AS (
        SELECT
          COALESCE(SUM(
            COALESCE((
              SELECT SUM(si.quantity * si.unit_price)
              FROM sale_items si
              WHERE si.sale_id = s.id
            ), 0)
            + COALESCE((
              SELECT SUM(ssi.quantity * ssi.unit_price)
              FROM service_sale_items ssi
              WHERE ssi.sale_id = s.id
            ), 0)
          ), 0) as total_revenue,
          COALESCE(SUM((
            SELECT COALESCE(SUM(si.quantity * si.unit_cost), 0)
            FROM sale_items si
            WHERE si.sale_id = s.id
          )), 0) as total_cost,
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
          COUNT(*) as total_sales,
          COALESCE(SUM(s.tax), 0) as total_tax,
          COALESCE(SUM(s.discount), 0) as total_discount
        FROM sales s
        WHERE DATE(s.created_at) BETWEEN DATE(?) AND DATE(?)
          AND s.deleted_at IS NULL
          AND s.refund_for_sale_id IS NULL
          AND COALESCE(s.branch_id, ?) = ?
      ),
      expense_totals AS (
        SELECT
          COALESCE(SUM(amount), 0) as total_expenses
        FROM expenses
        WHERE DATE(incurred_on) BETWEEN DATE(?) AND DATE(?)
          AND COALESCE(branch_id, ?) = ?
      )
      SELECT
        sales_totals.total_revenue,
        sales_totals.total_cost,
        sales_totals.gross_profit,
        sales_totals.total_sales,
        sales_totals.total_tax,
        sales_totals.total_discount,
        expense_totals.total_expenses,
        sales_totals.gross_profit - expense_totals.total_expenses as net_profit
      FROM sales_totals, expense_totals
      ''',
      [
        range.start,
        range.end,
        ..._currentBranchArgs,
        range.start,
        range.end,
        ..._currentBranchArgs,
      ],
    );

    return rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : {};
  }

  static Future<List<Map<String, dynamic>>> getExpenseCategoryTotals({
    required int daysRange,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final range = _resolveDateRange(
      daysRange: daysRange,
      startDate: startDate,
      endDate: endDate,
    );
    return DatabaseService.rawQuery(
      '''
      SELECT
        COALESCE(category_name, 'Uncategorized') as category_name,
        COALESCE(SUM(amount), 0) as total_amount,
        COUNT(*) as expense_count
      FROM expenses
      WHERE DATE(incurred_on) BETWEEN DATE(?) AND DATE(?)
        AND COALESCE(branch_id, ?) = ?
      GROUP BY COALESCE(category_name, 'Uncategorized')
      ORDER BY total_amount DESC, category_name ASC
      ''',
      [range.start, range.end, ..._currentBranchArgs],
    );
  }

  static Future<List<Map<String, dynamic>>> getDailyExpenseCategoryReport({
    required int daysRange,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final range = _resolveDateRange(
      daysRange: daysRange,
      startDate: startDate,
      endDate: endDate,
    );
    return DatabaseService.rawQuery(
      '''
      SELECT
        DATE(incurred_on) as day_key,
        COALESCE(category_name, 'Uncategorized') as category_name,
        COALESCE(SUM(amount), 0) as total_amount,
        COUNT(*) as expense_count
      FROM expenses
      WHERE DATE(incurred_on) BETWEEN DATE(?) AND DATE(?)
        AND COALESCE(branch_id, ?) = ?
      GROUP BY DATE(incurred_on), COALESCE(category_name, 'Uncategorized')
      ORDER BY day_key DESC, total_amount DESC, category_name ASC
      ''',
      [range.start, range.end, ..._currentBranchArgs],
    );
  }

  static _ExpenseDateRange _resolveDateRange({
    required int daysRange,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final today = DateTime.now();
    final end = _dateOnly(endDate ?? today);
    final start = _dateOnly(
      startDate ?? end.subtract(Duration(days: daysRange - 1)),
    );
    return _ExpenseDateRange(
      _formatSqlDate(start.isAfter(end) ? end : start),
      _formatSqlDate(end),
    );
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _formatSqlDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _ExpenseDateRange {
  final String start;
  final String end;

  const _ExpenseDateRange(this.start, this.end);
}
