import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/database_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/shop_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme_extensions.dart';
import '../products/data/product_repository.dart';
import '../sales/data/sale_repository.dart';
import '../training/widgets/training_anchor.dart';
import 'app_shell.dart';
import 'widgets/storefront_share_dialog.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final DashboardData? initialData;

  const DashboardScreen({super.key, this.initialData});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final NumberFormat _moneyFormat = NumberFormat('#,##0.00');
  Map<String, dynamic> _todaySummary = const {};
  Map<String, dynamic> _monthSummary = const {};
  List<Map<String, dynamic>> _lowStockProducts = const [];
  List<Map<String, dynamic>> _reorderSuggestions = const [];
  List<Map<String, dynamic>> _recentSales = const [];
  String? _topProductName;
  int _pendingOrders = 0;
  int _activeStaff = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final initialData = widget.initialData;
    if (initialData == null) {
      _loadDashboard();
    } else {
      _todaySummary = initialData.todaySummary;
      _monthSummary = initialData.monthSummary;
      _lowStockProducts = initialData.lowStockProducts;
      _reorderSuggestions = initialData.reorderSuggestions;
      _recentSales = initialData.recentSales;
      _topProductName = initialData.topProductName;
      _pendingOrders = initialData.pendingOrders;
      _activeStaff = initialData.activeStaff;
      _isLoading = false;
    }
  }

  Future<void> _loadDashboard() async {
    if (mounted) setState(() => _isLoading = true);

    Map<String, dynamic> summary = const {};
    Map<String, dynamic> monthSummary = const {};
    List<Map<String, dynamic>> lowStock = const [];
    List<Map<String, dynamic>> reorderSuggestions = const [];
    List<Map<String, dynamic>> recentSales = const [];
    String? topProductName;
    var pendingOrders = 0;
    var activeStaff = 0;

    try {
      summary = await SaleRepository.getTodaySummary();
    } catch (error) {
      debugPrint('[Dashboard] Could not load today summary: $error');
    }
    try {
      lowStock = await ProductRepository.getLowStock();
    } catch (error) {
      debugPrint('[Dashboard] Could not load low stock: $error');
    }
    try {
      reorderSuggestions = await ProductRepository.getReorderSuggestions(
        limit: 5,
      );
    } catch (error) {
      debugPrint('[Dashboard] Could not load reorder suggestions: $error');
    }
    try {
      recentSales = (await SaleRepository.getAll()).take(5).toList();
    } catch (error) {
      debugPrint('[Dashboard] Could not load recent sales: $error');
    }
    try {
      final month = DateFormat('yyyy-MM').format(DateTime.now());
      final rows = await DatabaseService.rawQuery(
        '''
        SELECT COALESCE(SUM(total_amount), 0) AS total_revenue
        FROM sales
        WHERE strftime('%Y-%m', created_at) = ?
          AND deleted_at IS NULL
          AND COALESCE(branch_id, ?) = ?
        ''',
        [
          month,
          DatabaseService.defaultBranchId,
          DatabaseService.currentBranchId,
        ],
      );
      monthSummary = rows.isEmpty ? const {} : rows.first;
    } catch (error) {
      debugPrint('[Dashboard] Could not load monthly sales: $error');
    }
    try {
      final month = DateFormat('yyyy-MM').format(DateTime.now());
      final rows = await DatabaseService.rawQuery(
        '''
        SELECT p.name, COALESCE(SUM(si.quantity), 0) AS quantity_sold
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        JOIN products p ON p.id = si.product_id
        WHERE strftime('%Y-%m', s.created_at) = ?
          AND s.deleted_at IS NULL
          AND COALESCE(s.branch_id, ?) = ?
        GROUP BY p.id, p.name
        HAVING SUM(si.quantity) > 0
        ORDER BY quantity_sold DESC,
          SUM(si.quantity * si.unit_price) DESC
        LIMIT 1
        ''',
        [
          month,
          DatabaseService.defaultBranchId,
          DatabaseService.currentBranchId,
        ],
      );
      if (rows.isNotEmpty) {
        topProductName = rows.first['name']?.toString();
      }
    } catch (error) {
      debugPrint('[Dashboard] Could not load top product: $error');
    }
    try {
      final rows = await DatabaseService.rawQuery(
        '''
        SELECT COUNT(*) AS count
        FROM public_catalog_orders
        WHERE status = 'pending'
          AND COALESCE(branch_id, ?) = ?
        ''',
        [DatabaseService.defaultBranchId, DatabaseService.currentBranchId],
      );
      pendingOrders = (rows.firstOrNull?['count'] as num? ?? 0).toInt();
    } catch (error) {
      debugPrint('[Dashboard] Could not load pending orders: $error');
    }
    try {
      final rows = await DatabaseService.rawQuery(
        'SELECT COUNT(*) AS count FROM users WHERE deleted_at IS NULL',
      );
      activeStaff = (rows.firstOrNull?['count'] as num? ?? 0).toInt();
    } catch (error) {
      debugPrint('[Dashboard] Could not load active staff: $error');
    }

    if (!mounted) return;
    setState(() {
      _todaySummary = summary;
      _monthSummary = monthSummary;
      _lowStockProducts = lowStock;
      _reorderSuggestions = reorderSuggestions;
      _recentSales = recentSales;
      _topProductName = topProductName;
      _pendingOrders = pendingOrders;
      _activeStaff = activeStaff;
      _isLoading = false;
    });
  }

  List<_HomeAction> get _actions => [
    _HomeAction(
      label: 'Sell',
      description: 'Start a new sale',
      icon: Icons.shopping_cart_checkout_rounded,
      destinationIndex:
          (SessionService.canUseProductPos &&
              SessionService.canAccessFeature(UserAccessProfile.featurePos))
          ? 0
          : 11,
      available:
          (SessionService.canUseProductPos &&
              SessionService.canAccessFeature(UserAccessProfile.featurePos)) ||
          (SessionService.canUseServicePos &&
              SessionService.canAccessFeature(
                UserAccessProfile.featureServices,
              )),
    ),
    _HomeAction(
      label: 'Products',
      description: 'Manage products',
      icon: Icons.inventory_2_outlined,
      destinationIndex: 1,
      available: SessionService.canAccessFeature(
        UserAccessProfile.featureProducts,
      ),
    ),
    _HomeAction(
      label: 'Orders',
      description: 'View customer orders',
      icon: Icons.assignment_outlined,
      destinationIndex: 17,
      available:
          SessionService.canUseProductPos &&
          (SessionService.canAccessFeature(UserAccessProfile.featurePos) ||
              SessionService.canAccessFeature(UserAccessProfile.featureSales)),
    ),
    _HomeAction(
      label: 'Customers',
      description: 'Customer accounts',
      icon: Icons.people_outline_rounded,
      destinationIndex: 18,
      available:
          SessionService.canAccessFeature(UserAccessProfile.featureKopesha) ||
          SessionService.canAccessFeature(UserAccessProfile.featurePurchases),
    ),
    _HomeAction(
      label: 'Reports',
      description: 'Sales and performance',
      icon: Icons.bar_chart_rounded,
      destinationIndex: 8,
      available: SessionService.canAccessFeature(
        UserAccessProfile.featureReports,
      ),
    ),
    _HomeAction(
      label: 'Inventory',
      description: 'Review stock levels',
      icon: Icons.warehouse_outlined,
      destinationIndex: 12,
      available:
          SessionService.canAccessFeature(UserAccessProfile.featureStockList) ||
          SessionService.canAccessFeature(UserAccessProfile.featureProducts),
    ),
    _HomeAction(
      label: 'Expenses',
      description: 'Track business costs',
      icon: Icons.money_off_rounded,
      destinationIndex: 7,
      available: SessionService.canAccessFeature(
        UserAccessProfile.featureProfitLoss,
      ),
    ),
    _HomeAction(
      label: 'Staff',
      description: 'Team and permissions',
      icon: Icons.badge_outlined,
      destinationIndex: 9,
      available: RolePermissions.canManageUsers(SessionService.currentUserRole),
    ),
    _HomeAction(
      label: 'Storefront',
      description: 'Share online store',
      icon: Icons.storefront_outlined,
      destinationIndex: -1,
      available:
          SessionService.canAccessFeature(UserAccessProfile.featureProducts) ||
          SessionService.canAccessFeature(UserAccessProfile.featurePos) ||
          SessionService.canAccessFeature(UserAccessProfile.featureReports),
    ),
  ];

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _firstName {
    final name = SessionService.currentUserName.trim();
    if (name.isEmpty || name == 'Unknown Cashier') return 'there';
    return name.split(RegExp(r'\s+')).first;
  }

  String _money(num? value) {
    return '${ShopSettings.currency} ${_moneyFormat.format((value ?? 0).toDouble())}';
  }

  String _timeLabel(String? raw) {
    final parsed = DateTime.tryParse(raw ?? '');
    if (parsed == null) return '';
    return DateFormat('h:mm a').format(parsed.toLocal());
  }

  String _saleReference(Map<String, dynamic> sale) {
    final raw = (sale['receipt_number'] ?? sale['id'] ?? '').toString();
    if (raw.isEmpty) return 'Sale';
    final short = raw.length > 8 ? raw.substring(0, 8) : raw;
    return 'Sale #$short';
  }

  void _openAction(_HomeAction action) {
    if (!action.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This feature is not available for your account.'),
        ),
      );
      return;
    }
    if (action.destinationIndex == -1) {
      StorefrontShareDialog.show(context);
      return;
    }
    AppShell.selectIndex(action.destinationIndex);
  }

  Future<void> _showActionSearch() async {
    final controller = TextEditingController();
    var query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final matches = _actions.where((action) {
              final haystack = '${action.label} ${action.description}'
                  .toLowerCase();
              return haystack.contains(query.toLowerCase());
            }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  20 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 620,
                    maxHeight: 560,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What do you want to do?',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        onChanged: (value) =>
                            setModalState(() => query = value),
                        decoration: const InputDecoration(
                          hintText: 'Search actions',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: matches.length,
                          separatorBuilder: (_, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final action = matches[index];
                            return ListTile(
                              enabled: action.available,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 3,
                              ),
                              leading: _ActionIcon(icon: action.icon),
                              title: Text(action.label),
                              subtitle: Text(action.description),
                              trailing: Icon(
                                action.available
                                    ? Icons.arrow_forward_ios_rounded
                                    : Icons.lock_outline_rounded,
                                size: 16,
                              ),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _openAction(action);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 1050;
    final horizontalPadding = width < 600 ? 18.0 : 28.0;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboard,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1320),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        18,
                        horizontalPadding,
                        32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: AppSpacing.xl),
                          _buildSearch(),
                          const SizedBox(height: AppSpacing.xl),
                          if (_isLoading)
                            const LinearProgressIndicator(minHeight: 2)
                          else if (isWide)
                            _buildWideLayout()
                          else
                            _buildCompactLayout(width),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.cover,
              errorBuilder: (_, error, stackTrace) => ColoredBox(
                color: theme.colorScheme.primaryContainer,
                child: Center(
                  child: Text(
                    _firstName.substring(0, 1).toUpperCase(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_greeting, $_firstName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 3),
              Text(
                ShopSettings.shopName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Refresh data',
          onPressed: _loadDashboard,
          icon: const Icon(Icons.refresh_rounded),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => AppShell.showNotificationsSheet(context),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            if (SessionService.canUseProductPos &&
                (SessionService.canAccessFeature(
                      UserAccessProfile.featureProducts,
                    ) ||
                    SessionService.canAccessFeature(
                      UserAccessProfile.featureStockList,
                    )) &&
                _lowStockProducts.isNotEmpty)
              Positioned(
                right: 5,
                top: 5,
                child: Container(
                  width: 17,
                  height: 17,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    _lowStockProducts.length > 9
                        ? '9+'
                        : '${_lowStockProducts.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearch() {
    return Semantics(
      button: true,
      label: 'Search app actions',
      child: InkWell(
        onTap: _showActionSearch,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: IgnorePointer(
          child: TextField(
            decoration: InputDecoration(
              hintText: 'What do you want to do today?',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: Icon(
                Icons.tune_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    final hasProductAccess =
        SessionService.canUseProductPos &&
        (SessionService.canAccessFeature(UserAccessProfile.featureProducts) ||
            SessionService.canAccessFeature(
              UserAccessProfile.featureStockList,
            ));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 7,
          child: Column(
            children: [
              TrainingAnchor(id: 'dashboard.kpis', child: _buildKpiGrid()),
              const SizedBox(height: AppSpacing.xl),
              TrainingAnchor(
                id: 'dashboard.insights',
                child: _buildActions(crossAxisCount: 4),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xl),
        SizedBox(
          width: 390,
          child: Column(
            children: [
              if (hasProductAccess) ...[
                _buildReorderSuggestionsCard(),
                const SizedBox(height: AppSpacing.xl),
              ],
              TrainingAnchor(
                id: 'dashboard.recentSales',
                child: _buildRecentActivity(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(double width) {
    final columns = width >= 700 ? 4 : 2;
    final hasProductAccess =
        SessionService.canUseProductPos &&
        (SessionService.canAccessFeature(UserAccessProfile.featureProducts) ||
            SessionService.canAccessFeature(
              UserAccessProfile.featureStockList,
            ));

    return Column(
      children: [
        TrainingAnchor(id: 'dashboard.kpis', child: _buildKpiGrid()),
        const SizedBox(height: AppSpacing.xl),
        TrainingAnchor(
          id: 'dashboard.insights',
          child: _buildActions(crossAxisCount: columns),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (hasProductAccess) ...[
          _buildReorderSuggestionsCard(),
          const SizedBox(height: AppSpacing.xl),
        ],
        TrainingAnchor(
          id: 'dashboard.recentSales',
          child: _buildRecentActivity(),
        ),
      ],
    );
  }

  Widget _buildKpiGrid() {
    final metrics = [
      _DashboardMetric(
        label: 'Sales Today',
        value: _money(_todaySummary['total_revenue'] as num?),
        icon: Icons.point_of_sale_rounded,
        color: context.metricColor('sales'),
        destinationIndex: 4,
      ),
      _DashboardMetric(
        label: 'Sales This Month',
        value: _money(_monthSummary['total_revenue'] as num?),
        icon: Icons.calendar_month_rounded,
        color: context.metricColor('month'),
        destinationIndex: 8,
      ),
      _DashboardMetric(
        label: 'Profit Today',
        value: _money(_todaySummary['total_profit'] as num?),
        icon: Icons.trending_up_rounded,
        color: context.metricColor('profit'),
        destinationIndex: 7,
      ),
      _DashboardMetric(
        label: 'Top Product',
        value: _topProductName?.trim().isNotEmpty == true
            ? _topProductName!.trim()
            : 'No sales yet',
        icon: Icons.emoji_events_outlined,
        color: context.metricColor('top'),
        destinationIndex: 8,
      ),
      _DashboardMetric(
        label: 'Low Stock Items',
        value: '${_lowStockProducts.length}',
        icon: Icons.inventory_2_outlined,
        color: context.metricColor('stock'),
        destinationIndex: 12,
      ),
      _DashboardMetric(
        label: 'Pending Orders',
        value: '$_pendingOrders',
        icon: Icons.pending_actions_rounded,
        color: context.metricColor('orders'),
        destinationIndex: 17,
      ),
      _DashboardMetric(
        label: 'Active Staff',
        value: '$_activeStaff',
        icon: Icons.badge_outlined,
        color: context.metricColor('staff'),
        destinationIndex: 9,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(
          title: 'Business overview',
          subtitle: 'Live performance at a glance',
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 820
                ? 4
                : constraints.maxWidth >= 560
                ? 3
                : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                mainAxisExtent: 132,
              ),
              itemCount: metrics.length,
              itemBuilder: (context, index) {
                final metric = metrics[index];
                return _MetricTile(
                  metric: metric,
                  onTap: () => AppShell.selectIndex(metric.destinationIndex),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildActions({required int crossAxisCount}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Quick actions',
          subtitle: 'Your most-used business tasks',
        ),
        const SizedBox(height: AppSpacing.md),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: crossAxisCount == 2 ? 1.28 : 1.22,
          ),
          itemCount: _actions.length,
          itemBuilder: (context, index) {
            final action = _actions[index];
            return _ActionTile(
              action: action,
              onTap: () => _openAction(action),
            );
          },
        ),
      ],
    );
  }

  Widget _buildReorderSuggestionsCard() {
    final theme = Theme.of(context);
    final suggestions = _reorderSuggestions;
    return _Panel(
      backgroundColor: context.warningPanelBackground(),
      borderColor: AppColors.warning.withValues(alpha: 0.22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.assignment_returned_rounded,
                  color: AppColors.warning,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reorder suggestions',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      suggestions.isEmpty
                          ? 'Stock cover looks healthy right now'
                          : '${suggestions.length} ${suggestions.length == 1 ? 'item needs' : 'items need'} attention',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open stock list',
                onPressed: () => AppShell.selectIndex(12),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            ...suggestions.take(3).map((item) {
              final unit = (item['stock_unit'] ?? '').toString();
              final suggestedQty = (item['suggested_qty'] as num? ?? 0)
                  .toDouble();
              final cover = (item['days_of_cover'] as num?)?.toDouble();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (item['item_name'] ?? 'Product').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            cover == null
                                ? 'Below reorder level'
                                : '${cover.toStringAsFixed(cover % 1 == 0 ? 0 : 1)} days cover',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Order ${_quantityLabel(suggestedQty, unit)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  String _quantityLabel(double value, String unit) {
    final quantity = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
    return unit.trim().isEmpty ? quantity : '$quantity $unit';
  }

  Widget _buildRecentActivity() {
    final theme = Theme.of(context);
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              18,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent activity',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => AppShell.selectIndex(4),
                  child: const Text('View all'),
                ),
              ],
            ),
          ),
          if (_recentSales.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xs,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Row(
                children: [
                  _ActionIcon(icon: Icons.receipt_long_outlined),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Completed sales will appear here.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            )
          else
            ..._recentSales.asMap().entries.map((entry) {
              final sale = entry.value;
              final isLast = entry.key == _recentSales.length - 1;
              final payment = (sale['payment_type'] ?? 'Payment').toString();
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        const _ActionIcon(icon: Icons.shopping_bag_outlined),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _saleReference(sale),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_money(sale['total_amount'] as num?)} - $payment',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _timeLabel(sale['created_at'] as String?),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (!isLast) const Divider(height: 1, indent: 72),
                ],
              );
            }),
        ],
      ),
    );
  }
}

class DashboardData {
  final Map<String, dynamic> todaySummary;
  final Map<String, dynamic> monthSummary;
  final List<Map<String, dynamic>> lowStockProducts;
  final List<Map<String, dynamic>> reorderSuggestions;
  final List<Map<String, dynamic>> recentSales;
  final String? topProductName;
  final int pendingOrders;
  final int activeStaff;

  const DashboardData({
    this.todaySummary = const {},
    this.monthSummary = const {},
    this.lowStockProducts = const [],
    this.reorderSuggestions = const [],
    this.recentSales = const [],
    this.topProductName,
    this.pendingOrders = 0,
    this.activeStaff = 0,
  });
}

class _DashboardMetric {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final int destinationIndex;

  const _DashboardMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.destinationIndex,
  });
}

class _MetricTile extends StatelessWidget {
  final _DashboardMetric metric;
  final VoidCallback onTap;

  const _MetricTile({required this.metric, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: metric.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(metric.icon, size: 20, color: metric.color),
              ),
              const Spacer(),
              Text(
                metric.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                metric.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeAction {
  final String label;
  final String description;
  final IconData icon;
  final int destinationIndex;
  final bool available;

  const _HomeAction({
    required this.label,
    required this.description,
    required this.icon,
    required this.destinationIndex,
    required this.available,
  });
}

class _ActionTile extends StatelessWidget {
  final _HomeAction action;
  final VoidCallback onTap;

  const _ActionTile({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _ActionIcon(icon: action.icon, enabled: action.available),
              const Spacer(),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: action.available
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                action.available ? action.description : 'No access',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final bool enabled;

  const _ActionIcon({required this.icon, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: 22, color: color),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;

  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color:
              borderColor ?? theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
        boxShadow: context.appPanelShadow,
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: context.appSectionHeaderStyle),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
