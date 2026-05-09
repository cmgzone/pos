import 'package:flutter/material.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/services/database_service.dart';
import '../../products/data/product_repository.dart';
import '../../purchases/data/purchase_repository.dart';
import '../../reports/data/expense_repository.dart';
import '../../reports/data/report_repository.dart';
import '../../sales/data/sale_repository.dart';
import '../../shifts/data/shift_repository.dart';
import 'piki_models.dart';

// ─── Skill definitions ──────────────────────────────────────────────────────

enum PikiSkill {
  analyzeLowStock,
  todaysSummary,
  restockList,
  salesReport,
  productSearch,
  profitSummary,
  shiftSummary,
  expiryCheck,
  topDebtors,
  topProducts,
  expenseSummary,
  purchaseHistory,
}

class PikiRequestAnalysis {
  final String originalInput;
  final String normalizedInput;
  final List<PikiSkill> skills;
  final int daysRange;
  final int resultLimit;
  final String? productQuery;

  const PikiRequestAnalysis({
    required this.originalInput,
    required this.normalizedInput,
    required this.skills,
    this.daysRange = 1,
    this.resultLimit = 10,
    this.productQuery,
  });

  String get periodLabel => PikiAgentService.periodLabelForDays(daysRange);
}

// ─── Agent engine ───────────────────────────────────────────────────────────

class PikiAgentService {
  static const toolLowStock = 'low_stock';
  static const toolTodaySummary = 'sales_summary';
  static const toolRestockList = 'restock_list';
  static const toolSalesReport = 'sales_report';
  static const toolProductSearch = 'product_search';
  static const toolProfitSummary = 'profit_summary';
  static const toolShiftSummary = 'shift_summary';
  static const toolExpiryCheck = 'expiry_check';
  static const toolTopDebtors = 'top_debtors';
  static const toolTopProducts = 'top_products';
  static const toolExpenseSummary = 'expense_summary';
  static const toolPurchaseHistory = 'purchase_history';
  static const toolPurchaseDraft = 'purchase_draft';

  // Each skill has a list of keyword-group patterns (ALL keywords in a group
  // must appear for a match).
  static final _skillPatterns = <PikiSkill, List<List<String>>>{
    PikiSkill.analyzeLowStock: [
      ['low', 'stock'],
      ['stock', 'alert'],
      ['out', 'stock'],
      ['running', 'low'],
      ['inventory', 'check'],
      ['analyze', 'inventory'],
    ],
    PikiSkill.todaysSummary: [
      ['today', 'summary'],
      ['daily', 'summary'],
      ['today', 'sales'],
      ['sales', 'summary'],
      ['how', 'today'],
      ['today', 'report'],
    ],
    PikiSkill.restockList: [
      ['restock'],
      ['reorder'],
      ['need', 'order'],
      ['purchase', 'list'],
    ],
    PikiSkill.salesReport: [
      ['sales', 'report'],
      ['recent', 'sales'],
      ['show', 'sales'],
      ['list', 'sales'],
    ],
    PikiSkill.productSearch: [
      ['find', 'product'],
      ['search', 'product'],
      ['show', 'product'],
      ['list', 'product'],
    ],
    PikiSkill.profitSummary: [
      ['profit'],
      ['margin'],
      ['earnings'],
    ],
    PikiSkill.shiftSummary: [
      ['shift'],
    ],
    PikiSkill.expiryCheck: [
      ['expir'],
      ['expiry'],
      ['shelf', 'life'],
    ],
    PikiSkill.topDebtors: [
      ['top', 'debtor'],
      ['who', 'owes'],
      ['kopesha', 'balance'],
      ['outstanding', 'balance'],
      ['overdue', 'customer'],
      ['credit', 'customer'],
    ],
    PikiSkill.topProducts: [
      ['top', 'product'],
      ['best', 'seller'],
      ['best', 'selling'],
      ['top', 'selling'],
      ['popular', 'product'],
      ['most', 'sold'],
    ],
    PikiSkill.expenseSummary: [
      ['expense'],
      ['spending'],
      ['expenditure'],
      ['operating', 'cost'],
      ['expense', 'summary'],
    ],
    PikiSkill.purchaseHistory: [
      ['purchase'],
      ['supplier', 'order'],
      ['stock', 'received'],
      ['stock', 'in'],
      ['restock', 'history'],
    ],
  };

  static final _toolToSkill = <String, PikiSkill>{
    toolLowStock: PikiSkill.analyzeLowStock,
    toolTodaySummary: PikiSkill.todaysSummary,
    toolRestockList: PikiSkill.restockList,
    toolSalesReport: PikiSkill.salesReport,
    toolProductSearch: PikiSkill.productSearch,
    toolProfitSummary: PikiSkill.profitSummary,
    toolShiftSummary: PikiSkill.shiftSummary,
    toolExpiryCheck: PikiSkill.expiryCheck,
    toolTopDebtors: PikiSkill.topDebtors,
    toolTopProducts: PikiSkill.topProducts,
    toolExpenseSummary: PikiSkill.expenseSummary,
    toolPurchaseHistory: PikiSkill.purchaseHistory,
  };

  static final _toolLabels = <String, String>{
    toolLowStock: 'Check low stock',
    toolTodaySummary: 'Review sales summary',
    toolRestockList: 'Prepare restock list',
    toolSalesReport: 'Review sales history',
    toolProductSearch: 'Search products',
    toolProfitSummary: 'Check profit',
    toolShiftSummary: 'Review shifts',
    toolExpiryCheck: 'Check expiry',
    toolTopDebtors: 'Review top debtors',
    toolTopProducts: 'Review top products',
    toolExpenseSummary: 'Review expenses',
    toolPurchaseHistory: 'Review purchase history',
    toolPurchaseDraft: 'Create purchase draft',
  };

  static final _toolDescriptions = <String, String>{
    toolLowStock: 'Read current inventory levels and minimum stock thresholds.',
    toolTodaySummary: 'Read sales, revenue, and profit for a time period.',
    toolRestockList: 'Build a reorder list from live low-stock products.',
    toolSalesReport: 'List recent sales in a selected period.',
    toolProductSearch: 'Look up products by name, barcode, or SKU.',
    toolProfitSummary: 'Calculate profit for a selected period.',
    toolShiftSummary: 'Review recently closed cashier shifts.',
    toolExpiryCheck: 'Check batches for expired or soon-to-expire products.',
    toolTopDebtors: 'Find customers with the highest outstanding balances.',
    toolTopProducts: 'Rank best-selling products over a period.',
    toolExpenseSummary: 'Summarize recent operating expenses.',
    toolPurchaseHistory: 'Show recent stock-in and supplier history.',
    toolPurchaseDraft: 'Build a purchase draft from low stock and recent supplier history.',
  };

  static String toolCatalogPrompt() {
    final buffer = StringBuffer();
    for (final entry in _toolLabels.entries) {
      buffer.writeln(
        '- ${entry.key}: ${entry.value}. ${_toolDescriptions[entry.key]} '
        'Arguments: daysRange(int), limit(int), query(string).',
      );
    }
    return buffer.toString().trimRight();
  }

  static PikiRequestAnalysis analyzeRequest(String input) {
    final normalized = input
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final daysRange = _extractDaysRange(normalized);
    final resultLimit = _extractResultLimit(normalized);
    final productQuery = _extractProductQuery(input);
    final scores = <PikiSkill, int>{};

    void addScore(PikiSkill skill, int value) {
      scores[skill] = (scores[skill] ?? 0) + value;
    }

    bool hasAny(List<String> terms) =>
        terms.any((term) => normalized.contains(term));
    bool hasAll(List<String> terms) =>
        terms.every((term) => normalized.contains(term));

    if (hasAll(['low', 'stock']) ||
        hasAll(['stock', 'alert']) ||
        hasAll(['running', 'low']) ||
        hasAll(['out', 'stock'])) {
      addScore(PikiSkill.analyzeLowStock, 4);
    }
    if (hasAny(['restock', 'reorder']) ||
        hasAll(['need', 'order']) ||
        hasAll(['purchase', 'list'])) {
      addScore(PikiSkill.restockList, 4);
    }
    if (hasAny(['today', 'daily']) ||
        hasAll(['sales', 'summary']) ||
        normalized.contains('how are sales')) {
      addScore(PikiSkill.todaysSummary, 4);
    }
    if (hasAll(['sales', 'report']) ||
        hasAll(['recent', 'sales']) ||
        hasAll(['sales', 'history']) ||
        hasAll(['show', 'sales']) ||
        hasAll(['list', 'sales'])) {
      addScore(PikiSkill.salesReport, 4);
    }
    if (hasAny(['profit', 'margin', 'earnings']) ||
        hasAll(['how', 'much', 'made'])) {
      addScore(PikiSkill.profitSummary, 4);
    }
    if (hasAny(['shift', 'cashier summary', 'cash up'])) {
      addScore(PikiSkill.shiftSummary, 3);
    }
    if (hasAny(['expiry', 'expiring', 'expired', 'shelf life'])) {
      addScore(PikiSkill.expiryCheck, 4);
    }
    if (hasAll(['top', 'debtor']) ||
        hasAll(['who', 'owes']) ||
        hasAll(['outstanding', 'balance']) ||
        hasAll(['overdue', 'customer']) ||
        hasAll(['credit', 'customer']) ||
        hasAll(['kopesha', 'balance'])) {
      addScore(PikiSkill.topDebtors, 5);
    }
    if (hasAll(['top', 'product']) ||
        hasAll(['best', 'seller']) ||
        hasAll(['best', 'selling']) ||
        hasAll(['top', 'selling']) ||
        hasAll(['most', 'sold']) ||
        hasAll(['popular', 'product'])) {
      addScore(PikiSkill.topProducts, 5);
    }
    if (hasAny(['expense', 'expenses', 'spending', 'expenditure']) ||
        hasAll(['operating', 'cost'])) {
      addScore(PikiSkill.expenseSummary, 4);
    }
    if (hasAny(['purchase', 'purchases']) ||
        hasAll(['stock', 'received']) ||
        hasAll(['stock', 'in']) ||
        hasAll(['supplier', 'order']) ||
        hasAll(['restock', 'history'])) {
      addScore(PikiSkill.purchaseHistory, 4);
    }
    if (productQuery != null ||
        hasAll(['find', 'product']) ||
        hasAll(['search', 'product']) ||
        hasAll(['show', 'product']) ||
        hasAll(['lookup', 'product']) ||
        hasAll(['tell', 'me']) && normalized.contains('product')) {
      addScore(PikiSkill.productSearch, productQuery != null ? 5 : 3);
    }

    final sortedSkills = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return PikiRequestAnalysis(
      originalInput: input.trim(),
      normalizedInput: normalized,
      skills: sortedSkills.map((entry) => entry.key).toList(),
      daysRange: daysRange,
      resultLimit: resultLimit,
      productQuery: productQuery,
    );
  }

  /// Match user input to one or more skills.
  static List<PikiSkill> matchSkills(String input) {
    final analyzed = analyzeRequest(input);
    if (analyzed.skills.isNotEmpty) {
      return analyzed.skills;
    }

    final lower = input.toLowerCase();
    final matched = <PikiSkill>[];
    for (final entry in _skillPatterns.entries) {
      for (final pattern in entry.value) {
        if (pattern.every((kw) => lower.contains(kw))) {
          if (!matched.contains(entry.key)) matched.add(entry.key);
          break;
        }
      }
    }
    return matched;
  }

  // ── Skill metadata ──────────────────────────────────────────────────────

  static String skillLabel(PikiSkill skill) => switch (skill) {
    PikiSkill.analyzeLowStock => 'Analyze Inventory',
    PikiSkill.todaysSummary   => "Review Sales",
    PikiSkill.restockList     => 'Prepare Restock',
    PikiSkill.salesReport     => 'Compile Sales',
    PikiSkill.productSearch   => 'Search Products',
    PikiSkill.profitSummary   => 'Profit Summary',
    PikiSkill.shiftSummary    => 'Shift Summary',
    PikiSkill.expiryCheck     => 'Expiry Check',
    PikiSkill.topDebtors      => 'Top Debtors',
    PikiSkill.topProducts     => 'Top Products',
    PikiSkill.expenseSummary  => 'Expense Summary',
    PikiSkill.purchaseHistory => 'Purchase History',
  };

  static String skillDescription(PikiSkill skill) => switch (skill) {
    PikiSkill.analyzeLowStock => 'Scanning stock levels across all items',
    PikiSkill.todaysSummary   => 'Calculating sales and profit metrics',
    PikiSkill.restockList     => 'Identifying low stock & reorder qty',
    PikiSkill.salesReport     => 'Compiling recent sales data',
    PikiSkill.productSearch   => 'Searching product catalog',
    PikiSkill.profitSummary   => 'Calculating profit margins',
    PikiSkill.shiftSummary    => 'Reviewing closed shifts',
    PikiSkill.expiryCheck     => 'Checking product expiry dates',
    PikiSkill.topDebtors      => 'Finding customers with highest balances',
    PikiSkill.topProducts     => 'Ranking products by sales volume',
    PikiSkill.expenseSummary  => 'Totalling recent operating expenses',
    PikiSkill.purchaseHistory => 'Reviewing recent stock-in records',
  };

  static IconData skillIcon(PikiSkill skill) => switch (skill) {
    PikiSkill.analyzeLowStock => Icons.search_rounded,
    PikiSkill.todaysSummary   => Icons.bar_chart_rounded,
    PikiSkill.restockList     => Icons.inventory_2_rounded,
    PikiSkill.salesReport     => Icons.receipt_long_rounded,
    PikiSkill.productSearch   => Icons.shopping_bag_rounded,
    PikiSkill.profitSummary   => Icons.trending_up_rounded,
    PikiSkill.shiftSummary    => Icons.timer_rounded,
    PikiSkill.expiryCheck     => Icons.event_busy_rounded,
    PikiSkill.topDebtors      => Icons.people_alt_rounded,
    PikiSkill.topProducts     => Icons.leaderboard_rounded,
    PikiSkill.expenseSummary  => Icons.money_off_rounded,
    PikiSkill.purchaseHistory => Icons.local_shipping_rounded,
  };

  /// Build PikiStep list for Plan mode.
  static List<PikiStep> buildSteps(List<PikiSkill> skills) =>
      skills.map((s) => PikiStep(
        label: skillLabel(s),
        description: skillDescription(s),
        icon: skillIcon(s),
      )).toList();

  // ── Execution ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> executeSkill(
    PikiSkill skill, {
    PikiRequestAnalysis? request,
  }) async {
    final currency = ShopSettings.currency;
    switch (skill) {
      case PikiSkill.analyzeLowStock:
        final items = await ProductRepository.getLowStock();
        final prioritized = List<Map<String, dynamic>>.from(items)
          ..sort((a, b) {
            final aGap =
                ((a['low_stock'] as num? ?? 0).toDouble() -
                        (a['stock'] as num? ?? 0).toDouble())
                    .toDouble();
            final bGap =
                ((b['low_stock'] as num? ?? 0).toDouble() -
                        (b['stock'] as num? ?? 0).toDouble())
                    .toDouble();
            return bGap.compareTo(aGap);
          });
        return {
          'type': 'low_stock',
          'items': prioritized,
          'count': prioritized.length,
          'summary': prioritized.isEmpty
              ? 'All products are well-stocked!'
              : 'Low stock found: ${prioritized.take(3).map((p) => p['name']).join(', ')}',
          'details': prioritized.take(5).map((p) =>
              '${p['name']}: ${p['stock']} ${p['unit'] ?? 'pcs'}').toList(),
          'recommendations': _recommendationsForLowStock(prioritized),
        };

      case PikiSkill.todaysSummary:
        final s = await _buildSalesSummary(daysRange: request?.daysRange ?? 1);
        final rev = (s['total_revenue'] as num? ?? 0).toDouble();
        final profit = (s['total_profit'] as num? ?? 0).toDouble();
        final sales = (s['total_sales'] as num? ?? 0).toInt();
        final averageSale = sales > 0 ? rev / sales : 0.0;
        return {
          'type': 'today_summary',
          'data': s,
          'summary': '${request?.periodLabel ?? 'Today'}: '
              '$sales sales, revenue $currency${rev.toStringAsFixed(0)}, '
              'profit $currency${profit.toStringAsFixed(0)}',
          'total_sales': s['total_sales'] ?? 0,
          'total_revenue': rev,
          'total_profit': profit,
          'average_sale': averageSale,
          'days_range': request?.daysRange ?? 1,
          'recommendations': _recommendationsForSalesSummary(
            totalSales: sales,
            totalRevenue: rev,
            totalProfit: profit,
          ),
        };

      case PikiSkill.restockList:
        final items = await ProductRepository.getLowStock();
        final restock = items.map((p) {
          final cur = (p['stock'] as num? ?? 0).toDouble();
          final low = (p['low_stock'] as num? ?? 5).toDouble();
          final reorderQty = (low * 2 - cur).clamp(low, low * 3);
          return {
            ...p,
            'reorder_qty': reorderQty,
            'urgency_score': low <= 0 ? 0 : ((low - cur) / low),
          };
        }).toList()
          ..sort((a, b) => (b['urgency_score'] as num)
              .compareTo(a['urgency_score'] as num));
        return {
          'type': 'restock_list',
          'items': restock,
          'count': restock.length,
          'summary': restock.isEmpty
              ? 'No items need restocking'
              : 'Restock list created',
          'recommendations': _recommendationsForRestock(restock),
        };

      case PikiSkill.salesReport:
        final range = _dateRangeForDays(request?.daysRange ?? 7);
        final sales = await SaleRepository.getAll(
          startDate: range.start.toIso8601String(),
          endDate: range.end.toIso8601String(),
        );
        final limited = sales.take(request?.resultLimit ?? 10).toList();
        return {
          'type': 'sales_report',
          'items': limited,
          'total_count': sales.length,
          'days_range': request?.daysRange ?? 7,
          'summary':
              '${sales.length} sales found for ${periodLabelForDays(request?.daysRange ?? 7).toLowerCase()}',
          'recommendations': _recommendationsForSalesReport(sales.length),
        };

      case PikiSkill.productSearch:
        final query = request?.productQuery?.trim();
        final products = query != null && query.isNotEmpty
            ? await ProductRepository.search(query)
            : await ProductRepository.getAll();
        final limited = products.take(request?.resultLimit ?? 10).toList();
        return {
          'type': 'product_list',
          'items': limited,
          'count': products.length,
          'searched_query': query,
          'summary': query != null && query.isNotEmpty
              ? products.isEmpty
                    ? 'No products found for "$query"'
                    : '${products.length} product matches for "$query"'
              : '${products.length} products in catalog',
          'recommendations': _recommendationsForProductSearch(products, query),
        };

      case PikiSkill.profitSummary:
        final s = await _buildSalesSummary(daysRange: request?.daysRange ?? 1);
        final profit = (s['total_profit'] as num? ?? 0).toDouble();
        final revenue = (s['total_revenue'] as num? ?? 0).toDouble();
        return {
          'type': 'profit_summary',
          'data': s,
          'summary':
              '${request?.periodLabel ?? 'Today'} profit: $currency${profit.toStringAsFixed(2)}',
          'total_profit': profit,
          'total_revenue': revenue,
          'days_range': request?.daysRange ?? 1,
          'recommendations': _recommendationsForProfit(
            totalProfit: profit,
            totalRevenue: revenue,
          ),
        };

      case PikiSkill.shiftSummary:
        try {
          final shifts = await ShiftRepository.getClosedShifts(limit: 5);
          return {
            'type': 'shift_summary',
            'items': shifts,
            'count': shifts.length,
            'summary': shifts.isEmpty
                ? 'No closed shifts found'
                : '${shifts.length} recent closed shifts',
          };
        } catch (_) {
          return {
            'type': 'shift_summary',
            'items': <Map<String, dynamic>>[],
            'count': 0,
            'summary': 'No shift data available',
          };
        }

      case PikiSkill.expiryCheck:
        final alerts = await ProductRepository.getExpiryAlerts();
        return {
          'type': 'expiry_check',
          'items': alerts,
          'count': alerts.length,
          'summary': alerts.isEmpty
              ? 'No expiring products found'
              : '${alerts.length} products expiring soon',
          'details': alerts.take(5).map((b) =>
              '${b['product_name']}: ${b['days_to_expiry']} days').toList(),
        };

      case PikiSkill.topDebtors:
        final debtors = await ReportRepository.getTopDebtors(
          limit: request?.resultLimit ?? 10,
        );
        final totalOwed = debtors.fold<double>(
            0, (sum, d) => sum + (d['balance'] as num? ?? 0).toDouble());
        final currency = ShopSettings.currency;
        return {
          'type': 'top_debtors',
          'items': debtors,
          'count': debtors.length,
          'total_owed': totalOwed,
          'summary': debtors.isEmpty
              ? 'No outstanding Kopesha balances'
              : '${debtors.length} customers owe $currency${totalOwed.toStringAsFixed(2)}',
          'recommendations': _recommendationsForDebtors(debtors, totalOwed),
        };

      case PikiSkill.topProducts:
        final products = await ReportRepository.getTopProducts(
          daysRange: request?.daysRange ?? 30,
          limit: request?.resultLimit ?? 8,
        );
        return {
          'type': 'top_products',
          'items': products,
          'count': products.length,
          'days_range': request?.daysRange ?? 30,
          'summary': products.isEmpty
              ? 'No sales data in ${periodLabelForDays(request?.daysRange ?? 30).toLowerCase()}'
              : 'Top ${products.length} products by sales volume '
                  '(${periodLabelForDays(request?.daysRange ?? 30).toLowerCase()})',
          'recommendations': _recommendationsForTopProducts(products),
        };

      case PikiSkill.expenseSummary:
        final expenses = await ExpenseRepository.getRecentExpenses(
          daysRange: request?.daysRange ?? 30,
          limit: request?.resultLimit ?? 20,
        );
        final totalAmount = expenses.fold<double>(
            0, (sum, e) => sum + (e['amount'] as num? ?? 0).toDouble());
        final cur = ShopSettings.currency;
        return {
          'type': 'expense_summary',
          'items': expenses,
          'count': expenses.length,
          'total_amount': totalAmount,
          'days_range': request?.daysRange ?? 30,
          'summary': expenses.isEmpty
              ? 'No expenses recorded in ${periodLabelForDays(request?.daysRange ?? 30).toLowerCase()}'
              : '${expenses.length} expenses totalling $cur${totalAmount.toStringAsFixed(2)}',
          'recommendations': _recommendationsForExpenses(expenses, totalAmount),
        };

      case PikiSkill.purchaseHistory:
        final rows = await DatabaseService.rawQuery('''
          SELECT
            pb.id,
            p.name as product_name,
            pb.quantity_received,
            p.stock_unit,
            p.unit,
            pb.unit_cost as cost_per_unit,
            pb.received_at,
            pi.supplier_name
          FROM stock_batches pb
          JOIN products p ON p.id = pb.product_id
          LEFT JOIN purchase_invoices pi ON pi.id = pb.purchase_id
          WHERE pb.deleted_at IS NULL
          ORDER BY pb.received_at DESC
          LIMIT ${request?.resultLimit ?? 10}
        ''');
        return {
          'type': 'purchase_history',
          'items': rows,
          'count': rows.length,
          'summary': rows.isEmpty
              ? 'No recent purchases recorded'
              : '${rows.length} recent stock-in records',
          'recommendations': _recommendationsForPurchaseHistory(rows),
        };
    }
  }

  static PikiStep buildStepForTool(String tool) {
    final mappedSkill = _toolToSkill[tool];
    if (mappedSkill != null) {
      return PikiStep(
        label: skillLabel(mappedSkill),
        description: skillDescription(mappedSkill),
        icon: skillIcon(mappedSkill),
      );
    }
    return PikiStep(
      label: _toolLabels[tool] ?? tool,
      description: _toolDescriptions[tool] ?? 'Preparing a grounded response',
      icon: switch (tool) {
        toolPurchaseDraft => Icons.note_alt_rounded,
        _ => Icons.auto_awesome_rounded,
      },
    );
  }

  static Future<Map<String, dynamic>> executeAgentTool(
    String tool, {
    Map<String, dynamic>? args,
    Map<String, dynamic>? memory,
  }) async {
    final mappedSkill = _toolToSkill[tool];
    if (mappedSkill != null) {
      final request = PikiRequestAnalysis(
        originalInput: (args?['query'] as String?) ?? '',
        normalizedInput: ((args?['query'] as String?) ?? '').toLowerCase(),
        skills: [mappedSkill],
        daysRange: _coercePositiveInt(args?['daysRange'], _defaultDaysForTool(tool)),
        resultLimit: _coercePositiveInt(args?['limit'], _defaultLimitForTool(tool)),
        productQuery: (args?['query'] as String?)?.trim().isEmpty == true
            ? null
            : (args?['query'] as String?)?.trim(),
      );
      final result = await executeSkill(mappedSkill, request: request);
      return _enrichToolResult(
        tool,
        result,
        args: args ?? const <String, dynamic>{},
      );
    }

    switch (tool) {
      case toolPurchaseDraft:
        return _createPurchaseDraft(
          args: args ?? const <String, dynamic>{},
          memory: memory ?? const <String, dynamic>{},
        );
      default:
        throw Exception('Unknown agent tool: $tool');
    }
  }

  static String composeGroundedReply({
    required String userInput,
    required List<Map<String, dynamic>> results,
  }) {
    if (results.isEmpty) {
      return 'I could not find grounded data for that request yet.';
    }

    final lines = <String>[];
    final citations = <Map<String, dynamic>>[];
    var citationIndex = 1;

    for (final result in results) {
      final title = result['title'] as String? ?? 'Result';
      final summary = result['summary'] as String? ?? 'Done';
      final resultCitations =
          (result['citations'] as List?)?.whereType<Map>().map(
                (item) => Map<String, dynamic>.from(item),
              ).toList() ??
              const <Map<String, dynamic>>[];
      final marker = resultCitations.isNotEmpty ? ' [$citationIndex]' : '';
      lines.add('• $title: $summary$marker');

      final details =
          (result['details'] as List?)?.whereType<String>().take(2).toList() ??
              const <String>[];
      for (final detail in details) {
        lines.add('  - $detail');
      }

      if (resultCitations.isNotEmpty) {
        final primary = Map<String, dynamic>.from(resultCitations.first);
        citations.add({
          'index': citationIndex,
          ...primary,
        });
        citationIndex += 1;
      }
    }

    final pendingDraft = results.cast<Map<String, dynamic>?>().firstWhere(
          (result) => result?['type'] == 'purchase_draft',
          orElse: () => null,
        );
    if (pendingDraft != null &&
        ((pendingDraft['count'] as num? ?? 0).toInt() > 0)) {
      lines.add('');
      lines.add(
        'Reply "confirm purchase draft" to save it as real purchase records, or "cancel purchase draft" to discard it.',
      );
    }

    if (citations.isNotEmpty) {
      lines.add('');
      lines.add('Sources:');
      for (final citation in citations) {
        lines.add(
          '[${citation['index']}] ${citation['label']} - ${citation['detail']}',
        );
      }
    }

    return lines.join('\n');
  }

  static String periodLabelForDays(int daysRange) {
    if (daysRange <= 1) return 'Today';
    if (daysRange == 7) return 'Last 7 days';
    if (daysRange == 30) return 'Last 30 days';
    return 'Last $daysRange days';
  }

  static bool isAdviceFollowUp(String input) {
    final lower = input.toLowerCase();
    return [
      'what should i do',
      'what do you recommend',
      'what next',
      'next step',
      'next steps',
      'what action should i take',
      'what action should we take',
      'give me advice',
      'give me recommendations',
      'what is your advice',
    ].any(lower.contains);
  }

  static String? buildFollowUpResponse(
    String input,
    Map<String, dynamic> result,
  ) {
    if (!isAdviceFollowUp(input)) {
      return null;
    }

    final type = result['type'] as String? ?? '';
    final recommendations =
        (result['recommendations'] as List?)?.whereType<String>().toList() ??
            const <String>[];
    if (recommendations.isNotEmpty) {
      return 'Recommended next steps:\n'
          '${recommendations.take(4).map((step) => '• $step').join('\n')}';
    }

    switch (type) {
      case 'today_summary':
      case 'profit_summary':
        return 'Focus on three actions:\n'
            '• Check your top-selling items and keep them in stock.\n'
            '• Review low-margin or slow items before ordering more.\n'
            '• Compare today with the last 7 days for a stronger decision.';
      case 'product_list':
        return 'Next steps:\n'
            '• Open Products to review pricing and stock.\n'
            '• Search by barcode or SKU if the exact item is still unclear.\n'
            '• Use Sell Mode if you want to ring up one of these items.';
      default:
        return 'Next steps:\n'
            '• Open the related screen to review the full details.\n'
            '• Ask Piki for a focused follow-up like "show top products" or "create a restock list".';
    }
  }

  /// Generate a single-line insight from the first result.
  static String generateInsight(Map<String, dynamic> result) {
    final type = result['type'] as String?;
    switch (type) {
      case 'low_stock':
        final items = result['items'] as List? ?? [];
        if (items.isEmpty) return 'Inventory is healthy — all items above minimum.';
        return '${items.first['name']} is the fastest-moving low-stock item today.';
      case 'today_summary':
        final profit = (result['total_profit'] as num? ?? 0).toDouble();
        return profit > 0
            ? 'Good day so far — you\'re profitable.'
            : 'Sales are slow today. Consider a promotion.';
      case 'restock_list':
        final count = result['count'] as int? ?? 0;
        return count == 0
            ? 'No restocking needed right now.'
            : '$count items queued for restocking.';
      default:
        return 'Analysis complete. Review the results above.';
    }
  }

  static _PikiDateRange _dateRangeForDays(int daysRange) {
    final now = DateTime.now();
    final end = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
      999,
    );
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: daysRange - 1));
    return _PikiDateRange(start: start, end: end);
  }

  static Future<Map<String, dynamic>> _buildSalesSummary({
    required int daysRange,
  }) async {
    final range = _dateRangeForDays(daysRange);
    final rows = await DatabaseService.rawQuery(
      '''
      SELECT
        COUNT(*) as total_sales,
        COALESCE(SUM(s.total_amount), 0) as total_revenue,
        COALESCE(SUM(s.tax), 0) as total_tax,
        COALESCE(SUM(s.discount), 0) as total_discount,
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
          - COALESCE(s.discount, 0)
        ), 0) as total_profit
      FROM sales s
      WHERE s.deleted_at IS NULL
        AND s.refund_for_sale_id IS NULL
        AND s.created_at >= ?
        AND s.created_at <= ?
        AND COALESCE(s.branch_id, ?) = ?
      ''',
      [
        range.start.toIso8601String(),
        range.end.toIso8601String(),
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
      ],
    );
    return rows.isNotEmpty
        ? rows.first
        : {
            'total_sales': 0,
            'total_revenue': 0.0,
            'total_tax': 0.0,
            'total_discount': 0.0,
            'total_profit': 0.0,
          };
  }

  static int _extractDaysRange(String input) {
    if (input.contains('today')) return 1;
    if (input.contains('yesterday')) return 2;
    if (input.contains('this week') || input.contains('weekly')) return 7;
    if (input.contains('this month') || input.contains('monthly')) return 30;
    final explicitRange =
        RegExp(r'(?:last|past)\s+(\d{1,3})\s+(day|days|week|weeks|month|months)')
            .firstMatch(input);
    if (explicitRange != null) {
      final count = int.tryParse(explicitRange.group(1) ?? '') ?? 1;
      final unit = explicitRange.group(2) ?? 'days';
      if (unit.startsWith('week')) return count * 7;
      if (unit.startsWith('month')) return count * 30;
      return count;
    }
    if (input.contains('30 day') || input.contains('30-day')) return 30;
    if (input.contains('7 day') || input.contains('7-day')) return 7;
    return 1;
  }

  static int _extractResultLimit(String input) {
    final match =
        RegExp(r'\b(?:top|show|list|find)\s+(\d{1,2})\b').firstMatch(input);
    final value = int.tryParse(match?.group(1) ?? '') ?? 10;
    return value.clamp(1, 20);
  }

  static String? _extractProductQuery(String input) {
    final patterns = [
      RegExp(r'^\s*(?:find|search|lookup|look up|show|check)\s+(?:product\s+)?(.+)$',
          caseSensitive: false),
      RegExp(r'^\s*(?:tell me about|details for)\s+(.+)$',
          caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(input.trim());
      if (match != null) {
        final candidate = match.group(1)?.trim() ?? '';
        if (candidate.isNotEmpty &&
            !candidate.contains('sales') &&
            !candidate.contains('profit')) {
          return candidate;
        }
      }
    }
    return null;
  }

  static List<String> _recommendationsForLowStock(
    List<Map<String, dynamic>> items,
  ) {
    if (items.isEmpty) {
      return const [
        'No urgent stock action is needed right now.',
        'Review top-selling products before the next purchase cycle.',
      ];
    }
    final first = items.first;
    final firstName = first['name'] as String? ?? 'the most urgent item';
    return [
      'Restock $firstName first because it is furthest below its minimum stock.',
      'Open Stock List to review current batch quantities before buying.',
      'Compare low-stock items against top sellers before placing an order.',
    ];
  }

  static List<String> _recommendationsForRestock(
    List<Map<String, dynamic>> items,
  ) {
    if (items.isEmpty) {
      return const [
        'No restock draft is needed right now.',
      ];
    }
    return [
      'Start with the top 3 urgent items and confirm supplier availability.',
      'Review purchase history to reuse the most recent supplier and unit cost.',
      'Open Purchases after checking stock levels item by item.',
    ];
  }

  static List<String> _recommendationsForSalesSummary({
    required int totalSales,
    required double totalRevenue,
    required double totalProfit,
  }) {
    if (totalSales == 0) {
      return const [
        'Focus on attracting at least a few transactions before reviewing margins.',
        'Check whether your top products are visible and in stock.',
      ];
    }
    if (totalProfit <= 0) {
      return const [
        'Review discounts and low-margin items because profit is weak.',
        'Check expense levels if revenue is coming in but margin stays low.',
      ];
    }
    if (totalRevenue > 0 && totalProfit / totalRevenue < 0.15) {
      return const [
        'Revenue is healthy, but margin is thin. Review cost-heavy items first.',
        'Check product mix and reduce discount leakage where possible.',
      ];
    }
    return const [
      'Keep high-performing items in stock to protect momentum.',
      'Review top products and repeat what is already working.',
    ];
  }

  static List<String> _recommendationsForSalesReport(int totalSales) {
    if (totalSales == 0) {
      return const [
        'No sales were found in this period. Check the date range or start selling.',
      ];
    }
    return const [
      'Open Sales to inspect individual transactions in full detail.',
      'Ask for top products or profit summary to understand performance faster.',
    ];
  }

  static List<String> _recommendationsForProductSearch(
    List<Map<String, dynamic>> products,
    String? query,
  ) {
    if (products.isEmpty) {
      return [
        if (query != null && query.isNotEmpty)
          'Try a shorter search like a barcode, SKU, or one keyword from "$query".',
        'Open Products to review the full catalog.',
      ];
    }
    return const [
      'Open Products to review pricing, stock, and category placement.',
      'Use Sell Mode if you want to add one of these items directly to the cart.',
    ];
  }

  static List<String> _recommendationsForProfit({
    required double totalProfit,
    required double totalRevenue,
  }) {
    if (totalRevenue <= 0) {
      return const [
        'No revenue is recorded for this period yet.',
      ];
    }
    if (totalProfit < 0) {
      return const [
        'You are running at a loss in this period. Check cost-heavy items and expenses first.',
      ];
    }
    if (totalProfit / totalRevenue < 0.15) {
      return const [
        'Profit is positive but margin is thin. Review pricing and discounts.',
      ];
    }
    return const [
      'Profit is healthy. Keep top sellers available and watch expenses.',
    ];
  }

  static List<String> _recommendationsForDebtors(
    List<Map<String, dynamic>> debtors,
    double totalOwed,
  ) {
    if (debtors.isEmpty || totalOwed <= 0) {
      return const [
        'There are no urgent credit collections right now.',
      ];
    }
    final first = debtors.first['name'] as String? ?? 'the top debtor';
    return [
      'Follow up with $first first because they have the highest balance.',
      'Open Kopesha to review due dates before contacting customers.',
      'Prioritize overdue balances before creating new credit sales.',
    ];
  }

  static List<String> _recommendationsForTopProducts(
    List<Map<String, dynamic>> products,
  ) {
    if (products.isEmpty) {
      return const [
        'No best-seller insight is available yet for this period.',
      ];
    }
    final leader = products.first['name'] as String? ?? 'your top item';
    return [
      'Keep $leader visible and well-stocked because it is leading sales.',
      'Use the best sellers to guide restocking and merchandising decisions.',
      'Check whether slow items are taking shelf space from faster movers.',
    ];
  }

  static List<String> _recommendationsForExpenses(
    List<Map<String, dynamic>> expenses,
    double totalAmount,
  ) {
    if (expenses.isEmpty) {
      return const [
        'No recent expenses were recorded, so verify that operating costs are being captured consistently.',
      ];
    }
    return [
      'Review the largest recent expenses first because they drive most of the total.',
      'Compare expense totals against profit for the same period.',
      'Use categories to find controllable costs quickly.',
    ];
  }

  static List<String> _recommendationsForPurchaseHistory(
    List<Map<String, dynamic>> rows,
  ) {
    if (rows.isEmpty) {
      return const [
        'No stock-in history is available yet.',
      ];
    }
    return const [
      'Reuse recent supplier and unit-cost patterns when preparing the next purchase.',
      'Compare stock-in records with low-stock items before ordering.',
    ];
  }

  // ─── Sell Mode NLP helpers ───────────────────────────────────────────────

  /// Parses a sell-mode utterance into a qty + product-query pair.
  /// Returns null when the text is a cart-control command, not an add request.
  static ({double qty, String query})? parseSellIntent(String text) {
    if (isClearCartCommand(text) || isCheckoutCommand(text)) return null;

    final lower = text.trim().toLowerCase();

    // "sell/add/ring up/give me/scan {qty} {product}"
    final verbQtyProduct =
        RegExp(r'^(?:sell|add|ring\s+up|give\s+me|scan|get)\s+(\d+(?:\.\d+)?)\s+(.+)$');
    // "{product} x {qty}"
    final productXQty = RegExp(r'^(.+?)\s+[x×]\s*(\d+(?:\.\d+)?)$');
    // "{qty} {product}"
    final qtyProduct = RegExp(r'^(\d+(?:\.\d+)?)\s+(.+)$');
    // "sell/add/etc {product}" (qty implied 1)
    final verbProduct =
        RegExp(r'^(?:sell|add|ring\s+up|give\s+me|scan|get)\s+(.+)$');

    Match? m;

    m = verbQtyProduct.firstMatch(lower);
    if (m != null) {
      return (qty: double.parse(m.group(1)!), query: m.group(2)!.trim());
    }

    m = productXQty.firstMatch(lower);
    if (m != null) {
      return (qty: double.parse(m.group(2)!), query: m.group(1)!.trim());
    }

    m = qtyProduct.firstMatch(lower);
    if (m != null) {
      return (qty: double.parse(m.group(1)!), query: m.group(2)!.trim());
    }

    m = verbProduct.firstMatch(lower);
    if (m != null) {
      return (qty: 1.0, query: m.group(1)!.trim());
    }

    // Bare product name (no qty, no verb) — assume qty 1
    if (lower.isNotEmpty) {
      return (qty: 1.0, query: text.trim());
    }

    return null;
  }

  static bool isClearCartCommand(String text) {
    final lower = text.toLowerCase();
    return const [
      'clear cart',
      'empty cart',
      'remove all',
      'clear all',
      'reset cart',
      'cancel cart',
    ].any(lower.contains);
  }

  static bool isCheckoutCommand(String text) {
    final lower = text.toLowerCase();
    return const [
      'checkout',
      'check out',
      'go to pos',
      'process sale',
      'pay now',
      'complete sale',
      'done selling',
      'finish sale',
    ].any(lower.contains);
  }

  /// Fuzzy product search: matches name, barcode, or SKU.
  static Future<Map<String, dynamic>?> findProductForSale(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;

    final rows = await DatabaseService.rawQuery(
      '''
      SELECT * FROM products
      WHERE (LOWER(name) LIKE ? OR barcode = ? OR LOWER(sku) LIKE ?)
        AND deleted_at IS NULL
        AND COALESCE(branch_id, ?) = ?
      ORDER BY
        CASE WHEN LOWER(name) = ? THEN 0 ELSE 1 END,
        LENGTH(name) ASC
      LIMIT 1
      ''',
      [
        '%$q%',
        q,
        '%$q%',
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        q,
      ],
    );
    return rows.isEmpty ? null : rows.first;
  }

  static int _defaultDaysForTool(String tool) {
    return switch (tool) {
      toolSalesReport => 7,
      toolTopProducts => 30,
      toolExpenseSummary => 30,
      toolPurchaseHistory => 30,
      _ => 1,
    };
  }

  static int _defaultLimitForTool(String tool) {
    return switch (tool) {
      toolExpenseSummary => 20,
      toolTopProducts => 8,
      toolPurchaseHistory => 10,
      _ => 10,
    };
  }

  static int _coercePositiveInt(dynamic value, int fallback) {
    final parsed = switch (value) {
      int _ => value,
      num _ => value.toInt(),
      String _ => int.tryParse(value),
      _ => null,
    };
    if (parsed == null || parsed <= 0) {
      return fallback;
    }
    return parsed;
  }

  static Map<String, dynamic> _enrichToolResult(
    String tool,
    Map<String, dynamic> result, {
    required Map<String, dynamic> args,
  }) {
    final enriched = Map<String, dynamic>.from(result);
    enriched['tool'] = tool;
    enriched['title'] = _toolLabels[tool] ?? enriched['title'] ?? tool;
    enriched['citations'] = _citationsForTool(tool, result, args: args);
    return enriched;
  }

  static List<Map<String, dynamic>> _citationsForTool(
    String tool,
    Map<String, dynamic> result, {
    required Map<String, dynamic> args,
  }) {
    final period = periodLabelForDays(
      _coercePositiveInt(args['daysRange'], _defaultDaysForTool(tool)),
    );
    final query = (args['query'] as String?)?.trim();
    return switch (tool) {
      toolLowStock => [
          {
            'label': 'Inventory records',
            'detail':
                'Pulled from local product stock and low-stock thresholds for the current branch.',
          },
        ],
      toolTodaySummary || toolProfitSummary => [
          {
            'label': 'Sales ledger',
            'detail':
                'Calculated from sales and sale items for $period in the current branch.',
          },
        ],
      toolRestockList => [
          {
            'label': 'Restock analysis',
            'detail':
                'Built from current stock versus low-stock thresholds in the local product catalog.',
          },
        ],
      toolSalesReport => [
          {
            'label': 'Recent sales',
            'detail':
                'Listed from recorded sales between the selected start and end dates for $period.',
          },
        ],
      toolProductSearch => [
          {
            'label': 'Product catalog',
            'detail':
                query == null || query.isEmpty
                    ? 'Read from the local product catalog for the current branch.'
                    : 'Matched against local product name, barcode, or SKU using "$query".',
          },
        ],
      toolShiftSummary => [
          {
            'label': 'Closed shifts',
            'detail': 'Loaded from the most recent closed shifts in the current branch.',
          },
        ],
      toolExpiryCheck => [
          {
            'label': 'Stock batches',
            'detail': 'Based on stored batch expiry dates and remaining stock.',
          },
        ],
      toolTopDebtors => [
          {
            'label': 'Credit balances',
            'detail':
                'Ranked from customer balances and open Kopesha sales in the current branch.',
          },
        ],
      toolTopProducts => [
          {
            'label': 'Top products',
            'detail':
                'Ranked from sale item quantities and revenue for $period in the current branch.',
          },
        ],
      toolExpenseSummary => [
          {
            'label': 'Expense log',
            'detail':
                'Summarized from recorded operating expenses for $period in the current branch.',
          },
        ],
      toolPurchaseHistory => [
          {
            'label': 'Purchase history',
            'detail':
                'Read from stock-in batches joined with purchase invoices and suppliers.',
          },
        ],
      toolPurchaseDraft => [
          {
            'label': 'Draft inputs',
            'detail':
                'Built from low-stock items and the latest supplier and unit-cost history found locally.',
          },
        ],
      _ => const <Map<String, dynamic>>[],
    };
  }

  static Future<Map<String, dynamic>> _createPurchaseDraft({
    required Map<String, dynamic> args,
    required Map<String, dynamic> memory,
  }) async {
    final limit = _coercePositiveInt(args['limit'], 8).clamp(1, 20);
    final memoryRestock = memory[toolRestockList];
    final memoryLowStock = memory[toolLowStock];
    List<Map<String, dynamic>> baseItems =
        (memoryRestock is Map<String, dynamic>
                ? (memoryRestock['items'] as List?)
                : null)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
            <Map<String, dynamic>>[];

    if (baseItems.isEmpty) {
      baseItems = (memoryLowStock is Map<String, dynamic>
                  ? (memoryLowStock['items'] as List?)
                  : null)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList() ??
          <Map<String, dynamic>>[];
    }

    if (baseItems.isEmpty) {
      final lowStockResult = await executeAgentTool(toolRestockList);
      baseItems = ((lowStockResult['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    final suppliers = await PurchaseRepository.getSuppliers();
    final purchaseRows = await DatabaseService.rawQuery(
      '''
      SELECT
        sb.product_id,
        pi.supplier_id,
        pi.supplier_name,
        sb.unit_cost,
        sb.received_at
      FROM stock_batches sb
      LEFT JOIN purchase_invoices pi ON pi.id = sb.purchase_id
      WHERE sb.deleted_at IS NULL
        AND COALESCE(sb.branch_id, ?) = ?
      ORDER BY sb.received_at DESC
      ''',
      [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
    );

    final latestByProduct = <String, Map<String, dynamic>>{};
    for (final row in purchaseRows) {
      final productId = row['product_id'] as String?;
      if (productId == null || latestByProduct.containsKey(productId)) {
        continue;
      }
      latestByProduct[productId] = row;
    }

    final draftItems = <Map<String, dynamic>>[];
    for (final item in baseItems.take(limit)) {
      final productId = item['id'] as String? ?? item['product_id'] as String?;
      if (productId == null || productId.isEmpty) {
        continue;
      }
      final history = latestByProduct[productId];
      final reorderQty = (item['reorder_qty'] as num? ??
              (((item['low_stock'] as num? ?? 0).toDouble() * 2) -
                      (item['stock'] as num? ?? 0).toDouble()))
          .toDouble();
      draftItems.add({
        'product_id': productId,
        'product_name': item['name'] ?? item['product_name'],
        'recommended_qty': reorderQty <= 0 ? 1.0 : reorderQty,
        'unit': item['purchase_unit'] ?? item['stock_unit'] ?? item['unit'] ?? 'pcs',
        'last_unit_cost': (history?['unit_cost'] as num? ?? item['cost'] as num? ?? 0)
            .toDouble(),
        'suggested_supplier_name': history?['supplier_name'],
        'suggested_supplier_id': history?['supplier_id'],
        'last_received_at': history?['received_at'],
      });
    }

    final supplierCounts = <String, int>{};
    for (final item in draftItems) {
      final supplierName = (item['suggested_supplier_name'] as String?)?.trim();
      if (supplierName == null || supplierName.isEmpty) {
        continue;
      }
      supplierCounts[supplierName] = (supplierCounts[supplierName] ?? 0) + 1;
    }
    final topSupplier = supplierCounts.entries.isEmpty
        ? null
        : (supplierCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;

    final knownSupplierNames = suppliers
        .map((supplier) => supplier['name'] as String?)
        .whereType<String>()
        .take(5)
        .toList();
    final supplierGroups = <String, List<Map<String, dynamic>>>{};
    for (final item in draftItems) {
      final supplierName =
          (item['suggested_supplier_name'] as String?)?.trim() ?? '';
      final key = supplierName.isEmpty ? 'Unassigned supplier' : supplierName;
      supplierGroups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(item);
    }
    final groupedPreview = supplierGroups.entries.map((entry) {
      final items = entry.value;
      final estimatedTotal = items.fold<double>(
        0,
        (sum, item) =>
            sum +
            ((item['recommended_qty'] as num? ?? 0).toDouble() *
                (item['last_unit_cost'] as num? ?? 0).toDouble()),
      );
      return {
        'supplier_name': entry.key,
        'item_count': items.length,
        'estimated_total': estimatedTotal,
        'items': items
            .take(3)
            .map((item) => {
                  'product_name': item['product_name'],
                  'recommended_qty': item['recommended_qty'],
                  'unit': item['unit'],
                })
            .toList(),
      };
    }).toList()
      ..sort(
        (a, b) => (b['item_count'] as int).compareTo(a['item_count'] as int),
      );

    return _enrichToolResult(
      toolPurchaseDraft,
      {
        'type': 'purchase_draft',
        'items': draftItems,
        'count': draftItems.length,
        'preferred_supplier': topSupplier,
        'supplier_groups': groupedPreview,
        'known_suppliers': knownSupplierNames,
        'summary': draftItems.isEmpty
            ? 'No purchase draft could be built because there are no low-stock items yet.'
            : topSupplier == null
                ? 'Prepared a purchase draft for ${draftItems.length} low-stock items.'
                : 'Prepared a purchase draft for ${draftItems.length} items. $topSupplier is the best supplier match from recent history.',
        'details': draftItems
            .take(4)
            .map((item) {
              final qty = (item['recommended_qty'] as num? ?? 0).toDouble();
              final supplier = item['suggested_supplier_name'] as String?;
              return supplier == null || supplier.isEmpty
                  ? '${item['product_name']}: order ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} ${item['unit']}'
                  : '${item['product_name']}: order ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} ${item['unit']} from $supplier';
            })
            .toList(),
      },
      args: args,
    );
  }
}

class _PikiDateRange {
  final DateTime start;
  final DateTime end;

  const _PikiDateRange({required this.start, required this.end});
}
