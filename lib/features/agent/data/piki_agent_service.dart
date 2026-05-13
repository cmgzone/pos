import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/openrouter_service.dart';
import '../../customers/data/customer_repository.dart';
import '../../products/data/category_repository.dart';
import '../../products/data/product_repository.dart';
import '../../products/data/product_variant_repository.dart';
import '../../purchases/data/purchase_repository.dart';
import '../../reports/data/expense_repository.dart';
import '../../reports/data/report_repository.dart';
import '../../sales/data/sale_repository.dart';
import '../../services/data/service_repository.dart';
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
  dailyBrief,
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

class PikiSellableProduct {
  final Map<String, dynamic> product;
  final Map<String, dynamic>? variant;

  const PikiSellableProduct({required this.product, this.variant});

  String get cartKey {
    final productId = product['id'] as String? ?? '';
    final variantId = variant?['id'] as String?;
    return variantId == null || variantId.isEmpty
        ? productId
        : '${productId}_$variantId';
  }

  String get label {
    final productName = product['name'] as String? ?? 'Item';
    final variantName = variant?['name'] as String?;
    if (variantName == null || variantName.trim().isEmpty) {
      return productName;
    }
    return '$productName - $variantName';
  }
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
  static const toolDailyBrief = 'daily_brief';
  static const toolCreateProduct = 'create_product';
  static const toolCreateService = 'create_service';
  static const toolEditProduct = 'edit_product';
  static const toolAddVariant = 'add_variant';
  static const toolRecordProductSale = 'record_product_sale';
  static const toolRecordServiceSale = 'record_service_sale';
  static const toolCreateCategory = 'create_category';
  static const toolCreateExpenseCategory = 'create_expense_category';
  static const toolCreateCustomer = 'create_customer';
  static const toolCreateSupplier = 'create_supplier';
  static const toolReconcileStock = 'reconcile_stock';
  static const toolAddServiceField = 'add_service_field';
  static const toolCustomerSearch = 'customer_search';
  static const toolSupplierSearch = 'supplier_search';
  static const toolWebSearch = 'web_search';
  static const toolAddToCart = 'add_to_cart';
  static const toolRemoveFromCart = 'remove_from_cart';
  static const toolSetCartQuantity = 'set_cart_quantity';
  static const toolRepeatLast = 'repeat_last_item';
  static const toolClearCart = 'clear_cart';
  static const toolCheckout = 'checkout';
  static const toolHoldSale = 'hold_sale';
  static const toolTeachAlias = 'teach_alias';

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
    PikiSkill.dailyBrief: [
      ['daily', 'brief'],
      ['business', 'news'],
      ['market', 'comparison'],
      ['how', 'doing', 'compared'],
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
    toolDailyBrief: PikiSkill.dailyBrief,
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
    toolCreateProduct: 'Create product',
    toolCreateService: 'Create service',
    toolEditProduct: 'Edit product',
    toolAddVariant: 'Add variant',
    toolRecordProductSale: 'Record product sale',
    toolRecordServiceSale: 'Record service sale',
    toolCreateCategory: 'Create product category',
    toolCreateExpenseCategory: 'Create expense category',
    toolCreateCustomer: 'Create customer',
    toolCreateSupplier: 'Create supplier',
    toolReconcileStock: 'Reconcile stock',
    toolAddServiceField: 'Add service field',
    toolCustomerSearch: 'Search customers',
    toolSupplierSearch: 'Search suppliers',
    toolWebSearch: 'Search the web',
    toolAddToCart: 'Add to cart',
    toolRemoveFromCart: 'Remove from cart',
    toolSetCartQuantity: 'Set cart quantity',
    toolRepeatLast: 'Repeat last cart item',
    toolClearCart: 'Clear cart',
    toolCheckout: 'Checkout',
    toolHoldSale: 'Hold sale',
    toolTeachAlias: 'Teach cashier alias',
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
    toolPurchaseDraft:
        'Build a purchase draft from low stock and recent supplier history.',
    toolCreateProduct: 'Create a product when name and price are known.',
    toolCreateService:
        'Create a service template when name and price are known.',
    toolEditProduct:
        'Edit an existing product\'s details like price, cost, name, or low stock threshold.',
    toolAddVariant: 'Add a variant (size, color, etc.) to an existing product.',
    toolRecordProductSale:
        'Record a product sale immediately against inventory.',
    toolRecordServiceSale: 'Record a service sale immediately.',
    toolCreateCategory: 'Create a product category.',
    toolCreateExpenseCategory: 'Create an expense category.',
    toolCreateCustomer: 'Create a customer record.',
    toolCreateSupplier: 'Create a supplier record.',
    toolReconcileStock: 'Set a product stock count after a physical count.',
    toolAddServiceField: 'Add a custom field to an existing service template.',
    toolCustomerSearch: 'Look up customers by name, phone, or email.',
    toolSupplierSearch: 'Look up suppliers by name, phone, or email.',
    toolWebSearch:
        'Search live web results for current prices, market context, regulations, supplier information, or other external facts not stored in the POS.',
    toolAddToCart: 'Add products, variants, or services to the live POS cart.',
    toolRemoveFromCart: 'Remove a line or quantity from the live POS cart.',
    toolSetCartQuantity: 'Set an existing POS cart line to an exact quantity.',
    toolRepeatLast: 'Add the last sold item again.',
    toolClearCart: 'Empty the cart.',
    toolCheckout: 'Go to checkout screen.',
    toolHoldSale: 'Save the current cart as a held sale and clear the cart.',
    toolTeachAlias:
        'Remember a cashier phrase, nickname, or local term for a product query.',
  };

  static final _toolArguments = <String, String>{
    toolLowStock: 'daysRange(int), limit(int)',
    toolTodaySummary: 'daysRange(int)',
    toolRestockList: 'limit(int)',
    toolSalesReport: 'daysRange(int), limit(int)',
    toolProductSearch: 'query(string), limit(int)',
    toolProfitSummary: 'daysRange(int)',
    toolShiftSummary: 'limit(int)',
    toolExpiryCheck: 'limit(int)',
    toolTopDebtors: 'limit(int)',
    toolTopProducts: 'daysRange(int), limit(int)',
    toolExpenseSummary: 'daysRange(int), limit(int)',
    toolPurchaseHistory: 'daysRange(int), limit(int)',
    toolPurchaseDraft: 'limit(int)',
    toolCreateProduct:
        'name(string, required), price(number, required), cost(number), stock(number), unit(string), category_id(string), category(string), sku(string), barcode(string), brand(string)',
    toolCreateService:
        'name(string, required), price/base_price(number, required), category(string), description(string), duration_minutes(int)',
    toolEditProduct:
        'query/name(string, required), price(number), cost(number), new_name(string), low_stock(number), barcode(string)',
    toolAddVariant:
        'query/product_name(string, required), variant_name/name(string, required), price(number, required), cost(number), sku(string), barcode(string), stock(number), low_stock(number)',
    toolRecordProductSale:
        'product_name/query(string, required), quantity(number), unit_price/price(number), payment_type(string)',
    toolRecordServiceSale:
        'service_name/query(string, required), quantity(number), unit_price/price(number), payment_type(string), customer_name(string)',
    toolCreateCategory: 'name(string, required), color(string)',
    toolCreateExpenseCategory: 'name(string, required), color(string)',
    toolCreateCustomer: 'name(string, required), phone(string), email(string)',
    toolCreateSupplier:
        'name(string, required), phone(string), email(string), address(string), note(string)',
    toolReconcileStock:
        'product_name/query(string, required), new_count/count/stock(number, required)',
    toolAddServiceField:
        'service_name/query(string, required), field_label/label(string, required), field_type(string), options(list/string), is_required(bool)',
    toolCustomerSearch: 'query(string), limit(int)',
    toolSupplierSearch: 'query(string), limit(int)',
    toolWebSearch:
        'query(string, required), location(string), countryCode(string), language(string), limit(int)',
    toolAddToCart: 'query(string, required), qty(number)',
    toolRemoveFromCart: 'query(string), qty(number)',
    toolSetCartQuantity: 'query(string), qty/quantity(number, required)',
    toolRepeatLast: 'qty(number)',
    toolCheckout: 'payment_type(string)',
    toolTeachAlias: 'alias(string, required), target(string, required)',
  };

  static String toolCatalogPrompt() {
    final buffer = StringBuffer();
    for (final entry in _toolLabels.entries) {
      buffer.writeln(
        '- ${entry.key}: ${entry.value}. ${_toolDescriptions[entry.key]} '
        'Arguments: ${_toolArguments[entry.key] ?? 'none'}.',
      );
    }
    return buffer.toString().trimRight();
  }

  static bool isKnownTool(String tool) => _toolLabels.containsKey(tool);

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
    PikiSkill.todaysSummary => "Review Sales",
    PikiSkill.restockList => 'Prepare Restock',
    PikiSkill.salesReport => 'Compile Sales',
    PikiSkill.productSearch => 'Search Products',
    PikiSkill.profitSummary => 'Profit Summary',
    PikiSkill.shiftSummary => 'Shift Summary',
    PikiSkill.expiryCheck => 'Expiry Check',
    PikiSkill.topDebtors => 'Top Debtors',
    PikiSkill.topProducts => 'Top Products',
    PikiSkill.expenseSummary => 'Expense Summary',
    PikiSkill.purchaseHistory => 'Purchase History',
    PikiSkill.dailyBrief => 'Daily Market Brief',
  };

  static String skillDescription(PikiSkill skill) => switch (skill) {
    PikiSkill.analyzeLowStock => 'Scanning stock levels across all items',
    PikiSkill.todaysSummary => 'Calculating sales and profit metrics',
    PikiSkill.restockList => 'Identifying low stock & reorder qty',
    PikiSkill.salesReport => 'Compiling recent sales data',
    PikiSkill.productSearch => 'Searching product catalog',
    PikiSkill.profitSummary => 'Calculating profit margins',
    PikiSkill.shiftSummary => 'Reviewing closed shifts',
    PikiSkill.expiryCheck => 'Checking product expiry dates',
    PikiSkill.topDebtors => 'Finding customers with highest balances',
    PikiSkill.topProducts => 'Ranking products by sales volume',
    PikiSkill.expenseSummary => 'Totalling recent operating expenses',
    PikiSkill.purchaseHistory => 'Reviewing recent stock-in records',
    PikiSkill.dailyBrief =>
      'Fetching daily market news and comparing performance',
  };

  static IconData skillIcon(PikiSkill skill) => switch (skill) {
    PikiSkill.analyzeLowStock => Icons.search_rounded,
    PikiSkill.todaysSummary => Icons.bar_chart_rounded,
    PikiSkill.restockList => Icons.inventory_2_rounded,
    PikiSkill.salesReport => Icons.receipt_long_rounded,
    PikiSkill.productSearch => Icons.shopping_bag_rounded,
    PikiSkill.profitSummary => Icons.trending_up_rounded,
    PikiSkill.shiftSummary => Icons.timer_rounded,
    PikiSkill.expiryCheck => Icons.event_busy_rounded,
    PikiSkill.topDebtors => Icons.people_alt_rounded,
    PikiSkill.topProducts => Icons.leaderboard_rounded,
    PikiSkill.expenseSummary => Icons.money_off_rounded,
    PikiSkill.purchaseHistory => Icons.local_shipping_rounded,
    PikiSkill.dailyBrief => Icons.auto_awesome,
  };

  /// Build PikiStep list for Plan mode.
  static List<PikiStep> buildSteps(List<PikiSkill> skills) => skills
      .map(
        (s) => PikiStep(
          label: skillLabel(s),
          description: skillDescription(s),
          icon: skillIcon(s),
        ),
      )
      .toList();

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
          'details': prioritized
              .take(5)
              .map((p) => '${p['name']}: ${p['stock']} ${p['unit'] ?? 'pcs'}')
              .toList(),
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
          'summary':
              '${request?.periodLabel ?? 'Today'}: '
              '$sales sales, revenue $currency${rev.toStringAsFixed(0)}, '
              'profit $currency${profit.toStringAsFixed(0)}',
          'total_sales': s['total_sales'] ?? 0,
          'total_revenue': rev,
          'total_profit': profit,
          'average_sale': averageSale,
          'days_range': request?.daysRange ?? 1,
        };

      case PikiSkill.dailyBrief:
        return _buildDailyBrief(request: request);

      case PikiSkill.restockList:
        final items = await ProductRepository.getLowStock();
        final restock =
            items.map((p) {
              final cur = (p['stock'] as num? ?? 0).toDouble();
              final low = (p['low_stock'] as num? ?? 5).toDouble();
              final reorderQty = (low * 2 - cur).clamp(low, low * 3);
              return {
                ...p,
                'reorder_qty': reorderQty,
                'urgency_score': low <= 0 ? 0 : ((low - cur) / low),
              };
            }).toList()..sort(
              (a, b) => (b['urgency_score'] as num).compareTo(
                a['urgency_score'] as num,
              ),
            );
        return {
          'type': 'restock_list',
          'items': restock,
          'count': restock.length,
          'summary': restock.isEmpty
              ? 'No items need restocking'
              : 'Restock list created',
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
        };

      case PikiSkill.productSearch:
        final query = request?.productQuery?.trim();
        List<Map<String, dynamic>> products = [];
        bool usedSemanticSearch = false;

        if (query != null && query.isNotEmpty) {
          products = await ProductRepository.search(query);

          if (products.isEmpty && OpenRouterService.isEnabled) {
            try {
              final categories = await CategoryRepository.getAll();
              final catNames = categories.map((c) => c['name']).join(', ');

              final prompt =
                  '''
The user is searching for a product in a point-of-sale system.
Their natural language search query is: "$query".
Available product categories: $catNames.
Analyze their intent and provide a list of up to 5 single-word or short-phrase synonyms, categories, or keywords that would likely match the product name or brand in the database.
Return ONLY a valid JSON array of strings. Do not return any other text.
Example: ["detergent", "soap", "laundry"]
''';
              final aiResponse = await OpenRouterService.chat(
                messages: [
                  {'role': 'user', 'content': prompt},
                ],
                includeBusinessContext: false,
              );

              final List<dynamic> keywords = jsonDecode(aiResponse);
              final Set<String> matchedIds = {};

              for (final kw in keywords) {
                final kwStr = kw.toString().trim();
                if (kwStr.isNotEmpty) {
                  final matches = await ProductRepository.search(kwStr);
                  for (final m in matches) {
                    if (!matchedIds.contains(m['id'])) {
                      matchedIds.add(m['id']);
                      products.add(m);
                    }
                  }
                }
              }
              usedSemanticSearch = products.isNotEmpty;
            } catch (_) {
              // Fallback to empty if AI fails
            }
          }
        } else {
          products = await ProductRepository.getAll();
        }

        final limited = products.take(request?.resultLimit ?? 10).toList();
        return {
          'type': 'product_list',
          'items': limited,
          'count': products.length,
          'searched_query': query,
          'used_semantic_search': usedSemanticSearch,
          'summary': query != null && query.isNotEmpty
              ? products.isEmpty
                    ? 'No products found for "$query"'
                    : '${products.length} product matches for "$query"${usedSemanticSearch ? ' (via AI)' : ''}'
              : '${products.length} products in catalog',
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
          'details': alerts
              .take(5)
              .map((b) => '${b['product_name']}: ${b['days_to_expiry']} days')
              .toList(),
        };

      case PikiSkill.topDebtors:
        final debtors = await ReportRepository.getTopDebtors(
          limit: request?.resultLimit ?? 10,
        );
        final totalOwed = debtors.fold<double>(
          0,
          (sum, d) => sum + (d['balance'] as num? ?? 0).toDouble(),
        );
        final currency = ShopSettings.currency;
        return {
          'type': 'top_debtors',
          'items': debtors,
          'count': debtors.length,
          'total_owed': totalOwed,
          'summary': debtors.isEmpty
              ? 'No outstanding Kopesha balances'
              : '${debtors.length} customers owe $currency${totalOwed.toStringAsFixed(2)}',
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
        };

      case PikiSkill.expenseSummary:
        final expenses = await ExpenseRepository.getRecentExpenses(
          daysRange: request?.daysRange ?? 30,
          limit: request?.resultLimit ?? 20,
        );
        final totalAmount = expenses.fold<double>(
          0,
          (sum, e) => sum + (e['amount'] as num? ?? 0).toDouble(),
        );
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
        };

      case PikiSkill.purchaseHistory:
        final rows = await DatabaseService.rawQuery(
          '''
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
            AND COALESCE(pb.branch_id, ?) = ?
          ORDER BY pb.received_at DESC
          LIMIT ${request?.resultLimit ?? 10}
        ''',
          [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
        );
        return {
          'type': 'purchase_history',
          'items': rows,
          'count': rows.length,
          'summary': rows.isEmpty
              ? 'No recent purchases recorded'
              : '${rows.length} recent stock-in records',
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
        toolWebSearch => Icons.public_rounded,
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
        daysRange: _coercePositiveInt(
          args?['daysRange'],
          _defaultDaysForTool(tool),
        ),
        resultLimit: _coercePositiveInt(
          args?['limit'],
          _defaultLimitForTool(tool),
        ),
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
      case toolCreateProduct:
        return _createProduct(args ?? const <String, dynamic>{});
      case toolCreateService:
        return _createService(args ?? const <String, dynamic>{});
      case toolEditProduct:
        return _editProduct(args ?? const <String, dynamic>{});
      case toolAddVariant:
        return _addVariant(args ?? const <String, dynamic>{});
      case toolRecordProductSale:
        return _recordProductSale(args ?? const <String, dynamic>{});
      case toolRecordServiceSale:
        return _recordServiceSale(args ?? const <String, dynamic>{});
      case toolCreateCategory:
        return _createCategory(args ?? const <String, dynamic>{});
      case toolCreateExpenseCategory:
        return _createExpenseCategory(args ?? const <String, dynamic>{});
      case toolCreateCustomer:
        return _createCustomer(args ?? const <String, dynamic>{});
      case toolCreateSupplier:
        return _createSupplier(args ?? const <String, dynamic>{});
      case toolReconcileStock:
        return _reconcileStock(args ?? const <String, dynamic>{});
      case toolAddServiceField:
        return _addServiceField(args ?? const <String, dynamic>{});
      case toolCustomerSearch:
        return _searchCustomers(args ?? const <String, dynamic>{});
      case toolSupplierSearch:
        return _searchSuppliers(args ?? const <String, dynamic>{});
      case toolWebSearch:
        return _webSearch(args ?? const <String, dynamic>{});
      default:
        throw Exception('Unknown agent tool: $tool');
    }
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
  static Future<PikiInsightData> generateInsight(
    Map<String, dynamic> result,
  ) async {
    PikiInsightData fallbackInsight() {
      final type = result['type'] as String?;
      switch (type) {
        case 'low_stock':
          final items = result['items'] as List? ?? [];
          if (items.isEmpty) {
            return const PikiInsightData(
              text: 'Inventory is healthy — all items above minimum.',
            );
          }
          return PikiInsightData(
            text:
                '${items.first['name']} is the fastest-moving low-stock item today.',
          );
        case 'today_summary':
          final profit = (result['total_profit'] as num? ?? 0).toDouble();
          return PikiInsightData(
            text: profit > 0
                ? 'Good day so far — you\'re profitable.'
                : 'Sales are slow today. Consider a promotion.',
          );
        case 'restock_list':
          final count = result['count'] as int? ?? 0;
          return PikiInsightData(
            text: count == 0
                ? 'No restocking needed right now.'
                : '$count items queued for restocking.',
          );
        default:
          return const PikiInsightData(
            text: 'Analysis complete. Review the results above.',
          );
      }
    }

    if (!OpenRouterService.isEnabled) {
      return fallbackInsight();
    }

    try {
      final safeResult = Map<String, dynamic>.from(result);
      if (safeResult['items'] is List) {
        final list = safeResult['items'] as List;
        if (list.length > 10) {
          safeResult['items'] = list.take(10).toList();
        }
      }

      final prompt =
          '''
Analyze the following POS tool result and provide a single, punchy, actionable business insight (max 1 short sentence).
Do not use markdown. Do not wrap in quotes.
Tool Result:
${jsonEncode(safeResult)}
''';
      final aiResponse = await OpenRouterService.chat(
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        includeBusinessContext: false,
      );

      final cleanText = aiResponse.trim().replaceAll('"', '');
      if (cleanText.isNotEmpty) {
        return PikiInsightData(text: cleanText);
      }
    } catch (_) {
      // Fallback below
    }

    return fallbackInsight();
  }

  static Future<Map<String, dynamic>> _buildDailyBrief({
    PikiRequestAnalysis? request,
  }) async {
    final s = await _buildSalesSummary(daysRange: request?.daysRange ?? 1);
    final rev = (s['total_revenue'] as num? ?? 0).toDouble();
    final profit = (s['total_profit'] as num? ?? 0).toDouble();
    final sales = (s['total_sales'] as num? ?? 0).toInt();

    final prompt =
        '''
You are a business analyst. First, provide a very short, 2-sentence summary of today's general retail or business market news.
Then, look at the user's POS business data for today:
- Sales Count: $sales
- Revenue: $rev
- Profit: $profit
Write a brief paragraph comparing their performance to general market expectations and give them a short encouraging business brief.
Do not use markdown.
''';
    String aiResponse;
    try {
      if (OpenRouterService.isEnabled) {
        aiResponse = await OpenRouterService.chat(
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          includeBusinessContext: false,
        );
      } else {
        throw Exception('AI is disabled');
      }
    } catch (e) {
      aiResponse =
          "Could not fetch market news right now. But you had $sales sales for ${ShopSettings.currency}${rev.toStringAsFixed(2)} revenue today!";
    }

    return {
      'type': toolDailyBrief,
      'summary': aiResponse.trim().replaceAll('"', ''),
      'sales': sales,
      'revenue': rev,
      'profit': profit,
    };
  }

  static _PikiDateRange _dateRangeForDays(int daysRange) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
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
    final explicitRange = RegExp(
      r'(?:last|past)\s+(\d{1,3})\s+(day|days|week|weeks|month|months)',
    ).firstMatch(input);
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
    final match = RegExp(
      r'\b(?:top|show|list|find)\s+(\d{1,2})\b',
    ).firstMatch(input);
    final value = int.tryParse(match?.group(1) ?? '') ?? 10;
    return value.clamp(1, 20);
  }

  static String? _extractProductQuery(String input) {
    final patterns = [
      RegExp(
        r'^\s*(?:find|search|lookup|look up|show|check)\s+(?:product\s+)?(.+)$',
        caseSensitive: false,
      ),
      RegExp(
        r'^\s*(?:tell me about|details for)\s+(.+)$',
        caseSensitive: false,
      ),
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

  // ─── Sell Mode NLP helpers ───────────────────────────────────────────────

  /// Parses a sell-mode utterance into a qty + product-query pair.
  /// Returns null when the text is a cart-control command, not an add request.
  static ({double qty, String query})? parseSellIntent(String text) {
    if (isClearCartCommand(text) || isCheckoutCommand(text)) return null;

    final lower = text.trim().toLowerCase();

    // "sell/add/ring up/give me/scan {qty} {product}"
    final verbQtyProduct = RegExp(
      r'^(?:sell|add|ring\s+up|give\s+me|scan|get)\s+(\d+(?:\.\d+)?)\s+(.+)$',
    );
    // "{product} x {qty}"
    final productXQty = RegExp(r'^(.+?)\s+x\s*(\d+(?:\.\d+)?)$');
    // "{qty} {product}"
    final qtyProduct = RegExp(r'^(\d+(?:\.\d+)?)\s+(.+)$');
    // "sell/add/etc {product}" (qty implied 1)
    final verbProduct = RegExp(
      r'^(?:sell|add|ring\s+up|give\s+me|scan|get)\s+(.+)$',
    );

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

    if (rows.isNotEmpty) return rows.first;

    if (OpenRouterService.isEnabled) {
      try {
        final categories = await CategoryRepository.getAll();
        final catNames = categories.map((c) => c['name']).join(', ');

        final prompt =
            '''
The user wants to find or sell a product in a point-of-sale system.
Their natural language query, misspelling, or local term is: "$query".
Available product categories: $catNames.
Analyze their intent (including Swahili or local language translations, misspellings, or general categories) and provide a list of up to 5 single-word or short-phrase synonyms or correctly spelled keywords that would likely match the English product name or brand in the database.
Return ONLY a valid JSON array of strings. Do not return any other text.
Example for "unga": ["flour", "maize", "baking"]
''';
        final aiResponse = await OpenRouterService.chat(
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          includeBusinessContext: false,
        );

        final List<dynamic> keywords = jsonDecode(aiResponse);
        for (final kw in keywords) {
          final kwStr = kw.toString().trim().toLowerCase();
          if (kwStr.isNotEmpty) {
            final fallbackRows = await DatabaseService.rawQuery(
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
                '%$kwStr%',
                kwStr,
                '%$kwStr%',
                DatabaseService.defaultBranchId,
                DatabaseService.currentBranchId,
                kwStr,
              ],
            );
            if (fallbackRows.isNotEmpty) return fallbackRows.first;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  static Future<PikiSellableProduct?> findSellableProductForSale(
    String query, {
    Map<String, String> aliases = const <String, String>{},
  }) async {
    final q = _resolveAlias(query, aliases).trim().toLowerCase();
    if (q.isEmpty) return null;

    final variantRows = await DatabaseService.rawQuery(
      '''
      SELECT
        p.*,
        pv.id AS matched_variant_id,
        pv.name AS matched_variant_name,
        pv.sku AS matched_variant_sku,
        pv.barcode AS matched_variant_barcode,
        pv.price AS matched_variant_price,
        pv.cost AS matched_variant_cost,
        pv.stock AS matched_variant_stock,
        pv.low_stock AS matched_variant_low_stock
      FROM products p
      JOIN product_variants pv
        ON pv.product_id = p.id
       AND pv.deleted_at IS NULL
       AND COALESCE(pv.branch_id, ?) = ?
      WHERE p.deleted_at IS NULL
        AND COALESCE(p.branch_id, ?) = ?
        AND (
          LOWER(p.name || ' ' || pv.name) LIKE ?
          OR LOWER(pv.name) LIKE ?
          OR LOWER(COALESCE(pv.sku, '')) LIKE ?
          OR pv.barcode = ?
        )
      ORDER BY
        CASE
          WHEN LOWER(p.name || ' ' || pv.name) = ? THEN 0
          WHEN LOWER(pv.name) = ? THEN 1
          ELSE 2
        END,
        LENGTH(p.name || pv.name) ASC
      LIMIT 1
      ''',
      [
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        '%$q%',
        '%$q%',
        '%$q%',
        q,
        q,
        q,
      ],
    );
    if (variantRows.isNotEmpty) {
      return _sellableFromVariantSearchRow(variantRows.first);
    }

    final rows = await ProductRepository.searchForPos(q);
    if (rows.isNotEmpty) {
      final row = rows.first;
      if (row['result_type'] == 'variant') {
        return _sellableFromVariantSearchRow(row);
      }
      return PikiSellableProduct(product: row);
    }

    final product = await findProductForSale(q);
    return product == null ? null : PikiSellableProduct(product: product);
  }

  static String resolveSaleAlias(String query, Map<String, String> aliases) {
    return _resolveAlias(query, aliases);
  }

  static PikiSellableProduct _sellableFromVariantSearchRow(
    Map<String, dynamic> row,
  ) {
    return PikiSellableProduct(
      product: row,
      variant: {
        'id': row['matched_variant_id'],
        'product_id': row['id'],
        'branch_id': row['branch_id'],
        'business_id': row['business_id'],
        'name': row['matched_variant_name'],
        'sku': row['matched_variant_sku'],
        'barcode': row['matched_variant_barcode'],
        'price': row['matched_variant_price'],
        'cost': row['matched_variant_cost'],
        'stock': row['matched_variant_stock'],
        'low_stock': row['matched_variant_low_stock'],
      },
    );
  }

  static String _resolveAlias(String query, Map<String, String> aliases) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty || aliases.isEmpty) {
      return normalized;
    }
    return aliases[normalized]?.trim().toLowerCase() ?? normalized;
  }

  /// Fuzzy service search: matches name or category.
  static Future<Map<String, dynamic>?> findServiceForSale(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;

    final rows = await DatabaseService.rawQuery(
      '''
      SELECT * FROM services
      WHERE (LOWER(name) LIKE ? OR LOWER(category) LIKE ?)
        AND deleted_at IS NULL
        AND is_active = 1
        AND COALESCE(branch_id, ?) = ?
      ORDER BY
        CASE WHEN LOWER(name) = ? THEN 0 ELSE 1 END,
        LENGTH(name) ASC
      LIMIT 1
      ''',
      [
        '%$q%',
        '%$q%',
        DatabaseService.defaultBranchId,
        DatabaseService.currentBranchId,
        q,
      ],
    );

    if (rows.isNotEmpty) return rows.first;

    if (OpenRouterService.isEnabled) {
      try {
        final categoriesRows = await DatabaseService.rawQuery(
          'SELECT DISTINCT category FROM services WHERE category IS NOT NULL',
        );
        final catNames = categoriesRows.map((c) => c['category']).join(', ');

        final prompt =
            '''
The user wants to find or sell a service in a point-of-sale system.
Their natural language query, misspelling, or local term is: "$query".
Available service categories: $catNames.
Analyze their intent (including Swahili or local language translations, misspellings, or general categories) and provide a list of up to 5 single-word or short-phrase synonyms or correctly spelled keywords that would likely match the English service name in the database.
Return ONLY a valid JSON array of strings. Do not return any other text.
Example for "kinyozi": ["haircut", "barber", "shave"]
''';
        final aiResponse = await OpenRouterService.chat(
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          includeBusinessContext: false,
        );

        final List<dynamic> keywords = jsonDecode(aiResponse);
        for (final kw in keywords) {
          final kwStr = kw.toString().trim().toLowerCase();
          if (kwStr.isNotEmpty) {
            final fallbackRows = await DatabaseService.rawQuery(
              '''
              SELECT * FROM services
              WHERE (LOWER(name) LIKE ? OR LOWER(category) LIKE ?)
                AND deleted_at IS NULL
                AND is_active = 1
                AND COALESCE(branch_id, ?) = ?
              ORDER BY
                CASE WHEN LOWER(name) = ? THEN 0 ELSE 1 END,
                LENGTH(name) ASC
              LIMIT 1
              ''',
              [
                '%$kwStr%',
                '%$kwStr%',
                DatabaseService.defaultBranchId,
                DatabaseService.currentBranchId,
                kwStr,
              ],
            );
            if (fallbackRows.isNotEmpty) return fallbackRows.first;
          }
        }
      } catch (_) {}
    }

    return null;
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

  static String? _stringArg(Map<String, dynamic> args, List<String> keys) {
    for (final key in keys) {
      final value = args[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static String _requiredStringArg(
    Map<String, dynamic> args,
    List<String> keys,
    String label,
  ) {
    final value = _stringArg(args, keys);
    if (value == null) {
      throw Exception('$label is required');
    }
    return value;
  }

  static double? _doubleArg(Map<String, dynamic> args, List<String> keys) {
    for (final key in keys) {
      final value = args[key];
      if (value == null) continue;
      if (value is num) return value.toDouble();
      final cleaned = value
          .toString()
          .replaceAll(',', '')
          .replaceAll(RegExp(r'[^0-9.\-]'), '')
          .trim();
      final parsed = double.tryParse(cleaned);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static double _requiredPositiveDoubleArg(
    Map<String, dynamic> args,
    List<String> keys,
    String label,
  ) {
    final value = _doubleArg(args, keys);
    if (value == null || value <= 0) {
      throw Exception('$label must be greater than zero');
    }
    return value;
  }

  static double _nonNegativeDoubleArg(
    Map<String, dynamic> args,
    List<String> keys,
    double fallback,
  ) {
    final value = _doubleArg(args, keys);
    return value == null || value < 0 ? fallback : value;
  }

  static int? _intArg(Map<String, dynamic> args, List<String> keys) {
    final value = _doubleArg(args, keys);
    return value?.toInt();
  }

  static bool _boolArg(
    Map<String, dynamic> args,
    List<String> keys, {
    bool fallback = false,
  }) {
    for (final key in keys) {
      final value = args[key];
      if (value == null) continue;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final text = value.toString().trim().toLowerCase();
      if (['true', 'yes', 'y', '1', 'required'].contains(text)) return true;
      if (['false', 'no', 'n', '0', 'optional'].contains(text)) return false;
    }
    return fallback;
  }

  static List<String> _stringListArg(
    Map<String, dynamic> args,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = args[key];
      if (value == null) continue;
      if (value is List) {
        return value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList();
      }
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      return text
          .split(RegExp(r'[,|]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  static String _paymentTypeArg(Map<String, dynamic> args) {
    final raw = _stringArg(args, ['payment_type', 'paymentType', 'payment']);
    final normalized = raw?.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    return switch (normalized) {
      'card' || 'credit_card' || 'debit_card' => 'card',
      'mobile' || 'mobile_money' || 'mpesa' || 'm_pesa' => 'mobile_money',
      'kopesha' || 'credit' => 'kopesha',
      _ => 'cash',
    };
  }

  static String _currentUserId() => SessionService.currentUserId.isNotEmpty
      ? SessionService.currentUserId
      : 'admin';

  static Future<String?> _resolveProductCategoryId(
    Map<String, dynamic> args,
  ) async {
    final categoryId = _stringArg(args, ['category_id', 'categoryId']);
    if (categoryId != null) return categoryId;

    final categoryName = _stringArg(args, ['category', 'category_name']);
    if (categoryName == null) return null;
    final categories = await CategoryRepository.getAll();
    final normalized = categoryName.toLowerCase();
    for (final category in categories) {
      if ((category['name'] as String? ?? '').trim().toLowerCase() ==
          normalized) {
        return category['id'] as String?;
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _findService(String query) async {
    final services = await ServiceRepository.getServices(
      activeOnly: true,
      query: query,
    );
    if (services.isEmpty) return null;
    final normalized = query.trim().toLowerCase();
    for (final service in services) {
      if ((service['name'] as String? ?? '').trim().toLowerCase() ==
          normalized) {
        return service;
      }
    }
    return services.first;
  }

  static Future<Map<String, dynamic>> _createProduct(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'product_name',
    ], 'Product name');
    final price = _requiredPositiveDoubleArg(args, [
      'price',
      'unit_price',
      'selling_price',
    ], 'Product price');
    final cost = _doubleArg(args, ['cost', 'unit_cost']);
    final stock = _nonNegativeDoubleArg(args, ['stock', 'initial_stock'], 0);
    final lowStock = _nonNegativeDoubleArg(args, ['low_stock', 'lowStock'], 5);
    final unit = _stringArg(args, ['unit', 'sale_unit']) ?? 'pcs';
    final categoryId = await _resolveProductCategoryId(args);
    final id = await ProductRepository.create(
      name: name,
      price: price,
      cost: cost,
      brand: _stringArg(args, ['brand']),
      sku: _stringArg(args, ['sku']),
      barcode: _stringArg(args, ['barcode']),
      stock: stock,
      lowStock: lowStock,
      unit: unit,
      stockUnit: _stringArg(args, ['stock_unit', 'stockUnit']),
      saleUnit: _stringArg(args, ['sale_unit', 'saleUnit']),
      purchaseUnit: _stringArg(args, ['purchase_unit', 'purchaseUnit']),
      categoryId: categoryId,
      trackStock: _boolArg(args, ['track_stock', 'trackStock'], fallback: true),
    );

    return _enrichToolResult(toolCreateProduct, {
      'type': toolCreateProduct,
      'success': true,
      'id': id,
      'name': name,
      'price': price,
      'stock': stock,
      'summary':
          'Created product "$name" at ${ShopSettings.currency}${price.toStringAsFixed(2)}',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _createService(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'service_name',
    ], 'Service name');
    final price = _requiredPositiveDoubleArg(args, [
      'price',
      'base_price',
      'unit_price',
    ], 'Service price');
    final id = await ServiceRepository.createService(
      name: name,
      category: _stringArg(args, ['category']),
      description: _stringArg(args, ['description', 'note']),
      basePrice: price,
      durationMinutes: _intArg(args, ['duration_minutes', 'duration']),
      isActive: true,
    );

    return _enrichToolResult(toolCreateService, {
      'type': toolCreateService,
      'success': true,
      'id': id,
      'name': name,
      'price': price,
      'summary':
          'Created service "$name" at ${ShopSettings.currency}${price.toStringAsFixed(2)}',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _recordProductSale(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'product_name',
      'query',
      'name',
    ], 'Product name');
    final sellable = await findSellableProductForSale(query);
    if (sellable == null) {
      throw Exception('No product found matching "$query"');
    }
    final product = sellable.product;
    final variant = sellable.variant;
    final quantity = _requiredPositiveDoubleArg(
      {'quantity': args['quantity'] ?? 1},
      ['quantity'],
      'Quantity',
    );
    final saleToStockFactor = (product['sale_to_stock_factor'] as num? ?? 1)
        .toDouble();
    final unitPrice =
        _doubleArg(args, ['unit_price', 'price']) ??
        (variant?['price'] as num? ?? product['price'] as num? ?? 0).toDouble();
    if (unitPrice <= 0) {
      throw Exception('Unit price must be greater than zero');
    }
    final unitCost =
        ((variant?['cost'] as num? ?? product['cost'] as num? ?? 0)
            .toDouble()) *
        saleToStockFactor;
    final total = quantity * unitPrice;
    final saleId = await SaleRepository.createSale(
      totalAmount: total,
      tax: 0,
      discount: 0,
      paymentType: _paymentTypeArg(args),
      userId: _currentUserId(),
      items: [
        {
          'line_type': 'product',
          'product_id': product['id'],
          'product_name': sellable.label,
          'quantity': quantity,
          'unit_price': unitPrice,
          'unit_cost': unitCost,
          'unit':
              product['sale_unit'] as String? ??
              product['unit'] as String? ??
              'pcs',
          'sale_to_stock_factor': saleToStockFactor,
          'stock_unit':
              product['stock_unit'] as String? ??
              product['unit'] as String? ??
              'pcs',
          'track_stock': product['track_stock'] ?? 1,
          'variant_id': variant?['id'],
        },
      ],
    );

    return _enrichToolResult(toolRecordProductSale, {
      'type': toolRecordProductSale,
      'success': true,
      'id': saleId,
      'product_id': product['id'],
      'variant_id': variant?['id'],
      'product_name': sellable.label,
      'quantity': quantity,
      'total': total,
      'summary':
          'Recorded sale of $quantity x ${sellable.label} for ${ShopSettings.currency}${total.toStringAsFixed(2)}',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _recordServiceSale(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'service_name',
      'query',
      'name',
    ], 'Service name');
    final service = await _findService(query);
    if (service == null) {
      throw Exception('No active service found matching "$query"');
    }
    final quantity = _requiredPositiveDoubleArg(
      {'quantity': args['quantity'] ?? 1},
      ['quantity'],
      'Quantity',
    );
    final unitPrice =
        _doubleArg(args, ['unit_price', 'price']) ??
        (service['base_price'] as num? ?? 0).toDouble();
    if (unitPrice <= 0) {
      throw Exception('Unit price must be greater than zero');
    }
    final serviceName = service['name'] as String? ?? query;
    final serviceId = service['id'] as String;
    final total = quantity * unitPrice;
    final now = DateTime.now().toIso8601String();
    final assignedStaff = ServiceRepository.defaultAssignedStaffName();
    final orderId = await ServiceRepository.createOrder(
      serviceId: serviceId,
      serviceName: serviceName,
      customerName: _stringArg(args, ['customer_name', 'customer']),
      entryMode: 'walk_in',
      checkedInAt: now,
      status: 'completed',
      assignedStaff: assignedStaff,
      assignedStaffUserId: ServiceRepository.currentAssignedStaffUserIdFor(
        assignedStaff,
      ),
      price: total,
      note: _stringArg(args, ['note']),
    );
    final saleId = await SaleRepository.createSale(
      totalAmount: total,
      tax: 0,
      discount: 0,
      paymentType: _paymentTypeArg(args),
      userId: _currentUserId(),
      items: [
        {
          'line_type': 'service',
          'product_id': 'service:$orderId',
          'product_name': serviceName,
          'quantity': quantity,
          'unit_price': unitPrice,
          'service_order_id': orderId,
          'service_id': serviceId,
        },
      ],
    );

    return _enrichToolResult(toolRecordServiceSale, {
      'type': toolRecordServiceSale,
      'success': true,
      'id': saleId,
      'service_order_id': orderId,
      'service_id': serviceId,
      'service_name': serviceName,
      'quantity': quantity,
      'total': total,
      'summary':
          'Recorded service sale of $quantity x $serviceName for ${ShopSettings.currency}${total.toStringAsFixed(2)}',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _createCategory(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'category',
    ], 'Category name');
    final id = await CategoryRepository.create(
      name: name,
      color: _stringArg(args, ['color']),
    );
    return _enrichToolResult(toolCreateCategory, {
      'type': toolCreateCategory,
      'success': true,
      'id': id,
      'name': name,
      'summary': 'Created product category "$name"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _createExpenseCategory(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'category',
    ], 'Expense category name');
    final id = await ExpenseRepository.createCategory(
      name: name,
      color: _stringArg(args, ['color']),
    );
    return _enrichToolResult(toolCreateExpenseCategory, {
      'type': toolCreateExpenseCategory,
      'success': true,
      'id': id,
      'name': name,
      'summary': 'Created expense category "$name"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _createCustomer(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'customer_name',
    ], 'Customer name');
    final id = await CustomerRepository.create(
      name: name,
      phone: _stringArg(args, ['phone']),
      email: _stringArg(args, ['email']),
    );
    return _enrichToolResult(toolCreateCustomer, {
      'type': toolCreateCustomer,
      'success': true,
      'id': id,
      'name': name,
      'summary': 'Created customer "$name"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _createSupplier(
    Map<String, dynamic> args,
  ) async {
    final name = _requiredStringArg(args, [
      'name',
      'supplier_name',
    ], 'Supplier name');
    final id = await PurchaseRepository.createSupplier(
      name: name,
      phone: _stringArg(args, ['phone']),
      email: _stringArg(args, ['email']),
      address: _stringArg(args, ['address']),
      note: _stringArg(args, ['note']),
    );
    return _enrichToolResult(toolCreateSupplier, {
      'type': toolCreateSupplier,
      'success': true,
      'id': id,
      'name': name,
      'summary': 'Created supplier "$name"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _reconcileStock(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'product_name',
      'query',
      'name',
    ], 'Product name');
    final product = await findProductForSale(query);
    if (product == null) {
      throw Exception('No product found matching "$query"');
    }
    final newCount = _doubleArg(args, ['new_count', 'count', 'stock']);
    if (newCount == null || newCount < 0) {
      throw Exception('New stock count must be zero or greater');
    }
    final oldCount = (product['stock'] as num? ?? 0).toDouble();
    await ProductRepository.update(product['id'] as String, {
      'stock': newCount,
      'updated_at': DateTime.now().toIso8601String(),
      'sync_status': 'pending',
    });
    return _enrichToolResult(toolReconcileStock, {
      'type': toolReconcileStock,
      'success': true,
      'product_id': product['id'],
      'product_name': product['name'],
      'old_stock': oldCount,
      'new_stock': newCount,
      'summary': 'Updated ${product['name']} stock from $oldCount to $newCount',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _addServiceField(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'service_name',
      'query',
      'name',
    ], 'Service name');
    final service = await _findService(query);
    if (service == null) {
      throw Exception('No active service found matching "$query"');
    }
    final label = _requiredStringArg(args, [
      'field_label',
      'label',
    ], 'Field label');
    final fieldType =
        _stringArg(args, ['field_type', 'type'])?.toLowerCase() ?? 'text';
    final serviceId = service['id'] as String;
    final fields = await ServiceRepository.getFieldsForService(serviceId);
    fields.add({
      'label': label,
      'field_type': fieldType,
      'options': _stringListArg(args, ['options']),
      'is_required': _boolArg(args, ['is_required', 'required']),
      'sort_order': fields.length,
    });
    await ServiceRepository.updateService(
      id: serviceId,
      name: service['name'] as String? ?? query,
      category: service['category'] as String?,
      description: service['description'] as String?,
      basePrice: (service['base_price'] as num? ?? 0).toDouble(),
      durationMinutes: (service['duration_minutes'] as num?)?.toInt(),
      isActive: (service['is_active'] as num? ?? 1) != 0,
      fields: fields,
    );
    return _enrichToolResult(toolAddServiceField, {
      'type': toolAddServiceField,
      'success': true,
      'service_id': serviceId,
      'service_name': service['name'],
      'field_label': label,
      'summary': 'Added "$label" field to ${service['name']}',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _searchCustomers(
    Map<String, dynamic> args,
  ) async {
    final query = _stringArg(args, ['query', 'name', 'customer_name']) ?? '';
    final limit = _coercePositiveInt(args['limit'], 10).clamp(1, 20);
    final customers = await CustomerRepository.search(query);
    final limited = customers.take(limit).toList();
    return _enrichToolResult(toolCustomerSearch, {
      'type': toolCustomerSearch,
      'items': limited,
      'count': customers.length,
      'searched_query': query,
      'summary': query.isEmpty
          ? '${customers.length} customers found'
          : '${customers.length} customer matches for "$query"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _searchSuppliers(
    Map<String, dynamic> args,
  ) async {
    final query = _stringArg(args, ['query', 'name', 'supplier_name']) ?? '';
    final limit = _coercePositiveInt(args['limit'], 10).clamp(1, 20);
    final normalized = query.toLowerCase();
    final suppliers = await PurchaseRepository.getSuppliers();
    final matches = normalized.isEmpty
        ? suppliers
        : suppliers.where((supplier) {
            final haystack = [
              supplier['name'],
              supplier['phone'],
              supplier['email'],
              supplier['address'],
            ].whereType<Object>().join(' ').toLowerCase();
            return haystack.contains(normalized);
          }).toList();
    final limited = matches.take(limit).toList();
    return _enrichToolResult(toolSupplierSearch, {
      'type': toolSupplierSearch,
      'items': limited,
      'count': matches.length,
      'searched_query': query,
      'summary': query.isEmpty
          ? '${matches.length} suppliers found'
          : '${matches.length} supplier matches for "$query"',
    }, args: args);
  }

  static Future<Map<String, dynamic>> _webSearch(
    Map<String, dynamic> args,
  ) async {
    final query = (args['query'] ?? args['q'] ?? '').toString().trim();
    if (query.isEmpty) {
      throw Exception('Web search query is required.');
    }

    final result = await OpenRouterService.webSearch(
      query: query,
      location: (args['location'] as String?)?.trim(),
      countryCode:
          (args['countryCode'] as String?)?.trim() ??
          (args['gl'] as String?)?.trim(),
      language:
          (args['language'] as String?)?.trim() ??
          (args['hl'] as String?)?.trim(),
      limit: _coercePositiveInt(args['limit'], 5).clamp(1, 10),
    );
    final results =
        (result['results'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];

    final citations = results
        .where((item) => (item['link'] as String? ?? '').isNotEmpty)
        .take(5)
        .map(
          (item) => {
            'label': item['title'] as String? ?? 'Web result',
            'detail': item['link'] as String? ?? '',
          },
        )
        .toList();

    return _enrichToolResult(toolWebSearch, {
      ...result,
      'items': results,
      'citations': citations,
      'summary':
          result['summary'] as String? ??
          '${results.length} web result(s) found for "$query"',
    }, args: args);
  }

  static Map<String, dynamic> _enrichToolResult(
    String tool,
    Map<String, dynamic> result, {
    required Map<String, dynamic> args,
  }) {
    final enriched = Map<String, dynamic>.from(result);
    enriched['tool'] = tool;
    enriched['title'] = _toolLabels[tool] ?? enriched['title'] ?? tool;
    final existingCitations =
        (enriched['citations'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    enriched['citations'] = existingCitations.isNotEmpty
        ? existingCitations
        : _citationsForTool(tool, result, args: args);
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
          'detail': query == null || query.isEmpty
              ? 'Read from the local product catalog for the current branch.'
              : 'Matched against local product name, barcode, or SKU using "$query".',
        },
      ],
      toolShiftSummary => [
        {
          'label': 'Closed shifts',
          'detail':
              'Loaded from the most recent closed shifts in the current branch.',
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
      toolCustomerSearch => [
        {
          'label': 'Customer records',
          'detail': 'Read from local customers in the current branch.',
        },
      ],
      toolSupplierSearch => [
        {
          'label': 'Supplier records',
          'detail': 'Read from local supplier records in the current branch.',
        },
      ],
      toolWebSearch => [
        {
          'label': 'Web search',
          'detail': query == null || query.isEmpty
              ? 'Searched live Google results through the backend SerpAPI proxy.'
              : 'Searched live Google results for "$query" through the backend SerpAPI proxy.',
        },
      ],
      toolCreateProduct ||
      toolCreateService ||
      toolRecordProductSale ||
      toolRecordServiceSale ||
      toolCreateCategory ||
      toolCreateExpenseCategory ||
      toolCreateCustomer ||
      toolCreateSupplier ||
      toolReconcileStock ||
      toolAddServiceField => [
        {
          'label': 'Local POS write',
          'detail':
              'Executed against the local POS database for the current branch.',
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
      baseItems =
          (memoryLowStock is Map<String, dynamic>
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
      final reorderQty =
          (item['reorder_qty'] as num? ??
                  (((item['low_stock'] as num? ?? 0).toDouble() * 2) -
                      (item['stock'] as num? ?? 0).toDouble()))
              .toDouble();
      draftItems.add({
        'product_id': productId,
        'product_name': item['name'] ?? item['product_name'],
        'recommended_qty': reorderQty <= 0 ? 1.0 : reorderQty,
        'unit':
            item['purchase_unit'] ??
            item['stock_unit'] ??
            item['unit'] ??
            'pcs',
        'last_unit_cost':
            (history?['unit_cost'] as num? ?? item['cost'] as num? ?? 0)
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
    final groupedPreview =
        supplierGroups.entries.map((entry) {
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
                .map(
                  (item) => {
                    'product_name': item['product_name'],
                    'recommended_qty': item['recommended_qty'],
                    'unit': item['unit'],
                  },
                )
                .toList(),
          };
        }).toList()..sort(
          (a, b) => (b['item_count'] as int).compareTo(a['item_count'] as int),
        );

    return _enrichToolResult(toolPurchaseDraft, {
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
      'details': draftItems.take(4).map((item) {
        final qty = (item['recommended_qty'] as num? ?? 0).toDouble();
        final supplier = item['suggested_supplier_name'] as String?;
        return supplier == null || supplier.isEmpty
            ? '${item['product_name']}: order ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} ${item['unit']}'
            : '${item['product_name']}: order ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} ${item['unit']} from $supplier';
      }).toList(),
    }, args: args);
  }

  static Future<Map<String, dynamic>> _editProduct(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'query',
      'name',
      'product_name',
    ], 'Product query');
    final products = await ProductRepository.searchForPos(query);
    if (products.isEmpty) {
      throw Exception('Could not find product matching "$query".');
    }
    final target = products.first;
    final isVariant = target['result_type'] == 'variant';
    final id = isVariant
        ? target['matched_variant_id'] as String
        : target['id'] as String;

    final updates = <String, dynamic>{};
    final newName = _stringArg(args, ['new_name']);
    if (newName != null) updates['name'] = newName;
    final price = _doubleArg(args, ['price']);
    if (price != null) updates['price'] = price;
    final cost = _doubleArg(args, ['cost']);
    if (cost != null) updates['cost'] = cost;
    final lowStock = _doubleArg(args, ['low_stock']);
    if (lowStock != null && lowStock >= 0) updates['low_stock'] = lowStock;
    final barcode = _stringArg(args, ['barcode']);
    if (barcode != null) updates['barcode'] = barcode;

    if (updates.isEmpty) {
      throw Exception('No valid fields provided to edit.');
    }

    updates['updated_at'] = DateTime.now().toIso8601String();
    updates['sync_status'] = 'pending';

    if (isVariant) {
      await ProductVariantRepository.update(id, updates);
    } else {
      await ProductRepository.update(id, updates);
    }

    return {
      'tool': toolEditProduct,
      'summary':
          'Updated ${isVariant ? 'variant' : 'product'} "${target['name']}" with new details.',
      'updates': updates,
    };
  }

  static Future<Map<String, dynamic>> _addVariant(
    Map<String, dynamic> args,
  ) async {
    final query = _requiredStringArg(args, [
      'query',
      'product_name',
      'name',
    ], 'Product query');
    final products = await ProductRepository.search(query);
    if (products.isEmpty) {
      throw Exception('Could not find parent product matching "$query".');
    }
    final target = products.first;
    final productId = target['id'] as String;

    final variantName = _requiredStringArg(args, [
      'variant_name',
      'name',
    ], 'Variant name');
    final price = _requiredPositiveDoubleArg(args, ['price'], 'Variant price');
    final cost = _doubleArg(args, ['cost']);
    final sku = _stringArg(args, ['sku']);
    final barcode = _stringArg(args, ['barcode']);
    final stock = _nonNegativeDoubleArg(args, ['stock'], 0);
    final lowStock = _nonNegativeDoubleArg(args, ['low_stock'], 0);

    final id = await ProductVariantRepository.create(
      productId: productId,
      name: variantName,
      price: price,
      cost: cost,
      sku: sku,
      barcode: barcode,
      stock: stock,
      lowStock: lowStock,
    );

    await ProductVariantRepository.setProductHasVariants(productId, true);
    await ProductVariantRepository.syncAggregateStock(productId);

    return {
      'tool': toolAddVariant,
      'summary': 'Added variant "$variantName" to product "${target['name']}".',
      'variant_id': id,
    };
  }
}

class _PikiDateRange {
  final DateTime start;
  final DateTime end;

  const _PikiDateRange({required this.start, required this.end});
}
