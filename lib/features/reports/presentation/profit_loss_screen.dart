import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/sync_controller.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/error_messages.dart';
import '../../app/app_shell.dart';
import '../../training/widgets/training_anchor.dart';
import '../../../widgets/compact_header_actions.dart';
import '../../../widgets/smart_import_preview_dialog.dart';
import '../data/expense_import_service.dart';
import '../data/expense_repository.dart';

class ProfitLossScreen extends ConsumerStatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  ConsumerState<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends ConsumerState<ProfitLossScreen> {
  List<Map<String, dynamic>> _dailyData = [];
  List<Map<String, dynamic>> _recentExpenses = [];
  List<Map<String, dynamic>> _categoryTotals = [];
  List<Map<String, dynamic>> _dailyExpenseReport = [];
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic> _totals = {};
  bool _isLoading = true;
  bool _isImportingExpenses = false;
  int _daysRange = 7;
  String _periodMode = '7';
  DateTime? _customStartDate;
  DateTime? _customEndDate;

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
        startDate: _rangeStartDate,
        endDate: _rangeEndDate,
      );
      _totals = await ExpenseRepository.getProfitLossTotals(
        daysRange: _daysRange,
        startDate: _rangeStartDate,
        endDate: _rangeEndDate,
      );
      _categories = await ExpenseRepository.getCategories();
      _categoryTotals = await ExpenseRepository.getExpenseCategoryTotals(
        daysRange: _daysRange,
        startDate: _rangeStartDate,
        endDate: _rangeEndDate,
      );
      _dailyExpenseReport =
          await ExpenseRepository.getDailyExpenseCategoryReport(
            daysRange: _daysRange,
            startDate: _rangeStartDate,
            endDate: _rangeEndDate,
          );
      _recentExpenses = await ExpenseRepository.getRecentExpenses(
        daysRange: _daysRange,
        limit: 20,
        startDate: _rangeStartDate,
        endDate: _rangeEndDate,
      );
    } catch (e) {
      debugPrint('[P&L] Error: $e');
      _dailyData = [];
      _totals = {};
      _categoryTotals = [];
      _dailyExpenseReport = [];
      _recentExpenses = [];
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  DateTime? get _rangeStartDate {
    final today = _dateOnly(DateTime.now());
    switch (_periodMode) {
      case 'today':
        return today;
      case 'yesterday':
        return today.subtract(const Duration(days: 1));
      case 'custom':
        return _customStartDate;
      default:
        return null;
    }
  }

  DateTime? get _rangeEndDate {
    final today = _dateOnly(DateTime.now());
    switch (_periodMode) {
      case 'today':
        return today;
      case 'yesterday':
        return today.subtract(const Duration(days: 1));
      case 'custom':
        return _customEndDate;
      default:
        return null;
    }
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  void _setPeriod(String mode, int daysRange) {
    setState(() {
      _periodMode = mode;
      _daysRange = daysRange;
    });
    _loadData();
  }

  Future<void> _pickCustomExpenseRange() async {
    final today = _dateOnly(DateTime.now());
    final initialStart =
        _customStartDate ?? today.subtract(const Duration(days: 6));
    final initialEnd = _customEndDate ?? today;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );
    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _periodMode = 'custom';
      _customStartDate = _dateOnly(picked.start);
      _customEndDate = _dateOnly(picked.end);
      _daysRange = picked.duration.inDays + 1;
    });
    _loadData();
  }

  Future<void> _showAddCategoryDialog() async {
    final controller = TextEditingController();
    bool saving = false;
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Add Expense Category'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Category Name',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: Text('Cancel'),
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
                              content: Text(
                                AppErrorMessage.from(
                                  e,
                                  fallback: AppErrorMessage.saveFailed,
                                ),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              child: Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (created == true) {
      await _loadData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense category created'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
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
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Record Expense'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Expense Title',
                      prefixIcon: Icon(Icons.receipt_outlined),
                    ),
                  ),
                  SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategoryId,
                    decoration: InputDecoration(
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
                  SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixIcon: Icon(Icons.payments_outlined),
                      prefixText: '${ShopSettings.currency} ',
                    ),
                  ),
                  SizedBox(height: 12),
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
                      icon: Icon(Icons.calendar_today),
                      label: Text(_formatDateValue(selectedDate)),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
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
              child: Text('Cancel'),
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
                              content: Text(
                                AppErrorMessage.from(
                                  e,
                                  fallback: AppErrorMessage.saveFailed,
                                ),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              child: Text('Save'),
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
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expense added'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _importExpensesFromFile() async {
    if (_isImportingExpenses) {
      return;
    }
    setState(() => _isImportingExpenses = true);

    ExpenseImportResult? result;
    Object? importError;
    try {
      result = await ExpenseImportService.pickAndImportExpenses(
        confirmPlan: (plan) => showSmartImportPreviewDialog(
          context,
          plan: plan,
          title: 'Piki AI Expense Import Check',
          actionLabel: 'Import Expenses',
          minimumRequirements: const [
            'Expenses need title and amount columns.',
          ],
          optionalColumns: const ['date', 'category', 'note'],
          defaultsNote:
              'Blank optional fields are allowed. Missing dates use today, and new categories are created automatically.',
        ),
      );
    } catch (error) {
      importError = error;
    } finally {
      if (mounted) {
        setState(() => _isImportingExpenses = false);
      }
    }

    if (!mounted) {
      return;
    }

    if (importError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.withContext(
              importError,
              prefix: 'Could not import expenses.',
              fallback:
                  'Use an .xlsx or .csv file with title and amount columns. Date, category, and note are optional.',
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (result == null) {
      return;
    }
    final importResult = result;

    await _loadData();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Expense Import Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${importResult.imported} expense${importResult.imported == 1 ? '' : 's'} imported'
              '${importResult.fileName == null ? '' : ' from ${importResult.fileName}'}.',
            ),
            if (importResult.categoriesCreated > 0) ...[
              SizedBox(height: 8),
              Text(
                '${importResult.categoriesCreated} expense categor${importResult.categoriesCreated == 1 ? 'y' : 'ies'} created.',
                style: TextStyle(color: AppColors.success),
              ),
            ],
            if (importResult.skipped > 0) ...[
              SizedBox(height: 8),
              Text(
                '${importResult.skipped} row${importResult.skipped == 1 ? '' : 's'} skipped.',
                style: TextStyle(color: AppColors.warning),
              ),
            ],
            if (importResult.errors.isNotEmpty) ...[
              SizedBox(height: 12),
              Text(
                'Check these rows:',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              ...importResult.errors.map(
                (error) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Done'),
          ),
        ],
      ),
    );
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
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && next != previous && mounted) {
          _loadData();
        }
      },
    );

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
        backgroundColor: Theme.of(context).colorScheme.surface,
        toolbarHeight: 50,
        leading: isMobile
            ? IconButton(
                icon: Icon(Icons.menu),
                onPressed: () =>
                    AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        title: Text(
          'Profit & Loss',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          CompactHeaderIconButton(
            icon: Icons.refresh,
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
          SizedBox(width: isMobile ? 4 : 8),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
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
                            Text(
                              'Period:',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            _PeriodChip(
                              label: 'Today',
                              selected: _periodMode == 'today',
                              onTap: () => _setPeriod('today', 1),
                            ),
                            _PeriodChip(
                              label: 'Yesterday',
                              selected: _periodMode == 'yesterday',
                              onTap: () => _setPeriod('yesterday', 1),
                            ),
                            _PeriodChip(
                              label: '7 Days',
                              selected: _periodMode == '7',
                              onTap: () => _setPeriod('7', 7),
                            ),
                            _PeriodChip(
                              label: '30 Days',
                              selected: _periodMode == '30',
                              onTap: () => _setPeriod('30', 30),
                            ),
                            _PeriodChip(
                              label: '90 Days',
                              selected: _periodMode == '90',
                              onTap: () => _setPeriod('90', 90),
                            ),
                            _PeriodChip(
                              label: _periodMode == 'custom'
                                  ? '${_formatDateValue(_rangeStartDate ?? DateTime.now())} - ${_formatDateValue(_rangeEndDate ?? DateTime.now())}'
                                  : 'Custom Date',
                              selected: _periodMode == 'custom',
                              onTap: _pickCustomExpenseRange,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 14),
                      _ExpenseActionsBar(
                        isMobile: isMobile,
                        isImporting: _isImportingExpenses,
                        onCreateCategory: _showAddCategoryDialog,
                        onAddExpense: _showAddExpenseDialog,
                        onImportExpenses: _importExpensesFromFile,
                      ),
                      SizedBox(height: 24),
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
                      SizedBox(height: 20),
                      _SectionCard(
                        title: 'Snapshot',
                        icon: Icons.analytics_outlined,
                        child: Wrap(
                          spacing: 24,
                          runSpacing: 12,
                          children: [
                            _LegendDot(
                              color: Theme.of(context).colorScheme.secondary,
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
                      SizedBox(height: 20),
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
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${category['expense_count']} entries',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                        fontSize: 12,
                                      ),
                                    ),
                                    SizedBox(width: 16),
                                    Text(
                                      '${ShopSettings.currency}${((category['total_amount'] as num? ?? 0).toDouble()).toStringAsFixed(2)}',
                                      style: TextStyle(
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
                      SizedBox(height: 20),
                      _SectionCard(
                        title: 'Profit & Loss Report',
                        icon: Icons.stacked_line_chart_outlined,
                        child: _dailyData.isEmpty
                            ? Text(
                                'No profit or loss data for this date range',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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
                                  final grossProfit =
                                      (day['gross_profit'] as num? ?? 0)
                                          .toDouble();
                                  final net = (day['net_profit'] as num? ?? 0)
                                      .toDouble();
                                  final grossPositive = grossProfit >= 0;
                                  final positive = net >= 0;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outline,
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
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${day['sale_count'] ?? 0} sales',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 10),
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
                                              label: 'Gross Profit',
                                              value:
                                                  '${grossPositive ? '+' : ''}${ShopSettings.currency}${grossProfit.toStringAsFixed(2)}',
                                              color: grossPositive
                                                  ? AppColors.success
                                                  : AppColors.error,
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
                      SizedBox(height: 20),
                      _SectionCard(
                        title: 'Expenses Report',
                        icon: Icons.request_quote_outlined,
                        child: _dailyExpenseReport.isEmpty
                            ? Text(
                                'No expenses recorded for this date range',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              )
                            : _DailyExpenseReportList(
                                rows: _dailyExpenseReport,
                                formatDate: _formatDate,
                              ),
                      ),
                      SizedBox(height: 20),
                      TrainingAnchor(
                        id: 'pl.expenses',
                        child: _SectionCard(
                          title: 'Expense Records',
                          icon: Icons.receipt_long_outlined,
                          child: _recentExpenses.isEmpty
                              ? Text(
                                  'No expenses recorded yet',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                Text(
                                                  '${expense['category_name'] ?? 'Uncategorized'} - ${_formatDate(expense['incurred_on'] as String? ?? '')}',
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '${ShopSettings.currency}${((expense['amount'] as num? ?? 0).toDouble()).toStringAsFixed(2)}',
                                            style: TextStyle(
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
      color: selected ? AppColors.primary : context.appSurfaceHighlight,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyExpenseReportList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final String Function(String value) formatDate;

  const _DailyExpenseReportList({required this.rows, required this.formatDate});

  @override
  Widget build(BuildContext context) {
    final groupedRows = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final day = row['day_key'] as String? ?? '';
      groupedRows.putIfAbsent(day, () => []).add(row);
    }

    return Column(
      children: groupedRows.entries.map((entry) {
        final dayTotal = entry.value.fold<double>(
          0,
          (sum, row) => sum + ((row['total_amount'] as num?) ?? 0).toDouble(),
        );
        final entryCount = entry.value.fold<int>(
          0,
          (sum, row) => sum + ((row['expense_count'] as num?) ?? 0).toInt(),
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatDate(entry.key),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Text(
                    '$entryCount entries',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    '${ShopSettings.currency}${dayTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: AppColors.error,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              Column(
                children: entry.value.map((row) {
                  final amount = ((row['total_amount'] as num?) ?? 0)
                      .toDouble();
                  final count = ((row['expense_count'] as num?) ?? 0).toInt();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            row['category_name'] as String? ?? 'Uncategorized',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          '$count',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(width: 16),
                        Text(
                          '${ShopSettings.currency}${amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _ExpenseActionsBar extends StatelessWidget {
  final bool isMobile;
  final bool isImporting;
  final VoidCallback onCreateCategory;
  final VoidCallback onAddExpense;
  final VoidCallback onImportExpenses;

  const _ExpenseActionsBar({
    required this.isMobile,
    required this.isImporting,
    required this.onCreateCategory,
    required this.onAddExpense,
    required this.onImportExpenses,
  });

  @override
  Widget build(BuildContext context) {
    final createCategoryButton = OutlinedButton.icon(
      onPressed: onCreateCategory,
      icon: Icon(Icons.label_outline, size: 18),
      label: Text('Create Expense Category'),
    );
    final addExpenseButton = TrainingAnchor(
      id: 'pl.addExpense',
      child: FilledButton.icon(
        onPressed: onAddExpense,
        icon: Icon(Icons.add, size: 18),
        label: Text('Add Expense'),
        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
      ),
    );
    final importExpensesButton = OutlinedButton.icon(
      onPressed: isImporting ? null : onImportExpenses,
      icon: Icon(Icons.upload_file_outlined, size: 18),
      label: Text(isImporting ? 'Importing...' : 'Import Expenses'),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          addExpenseButton,
          SizedBox(height: 10),
          importExpensesButton,
          SizedBox(height: 10),
          createCategoryButton,
        ],
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [addExpenseButton, importExpensesButton, createCategoryButton],
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          SizedBox(height: 6),
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
        SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
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
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: TextStyle(
              color: color ?? Theme.of(context).colorScheme.onSurface,
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryLight, size: 18),
              SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
