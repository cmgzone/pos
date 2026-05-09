import 'package:flutter/material.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/database_service.dart';
import '../../core/services/shop_settings.dart';
import '../../core/utils/expiry_utils.dart';
import '../../core/utils/unit_utils.dart';
import '../training/widgets/training_anchor.dart';
import '../products/data/product_repository.dart';
import '../reports/data/report_repository.dart';
import '../sales/data/sale_repository.dart';
import '../services/data/service_repository.dart';
import '../shifts/data/shift_repository.dart';
import 'app_shell.dart';
import '../../widgets/beautiful_icon.dart';
import '../../widgets/empty_state_widget.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic> _todaySummary = {};
  List<Map<String, dynamic>> _lowStockProducts = [];
  List<Map<String, dynamic>> _expiryAlerts = [];
  List<Map<String, dynamic>> _recentSales = [];
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _employeeSales = [];
  Map<String, dynamic> _closedShiftSummary = {};
  List<Map<String, dynamic>> _closedShifts = [];
  List<Map<String, dynamic>> _missingCostProducts = [];
  Map<String, dynamic> _saleTypeSummary = {};
  List<Map<String, dynamic>> _readyServiceOrders = [];
  List<Map<String, dynamic>> _topServices = [];
  bool _isLoading = true;

  bool get _isCashierView =>
      RolePermissions.normalizeRole(SessionService.currentUserRole) ==
      RolePermissions.cashier;

  bool get _canSeeEmployeeSales => !_isCashierView;

  String? get _salesViewerId {
    final userId = SessionService.currentUserId.trim();
    if (!_isCashierView) {
      return null;
    }
    return userId.isEmpty ? '__missing_cashier__' : userId;
  }

  Color _roleColor(String? role) {
    switch (RolePermissions.normalizeRole(role)) {
      case RolePermissions.admin:
        return AppColors.primary;
      case RolePermissions.manager:
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  Color _shiftDifferenceColor(num? difference) {
    final value = (difference ?? 0).toDouble();
    if (value < -0.009) {
      return AppColors.error;
    }
    if (value > 0.009) {
      return AppColors.warning;
    }
    return AppColors.success;
  }

  String _shiftDifferenceLabel(num? difference) {
    final value = (difference ?? 0).toDouble();
    if (value < -0.009) {
      return 'Short';
    }
    if (value > 0.009) {
      return 'Over';
    }
    return 'Balanced';
  }

  String _timeLabel(String? raw) {
    final date = DateTime.tryParse(raw ?? '');
    if (date == null) {
      return '--:--';
    }
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<Map<String, dynamic>> _loadSaleTypeSummary(String? cashierId) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final args = <dynamic>['$today%'];
    final cashierClause = cashierId == null || cashierId.isEmpty
        ? ''
        : 'AND s.user_id = ?';
    if (cashierClause.isNotEmpty) {
      args.add(cashierId);
    }

    final rows = await DatabaseService.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN product_lines > 0 AND service_lines = 0 THEN total_amount ELSE 0 END), 0) as product_revenue,
        COALESCE(SUM(CASE WHEN service_lines > 0 AND product_lines = 0 THEN total_amount ELSE 0 END), 0) as service_revenue,
        COALESCE(SUM(CASE WHEN product_lines > 0 AND service_lines > 0 THEN total_amount ELSE 0 END), 0) as mixed_revenue,
        SUM(CASE WHEN product_lines > 0 AND service_lines = 0 THEN 1 ELSE 0 END) as product_sales,
        SUM(CASE WHEN service_lines > 0 AND product_lines = 0 THEN 1 ELSE 0 END) as service_sales,
        SUM(CASE WHEN product_lines > 0 AND service_lines > 0 THEN 1 ELSE 0 END) as mixed_sales
      FROM (
        SELECT
          s.id,
          s.total_amount,
          COALESCE((SELECT COUNT(*) FROM sale_items si WHERE si.sale_id = s.id AND si.deleted_at IS NULL), 0) as product_lines,
          COALESCE((SELECT COUNT(*) FROM service_sale_items ssi WHERE ssi.sale_id = s.id AND ssi.deleted_at IS NULL), 0) as service_lines
        FROM sales s
        WHERE s.created_at LIKE ? AND s.deleted_at IS NULL $cashierClause
      ) typed_sales
    ''', args);

    return rows.isEmpty ? <String, dynamic>{} : rows.first;
  }

  Future<void> _loadDashboard() async {
    setState(() => _isLoading = true);

    try {
      final salesViewerId = _salesViewerId;
      final summary = await SaleRepository.getTodaySummary(
        cashierId: salesViewerId,
      );
      // Total products count
      final allProducts = await ProductRepository.getAll();
      // Build a fresh mutable map (sqflite returns read-only QueryRow objects)
      _todaySummary = {
        'total_revenue': summary['total_revenue'] ?? 0,
        'total_sales': summary['total_sales'] ?? 0,
        'total_tax': summary['total_tax'] ?? 0,
        'total_discount': summary['total_discount'] ?? 0,
        'total_profit': summary['total_profit'] ?? 0,
        'total_products': allProducts.length,
      };

      _lowStockProducts = await ProductRepository.getLowStock();
      _expiryAlerts = await ProductRepository.getExpiryAlerts();
      _recentSales = await SaleRepository.getAll(cashierId: salesViewerId);

      if (_recentSales.length > 5) _recentSales = _recentSales.sublist(0, 5);

      if (_canSeeEmployeeSales) {
        try {
          _employeeSales = await ReportRepository.getDailyCashierSummary();
        } catch (_) {
          _employeeSales = [];
        }
        try {
          _closedShiftSummary = await ShiftRepository.getClosedShiftSummary();
          _closedShifts = await ShiftRepository.getClosedShifts(limit: 5);
        } catch (_) {
          _closedShiftSummary = {};
          _closedShifts = [];
        }
      } else {
        _employeeSales = [];
        _closedShiftSummary = {};
        _closedShifts = [];
      }

      // Top selling products
      try {
        _topProducts = await DatabaseService.rawQuery('''
          SELECT p.name, si.unit, SUM(si.quantity) as total_sold, SUM(si.quantity * si.unit_price) as total_revenue
          FROM sale_items si
          JOIN products p ON si.product_id = p.id
          GROUP BY p.id, si.unit
          ORDER BY total_sold DESC
          LIMIT 5
        ''');
      } catch (_) {
        _topProducts = [];
      }

      // Products missing cost price
      try {
        _missingCostProducts = await DatabaseService.rawQuery(
          "SELECT id, name FROM products WHERE cost IS NULL OR cost = 0",
        );
      } catch (_) {
        _missingCostProducts = [];
      }

      try {
        _saleTypeSummary = await _loadSaleTypeSummary(salesViewerId);
      } catch (_) {
        _saleTypeSummary = {};
      }

      try {
        final serviceStats = await ServiceRepository.getServiceStats();
        _topServices =
            (serviceStats['top_services'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList() ??
            [];
      } catch (_) {
        _topServices = [];
      }

      try {
        final activeOrders = await ServiceRepository.getOrders(
          filter: 'active',
        );
        _readyServiceOrders = activeOrders
            .where((order) {
              final status = order['status'] as String? ?? '';
              final saleId = (order['sale_id'] as String? ?? '').trim();
              return saleId.isEmpty &&
                  (status == 'ready' || status == 'completed');
            })
            .take(5)
            .toList();
      } catch (_) {
        _readyServiceOrders = [];
      }
    } catch (e) {
      debugPrint('[Dashboard] Error loading: $e');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Widget _buildQuickActions(bool isMobile) {
    final actions = [
      _DashboardAction(
        icon: Icons.shopping_cart_checkout_outlined,
        label: 'Open POS',
        color: AppColors.primary,
        onTap: () => AppShell.selectIndex(0),
      ),
      _DashboardAction(
        icon: Icons.design_services_outlined,
        label: 'Sell Service',
        color: AppColors.secondary,
        onTap: () => AppShell.selectIndex(11),
      ),
      _DashboardAction(
        icon: Icons.receipt_long_outlined,
        label: 'Sales',
        color: AppColors.success,
        onTap: () => AppShell.selectIndex(4),
      ),
      _DashboardAction(
        icon: Icons.analytics_outlined,
        label: 'Reports',
        color: AppColors.warning,
        onTap: () => AppShell.selectIndex(8),
      ),
      _DashboardAction(
        icon: Icons.auto_awesome_outlined,
        label: 'Ask Piki AI',
        color: const Color(0xFF9B5CFF),
        onTap: () => AppShell.selectIndex(16),
      ),
    ];

    if (isMobile) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.6,
        children: actions,
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: actions
          .map((action) => SizedBox(width: 180, child: action))
          .toList(),
    );
  }

  Widget _buildPikiBanner() {
    return GestureDetector(
      onTap: () => AppShell.selectIndex(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A0A2E), Color(0xFF2D1060)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF9B5CFF).withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF9B5CFF).withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // AI Icon glow
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9B5CFF), Color(0xFFFF2A5F)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF9B5CFF).withValues(alpha: 0.4),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'P',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Piki AI Agent',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ask about stock, profits, sales or restock needs — Piki plans and acts for you.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF9B5CFF).withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF9B5CFF).withValues(alpha: 0.5),
                ),
              ),
              child: const Text(
                'Ask now →',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceSnapshot(bool isMobile) {
    final serviceSales = (_saleTypeSummary['service_sales'] as num? ?? 0)
        .toInt();
    final productSales = (_saleTypeSummary['product_sales'] as num? ?? 0)
        .toInt();
    final mixedSales = (_saleTypeSummary['mixed_sales'] as num? ?? 0).toInt();
    final serviceRevenue = (_saleTypeSummary['service_revenue'] as num? ?? 0)
        .toDouble();
    final productRevenue = (_saleTypeSummary['product_revenue'] as num? ?? 0)
        .toDouble();
    final mixedRevenue = (_saleTypeSummary['mixed_revenue'] as num? ?? 0)
        .toDouble();

    final stats = [
      _MiniStat(
        label: 'Service Sales',
        value:
            '$serviceSales • ${ShopSettings.currency}${serviceRevenue.toStringAsFixed(2)}',
        color: AppColors.secondary,
      ),
      _MiniStat(
        label: 'Product Sales',
        value:
            '$productSales • ${ShopSettings.currency}${productRevenue.toStringAsFixed(2)}',
        color: AppColors.primary,
        compact: isMobile,
      ),
      _MiniStat(
        label: 'Mixed Sales',
        value:
            '$mixedSales • ${ShopSettings.currency}${mixedRevenue.toStringAsFixed(2)}',
        color: AppColors.warning,
        compact: isMobile,
      ),
      _MiniStat(
        label: 'Ready Unpaid',
        value: '${_readyServiceOrders.length}',
        color: _readyServiceOrders.isEmpty
            ? AppColors.success
            : AppColors.error,
        compact: isMobile,
      ),
    ];

    return _DashboardCard(
      title: 'Service Snapshot Today',
      icon: Icons.design_services_outlined,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            isMobile
                ? GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.85,
                    children: stats,
                  )
                : Wrap(spacing: 12, runSpacing: 12, children: stats),
            if (_readyServiceOrders.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 12),
              const Text(
                'Ready to collect payment',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ..._readyServiceOrders.map((order) {
                final service = order['service_name'] as String? ?? 'Service';
                final customer =
                    (order['customer_name'] as String?)?.trim().isNotEmpty ==
                        true
                    ? order['customer_name'] as String
                    : 'Walk-in';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 18,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$service • $customer',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${ShopSettings.currency}${(order['price'] as num? ?? 0).toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => AppShell.selectIndex(11),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Open Services'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopServicesCard() {
    return _DashboardCard(
      title: 'Top Services',
      icon: Icons.auto_graph_outlined,
      child: _topServices.isEmpty
          ? const EmptyStateWidget(
              icon: Icons.design_services_outlined,
              title: 'No service activity yet',
              subtitle:
                  'Top services will appear after service orders or sales.',
            )
          : Column(
              children: _topServices.take(5).toList().asMap().entries.map((
                entry,
              ) {
                final i = entry.key;
                final service = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: i == 0
                              ? AppColors.secondary.withValues(alpha: 0.18)
                              : AppColors.surfaceHighlight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: i == 0
                                  ? AppColors.secondary
                                  : AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          service['service_name'] as String? ?? 'Service',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        '${(service['order_count'] as num? ?? 0).toInt()} jobs',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        '${ShopSettings.currency}${(service['revenue'] as num? ?? 0).toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final isMobile = MediaQuery.of(context).size.width < 800;
    final revenueLabel = _isCashierView
        ? 'Your Revenue Today'
        : "Today's Revenue";
    final profitLabel = _isCashierView ? 'Your Profit Today' : "Today's Profit";
    final salesLabel = _isCashierView ? 'Your Sales Today' : "Today's Sales";
    final recentSalesTitle = _isCashierView
        ? 'Your Recent Sales'
        : 'Recent Sales';

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
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadDashboard,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Missing Cost Warning ──
                if (_missingCostProducts.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.warning,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Missing Cost Prices',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.warning,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_missingCostProducts.length} product(s) have no cost price. P&L reports may be inaccurate: ${_missingCostProducts.take(3).map((p) => p['name']).join(', ')}${_missingCostProducts.length > 3 ? '...' : ''}',
                                style: TextStyle(
                                  color: AppColors.warning.withValues(
                                    alpha: 0.8,
                                  ),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── KPI Cards ──
                if (_expiryAlerts.isNotEmpty)
                  Builder(
                    builder: (context) {
                      final hasExpired = _expiryAlerts.any(
                        (batch) =>
                            ExpiryUtils.statusFor(batch['expiry_date']) ==
                            ExpiryStatus.expired,
                      );
                      final tone = hasExpired
                          ? AppColors.error
                          : AppColors.warning;
                      final preview = _expiryAlerts
                          .take(3)
                          .map(
                            (batch) =>
                                '${batch['product_name']} (${ExpiryUtils.statusLabel(batch['expiry_date'])})',
                          )
                          .join(', ');
                      return Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: tone.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              hasExpired
                                  ? Icons.error_outline
                                  : Icons.event_busy_outlined,
                              color: tone,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    hasExpired
                                        ? 'Expired Stock Alert'
                                        : 'Expiry Alert',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: tone,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_expiryAlerts.length} batch(es) need attention: $preview${_expiryAlerts.length > 3 ? '...' : ''}',
                                    style: TextStyle(
                                      color: tone.withValues(alpha: 0.85),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                if (_isCashierView)
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Dashboard totals and recent sales are showing your activity only.',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                TrainingAnchor(
                  id: 'dashboard.kpis',
                  child: isMobile
                      ? GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.48,
                          children: [
                            _KpiCard(
                              icon: Icons.attach_money,
                              label: revenueLabel,
                              value:
                                  '${ShopSettings.currency}${(_todaySummary['total_revenue'] as num? ?? 0).toStringAsFixed(2)}',
                              color: AppColors.success,
                              compact: true,
                            ),
                            _KpiCard(
                              icon: Icons.monetization_on,
                              label: profitLabel,
                              value:
                                  '${ShopSettings.currency}${(_todaySummary['total_profit'] as num? ?? 0).toStringAsFixed(2)}',
                              color:
                                  ((_todaySummary['total_profit'] as num? ??
                                          0) >=
                                      0)
                                  ? AppColors.success
                                  : AppColors.error,
                              compact: true,
                            ),
                            _KpiCard(
                              icon: Icons.receipt_long,
                              label: salesLabel,
                              value: '${_todaySummary['total_sales'] ?? 0}',
                              color: AppColors.primary,
                              compact: true,
                            ),
                            _KpiCard(
                              icon: Icons.design_services_outlined,
                              label: 'Service Sales',
                              value:
                                  '${(_saleTypeSummary['service_sales'] as num? ?? 0).toInt()}',
                              color: AppColors.secondary,
                              compact: true,
                            ),
                            _KpiCard(
                              icon: Icons.inventory_2,
                              label: 'Products',
                              value: '${_todaySummary['total_products'] ?? 0}',
                              color: AppColors.secondary,
                              compact: true,
                            ),
                            _KpiCard(
                              icon: Icons.warning_amber,
                              label: 'Low Stock',
                              value: '${_lowStockProducts.length}',
                              color: _lowStockProducts.isNotEmpty
                                  ? AppColors.warning
                                  : AppColors.success,
                              compact: true,
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: _KpiCard(
                                icon: Icons.attach_money,
                                label: revenueLabel,
                                value:
                                    '${ShopSettings.currency}${(_todaySummary['total_revenue'] as num? ?? 0).toStringAsFixed(2)}',
                                color: AppColors.success,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _KpiCard(
                                icon: Icons.monetization_on,
                                label: profitLabel,
                                value:
                                    '${ShopSettings.currency}${(_todaySummary['total_profit'] as num? ?? 0).toStringAsFixed(2)}',
                                color:
                                    ((_todaySummary['total_profit'] as num? ??
                                            0) >=
                                        0)
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _KpiCard(
                                icon: Icons.receipt_long,
                                label: salesLabel,
                                value: '${_todaySummary['total_sales'] ?? 0}',
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _KpiCard(
                                icon: Icons.inventory_2,
                                label: 'Total Products',
                                value:
                                    '${_todaySummary['total_products'] ?? 0}',
                                color: AppColors.secondary,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _KpiCard(
                                icon: Icons.warning_amber,
                                label: 'Low Stock Items',
                                value: '${_lowStockProducts.length}',
                                color: _lowStockProducts.isNotEmpty
                                    ? AppColors.warning
                                    : AppColors.success,
                              ),
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 24),
                _DashboardCard(
                  title: 'Quick Actions',
                  icon: Icons.bolt_outlined,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildQuickActions(isMobile),
                  ),
                ),

                const SizedBox(height: 24),
                _buildPikiBanner(),

                const SizedBox(height: 24),
                _buildServiceSnapshot(isMobile),

                if (_canSeeEmployeeSales) ...[
                  const SizedBox(height: 32),
                  _DashboardCard(
                    title: 'Employee Sales Today',
                    icon: Icons.badge_outlined,
                    child: _employeeSales.isEmpty
                        ? const EmptyStateWidget(
                            icon: Icons.person_off_outlined,
                            title: 'No activity yet',
                            subtitle:
                                'Daily sales by employee will appear here.',
                          )
                        : Column(
                            children: _employeeSales.take(5).map((employee) {
                              final name =
                                  (employee['cashier_name'] as String? ??
                                          'Employee')
                                      .trim();
                              final displayName = name.isEmpty
                                  ? 'Employee'
                                  : name;
                              final role = employee['cashier_role'] as String?;
                              final roleColor = _roleColor(role);
                              final initial = displayName
                                  .substring(0, 1)
                                  .toUpperCase();
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: roleColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Center(
                                        child: Text(
                                          initial,
                                          style: TextStyle(
                                            color: roleColor,
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
                                          Text(
                                            displayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: roleColor.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              RolePermissions.label(role),
                                              style: TextStyle(
                                                color: roleColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
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
                                          '${ShopSettings.currency}${(employee['total_revenue'] as num? ?? 0).toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: AppColors.success,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          '${(employee['total_sales'] as num? ?? 0).toInt()} sales',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                  ),
                ],

                if (_canSeeEmployeeSales) ...[
                  const SizedBox(height: 24),
                  _DashboardCard(
                    title: 'Cash Reconciliation Today',
                    icon: Icons.lock_clock_outlined,
                    child: _closedShifts.isEmpty
                        ? const EmptyStateWidget(
                            icon: Icons.lock_reset_outlined,
                            title: 'No shifts closed',
                            subtitle:
                                'Reconciliation data appears after shift closure.',
                          )
                        : Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  20,
                                  20,
                                  12,
                                ),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _MiniStat(
                                      label: 'Closed Shifts',
                                      value:
                                          '${(_closedShiftSummary['closed_shift_count'] as num? ?? 0).toInt()}',
                                      color: AppColors.primary,
                                    ),
                                    _MiniStat(
                                      label: 'Counted Cash',
                                      value:
                                          '${ShopSettings.currency}${((_closedShiftSummary['counted_cash_total'] as num?) ?? 0).toStringAsFixed(2)}',
                                      color: AppColors.success,
                                    ),
                                    _MiniStat(
                                      label: 'Net Over/Short',
                                      value:
                                          '${ShopSettings.currency}${((_closedShiftSummary['net_difference'] as num?) ?? 0).toStringAsFixed(2)}',
                                      color: _shiftDifferenceColor(
                                        _closedShiftSummary['net_difference']
                                            as num?,
                                      ),
                                    ),
                                    _MiniStat(
                                      label: 'Balanced',
                                      value:
                                          '${(_closedShiftSummary['balanced_shift_count'] as num? ?? 0).toInt()}',
                                      color: AppColors.success,
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),
                              ..._closedShifts.map((shift) {
                                final difference =
                                    (shift['difference'] as num?)?.toDouble() ??
                                    0;
                                final tone = _shiftDifferenceColor(difference);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: tone.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Center(
                                          child: Icon(
                                            difference.abs() < 0.009
                                                ? Icons.check_circle_outline
                                                : difference > 0
                                                ? Icons.arrow_upward_rounded
                                                : Icons.arrow_downward_rounded,
                                            color: tone,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              shift['cashier_name']
                                                      as String? ??
                                                  'Cashier',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Closed ${_timeLabel(shift['closed_at'] as String?)} • Expected ${ShopSettings.currency}${((shift['expected_cash'] as num?) ?? 0).toStringAsFixed(2)}',
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
                                            '${ShopSettings.currency}${((shift['closing_cash_counted'] as num?) ?? 0).toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            '${_shiftDifferenceLabel(difference)} ${ShopSettings.currency}${difference.abs().toStringAsFixed(2)}',
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
                                );
                              }),
                            ],
                          ),
                  ),
                ],

                const SizedBox(height: 32),

                // ── Two-column: Top Products + Low Stock ──
                TrainingAnchor(
                  id: 'dashboard.insights',
                  child: isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Top products
                            _DashboardCard(
                              title: 'Top Selling Products',
                              icon: Icons.trending_up,
                              child: _topProducts.isEmpty
                                  ? const EmptyStateWidget(
                                      icon: Icons.analytics_outlined,
                                      title: 'Calculating insights',
                                      subtitle:
                                          'Top products will appear once sales occur.',
                                    )
                                  : Column(
                                      children: _topProducts.asMap().entries.map((
                                        entry,
                                      ) {
                                        final i = entry.key;
                                        final p = entry.value;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: i == 0
                                                      ? AppColors.warning
                                                            .withValues(
                                                              alpha: 0.2,
                                                            )
                                                      : i == 1
                                                      ? AppColors.textSecondary
                                                            .withValues(
                                                              alpha: 0.15,
                                                            )
                                                      : AppColors
                                                            .surfaceHighlight,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    '${i + 1}',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color: i == 0
                                                          ? AppColors.warning
                                                          : AppColors
                                                                .textSecondary,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  p['name'] as String? ?? '',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '${UnitUtils.formatWithUnit(p['total_sold'] as num?, p['unit'] as String?)} sold',
                                                style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Text(
                                                '${ShopSettings.currency}${(p['total_revenue'] as num? ?? 0).toStringAsFixed(2)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.success,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                            ),
                            const SizedBox(height: 24),
                            // Low stock alerts
                            _DashboardCard(
                              title: 'Low Stock Alerts',
                              icon: Icons.warning_amber_rounded,
                              child: _lowStockProducts.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.check_circle,
                                            color: AppColors.success,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'All products well stocked!',
                                            style: TextStyle(
                                              color: AppColors.success,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Column(
                                      children: _lowStockProducts
                                          .take(5)
                                          .map(
                                            (p) => Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 10,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      color:
                                                          ((p['stock'] as num? ??
                                                                      0)
                                                                  .toDouble()) ==
                                                              0
                                                          ? AppColors.error
                                                          : AppColors.warning,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      p['name'] as String? ??
                                                          '',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          ((p['stock']
                                                                          as num? ??
                                                                      0)
                                                                  .toDouble()) ==
                                                              0
                                                          ? AppColors.error
                                                                .withValues(
                                                                  alpha: 0.12,
                                                                )
                                                          : AppColors.warning
                                                                .withValues(
                                                                  alpha: 0.12,
                                                                ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      UnitUtils.formatWithUnit(
                                                        p['stock'] as num?,
                                                        UnitUtils.stockUnitForProduct(
                                                          p,
                                                        ),
                                                      ),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            ((p['stock'] as num? ??
                                                                        0)
                                                                    .toDouble()) ==
                                                                0
                                                            ? AppColors.error
                                                            : AppColors.warning,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top products
                            Expanded(
                              child: _DashboardCard(
                                title: 'Top Selling Products',
                                icon: Icons.trending_up,
                                child: _topProducts.isEmpty
                                    ? const Padding(
                                        padding: EdgeInsets.all(24),
                                        child: Text(
                                          'No sales data yet',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      )
                                    : Column(
                                        children: _topProducts.asMap().entries.map((
                                          entry,
                                        ) {
                                          final i = entry.key;
                                          final p = entry.value;
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 28,
                                                  height: 28,
                                                  decoration: BoxDecoration(
                                                    color: i == 0
                                                        ? AppColors.warning
                                                              .withValues(
                                                                alpha: 0.2,
                                                              )
                                                        : i == 1
                                                        ? AppColors
                                                              .textSecondary
                                                              .withValues(
                                                                alpha: 0.15,
                                                              )
                                                        : AppColors
                                                              .surfaceHighlight,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Center(
                                                    child: Text(
                                                      '${i + 1}',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12,
                                                        color: i == 0
                                                            ? AppColors.warning
                                                            : AppColors
                                                                  .textSecondary,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    p['name'] as String? ?? '',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  '${UnitUtils.formatWithUnit(p['total_sold'] as num?, p['unit'] as String?)} sold',
                                                  style: const TextStyle(
                                                    color:
                                                        AppColors.textSecondary,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Text(
                                                  '${ShopSettings.currency}${(p['total_revenue'] as num? ?? 0).toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.success,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            // Low stock alerts
                            Expanded(
                              child: _DashboardCard(
                                title: 'Low Stock Alerts',
                                icon: Icons.warning_amber_rounded,
                                child: _lowStockProducts.isEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.check_circle,
                                              color: AppColors.success,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'All products well stocked!',
                                              style: TextStyle(
                                                color: AppColors.success,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Column(
                                        children: _lowStockProducts
                                            .take(5)
                                            .map(
                                              (p) => Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 10,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    Container(
                                                      width: 8,
                                                      height: 8,
                                                      decoration: BoxDecoration(
                                                        color:
                                                            ((p['stock'] as num? ??
                                                                        0)
                                                                    .toDouble()) ==
                                                                0
                                                            ? AppColors.error
                                                            : AppColors.warning,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Text(
                                                        p['name'] as String? ??
                                                            '',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 10,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            AppColors.surface,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                        border: Border.all(
                                                          color:
                                                              AppColors.border,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        UnitUtils.formatWithUnit(
                                                          p['stock'] as num?,
                                                          UnitUtils.stockUnitForProduct(
                                                            p,
                                                          ),
                                                        ),
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                              ),
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 32),

                _buildTopServicesCard(),

                const SizedBox(height: 32),

                // ── Recent Sales ──
                TrainingAnchor(
                  id: 'dashboard.recentSales',
                  child: _DashboardCard(
                    title: recentSalesTitle,
                    icon: Icons.history,
                    child: _recentSales.isEmpty
                        ? EmptyStateWidget(
                            icon: Icons.receipt_long_outlined,
                            title: _isCashierView
                                ? 'No sales yet'
                                : 'Empty history',
                            subtitle: _isCashierView
                                ? 'Start selling to see your recent transactions.'
                                : 'Recent shop transactions will be listed here.',
                          )
                        : Column(
                            children: _recentSales.map((sale) {
                              final dt = DateTime.tryParse(
                                sale['created_at'] as String? ?? '',
                              );
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: AppColors.success.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.receipt,
                                        color: AppColors.success,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Sale #${(sale['id'] as String).substring(0, 8)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (dt != null)
                                            Text(
                                              '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          if (_canSeeEmployeeSales &&
                                              (sale['cashier_name'] as String?)
                                                      ?.isNotEmpty ==
                                                  true)
                                            Text(
                                              sale['cashier_name'] as String,
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${ShopSettings.currency}${(sale['total_amount'] as num).toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.success,
                                        fontSize: 16,
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

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool compact;
  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(compact ? 14 : 22),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.all(compact ? 8 : 12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(compact ? 10 : 14),
                ),
                child: BeautifulIcon(
                  icon,
                  color: color,
                  size: compact ? 17 : 24,
                ),
              ),
              if (!compact)
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
            ],
          ),
          SizedBox(height: compact ? 8 : 20),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: compact ? 2 : 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: compact ? 19 : 26,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool compact;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? null : 170,
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: compact ? 10 : 12,
            ),
          ),
          SizedBox(height: compact ? 3 : 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 13 : 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _DashboardAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 800;

    return Material(
      color: AppColors.surfaceHighlight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 9 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 28 : 34,
                height: compact ? 28 : 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(compact ? 8 : 10),
                ),
                child: Icon(icon, color: color, size: compact ? 15 : 18),
              ),
              SizedBox(width: compact ? 7 : 10),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 12 : 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _DashboardCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                BeautifulIcon(icon, color: AppColors.primaryLight, size: 20),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          child,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
