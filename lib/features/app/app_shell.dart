import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/session_service.dart';
import '../../core/services/shop_settings.dart';
import '../../core/services/branch_service.dart';
import '../../core/services/sync_controller.dart';
import '../../core/services/license_service.dart';
import '../../core/theme/app_colors.dart';
import '../agent/presentation/piki_agent_screen.dart';
import '../training/application/training_controller.dart';
import '../training/presentation/training_hub_screen.dart';
import '../training/widgets/training_anchor.dart';
import '../customers/presentation/kopesha_screen.dart';
import '../products/presentation/category_management_screen.dart';
import '../products/presentation/product_list_screen.dart';
import '../products/presentation/stock_list_screen.dart';
import '../products/presentation/stock_transfer_screen.dart';
import '../purchases/presentation/purchase_management_screen.dart';
import '../reports/presentation/profit_loss_screen.dart';
import '../reports/presentation/reports_screen.dart';
import '../sales/presentation/pos_screen.dart';
import '../sales/presentation/sales_history_screen.dart';
import '../services/presentation/service_management_screen.dart';
import '../settings/presentation/audit_log_screen.dart';
import '../settings/presentation/branch_management_screen.dart';
import '../settings/presentation/settings_screen.dart';
import '../shifts/presentation/shift_management_screen.dart';
import 'dashboard_screen.dart';
import '../../widgets/beautiful_icon.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  static final GlobalKey<ScaffoldState> scaffoldKey =
      GlobalKey<ScaffoldState>();
  static final GlobalKey<AppShellState> shellKey = GlobalKey<AppShellState>();

  static void selectIndex(int index) {
    shellKey.currentState?._selectIndex(index);
  }

  @override
  ConsumerState<AppShell> createState() => AppShellState();
}

class AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;
  String _trainingPromptUserId = '';

  final _destinations = const [
    _NavDestination(
      index: 5,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.space_dashboard_outlined,
        selectedIcon: Icons.space_dashboard_rounded,
        label: 'Dashboard',
      ),
    ),
    _NavDestination(
      index: 0,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.shopping_cart_checkout_outlined,
        selectedIcon: Icons.shopping_cart_checkout_rounded,
        label: 'POS',
      ),
    ),
    _NavDestination(
      index: 11,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.design_services_outlined,
        selectedIcon: Icons.design_services_rounded,
        label: 'Services',
      ),
    ),
    _NavDestination(
      index: 4,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        label: 'Sales',
      ),
    ),
    _NavDestination(
      index: 10,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.timer_outlined,
        selectedIcon: Icons.timer_rounded,
        label: 'Shifts',
      ),
    ),
    _NavDestination(
      index: 16,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.auto_awesome_outlined,
        selectedIcon: Icons.auto_awesome_rounded,
        label: 'Piki AI',
      ),
    ),
    _NavDestination(
      index: 1,
      section: _NavSection.inventory,
      item: _NavItem(
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
        label: 'Products',
      ),
    ),
    _NavDestination(
      index: 12,
      section: _NavSection.inventory,
      item: _NavItem(
        icon: Icons.fact_check_outlined,
        selectedIcon: Icons.fact_check_rounded,
        label: 'Stock List',
      ),
    ),
    _NavDestination(
      index: 2,
      section: _NavSection.inventory,
      item: _NavItem(
        icon: Icons.category_outlined,
        selectedIcon: Icons.category_rounded,
        label: 'Categories',
      ),
    ),
    _NavDestination(
      index: 3,
      section: _NavSection.inventory,
      item: _NavItem(
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping_rounded,
        label: 'Purchases',
      ),
    ),
    _NavDestination(
      index: 15,
      section: _NavSection.inventory,
      item: _NavItem(
        icon: Icons.swap_horiz_outlined,
        selectedIcon: Icons.swap_horiz_rounded,
        label: 'Transfers',
      ),
    ),
    _NavDestination(
      index: 8,
      section: _NavSection.reports,
      item: _NavItem(
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics_rounded,
        label: 'Reports',
      ),
    ),
    _NavDestination(
      index: 7,
      section: _NavSection.reports,
      item: _NavItem(
        icon: Icons.insert_chart_outlined,
        selectedIcon: Icons.insert_chart_rounded,
        label: 'P&L',
      ),
    ),
    _NavDestination(
      index: 6,
      section: _NavSection.reports,
      item: _NavItem(
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet_rounded,
        label: 'Kopesha',
      ),
    ),
    _NavDestination(
      index: 9,
      section: _NavSection.system,
      item: _NavItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: 'Settings',
      ),
    ),
    _NavDestination(
      index: 13,
      section: _NavSection.system,
      item: _NavItem(
        icon: Icons.store_mall_directory_outlined,
        selectedIcon: Icons.store_mall_directory_rounded,
        label: 'Branches',
      ),
    ),
    _NavDestination(
      index: 14,
      section: _NavSection.system,
      item: _NavItem(
        icon: Icons.manage_search_outlined,
        selectedIcon: Icons.manage_search_rounded,
        label: 'Audit Logs',
      ),
    ),
  ];

  static const _mobileBottomDefaults = [0, 11, 4, 5];

  List<int> get _allowedIndices {
    final indices = [...SessionService.currentNavigationIndices];
    if (RolePermissions.canManageOperationalSettings(
      SessionService.currentUserRole,
    )) {
      indices.addAll([13, 14]);
    }
    if (SessionService.canAccessFeature(UserAccessProfile.featureProducts) ||
        SessionService.canAccessFeature(UserAccessProfile.featurePurchases)) {
      indices.add(15);
    }
    return indices.where(_isAllowedBySubscription).toList();
  }

  bool _isAllowedBySubscription(int index) {
    final feature = UserAccessProfile.featureForNavigationIndex(index);
    return feature == null ||
        LicenseService.currentSnapshot.allowsFeature(feature);
  }

  int get _currentIndex => _allowedIndices.contains(_selectedIndex)
      ? _selectedIndex
      : _allowedIndices.first;

  List<_NavDestination> get _allowedDestinations => _destinations
      .where((destination) => _allowedIndices.contains(destination.index))
      .toList();

  List<_NavDestination> get _mobileBottomDestinations {
    final indices = _mobileBottomDefaults
        .where(_allowedIndices.contains)
        .toList(growable: false);
    if (indices.isEmpty) {
      return [_allowedDestinations.first];
    }
    return _destinations.where((d) => indices.contains(d.index)).toList();
  }

  List<_NavDestination> _getDestinationsBySection(_NavSection section) =>
      _allowedDestinations.where((d) => d.section == section).toList();

  String _sectionLabel(_NavSection section) {
    switch (section) {
      case _NavSection.main:
        return 'SHOP OPERATIONS';
      case _NavSection.inventory:
        return 'STOCK & SERVICES';
      case _NavSection.reports:
        return 'REPORTS & ANALYTICS';
      case _NavSection.system:
        return 'ADMINISTRATION';
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowTrainingPrompt();
    });
  }

  void _selectIndex(int index) {
    if (!_allowedIndices.contains(index) || _selectedIndex == index) {
      return;
    }
    setState(() => _selectedIndex = index);
  }

  Future<void> _maybeShowTrainingPrompt() async {
    final training = ref.read(trainingControllerProvider);
    await training.ensureLoadedForCurrentUser();
    if (!mounted) {
      return;
    }

    final userId = SessionService.currentUserId.trim();
    if (_trainingPromptUserId == userId || !training.shouldShowPrompt) {
      return;
    }
    _trainingPromptUserId = userId;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.school_outlined,
                        color: AppColors.primaryLight,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Training Hub',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Later',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(ctx, 'later'),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Guided tours only show modules for enabled features.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, 'later'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('Later'),
                    ),
                    const Spacer(),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, 'hub'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Modules'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, 'tour'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      child: const Text('Start'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == 'tour') {
      training.startFullTour();
      return;
    }

    if (action == 'hub') {
      training.dismissPrompt();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TrainingHubScreen()),
      );
      return;
    }

    training.dismissPrompt();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncControllerProvider);
    final isWide = MediaQuery.of(context).size.width > 800;
    final currentIndex = _currentIndex;
    final mobileBottomDestinations = _mobileBottomDestinations;
    final mobileSelectedIndex = mobileBottomDestinations.indexWhere(
      (destination) => destination.index == currentIndex,
    );

    return Scaffold(
      key: AppShell.scaffoldKey,
      drawer: !isWide ? _buildDrawer(context, currentIndex) : null,
      body: Row(
        children: [
          if (isWide)
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height,
                ),
                child: IntrinsicHeight(
                  child: TrainingAnchor(
                    id: 'shell.navigation',
                    child: NavigationRail(
                      backgroundColor: AppColors.surface,
                      indicatorColor: Colors.transparent,
                      selectedIndex: _allowedDestinations.indexWhere(
                        (d) => d.index == currentIndex,
                      ),
                      onDestinationSelected: (i) =>
                          _selectIndex(_allowedDestinations[i].index),
                      labelType: NavigationRailLabelType.all,
                      leading: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          AppColors.primary,
                                          AppColors.primaryLight,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(
                                      Icons.point_of_sale_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 10),
                            _BranchPill(
                              compact: true,
                              onTap: () => _selectIndex(13),
                            ),
                          ],
                        ),
                      ),
                      destinations: _allowedDestinations
                          .map(
                            (destination) => NavigationRailDestination(
                              icon: BeautifulIcon(
                                destination.item.icon,
                                color: AppColors.textSecondary,
                              ),
                              selectedIcon: BeautifulIcon(
                                destination.item.selectedIcon,
                                color: AppColors.primary,
                                withBackground: true,
                              ),
                              label: Text(destination.item.label),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
            ),
          if (isWide) const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(child: _buildScreen(currentIndex)),
        ],
      ),
      bottomNavigationBar: !isWide
          ? TrainingAnchor(
              id: 'shell.navigation',
              child: NavigationBar(
                backgroundColor: AppColors.surface,
                indicatorColor: Colors.transparent,
                selectedIndex: mobileSelectedIndex >= 0
                    ? mobileSelectedIndex
                    : 0,
                onDestinationSelected: (i) =>
                    _selectIndex(mobileBottomDestinations[i].index),
                destinations: mobileBottomDestinations
                    .map(
                      (destination) => NavigationDestination(
                        icon: BeautifulIcon(destination.item.icon),
                        selectedIcon: BeautifulIcon(
                          destination.item.selectedIcon,
                          color: AppColors.primary,
                          withBackground: true,
                        ),
                        label: destination.item.label,
                      ),
                    )
                    .toList(),
              ),
            )
          : null,
    );
  }

  Widget _buildDrawer(BuildContext context, int currentIndex) {
    final syncState = ref.watch(syncControllerProvider);

    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.point_of_sale_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    ShopSettings.shopName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${SessionService.currentUserName} • ${RolePermissions.label(SessionService.currentUserRole)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _BranchPill(
                    onTap: () {
                      Navigator.pop(context);
                      _selectIndex(13);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildDrawerBadge(
                        icon: Icons.verified,
                        label:
                            syncState.licenseSnapshot.accessStatus ==
                                LicenseAccessStatus.active
                            ? 'Active'
                            : 'License',
                        color:
                            syncState.licenseSnapshot.accessStatus ==
                                LicenseAccessStatus.active
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                      const SizedBox(width: 8),
                      _buildDrawerBadge(
                        icon: syncState.indicator == SyncIndicatorState.synced
                            ? Icons.cloud_done
                            : Icons.cloud_sync,
                        label: syncState.indicator == SyncIndicatorState.synced
                            ? 'Synced'
                            : 'Syncing',
                        color: syncState.indicator == SyncIndicatorState.synced
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final section in _NavSection.values)
                      ...(() {
                        final items = _getDestinationsBySection(section);
                        if (items.isEmpty) return <Widget>[];
                        return [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                            child: Text(
                              _sectionLabel(section),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          ...items.map(
                            (destination) => _DrawerItem(
                              icon: destination.item.icon,
                              selectedIcon: destination.item.selectedIcon,
                              label: destination.item.label,
                              isSelected: currentIndex == destination.index,
                              onTap: () {
                                setState(
                                  () => _selectedIndex = destination.index,
                                );
                                Navigator.pop(context);
                              },
                            ),
                          ),
                        ];
                      })(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Devis POS v1.0.0',
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreen(int index) {
    switch (index) {
      case 0:
        return const PosScreen();
      case 1:
        return const ProductListScreen();
      case 2:
        return const CategoryManagementScreen();
      case 3:
        return const PurchaseManagementScreen();
      case 4:
        return const SalesHistoryScreen();
      case 5:
        return const DashboardScreen();
      case 6:
        return const KopeshaScreen();
      case 7:
        return const ProfitLossScreen();
      case 8:
        return const ReportsScreen();
      case 9:
        return const SettingsScreen();
      case 10:
        return const ShiftManagementScreen();
      case 11:
        return const ServiceManagementScreen();
      case 12:
        return const StockListScreen();
      case 13:
        return const BranchManagementScreen();
      case 14:
        return const AuditLogScreen();
      case 15:
        return const StockTransferScreen();
      case 16:
        return const PikiAgentScreen();
      default:
        return const PosScreen();
    }
  }

  Widget _buildDrawerBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchPill extends StatelessWidget {
  final bool compact;
  final VoidCallback onTap;

  const _BranchPill({this.compact = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: BranchService.getBranches(activeOnly: true),
      builder: (context, snapshot) {
        final currentId = BranchService.currentBranchId;
        final branches = snapshot.data ?? const <Map<String, dynamic>>[];
        final current = branches.where((b) => b['id'] == currentId).firstOrNull;
        final name = (current?['name'] as String?)?.trim().isNotEmpty == true
            ? current!['name'] as String
            : 'Main Branch';
        return Material(
          color: compact
              ? AppColors.surfaceHighlight
              : Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 10,
                vertical: compact ? 5 : 7,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.store_mall_directory_rounded,
                    size: compact ? 13 : 15,
                    color: compact ? AppColors.primary : Colors.white,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      compact ? (current?['code'] as String? ?? 'MAIN') : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: compact ? AppColors.textPrimary : Colors.white,
                        fontSize: compact ? 10 : 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

enum _NavSection { main, inventory, reports, system }

class _NavDestination {
  final int index;
  final _NavSection section;
  final _NavItem item;

  const _NavDestination({
    required this.index,
    required this.section,
    required this.item,
  });
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                BeautifulIcon(
                  isSelected ? selectedIcon : icon,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  size: 22,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                    fontSize: 15,
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

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
