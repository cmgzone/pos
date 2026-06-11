import 'package:flutter/material.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../auth/data/user_repository.dart';
import '../../app/app_shell.dart';
import '../../shifts/data/shift_repository.dart';
import '../../training/widgets/training_anchor.dart';
import '../data/kra_report_export_service.dart';
import '../data/report_repository.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportTab extends StatelessWidget {
  final Icon icon;
  final String label;

  const _ReportTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 42,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon.icon, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  int _productDays = 30;
  ReportBranchScope _branchScope = ReportBranchScope.current;

  bool get _isManagerOrAdmin {
    final role = RolePermissions.normalizeRole(SessionService.currentUserRole);
    return role == RolePermissions.admin || role == RolePermissions.manager;
  }

  int get _tabCount => _isManagerOrAdmin ? 7 : 5;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        toolbarHeight: 50,
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () =>
                    AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        title: const Text(
          'Reports',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_isManagerOrAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SegmentedButton<ReportBranchScope>(
                segments: const [
                  ButtonSegment(
                    value: ReportBranchScope.current,
                    icon: Icon(Icons.store_outlined, size: 14),
                    label: Text('Current', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: ReportBranchScope.all,
                    icon: Icon(Icons.business_outlined, size: 14),
                    label: Text('All', style: TextStyle(fontSize: 11)),
                  ),
                ],
                selected: {_branchScope},
                onSelectionChanged: (selection) {
                  setState(() => _branchScope = selection.first);
                },
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: WidgetStateProperty.all(const Size(0, 32)),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: TrainingAnchor(
            id: 'reports.tabs',
            child: TabBar(
              controller: _tabs,
              isScrollable: isMobile || _isManagerOrAdmin,
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              indicatorColor: AppColors.primary,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: [
                const _ReportTab(
                  icon: Icon(Icons.badge_outlined),
                  label: 'Cashier Summary',
                ),
                const _ReportTab(
                  icon: Icon(Icons.bar_chart_rounded),
                  label: 'Top Products',
                ),
                const _ReportTab(
                  icon: Icon(Icons.people_outline),
                  label: 'Top Debtors',
                ),
                const _ReportTab(
                  icon: Icon(Icons.schedule_outlined),
                  label: 'Overdue Aging',
                ),
                const _ReportTab(
                  icon: Icon(Icons.swap_vert_rounded),
                  label: 'Stock Movement',
                ),
                if (_isManagerOrAdmin)
                  const _ReportTab(
                    icon: Icon(Icons.receipt_long_outlined),
                    label: 'Kenya Reports',
                  ),
                if (_isManagerOrAdmin)
                  const _ReportTab(
                    icon: Icon(Icons.compare_arrows_rounded),
                    label: 'Compare Branches',
                  ),
              ],
            ),
          ),
        ),
      ),
      body: TrainingAnchor(
        id: 'reports.body',
        child: TabBarView(
          controller: _tabs,
          children: [
            _DailyCashierSummaryTab(branchScope: _branchScope),
            _TopProductsTab(
              daysRange: _productDays,
              onDaysChanged: (d) => setState(() => _productDays = d),
              branchScope: _branchScope,
            ),
            const _TopDebtorsTab(),
            const _OverdueAgingTab(),
            _StockMovementTab(branchScope: _branchScope),
            if (_isManagerOrAdmin) _KenyaReportsTab(branchScope: _branchScope),
            if (_isManagerOrAdmin) const _BranchComparisonTab(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — Top / Worst Selling Products
// ─────────────────────────────────────────────────────────────────────────────

class _DailyCashierSummaryTab extends StatefulWidget {
  final ReportBranchScope branchScope;
  const _DailyCashierSummaryTab({this.branchScope = ReportBranchScope.current});

  @override
  State<_DailyCashierSummaryTab> createState() =>
      _DailyCashierSummaryTabState();
}

class _DailyCashierSummaryTabState extends State<_DailyCashierSummaryTab> {
  static const _allEmployeesId = '__all_employees__';

  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _closedShiftSummary = {};
  List<Map<String, dynamic>> _cashiers = [];
  List<Map<String, dynamic>> _closedShifts = [];
  List<Map<String, dynamic>> _employeeOptions = [];
  String _selectedCashierId = _allEmployeesId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_DailyCashierSummaryTab old) {
    super.didUpdateWidget(old);
    if (old.branchScope != widget.branchScope) _load();
  }

  String get _dateKey =>
      '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

  bool get _isFilteredToEmployee => _selectedCashierId != _allEmployeesId;

  int _roleRank(String? role) {
    switch ((role ?? '').toUpperCase()) {
      case 'ADMIN':
        return 0;
      case 'MANAGER':
        return 1;
      default:
        return 2;
    }
  }

  List<Map<String, dynamic>> _buildEmployeeOptions(
    List<Map<String, dynamic>> staff,
    List<Map<String, dynamic>> activeCashiers,
  ) {
    final byId = <String, Map<String, dynamic>>{};

    for (final user in staff) {
      final id = (user['id'] as String? ?? '').trim();
      if (id.isEmpty) {
        continue;
      }
      final rawName = (user['name'] as String?)?.trim();
      final rawEmail = (user['email'] as String?)?.trim();
      byId[id] = {
        'cashier_id': id,
        'cashier_name': rawName?.isNotEmpty == true
            ? rawName
            : rawEmail?.isNotEmpty == true
            ? rawEmail
            : id,
        'cashier_role': user['role'] as String? ?? 'CASHIER',
      };
    }

    for (final cashier in activeCashiers) {
      final id = (cashier['cashier_id'] as String? ?? '').trim();
      if (id.isEmpty) {
        continue;
      }
      byId[id] ??= {
        'cashier_id': id,
        'cashier_name': cashier['cashier_name'] as String? ?? id,
        'cashier_role': cashier['cashier_role'] as String? ?? 'CASHIER',
      };
    }

    final options = byId.values.toList();
    options.sort((a, b) {
      final roleCompare = _roleRank(
        a['cashier_role'] as String?,
      ).compareTo(_roleRank(b['cashier_role'] as String?));
      if (roleCompare != 0) {
        return roleCompare;
      }
      final aName = (a['cashier_name'] as String? ?? '').toLowerCase();
      final bName = (b['cashier_name'] as String? ?? '').toLowerCase();
      return aName.compareTo(bName);
    });
    return options;
  }

  String get _selectedCashierName {
    if (!_isFilteredToEmployee) {
      return 'All employees';
    }
    for (final employee in _employeeOptions) {
      if ((employee['cashier_id'] as String? ?? '') == _selectedCashierId) {
        return employee['cashier_name'] as String? ?? 'Selected employee';
      }
    }
    return 'Selected employee';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ReportRepository.getDailyCashierSummary(
        date: _dateKey,
        branchScope: widget.branchScope,
      ),
      UserRepository.getAll(),
    ]);
    final activeCashiers = List<Map<String, dynamic>>.from(results[0] as List);
    final staff = List<Map<String, dynamic>>.from(results[1] as List);
    final employeeOptions = _buildEmployeeOptions(staff, activeCashiers);
    final nextSelectedCashierId =
        _selectedCashierId == _allEmployeesId ||
            employeeOptions.any(
              (employee) =>
                  (employee['cashier_id'] as String? ?? '') ==
                  _selectedCashierId,
            )
        ? _selectedCashierId
        : _allEmployeesId;
    final summary = await ReportRepository.getDailySummary(
      date: _dateKey,
      cashierId: nextSelectedCashierId == _allEmployeesId
          ? null
          : nextSelectedCashierId,
      branchScope: widget.branchScope,
    );
    final closedShiftSummary = await ShiftRepository.getClosedShiftSummary(
      date: _dateKey,
      userId: nextSelectedCashierId == _allEmployeesId
          ? null
          : nextSelectedCashierId,
      allBranches: widget.branchScope == ReportBranchScope.all,
    );
    final closedShifts = await ShiftRepository.getClosedShifts(
      date: _dateKey,
      userId: nextSelectedCashierId == _allEmployeesId
          ? null
          : nextSelectedCashierId,
      limit: 20,
      allBranches: widget.branchScope == ReportBranchScope.all,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _summary = summary;
      _closedShiftSummary = closedShiftSummary;
      _closedShifts = closedShifts;
      _employeeOptions = employeeOptions;
      _selectedCashierId = nextSelectedCashierId;
      _cashiers = nextSelectedCashierId == _allEmployeesId
          ? activeCashiers
          : activeCashiers
                .where(
                  (cashier) =>
                      (cashier['cashier_id'] as String? ?? '') ==
                      nextSelectedCashierId,
                )
                .toList();
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _selectedDate = picked);
    await _load();
  }

  String _displayDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  String _displayMoney(dynamic value) {
    final amount = (value as num? ?? 0).toDouble();
    return '${ShopSettings.currency}${amount.toStringAsFixed(2)}';
  }

  String _displayTime(String? raw) {
    final date = DateTime.tryParse(raw ?? '');
    if (date == null) {
      return '-';
    }
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Color _differenceColor(num? difference) {
    final value = (difference ?? 0).toDouble();
    if (value < -0.009) {
      return AppColors.error;
    }
    if (value > 0.009) {
      return AppColors.warning;
    }
    return AppColors.success;
  }

  String _differenceLabel(num? difference) {
    final value = (difference ?? 0).toDouble();
    if (value < -0.009) {
      return 'Short';
    }
    if (value > 0.009) {
      return 'Over';
    }
    return 'Balanced';
  }

  String _roleLabel(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'ADMIN':
        return 'Admin';
      case 'MANAGER':
        return 'Manager';
      default:
        return 'Cashier';
    }
  }

  bool _isOnline(String? lastSeenAt) {
    if (lastSeenAt == null) {
      return false;
    }
    final lastSeen = DateTime.tryParse(lastSeenAt);
    if (lastSeen == null) {
      return false;
    }
    // Consider online if seen in the last 5 minutes
    return DateTime.now().difference(lastSeen).inMinutes < 5;
  }

  @override
  Widget build(BuildContext context) {
    final topProducts = List<Map<String, dynamic>>.from(
      _summary['top_products'] as List? ?? const [],
    );
    final topServices = List<Map<String, dynamic>>.from(
      _summary['top_services'] as List? ?? const [],
    );
    final showEmptyState =
        !_isFilteredToEmployee && _cashiers.isEmpty && _closedShifts.isEmpty;

    return Column(
      children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Chip(
                label: _displayDate(_selectedDate),
                selected: true,
                onTap: _pickDate,
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Choose Date'),
              ),
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedCashierId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Employee',
                    isDense: true,
                    prefixIcon: Icon(Icons.person_search_outlined),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: _allEmployeesId,
                      child: Text('All employees'),
                    ),
                    ..._employeeOptions.map((employee) {
                      final name =
                          employee['cashier_name'] as String? ?? 'Employee';
                      final role = _roleLabel(
                        employee['cashier_role'] as String?,
                      );
                      return DropdownMenuItem(
                        value: employee['cashier_id'] as String? ?? '',
                        child: Text('$name - $role'),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    if (value == null || value == _selectedCashierId) {
                      return;
                    }
                    setState(() => _selectedCashierId = value);
                    _load();
                  },
                ),
              ),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : showEmptyState
              ? _EmptyState(
                  icon: Icons.badge_outlined,
                  message: 'No employee activity for this date',
                  subtitle: 'Try a different day or complete a sale first.',
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _SummaryMetricCard(
                            label: 'Revenue',
                            value: _displayMoney(_summary['total_revenue']),
                            compactValue: NumberUtils.formatCompact(
                              _summary['total_revenue'] as num?,
                              isCurrency: true,
                            ),
                            color: AppColors.success,
                            icon: Icons.attach_money,
                          ),
                          _SummaryMetricCard(
                            label: 'Sales',
                            value:
                                '${(_summary['total_sales'] as num? ?? 0).toInt()}',
                            compactValue: NumberUtils.formatCompact(
                              _summary['total_sales'] as num?,
                            ),
                            color: AppColors.primary,
                            icon: Icons.receipt_long_outlined,
                          ),
                          _SummaryMetricCard(
                            label: 'Gross Profit',
                            value: _displayMoney(_summary['gross_profit']),
                            compactValue: NumberUtils.formatCompact(
                              _summary['gross_profit'] as num?,
                              isCurrency: true,
                            ),
                            color: AppColors.primaryLight,
                            icon: Icons.trending_up_rounded,
                          ),
                          _SummaryMetricCard(
                            label: 'Product Sales',
                            value: _displayMoney(_summary['product_revenue']),
                            color: AppColors.primary,
                            icon: Icons.inventory_2_outlined,
                            subtitle:
                                '${(_summary['product_sales'] as num? ?? 0).toInt()} sales',
                          ),
                          _SummaryMetricCard(
                            label: 'Service Sales',
                            value: _displayMoney(_summary['service_revenue']),
                            color: AppColors.secondary,
                            icon: Icons.design_services_rounded,
                            subtitle:
                                '${(_summary['service_sales'] as num? ?? 0).toInt()} sales',
                          ),
                          _SummaryMetricCard(
                            label: _isFilteredToEmployee
                                ? 'Employee'
                                : 'Employees',
                            value: '${_cashiers.length}',
                            color: AppColors.warning,
                            icon: Icons.people_outline,
                          ),
                          _SummaryMetricCard(
                            label: 'Closed Shifts',
                            value:
                                '${(_closedShiftSummary['closed_shift_count'] as num? ?? 0).toInt()}',
                            color: AppColors.primary,
                            icon: Icons.lock_clock_outlined,
                          ),
                          _SummaryMetricCard(
                            label: 'Counted Cash',
                            value: _displayMoney(
                              _closedShiftSummary['counted_cash_total'],
                            ),
                            color: AppColors.success,
                            icon: Icons.point_of_sale_outlined,
                          ),
                          _SummaryMetricCard(
                            label: 'Over / Short',
                            value: _displayMoney(
                              _closedShiftSummary['net_difference'],
                            ),
                            color: _differenceColor(
                              _closedShiftSummary['net_difference'] as num?,
                            ),
                            icon: Icons.balance_outlined,
                          ),
                        ],
                      ),
                      if (topProducts.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          _isFilteredToEmployee
                              ? 'Top products sold by $_selectedCashierName'
                              : 'Top products for ${_displayDate(_selectedDate)}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: topProducts.map((product) {
                            final qty = (product['qty_sold'] as num? ?? 0)
                                .toDouble();
                            final unit =
                                product['sale_unit'] as String? ?? 'pcs';
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product['name'] as String? ?? 'Product',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${qty % 1 == 0 ? qty.toInt() : qty.toStringAsFixed(2)} $unit sold',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (topServices.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          _isFilteredToEmployee
                              ? 'Top services sold by $_selectedCashierName'
                              : 'Top services for ${_displayDate(_selectedDate)}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: topServices.map((service) {
                            final qty = (service['qty_sold'] as num? ?? 0)
                                .toDouble();
                            final revenue = (service['revenue'] as num? ?? 0)
                                .toDouble();
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    service['name'] as String? ?? 'Service',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${qty % 1 == 0 ? qty.toInt() : qty.toStringAsFixed(2)} sold - ${_displayMoney(revenue)}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        _isFilteredToEmployee
                            ? 'Shift reconciliation for $_selectedCashierName'
                            : 'Closed shift reconciliation',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      if (_closedShifts.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            _isFilteredToEmployee
                                ? 'No closed shifts were recorded for $_selectedCashierName on ${_displayDate(_selectedDate)}.'
                                : 'No closed shifts were recorded on ${_displayDate(_selectedDate)}.',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      else
                        ..._closedShifts.map((shift) {
                          final difference =
                              (shift['difference'] as num?)?.toDouble() ?? 0;
                          final tone = _differenceColor(difference);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: tone.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        difference.abs() < 0.009
                                            ? Icons.check_circle_outline
                                            : difference > 0
                                            ? Icons.arrow_upward_rounded
                                            : Icons.arrow_downward_rounded,
                                        color: tone,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            shift['cashier_name'] as String? ??
                                                'Cashier',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Closed ${_displayTime(shift['closed_at'] as String?)} • Expected ${_displayMoney(shift['expected_cash'])}',
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _displayMoney(
                                            shift['closing_cash_counted'],
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          '${_differenceLabel(difference)} ${_displayMoney(difference.abs())}',
                                          style: TextStyle(
                                            color: tone,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _CashierStatTile(
                                        label: 'Cash Sales',
                                        value: _displayMoney(
                                          shift['cash_sales_total'],
                                        ),
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _CashierStatTile(
                                        label: 'Cash In',
                                        value: _displayMoney(
                                          shift['cash_in_total'],
                                        ),
                                        color: AppColors.success,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _CashierStatTile(
                                        label: 'Cash Out',
                                        value: _displayMoney(
                                          shift['cash_out_total'],
                                        ),
                                        color: AppColors.warning,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 24),
                      Text(
                        _isFilteredToEmployee
                            ? 'Sales for $_selectedCashierName'
                            : 'Employee breakdown',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      if (_cashiers.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            'No sales were recorded for $_selectedCashierName on ${_displayDate(_selectedDate)}.',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      else
                        ..._cashiers.map((cashier) {
                          final refunds =
                              (cashier['refunds_issued'] as num? ?? 0)
                                  .toDouble();
                          final refundCount =
                              (cashier['refund_count'] as num? ?? 0).toInt();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: Text(
                                          ((cashier['cashier_name']
                                                      as String?) ??
                                                  '?')
                                              .substring(0, 1)
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  cashier['cashier_name']
                                                          as String? ??
                                                      'Unknown Cashier',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 15,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (_isOnline(
                                                cashier['last_seen_at']
                                                    as String?,
                                              )) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration:
                                                      const BoxDecoration(
                                                        color:
                                                            AppColors.success,
                                                        shape: BoxShape.circle,
                                                      ),
                                                ),
                                                const SizedBox(width: 4),
                                                const Text(
                                                  'Online',
                                                  style: TextStyle(
                                                    color: AppColors.success,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _roleLabel(
                                              cashier['cashier_role']
                                                  as String?,
                                            ),
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _displayMoney(
                                            cashier['total_revenue'],
                                          ),
                                          style: const TextStyle(
                                            color: AppColors.success,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          '${(cashier['total_sales'] as num? ?? 0).toInt()} sales',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _CashierStatTile(
                                        label: 'Cash',
                                        value: _displayMoney(
                                          cashier['cash_revenue'],
                                        ),
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _CashierStatTile(
                                        label: 'Kopesha',
                                        value: _displayMoney(
                                          cashier['kopesha_revenue'],
                                        ),
                                        color: AppColors.warning,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _CashierStatTile(
                                        label: 'Profit',
                                        value: _displayMoney(
                                          cashier['gross_profit'],
                                        ),
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _CashierStatTile(
                                        label: 'Products',
                                        value: _displayMoney(
                                          cashier['product_revenue'],
                                        ),
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _CashierStatTile(
                                        label: 'Services',
                                        value: _displayMoney(
                                          cashier['service_revenue'],
                                        ),
                                        color: AppColors.secondary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _CashierStatTile(
                                        label: 'Service Sales',
                                        value:
                                            '${(cashier['service_sales'] as num? ?? 0).toInt()}',
                                        color: AppColors.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 16,
                                  runSpacing: 8,
                                  children: [
                                    Text(
                                      'Shift: ${_displayTime(cashier['first_sale_at'] as String?)} - ${_displayTime(cashier['last_sale_at'] as String?)}',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (refundCount > 0 || refunds > 0)
                                      Text(
                                        'Refunds: $refundCount (${_displayMoney(refunds)})',
                                        style: const TextStyle(
                                          color: AppColors.error,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _TopProductsTab extends StatefulWidget {
  final int daysRange;
  final ValueChanged<int> onDaysChanged;
  final ReportBranchScope branchScope;

  const _TopProductsTab({
    required this.daysRange,
    required this.onDaysChanged,
    this.branchScope = ReportBranchScope.current,
  });

  @override
  State<_TopProductsTab> createState() => _TopProductsTabState();
}

class _TopProductsTabState extends State<_TopProductsTab> {
  bool _showWorst = false;
  List<Map<String, dynamic>> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_TopProductsTab old) {
    super.didUpdateWidget(old);
    if (old.daysRange != widget.daysRange ||
        old.branchScope != widget.branchScope) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _products = await ReportRepository.getTopProducts(
      daysRange: widget.daysRange,
      ascending: _showWorst,
      branchScope: widget.branchScope,
    );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Controls
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              // Period chips
              ...[7, 14, 30, 90].map(
                (d) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Chip(
                    label: '${d}d',
                    selected: widget.daysRange == d,
                    onTap: () {
                      widget.onDaysChanged(d);
                      _load();
                    },
                  ),
                ),
              ),
              const Spacer(),
              // Toggle best/worst
              _Chip(
                label: _showWorst ? 'Worst Sellers' : 'Best Sellers',
                selected: true,
                color: _showWorst ? AppColors.error : AppColors.success,
                onTap: () {
                  setState(() => _showWorst = !_showWorst);
                  _load();
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _products.isEmpty
              ? _EmptyState(
                  icon: Icons.bar_chart_rounded,
                  message: 'No sales data for this period',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _products.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final p = _products[index];
                    final revenue = (p['total_revenue'] as num? ?? 0)
                        .toDouble();
                    final profit = (p['total_profit'] as num? ?? 0).toDouble();
                    final qtySold = (p['total_qty_sold'] as num? ?? 0)
                        .toDouble();
                    final txns = (p['transaction_count'] as num? ?? 0).toInt();
                    final rank = index + 1;

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          // Rank badge
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: rank <= 3
                                  ? AppColors.primary.withValues(alpha: 0.15)
                                  : AppColors.surfaceHighlight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                '#$rank',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: rank <= 3
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p['name'] as String? ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${qtySold % 1 == 0 ? qtySold.toInt() : qtySold.toStringAsFixed(2)} ${p['sale_unit'] ?? 'pcs'} sold · $txns transactions',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${ShopSettings.currency}${revenue.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryLight,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                'Profit: ${ShopSettings.currency}${profit.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: profit >= 0
                                      ? AppColors.success
                                      : AppColors.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — Top Debtors
// ─────────────────────────────────────────────────────────────────────────────

class _TopDebtorsTab extends StatefulWidget {
  const _TopDebtorsTab();

  @override
  State<_TopDebtorsTab> createState() => _TopDebtorsTabState();
}

class _TopDebtorsTabState extends State<_TopDebtorsTab> {
  List<Map<String, dynamic>> _debtors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _debtors = await ReportRepository.getTopDebtors();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_debtors.isEmpty) {
      return _EmptyState(
        icon: Icons.people_outline,
        message: 'No outstanding Kopesha balances',
      );
    }

    final totalOutstanding = _debtors.fold<double>(
      0,
      (s, d) => s + ((d['balance'] as num? ?? 0).toDouble()),
    );

    return Column(
      children: [
        // Total banner
        Container(
          color: AppColors.warning.withValues(alpha: 0.1),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: AppColors.warning,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total Outstanding',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${ShopSettings.currency}${totalOutstanding.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${_debtors.length} customers',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: _debtors.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final d = _debtors[index];
              final balance = (d['balance'] as num? ?? 0).toDouble();
              final openSales = (d['open_sales'] as num? ?? 0).toInt();
              final share = totalOutstanding > 0
                  ? (balance / totalOutstanding)
                  : 0.0;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              (d['name'] as String? ?? '?')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.warning,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d['name'] as String? ?? 'Unknown',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                              if ((d['phone'] as String?)?.isNotEmpty == true)
                                Text(
                                  d['phone'] as String,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${ShopSettings.currency}${balance.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppColors.warning,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '$openSales open ${openSales == 1 ? 'sale' : 'sales'}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Share bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: share.clamp(0.0, 1.0),
                        backgroundColor: AppColors.warning.withValues(
                          alpha: 0.1,
                        ),
                        valueColor: const AlwaysStoppedAnimation(
                          AppColors.warning,
                        ),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${(share * 100).toStringAsFixed(1)}% of total',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 3 — Overdue Aging
// ─────────────────────────────────────────────────────────────────────────────

class _OverdueAgingTab extends StatefulWidget {
  const _OverdueAgingTab();

  @override
  State<_OverdueAgingTab> createState() => _OverdueAgingTabState();
}

class _OverdueAgingTabState extends State<_OverdueAgingTab> {
  List<Map<String, dynamic>> _sales = [];
  Map<String, dynamic> _summary = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      ReportRepository.getOverdueAging(),
      ReportRepository.getOverdueAgingSummary(),
    ]);
    if (mounted) {
      setState(() {
        _sales = results[0] as List<Map<String, dynamic>>;
        _summary = results[1] as Map<String, dynamic>;
        _loading = false;
      });
    }
  }

  Color _bucketColor(String bucket) => switch (bucket) {
    '1_7' => AppColors.warning,
    '8_30' => const Color(0xFFFF6B35),
    '31_60' => AppColors.error,
    'over_60' => const Color(0xFF8B0000),
    _ => AppColors.success,
  };

  String _bucketLabel(String bucket) => switch (bucket) {
    '1_7' => '1–7 days overdue',
    '8_30' => '8–30 days overdue',
    '31_60' => '31–60 days overdue',
    'over_60' => '60+ days overdue',
    _ => 'Not yet due',
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final total = (_summary['total_outstanding'] as num? ?? 0).toDouble();
    final totalCount = (_summary['total_count'] as num? ?? 0).toInt();

    if (totalCount == 0) {
      return _EmptyState(
        icon: Icons.check_circle_outline,
        message: 'No outstanding Kopesha balances 🎉',
        subtitle: "All credit sales are settled.",
      );
    }

    // Build bucket summaries
    final buckets = [
      _AgingBucket(
        label: 'Not Yet Due',
        amount: (_summary['current_amount'] as num? ?? 0).toDouble(),
        count: (_summary['current_count'] as num? ?? 0).toInt(),
        color: AppColors.success,
        bucket: 'current',
      ),
      _AgingBucket(
        label: '1–7 Days',
        amount: (_summary['d1_7_amount'] as num? ?? 0).toDouble(),
        count: (_summary['d1_7_count'] as num? ?? 0).toInt(),
        color: AppColors.warning,
        bucket: '1_7',
      ),
      _AgingBucket(
        label: '8–30 Days',
        amount: (_summary['d8_30_amount'] as num? ?? 0).toDouble(),
        count: (_summary['d8_30_count'] as num? ?? 0).toInt(),
        color: const Color(0xFFFF6B35),
        bucket: '8_30',
      ),
      _AgingBucket(
        label: '31–60 Days',
        amount: (_summary['d31_60_amount'] as num? ?? 0).toDouble(),
        count: (_summary['d31_60_count'] as num? ?? 0).toInt(),
        color: AppColors.error,
        bucket: '31_60',
      ),
      _AgingBucket(
        label: '60+ Days',
        amount: (_summary['over60_amount'] as num? ?? 0).toDouble(),
        count: (_summary['over60_count'] as num? ?? 0).toInt(),
        color: const Color(0xFF8B0000),
        bucket: 'over_60',
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header total
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Outstanding Kopesha',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$totalCount open sales',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _load,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Bucket cards
              ...buckets
                  .where((b) => b.count > 0)
                  .map(
                    (b) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: b.color.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: b.color.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: b.color,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  b.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: b.color,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${b.count} ${b.count == 1 ? 'sale' : 'sales'}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  '${ShopSettings.currency}${b.amount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: b.color,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            if (total > 0) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: (b.amount / total).clamp(0.0, 1.0),
                                  backgroundColor: b.color.withValues(
                                    alpha: 0.1,
                                  ),
                                  valueColor: AlwaysStoppedAnimation(b.color),
                                  minHeight: 5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

              const SizedBox(height: 8),
              Text(
                'Individual Sales',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              // Individual sales list
              ..._sales.map((s) {
                final bucket = s['age_bucket'] as String? ?? 'current';
                final bColor = _bucketColor(bucket);
                final balance = (s['balance_due'] as num? ?? 0).toDouble();
                final daysOverdue = (s['days_overdue'] as num? ?? 0).toInt();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 40,
                          decoration: BoxDecoration(
                            color: bColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s['customer_name'] as String? ??
                                    'Unknown Customer',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                bucket == 'current'
                                    ? 'Due: ${s['due_date'] ?? 'N/A'}'
                                    : _bucketLabel(bucket),
                                style: TextStyle(
                                  color: bColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${ShopSettings.currency}${balance.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: bColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (daysOverdue > 0)
                              Text(
                                '$daysOverdue days late',
                                style: TextStyle(color: bColor, fontSize: 11),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 4 — Stock Movement
// ─────────────────────────────────────────────────────────────────────────────

class _StockMovementTab extends StatefulWidget {
  final ReportBranchScope branchScope;
  const _StockMovementTab({this.branchScope = ReportBranchScope.current});

  @override
  State<_StockMovementTab> createState() => _StockMovementTabState();
}

class _StockMovementTabState extends State<_StockMovementTab> {
  int _days = 30;
  List<Map<String, dynamic>> _data = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_StockMovementTab old) {
    super.didUpdateWidget(old);
    if (old.branchScope != widget.branchScope) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _data = await ReportRepository.getStockMovement(
      daysRange: _days,
      branchScope: widget.branchScope,
    );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Period picker
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              ...[7, 14, 30, 90].map(
                (d) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Chip(
                    label: '${d}d',
                    selected: _days == d,
                    onTap: () {
                      setState(() => _days = d);
                      _load();
                    },
                  ),
                ),
              ),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
            ],
          ),
        ),
        const Divider(height: 1),
        // Legend
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              _LegendDot(color: AppColors.success, label: 'Stock In'),
              const SizedBox(width: 16),
              _LegendDot(color: AppColors.error, label: 'Stock Out (sold)'),
              const SizedBox(width: 16),
              _LegendDot(color: AppColors.warning, label: 'Low / Out of stock'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _data.isEmpty
              ? _EmptyState(
                  icon: Icons.swap_vert_rounded,
                  message: 'No stock movement in this period',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  itemCount: _data.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _data[index];
                    final qtyIn = (item['qty_in'] as num? ?? 0).toDouble();
                    final qtyOut = (item['qty_out'] as num? ?? 0).toDouble();
                    final current = (item['current_stock'] as num? ?? 0)
                        .toDouble();
                    final status = item['stock_status'] as String? ?? 'ok';
                    final statusColor = status == 'out'
                        ? AppColors.error
                        : status == 'low'
                        ? AppColors.warning
                        : AppColors.success;
                    final unit = item['stock_unit'] as String? ?? 'pcs';

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item['name'] as String? ?? '',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status == 'out'
                                      ? 'Out of stock'
                                      : status == 'low'
                                      ? 'Low stock'
                                      : '$current $unit left',
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _MovementTile(
                                label: 'In',
                                value: qtyIn,
                                unit: unit,
                                color: AppColors.success,
                                icon: Icons.add_circle_outline,
                              ),
                              const SizedBox(width: 16),
                              _MovementTile(
                                label: 'Out',
                                value: qtyOut,
                                unit: unit,
                                color: AppColors.error,
                                icon: Icons.remove_circle_outline,
                              ),
                              const SizedBox(width: 16),
                              _MovementTile(
                                label: 'Net',
                                value: qtyIn - qtyOut,
                                unit: unit,
                                color: (qtyIn - qtyOut) >= 0
                                    ? AppColors.primaryLight
                                    : AppColors.error,
                                icon: Icons.swap_vert_rounded,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _AgingBucket {
  final String label;
  final double amount;
  final int count;
  final Color color;
  final String bucket;

  const _AgingBucket({
    required this.label,
    required this.amount,
    required this.count,
    required this.color,
    required this.bucket,
  });
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c : AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? c : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _KenyaReportsTab extends StatefulWidget {
  final ReportBranchScope branchScope;

  const _KenyaReportsTab({this.branchScope = ReportBranchScope.current});

  @override
  State<_KenyaReportsTab> createState() => _KenyaReportsTabState();
}

class _KenyaReportsTabState extends State<_KenyaReportsTab> {
  bool _loading = true;
  Map<String, dynamic> _zReport = {};
  Map<String, dynamic> _vat = {};
  Map<String, dynamic> _etims = {};
  List<Map<String, dynamic>> _exportRows = [];
  bool _savingPdf = false;
  bool _savingCsv = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_KenyaReportsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchScope != widget.branchScope) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final zReport = await ReportRepository.getZReport(
      branchScope: widget.branchScope,
    );
    final vat = await ReportRepository.getKenyaVatSummary(
      branchScope: widget.branchScope,
    );
    final etims = await ReportRepository.getEtimsSummary(
      branchScope: widget.branchScope,
    );
    final exportRows = await ReportRepository.getAccountantExportRows(
      branchScope: widget.branchScope,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _zReport = zReport;
      _vat = vat;
      _etims = etims;
      _exportRows = exportRows;
      _loading = false;
    });
  }

  Future<void> _savePdf() async {
    if (_savingPdf) {
      return;
    }
    setState(() => _savingPdf = true);
    try {
      final path = await KraReportExportService.savePdf(
        zReport: _zReport,
        vat: _vat,
        etims: _etims,
        rows: _exportRows,
      );
      _showExportMessage(path, 'PDF');
    } catch (e) {
      _showExportError(e);
    } finally {
      if (mounted) {
        setState(() => _savingPdf = false);
      }
    }
  }

  Future<void> _saveCsv() async {
    if (_savingCsv) {
      return;
    }
    setState(() => _savingCsv = true);
    try {
      final path = await KraReportExportService.saveCsv(
        zReport: _zReport,
        vat: _vat,
        etims: _etims,
        rows: _exportRows,
      );
      _showExportMessage(path, 'CSV');
    } catch (e) {
      _showExportError(e);
    } finally {
      if (mounted) {
        setState(() => _savingCsv = false);
      }
    }
  }

  void _showExportMessage(String? path, String type) {
    if (!mounted) {
      return;
    }
    if (path == null || path.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$type export cancelled')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$type KRA report saved'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  void _showExportError(Object error) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error.toString().replaceFirst('Exception: ', '').trim().isEmpty
              ? 'Could not save KRA report'
              : error.toString().replaceFirst('Exception: ', ''),
        ),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Kenya Launch Reports',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Z-report, VAT-ready summary, KRA eTIMS status, and accountant export counts.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _savingPdf ? null : _savePdf,
                icon: _savingPdf
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(_savingPdf ? 'Saving PDF...' : 'Download PDF'),
              ),
              OutlinedButton.icon(
                onPressed: _savingCsv ? null : _saveCsv,
                icon: _savingCsv
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.table_chart_outlined, size: 18),
                label: Text(_savingCsv ? 'Saving CSV...' : 'Download CSV'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _SummaryMetricCard(
                label: 'Today Sales',
                value: _money(_zReport['total_sales']),
                color: AppColors.success,
                icon: Icons.point_of_sale_outlined,
                subtitle: '${_zReport['sale_count'] ?? 0} receipts',
              ),
              _SummaryMetricCard(
                label: 'Today Tax',
                value: _money(_zReport['total_tax']),
                color: AppColors.primaryLight,
                icon: Icons.receipt_long_outlined,
              ),
              _SummaryMetricCard(
                label: 'Output VAT',
                value: _money(_vat['output_vat']),
                color: AppColors.warning,
                icon: Icons.account_balance_outlined,
                subtitle: '${_vat['receipt_count'] ?? 0} receipts this period',
              ),
              _SummaryMetricCard(
                label: 'eTIMS Submitted',
                value: '${_etims['submitted_count'] ?? 0}',
                color: AppColors.success,
                icon: Icons.fact_check_outlined,
                subtitle:
                    '${_etims['pending_count'] ?? 0} pending, ${_etims['failed_count'] ?? 0} failed',
              ),
              _SummaryMetricCard(
                label: 'Export Rows',
                value: '${_exportRows.length}',
                color: AppColors.secondary,
                icon: Icons.file_download_outlined,
                subtitle: 'CSV/PDF-ready records',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _money(Object? value) {
    final amount = (value as num? ?? 0).toDouble();
    return '${ShopSettings.currency}${NumberUtils.formatCompact(amount)}';
  }
}

class _SummaryMetricCard extends StatefulWidget {
  final String label;
  final String value;
  final String? compactValue;
  final Color color;
  final IconData icon;
  final String? subtitle;

  const _SummaryMetricCard({
    required this.label,
    required this.value,
    this.compactValue,
    required this.color,
    required this.icon,
    this.subtitle,
  });

  @override
  State<_SummaryMetricCard> createState() => _SummaryMetricCardState();
}

class _SummaryMetricCardState extends State<_SummaryMetricCard> {
  bool _showExact = false;

  @override
  Widget build(BuildContext context) {
    final displayValue = (_showExact || widget.compactValue == null)
        ? widget.value
        : widget.compactValue!;
    return GestureDetector(
      onTap: widget.compactValue != null
          ? () {
              setState(() {
                _showExact = !_showExact;
              });
            }
          : null,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, color: widget.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      displayValue,
                      style: TextStyle(
                        color: widget.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CashierStatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _CashierStatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
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

class _MovementTile extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;
  final IconData icon;

  const _MovementTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final display = value % 1 == 0
        ? value.toInt().toString()
        : value.toStringAsFixed(2);

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    '$display $unit',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? subtitle;

  const _EmptyState({required this.icon, required this.message, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: AppColors.textSecondary.withValues(alpha: 0.35),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 6 — Compare Branches (Manager / Admin only)
// ─────────────────────────────────────────────────────────────────────────────

class _BranchComparisonTab extends StatefulWidget {
  const _BranchComparisonTab();

  @override
  State<_BranchComparisonTab> createState() => _BranchComparisonTabState();
}

class _BranchComparisonTabState extends State<_BranchComparisonTab> {
  int _days = 30;
  List<Map<String, dynamic>> _branches = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _branches = await ReportRepository.getBranchComparison(daysRange: _days);
    if (mounted) setState(() => _loading = false);
  }

  String _money(dynamic v) {
    final val = (v as num? ?? 0).toDouble();
    return '${ShopSettings.currency}${val.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Period selector
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              ...[7, 14, 30, 90].map(
                (d) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Chip(
                    label: '${d}d',
                    selected: _days == d,
                    onTap: () {
                      setState(() => _days = d);
                      _load();
                    },
                  ),
                ),
              ),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
            ],
          ),
        ),
        const Divider(height: 1),
        // Content
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _branches.isEmpty
              ? const _EmptyState(
                  icon: Icons.compare_arrows_rounded,
                  message: 'No branches found',
                  subtitle:
                      'Create branches in Settings to compare performance.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _branches.length,
                  separatorBuilder: (context, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final b = _branches[index];
                    final name = b['branch_name'] as String? ?? 'Branch';
                    final revenue = (b['revenue'] as num? ?? 0).toDouble();
                    final grossProfit = (b['gross_profit'] as num? ?? 0)
                        .toDouble();
                    final netProfit = (b['net_profit'] as num? ?? 0).toDouble();
                    final expenses = (b['total_expenses'] as num? ?? 0)
                        .toDouble();
                    final productRev = (b['product_revenue'] as num? ?? 0)
                        .toDouble();
                    final serviceRev = (b['service_revenue'] as num? ?? 0)
                        .toDouble();
                    final saleCount = (b['sale_count'] as num? ?? 0).toInt();
                    final refundTotal = (b['refund_total'] as num? ?? 0)
                        .toDouble();
                    final refundCount = (b['refund_count'] as num? ?? 0)
                        .toInt();

                    // Rank badge colors
                    final rankColor = index == 0
                        ? AppColors.primary
                        : index == 1
                        ? AppColors.primaryLight
                        : AppColors.textSecondary;

                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: index == 0
                              ? AppColors.primary.withValues(alpha: 0.3)
                              : AppColors.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: rankColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    '#${index + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: rankColor,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                    Text(
                                      '$saleCount sales · $_days day period',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _money(revenue),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryLight,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const Text(
                                    'Revenue',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Metrics grid
                          Row(
                            children: [
                              _BranchMetric(
                                label: 'Gross Profit',
                                value: _money(grossProfit),
                                color: grossProfit >= 0
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                              const SizedBox(width: 10),
                              _BranchMetric(
                                label: 'Expenses',
                                value: _money(expenses),
                                color: AppColors.warning,
                              ),
                              const SizedBox(width: 10),
                              _BranchMetric(
                                label: 'Net Profit',
                                value: _money(netProfit),
                                color: netProfit >= 0
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _BranchMetric(
                                label: 'Products',
                                value: _money(productRev),
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 10),
                              _BranchMetric(
                                label: 'Services',
                                value: _money(serviceRev),
                                color: AppColors.secondary,
                              ),
                              const SizedBox(width: 10),
                              _BranchMetric(
                                label: 'Refunds',
                                value: refundCount > 0
                                    ? '$refundCount (${_money(refundTotal)})'
                                    : '0',
                                color: AppColors.error,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _BranchMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BranchMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
