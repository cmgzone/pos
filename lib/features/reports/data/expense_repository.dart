import 'package:uuid/uuid.dart';

import '../../../core/services/database_service.dart';
import '../../../core/services/license_service.dart';

const _uuid = Uuid();

class ExpenseRepository {
  static Future<List<Map<String, dynamic>>> getCategories() async {
    return DatabaseService.queryAll('expense_categories', orderBy: 'name ASC');
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
  }) async {
    return DatabaseService.rawQuery('''
      SELECT *
      FROM expenses
      WHERE incurred_on >= date('now', '-$daysRange days')
      ORDER BY incurred_on DESC, created_at DESC
      LIMIT $limit
      ''');
  }

  static Future<List<Map<String, dynamic>>> getDailyProfitLoss({
    required int daysRange,
  }) async {
    return DatabaseService.rawQuery('''
      WITH daily_sales AS (
        SELECT
          DATE(s.created_at) as day_key,
          COUNT(DISTINCT s.id) as sale_count,
          COALESCE(SUM(si.quantity * si.unit_price), 0) as revenue,
          COALESCE(SUM(si.quantity * si.unit_cost), 0) as total_cost,
          COALESCE(SUM(si.quantity * si.unit_price), 0) - COALESCE(SUM(si.quantity * si.unit_cost), 0) as gross_profit,
          COALESCE(SUM(s.tax), 0) as tax,
          COALESCE(SUM(s.discount), 0) as discount
        FROM sales s
        JOIN sale_items si ON si.sale_id = s.id
        WHERE s.created_at >= datetime('now', '-$daysRange days')
        GROUP BY DATE(s.created_at)
      ),
      daily_expenses AS (
        SELECT
          DATE(e.incurred_on) as day_key,
          COALESCE(SUM(e.amount), 0) as total_expenses
        FROM expenses e
        WHERE DATE(e.incurred_on) >= date('now', '-$daysRange days')
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
      ''');
  }

  static Future<Map<String, dynamic>> getProfitLossTotals({
    required int daysRange,
  }) async {
    final rows = await DatabaseService.rawQuery('''
      WITH sales_totals AS (
        SELECT
          COALESCE(SUM(si.quantity * si.unit_price), 0) as total_revenue,
          COALESCE(SUM(si.quantity * si.unit_cost), 0) as total_cost,
          COALESCE(SUM(si.quantity * si.unit_price), 0) - COALESCE(SUM(si.quantity * si.unit_cost), 0) as gross_profit,
          COUNT(DISTINCT s.id) as total_sales,
          COALESCE(SUM(s.tax), 0) as total_tax,
          COALESCE(SUM(s.discount), 0) as total_discount
        FROM sales s
        JOIN sale_items si ON si.sale_id = s.id
        WHERE s.created_at >= datetime('now', '-$daysRange days')
      ),
      expense_totals AS (
        SELECT
          COALESCE(SUM(amount), 0) as total_expenses
        FROM expenses
        WHERE DATE(incurred_on) >= date('now', '-$daysRange days')
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
      ''');

    return rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : {};
  }

  static Future<List<Map<String, dynamic>>> getExpenseCategoryTotals({
    required int daysRange,
  }) async {
    return DatabaseService.rawQuery('''
      SELECT
        COALESCE(category_name, 'Uncategorized') as category_name,
        COALESCE(SUM(amount), 0) as total_amount,
        COUNT(*) as expense_count
      FROM expenses
      WHERE DATE(incurred_on) >= date('now', '-$daysRange days')
      GROUP BY COALESCE(category_name, 'Uncategorized')
      ORDER BY total_amount DESC, category_name ASC
      ''');
  }
}
