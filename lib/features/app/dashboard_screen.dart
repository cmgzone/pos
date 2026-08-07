import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/database_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/shop_settings.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme_extensions.dart';
import '../../widgets/piki_mark.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stitch_kit.dart';
import '../products/data/product_repository.dart';
import '../sales/data/sale_repository.dart';
import '../training/widgets/training_anchor.dart';
import 'app_shell.dart';

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

  bool get _canStartSale => SessionService.isRestaurantMode
      ? SessionService.canAccessFeature(UserAccessProfile.featureRestaurantMode)
      : (SessionService.canUseProductPos &&
                SessionService.canAccessFeature(
                  UserAccessProfile.featurePos,
                )) ||
            (SessionService.canUseServicePos &&
                SessionService.canAccessFeature(
                  UserAccessProfile.featureServices,
                ));

  List<_HomeAction> get _actions => [
    _HomeAction(
      label: SessionService.isRestaurantMode ? 'Restaurant' : 'Sell',
      description: SessionService.isRestaurantMode
          ? 'Open tables and kitchen orders'
          : 'Start a new sale',
      icon: SessionService.isRestaurantMode
          ? Icons.restaurant_rounded
          : Icons.shopping_cart_checkout_rounded,
      destinationIndex: SessionService.isRestaurantMode
          ? 29
          : (SessionService.canUseProductPos &&
                SessionService.canAccessFeature(UserAccessProfile.featurePos))
          ? 0
          : 11,
      available: _canStartSale,
    ),
    _HomeAction(
      label: 'Products',
      description: 'Manage products',
      icon: Icons.inventory_2_outlined,
      destinationIndex: 1,
      available:
          SessionService.canUseProductPos &&
          SessionService.canAccessFeature(UserAccessProfile.featureProducts),
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
          SessionService.canUseProductPos &&
          (SessionService.canAccessFeature(
                UserAccessProfile.featureStockList,
              ) ||
              SessionService.canAccessFeature(
                UserAccessProfile.featureProducts,
              )),
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
      label: 'Online Store',
      description: 'Manage website and orders',
      icon: Icons.storefront_outlined,
      destinationIndex: 36,
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
                  20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
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
                          if (_lowStockProducts.isNotEmpty) ...[
                            _buildStockNotice(),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          _buildTradingPulse(),
                          const SizedBox(height: AppSpacing.xl),
                          _buildSearch(),
                          const SizedBox(height: AppSpacing.xl),
                          if (_isLoading)
                            const SkeletonKpiGrid()
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
        const PikiMark(size: 46),
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
                  width: 20,
                  height: 20,
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
                      fontSize: 10,
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

  Widget _buildTradingPulse() {
    final canSell =
        SessionService.canUseProductPos &&
        SessionService.canAccessFeature(UserAccessProfile.featurePos);
    final sales = _money(_todaySummary['total_revenue'] as num?);
    final profit = _money(_todaySummary['total_profit'] as num?);

    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final compact = constraints.maxWidth < 720;
        final summary = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OperationHeading(shopName: ShopSettings.shopName),
            const SizedBox(height: AppSpacing.md),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                sales,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontSize: compact ? 32 : 38,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.4,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _isLoading ? 'Loading today\'s trade…' : 'Sales recorded today',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
        final stats = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _OperationStat(label: 'Profit', value: profit),
            _OperationStat(label: 'Orders waiting', value: '$_pendingOrders'),
          ],
        );
        final action = FilledButton.icon(
          onPressed: () => AppShell.selectIndex(canSell ? 0 : 4),
          icon: Icon(
            canSell ? Icons.arrow_forward_rounded : Icons.receipt_long_rounded,
          ),
          label: Text(canSell ? 'Start a sale' : 'View sales'),
        );

        return SizedBox(
          width: double.infinity,
          child: StitchCard(
            padding: EdgeInsets.all(compact ? AppSpacing.xl : 28),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      summary,
                      const SizedBox(height: AppSpacing.lg),
                      stats,
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(width: double.infinity, child: action),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(flex: 5, child: summary),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(flex: 4, child: stats),
                      const SizedBox(width: AppSpacing.lg),
                      action,
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildStockNotice() {
    final theme = Theme.of(context);
    final count = _lowStockProducts.length;
    return Semantics(
      button: true,
      label: '$count low stock ${count == 1 ? 'item' : 'items'}. Review stock.',
      child: InkWell(
        onTap: () => AppShell.selectIndex(12),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: context.warningPanelBackground(),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.24),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Low stock needs attention',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$count ${count == 1 ? 'item is' : 'items are'} at or below the reorder level',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return StitchSearchBar(onTap: _showActionSearch);
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
              _buildSalesTrend(),
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
        _buildSalesTrend(),
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

  Widget _buildSalesTrend() {
    final theme = Theme.of(context);
    final values = _recentSales.reversed
        .map((sale) => (sale['total_amount'] as num? ?? 0).toDouble())
        .toList();
    final chartValues = values.isEmpty
        ? <double>[0, 0]
        : values.length == 1
        ? <double>[0, values.first]
        : values;

    return SizedBox(
      width: double.infinity,
      child: StitchCard(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sales trend', style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Recent completed sales',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'LIVE',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              image: true,
              label:
                  'Sales trend for ${values.length} recent completed ${values.length == 1 ? 'sale' : 'sales'}',
              child: SizedBox(
                height: 136,
                width: double.infinity,
                child: CustomPaint(
                  painter: _SalesTrendPainter(
                    values: chartValues,
                    lineColor: theme.colorScheme.primary,
                    gridColor: theme.colorScheme.outline.withValues(
                      alpha: 0.55,
                    ),
                    fillColor: theme.colorScheme.primary.withValues(
                      alpha: 0.08,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text('Oldest', style: theme.textTheme.labelSmall),
                const Spacer(),
                Text('Latest', style: theme.textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReorderSuggestionsCard() {
    final theme = Theme.of(context);
    final suggestions = _reorderSuggestions;
    return SizedBox(
      width: double.infinity,
      child: StitchCard(
        color: context.warningPanelBackground(),
        borderColor: AppColors.warning.withValues(alpha: 0.22),
        padding: const EdgeInsets.all(AppSpacing.xl),
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
      ),
    );
  }

  String _quantityLabel(double value, String unit) {
    final quantity = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
    return unit.trim().isEmpty ? quantity : '$quantity $unit';
  }

  Widget _buildRecentActivity() {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: StitchCard(
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
                    child: StitchSectionHeader(title: 'Recent activity'),
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
      ),
    );
  }
}

class _OperationHeading extends StatelessWidget {
  final String shopName;

  const _OperationHeading({required this.shopName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: AppColors.signal,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            'TODAY · ${shopName.toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.65,
            ),
          ),
        ),
      ],
    );
  }
}

class _OperationStat extends StatelessWidget {
  final String label;
  final String value;

  const _OperationStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 146,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesTrendPainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  final Color gridColor;
  final Color fillColor;

  const _SalesTrendPainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var index = 0; index < 4; index++) {
      final y = size.height * index / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final highest = values.reduce((a, b) => a > b ? a : b);
    final lowest = values.reduce((a, b) => a < b ? a : b);
    final range = highest == lowest ? 1.0 : highest - lowest;
    final points = <Offset>[];
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? 0.0
          : size.width * index / (values.length - 1);
      final normalized = (values[index] - lowest) / range;
      final y = size.height - (normalized * (size.height - 16)) - 8;
      points.add(Offset(x, y));
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    for (final point in points) {
      canvas.drawCircle(point, 3, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(covariant _SalesTrendPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.fillColor != fillColor;
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
    return StitchCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      radius: AppRadius.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(metric.icon, size: 18, color: metric.color),
            ],
          ),
          const Spacer(),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.45,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Open details',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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

class _ActionIcon extends StatelessWidget {
  final IconData icon;

  const _ActionIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: 22, color: color),
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
