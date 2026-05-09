import 'package:flutter/material.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';

/// Renders a structured metric card for fast-mode Piki results.
/// Switches layout based on the [data] 'type' field.
class PikiSummaryCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const PikiSummaryCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String? ?? '';
    switch (type) {
      case 'today_summary':
        return _TodaySummaryCard(data: data);
      case 'profit_summary':
        return _ProfitCard(data: data);
      case 'shift_summary':
        return _ShiftCard(data: data);
      case 'expiry_check':
        return _ExpiryCard(data: data);
      case 'sales_report':
        return _SalesReportCard(data: data);
      case 'top_debtors':
        return _TopDebtorsCard(data: data);
      case 'top_products':
        return _TopProductsCard(data: data);
      case 'expense_summary':
        return _ExpenseSummaryCard(data: data);
      case 'purchase_history':
        return _PurchaseHistoryCard(data: data);
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─── Today's Summary ─────────────────────────────────────────────────────────

class _TodaySummaryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TodaySummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final currency = ShopSettings.currency;
    final revenue = (data['total_revenue'] as num? ?? 0).toDouble();
    final profit = (data['total_profit'] as num? ?? 0).toDouble();
    final sales = (data['total_sales'] as num? ?? 0).toInt();
    final margin = revenue > 0 ? (profit / revenue * 100) : 0.0;

    return Column(
      children: [
        _MetricRow(
          icon: Icons.attach_money_rounded,
          label: 'Revenue',
          value: '$currency${revenue.toStringAsFixed(2)}',
          color: AppColors.success,
        ),
        const SizedBox(height: 8),
        _MetricRow(
          icon: Icons.trending_up_rounded,
          label: 'Profit',
          value: '$currency${profit.toStringAsFixed(2)}',
          color: profit >= 0 ? AppColors.success : AppColors.error,
        ),
        const SizedBox(height: 8),
        _MetricRow(
          icon: Icons.receipt_long_rounded,
          label: 'Transactions',
          value: '$sales sales',
          color: AppColors.primary,
        ),
        const SizedBox(height: 8),
        _MetricRow(
          icon: Icons.percent_rounded,
          label: 'Margin',
          value: '${margin.toStringAsFixed(1)}%',
          color: AppColors.secondary,
        ),
      ],
    );
  }
}

// ─── Profit Summary ───────────────────────────────────────────────────────────

class _ProfitCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ProfitCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final currency = ShopSettings.currency;
    final profit = (data['total_profit'] as num? ?? 0).toDouble();
    final revenue = (data['total_revenue'] as num? ?? 0).toDouble();
    final margin = revenue > 0 ? (profit / revenue * 100) : 0.0;

    return Column(
      children: [
        _MetricRow(
          icon: Icons.monetization_on_rounded,
          label: 'Net Profit',
          value: '$currency${profit.toStringAsFixed(2)}',
          color: profit >= 0 ? AppColors.success : AppColors.error,
        ),
        const SizedBox(height: 8),
        _MetricRow(
          icon: Icons.attach_money_rounded,
          label: 'Revenue',
          value: '$currency${revenue.toStringAsFixed(2)}',
          color: AppColors.success,
        ),
        const SizedBox(height: 8),
        _MetricRow(
          icon: Icons.percent_rounded,
          label: 'Profit Margin',
          value: '${margin.toStringAsFixed(1)}%',
          color: AppColors.secondary,
        ),
      ],
    );
  }
}

// ─── Shift Summary ────────────────────────────────────────────────────────────

class _ShiftCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ShiftCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final currency = ShopSettings.currency;
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isEmpty) {
      return const _MetricRow(
        icon: Icons.timer_off_rounded,
        label: 'No closed shifts',
        value: '--',
        color: AppColors.textSecondary,
      );
    }
    return Column(
      children: items.take(3).map((shift) {
        final cashier = (shift['user_name'] as String?)?.trim().isNotEmpty == true
            ? shift['user_name'] as String
            : (shift['opened_by'] as String?)?.trim().isNotEmpty == true
                ? shift['opened_by'] as String
                : 'Cashier';
        final total = (shift['total_sales'] as num? ?? 0).toDouble();
        final cash = (shift['cash_total'] as num? ?? 0).toDouble();
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.timer_rounded, size: 18, color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  cashier,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Text(
                '$currency${total.toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
              ),
              if (cash > 0) ...[
                const SizedBox(width: 8),
                Text(
                  'Cash: $currency${cash.toStringAsFixed(0)}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Expiry Check ─────────────────────────────────────────────────────────────

class _ExpiryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ExpiryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (items.isEmpty) {
      return const _MetricRow(
        icon: Icons.check_circle_rounded,
        label: 'Inventory expiry',
        value: 'All clear ✓',
        color: AppColors.success,
      );
    }
    return Column(
      children: items.take(5).map((batch) {
        final name = batch['product_name'] as String? ?? 'Product';
        final days = (batch['days_to_expiry'] as num? ?? 0).toInt();
        final color = days <= 0
            ? AppColors.error
            : days <= 7
                ? AppColors.warning
                : AppColors.success;
        final label = days <= 0
            ? 'EXPIRED'
            : days == 1
                ? 'Tomorrow'
                : 'in $days days';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _MetricRow(
            icon: Icons.event_busy_rounded,
            label: name,
            value: label,
            color: color,
          ),
        );
      }).toList(),
    );
  }
}

// ─── Sales Report ─────────────────────────────────────────────────────────────

class _SalesReportCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SalesReportCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final currency = ShopSettings.currency;
    final total = (data['total_count'] as num? ?? 0).toInt();
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricRow(
          icon: Icons.receipt_long_rounded,
          label: 'Total Sales',
          value: '$total transactions',
          color: AppColors.primary,
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...items.take(3).map((sale) {
            final amount = (sale['total_amount'] as num? ?? 0).toDouble();
            final date = sale['created_at'] as String? ?? '';
            final timeStr = date.length >= 16 ? date.substring(11, 16) : '--:--';
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_rounded,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Sale at $timeStr',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  Text(
                    '$currency${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}

// ─── Shared metric row ────────────────────────────────────────────────────────

class _MetricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─── Top Debtors ─────────────────────────────────────────────────────────────

class _TopDebtorsCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TopDebtorsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final currency = ShopSettings.currency;
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final totalOwed = (data['total_owed'] as num? ?? 0).toDouble();

    if (items.isEmpty) {
      return const _MetricRow(
        icon: Icons.check_circle_rounded,
        label: 'No outstanding balances',
        value: 'All clear',
        color: AppColors.success,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricRow(
          icon: Icons.account_balance_wallet_rounded,
          label: 'Total outstanding',
          value: '$currency${totalOwed.toStringAsFixed(2)}',
          color: AppColors.error,
        ),
        const SizedBox(height: 10),
        ...items.take(5).map((debtor) {
          final name = debtor['name'] as String? ?? 'Customer';
          final balance = (debtor['balance'] as num? ?? 0).toDouble();
          return Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                Text(
                  '$currency${balance.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─── Top Products ─────────────────────────────────────────────────────────────

class _TopProductsCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _TopProductsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final currency = ShopSettings.currency;
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (items.isEmpty) {
      return const _MetricRow(
        icon: Icons.leaderboard_rounded,
        label: 'No sales data yet',
        value: '--',
        color: AppColors.textSecondary,
      );
    }

    final rankColors = [AppColors.warning, AppColors.textSecondary, AppColors.primaryLight];

    return Column(
      children: items.asMap().entries.map((entry) {
        final i = entry.key;
        final p = entry.value;
        final name = p['name'] as String? ?? 'Product';
        final qty = (p['total_qty_sold'] as num? ?? 0).toDouble();
        final revenue = (p['total_revenue'] as num? ?? 0).toDouble();
        final unit = p['sale_unit'] as String? ?? p['unit'] as String? ?? 'pcs';
        final rankColor = i < rankColors.length ? rankColors[i] : AppColors.textSecondary;

        return Container(
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(color: rankColor, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Text(
                      '${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} $unit sold',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                '$currency${revenue.toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Expense Summary ──────────────────────────────────────────────────────────

class _ExpenseSummaryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ExpenseSummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final currency = ShopSettings.currency;
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final total = (data['total_amount'] as num? ?? 0).toDouble();

    if (items.isEmpty) {
      return const _MetricRow(
        icon: Icons.money_off_rounded,
        label: 'No expenses recorded',
        value: 'None (30 days)',
        color: AppColors.success,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricRow(
          icon: Icons.money_off_rounded,
          label: 'Total (30 days)',
          value: '$currency${total.toStringAsFixed(2)}',
          color: AppColors.warning,
        ),
        const SizedBox(height: 10),
        ...items.take(5).map((expense) {
          final title = expense['title'] as String? ?? 'Expense';
          final amount = (expense['amount'] as num? ?? 0).toDouble();
          final category = expense['category_name'] as String? ?? '';
          return Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_rounded, size: 16, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      if (category.isNotEmpty)
                        Text(category,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
                Text(
                  '$currency${amount.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          );
        }),
        if (items.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+ ${items.length - 5} more expenses',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

// ─── Purchase History ─────────────────────────────────────────────────────────

class _PurchaseHistoryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PurchaseHistoryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final currency = ShopSettings.currency;
    final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (items.isEmpty) {
      return const _MetricRow(
        icon: Icons.local_shipping_rounded,
        label: 'No purchases recorded',
        value: '--',
        color: AppColors.textSecondary,
      );
    }

    return Column(
      children: items.take(6).map((batch) {
        final product = batch['product_name'] as String? ?? 'Product';
        final qty = (batch['quantity_received'] as num? ?? 0).toDouble();
        final unit = batch['stock_unit'] as String? ?? batch['unit'] as String? ?? 'pcs';
        final cost = (batch['cost_per_unit'] as num? ?? 0).toDouble();
        final supplier = (batch['supplier_name'] as String?)?.trim().isNotEmpty == true
            ? batch['supplier_name'] as String
            : null;
        final received = batch['received_at'] as String? ?? '';
        final dateStr = received.length >= 10 ? received.substring(0, 10) : '--';

        return Container(
          margin: const EdgeInsets.only(bottom: 7),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.local_shipping_rounded, size: 16, color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(
                      '${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 1)} $unit'
                      '${supplier != null ? ' · $supplier' : ''} · $dateStr',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (cost > 0)
                Text(
                  '$currency${cost.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
