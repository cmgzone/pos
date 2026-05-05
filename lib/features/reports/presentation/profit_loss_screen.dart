import 'package:flutter/material.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../app/app_shell.dart';
import '../../training/widgets/training_anchor.dart';
import '../data/expense_repository.dart';

class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  List<Map<String, dynamic>> _dailyData = [];
  List<Map<String, dynamic>> _recentExpenses = [];
  List<Map<String, dynamic>> _categoryTotals = [];
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic> _totals = {};
  bool _isLoading = true;
  int _daysRange = 7;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _dailyData = await ExpenseRepository.getDailyProfitLoss(
        daysRange: _daysRange,
      );
      _totals = await ExpenseRepository.getProfitLossTotals(
        daysRange: _daysRange,
      );
      _categories = await ExpenseRepository.getCategories();
      _categoryTotals = await ExpenseRepository.getExpenseCategoryTotals(
        daysRange: _daysRange,
      );
      _recentExpenses = await ExpenseRepository.getRecentExpenses(
        daysRange: _daysRange,
        limit: 10,
      );
    } catch (e) {
      debugPrint('[P&L] Error: $e');
      _dailyData = [];
      _totals = {};
      _categoryTotals = [];
      _recentExpenses = [];
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddCategoryDialog() async {
    final controller = TextEditingController();
    bool saving = false;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Add Expense Category'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Category Name',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        await ExpenseRepository.createCategory(
                          name: controller.text,
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (created == true) {
      await _loadData();
    }
  }

  Future<void> _showAddExpenseDialog() async {
    if (_categories.isEmpty) {
      await _showAddCategoryDialog();
      if (!mounted) {
        return;
      }
    }

    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    var selectedDate = DateTime.now();
    String? selectedCategoryId = _categories.isNotEmpty
        ? _categories.first['id'] as String?
        : null;
    bool saving = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Record Expense'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Expense Title',
                      prefixIcon: Icon(Icons.receipt_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.label_outline),
                    ),
                    items: _categories
                        .map(
                          (category) => DropdownMenuItem(
                            value: category['id'] as String,
                            child: Text(category['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedCategoryId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: const Icon(Icons.payments_outlined),
                      prefixText: '${ShopSettings.currency} ',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: saving
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365),
                                ),
                              );
                              if (picked != null && context.mounted) {
                                setDialogState(() => selectedDate = picked);
                              }
                            },
                      icon: const Icon(Icons.calendar_today),
                      label: Text(_formatDateValue(selectedDate)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        final amount = double.tryParse(
                          amountController.text.trim(),
                        );
                        Map<String, dynamic>? selectedCategory;
                        for (final category in _categories) {
                          if (category['id'] == selectedCategoryId) {
                            selectedCategory = category;
                            break;
                          }
                        }
                        await ExpenseRepository.createExpense(
                          title: titleController.text,
                          amount: amount ?? 0.0,
                          incurredOn: selectedDate.toIso8601String(),
                          categoryId: selectedCategoryId,
                          categoryName: selectedCategory?['name'] as String?,
                          note: noteController.text,
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    titleController.dispose();
    amountController.dispose();
    noteController.dispose();

    if (created == true) {
      await _loadData();
    }
  }

  String _formatDateValue(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDate(String isoString) {
    if (isoString.isEmpty) {
      return 'Unknown';
    }
    try {
      return _formatDateValue(DateTime.parse(isoString));
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    final revenue = (_totals['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final cost = (_totals['total_cost'] as num?)?.toDouble() ?? 0.0;
    final grossProfit = (_totals['gross_profit'] as num?)?.toDouble() ?? 0.0;
    final expenses = (_totals['total_expenses'] as num?)?.toDouble() ?? 0.0;
    final netProfit = (_totals['net_profit'] as num?)?.toDouble() ?? 0.0;
    final salesCount = (_totals['total_sales'] as num?)?.toInt() ?? 0;
    final netPositive = netProfit >= 0;
    final margin = revenue > 0 ? (netProfit / revenue * 100.0) : 0.0;
    final summaryCards = [
      _SummaryCard(
        label: 'Revenue',
        value: '${ShopSettings.currency}${revenue.toStringAsFixed(2)}',
        color: AppColors.primary,
      ),
      _SummaryCard(
        label: 'Inventory Cost',
        value: '${ShopSettings.currency}${cost.toStringAsFixed(2)}',
        color: AppColors.warning,
      ),
      _SummaryCard(
        label: 'Gross Profit',
        value: '${ShopSettings.currency}${grossProfit.toStringAsFixed(2)}',
        color: grossProfit >= 0 ? AppColors.success : AppColors.error,
      ),
      _SummaryCard(
        label: 'Expenses',
        value: '${ShopSettings.currency}${expenses.toStringAsFixed(2)}',
        color: AppColors.error,
      ),
      _SummaryCard(
        label: 'Net Profit',
        value:
            '${netPositive ? '+' : ''}${ShopSettings.currency}${netProfit.toStringAsFixed(2)}',
        color: netPositive ? AppColors.success : AppColors.error,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () =>
                    AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        title: const Text('Profit & Loss'),
        actions: [
          if (isMobile) ...[
            IconButton(
              icon: const Icon(Icons.label_outline),
              tooltip: 'Add Category',
              onPressed: _showAddCategoryDialog,
            ),
            TrainingAnchor(
              id: 'pl.addExpense',
              child: IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Add Expense',
                onPressed: _showAddExpenseDialog,
              ),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.label_outline),
              tooltip: 'Add Category',
              onPressed: _showAddCategoryDialog,
            ),
            TrainingAnchor(
              id: 'pl.addExpense',
              child: FilledButton.icon(
                onPressed: _showAddExpenseDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Expense'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          SizedBox(width: isMobile ? 4 : 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16 : 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TrainingAnchor(
                        id: 'pl.filters',
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'Period:',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            _PeriodChip(
                              label: '7 Days',
                              selected: _daysRange == 7,
                              onTap: () {
                                _daysRange = 7;
                                _loadData();
                              },
                            ),
                            _PeriodChip(
                              label: '14 Days',
                              selected: _daysRange == 14,
                              onTap: () {
                                _daysRange = 14;
                                _loadData();
                              },
                            ),
                            _PeriodChip(
                              label: '30 Days',
                              selected: _daysRange == 30,
                              onTap: () {
                                _daysRange = 30;
                                _loadData();
                              },
                            ),
                            _PeriodChip(
                              label: '90 Days',
                              selected: _daysRange == 90,
                              onTap: () {
                                _daysRange = 90;
                                _loadData();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      TrainingAnchor(
                        id: 'pl.summary',
                        child: isMobile
                            ? GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                      mainAxisExtent: 116,
                                    ),
                                itemCount: summaryCards.length,
                                itemBuilder: (context, index) =>
                                    summaryCards[index],
                              )
                            : Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: summaryCards
                                    .map(
                                      (card) =>
                                          SizedBox(width: 190, child: card),
                                    )
                                    .toList(),
                              ),
                      ),
                      const SizedBox(height: 20),
                      _SectionCard(
                        title: 'Snapshot',
                        icon: Icons.analytics_outlined,
                        child: Wrap(
                          spacing: 24,
                          runSpacing: 12,
                          children: [
                            _LegendDot(
                              color: AppColors.secondary,
                              label: '$salesCount sales in period',
                            ),
                            _LegendDot(
                              color: AppColors.error,
                              label:
                                  'Operating Expenses: ${ShopSettings.currency}${expenses.toStringAsFixed(2)}',
                            ),
                            _LegendDot(
                              color: netPositive
                                  ? AppColors.success
                                  : AppColors.error,
                              label:
                                  'Net Margin: ${margin.toStringAsFixed(1)}%',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_categoryTotals.isNotEmpty)
                        _SectionCard(
                          title: 'Expense Categories',
                          icon: Icons.category_outlined,
                          child: Column(
                            children: _categoryTotals.map((category) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        category['category_name'] as String? ??
                                            'Uncategorized',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${category['expense_count']} entries',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Text(
                                      '${ShopSettings.currency}${((category['total_amount'] as num? ?? 0).toDouble()).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: AppColors.error,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      const SizedBox(height: 20),
                      _SectionCard(
                        title: 'Daily Breakdown',
                        icon: Icons.calendar_today,
                        child: _dailyData.isEmpty
                            ? const Text(
                                'No sales or expense data for this period',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              )
                            : Column(
                                children: _dailyData.map((day) {
                                  final revenue = (day['revenue'] as num? ?? 0)
                                      .toDouble();
                                  final cost = (day['total_cost'] as num? ?? 0)
                                      .toDouble();
                                  final dayExpenses =
                                      (day['total_expenses'] as num? ?? 0)
                                          .toDouble();
                                  final net = (day['net_profit'] as num? ?? 0)
                                      .toDouble();
                                  final positive = net >= 0;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: AppColors.border,
                                          width: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _formatDate(
                                                  day['sale_date'] as String? ??
                                                      '',
                                                ),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${day['sale_count'] ?? 0} sales',
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 18,
                                          runSpacing: 8,
                                          children: [
                                            _MiniMetric(
                                              label: 'Revenue',
                                              value:
                                                  '${ShopSettings.currency}${revenue.toStringAsFixed(2)}',
                                            ),
                                            _MiniMetric(
                                              label: 'Cost',
                                              value:
                                                  '${ShopSettings.currency}${cost.toStringAsFixed(2)}',
                                              color: AppColors.warning,
                                            ),
                                            _MiniMetric(
                                              label: 'Expenses',
                                              value:
                                                  '${ShopSettings.currency}${dayExpenses.toStringAsFixed(2)}',
                                              color: AppColors.error,
                                            ),
                                            _MiniMetric(
                                              label: 'Net',
                                              value:
                                                  '${positive ? '+' : ''}${ShopSettings.currency}${net.toStringAsFixed(2)}',
                                              color: positive
                                                  ? AppColors.success
                                                  : AppColors.error,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                      const SizedBox(height: 20),
                      TrainingAnchor(
                        id: 'pl.expenses',
                        child: _SectionCard(
                          title: 'Recent Expenses',
                          icon: Icons.receipt_long_outlined,
                          child: _recentExpenses.isEmpty
                              ? const Text(
                                  'No expenses recorded yet',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              : Column(
                                  children: _recentExpenses.map((expense) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  expense['title'] as String? ??
                                                      'Expense',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '${expense['category_name'] ?? 'Uncategorized'} - ${_formatDate(expense['incurred_on'] as String? ?? '')}',
                                                  style: const TextStyle(
                                                    color:
                                                        AppColors
                                                            .textSecondary,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '${ShopSettings.currency}${((expense['amount'] as num? ?? 0).toDouble()).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              color: AppColors.error,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surfaceHighlight,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _MiniMetric({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: TextStyle(
              color: color ?? AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryLight, size: 18),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
