import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/session_service.dart';
import '../../core/services/shop_settings.dart';
import '../../core/services/sync_controller.dart';
import '../../core/theme/app_colors.dart';
import '../customers/presentation/kopesha_screen.dart';
import '../products/presentation/category_management_screen.dart';
import '../products/presentation/product_list_screen.dart';
import '../purchases/presentation/purchase_management_screen.dart';
import '../reports/presentation/profit_loss_screen.dart';
import '../reports/presentation/reports_screen.dart';
import '../sales/presentation/pos_screen.dart';
import '../sales/presentation/sales_history_screen.dart';
import '../settings/presentation/settings_screen.dart';
import 'dashboard_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  static final GlobalKey<ScaffoldState> scaffoldKey =
      GlobalKey<ScaffoldState>();

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  final _destinations = const [
    _NavDestination(
      index: 0,
      section: _NavSection.core,
      item: _NavItem(
        icon: Icons.shopping_cart_checkout_outlined,
        selectedIcon: Icons.shopping_cart_checkout_rounded,
        label: 'POS',
      ),
    ),
    _NavDestination(
      index: 1,
      section: _NavSection.core,
      item: _NavItem(
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
        label: 'Products',
      ),
    ),
    _NavDestination(
      index: 2,
      section: _NavSection.more,
      item: _NavItem(
        icon: Icons.category_outlined,
        selectedIcon: Icons.category_rounded,
        label: 'Categories',
      ),
    ),
    _NavDestination(
      index: 3,
      section: _NavSection.more,
      item: _NavItem(
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping_rounded,
        label: 'Purchases',
      ),
    ),
    _NavDestination(
      index: 4,
      section: _NavSection.core,
      item: _NavItem(
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        label: 'Sales',
      ),
    ),
    _NavDestination(
      index: 5,
      section: _NavSection.core,
      item: _NavItem(
        icon: Icons.space_dashboard_outlined,
        selectedIcon: Icons.space_dashboard_rounded,
        label: 'Dashboard',
      ),
    ),
    _NavDestination(
      index: 6,
      section: _NavSection.more,
      item: _NavItem(
        icon: Icons.account_balance_wallet_outlined,
        selectedIcon: Icons.account_balance_wallet_rounded,
        label: 'Kopesha',
      ),
    ),
    _NavDestination(
      index: 7,
      section: _NavSection.more,
      item: _NavItem(
        icon: Icons.insert_chart_outlined,
        selectedIcon: Icons.insert_chart_rounded,
        label: 'P&L',
      ),
    ),
    _NavDestination(
      index: 8,
      section: _NavSection.more,
      item: _NavItem(
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics_rounded,
        label: 'Reports',
      ),
    ),
    _NavDestination(
      index: 9,
      section: _NavSection.more,
      item: _NavItem(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings_rounded,
        label: 'Settings',
      ),
    ),
  ];

  static const _mobileBottomDefaults = [0, 1, 4, 5];

  List<int> get _allowedIndices =>
      RolePermissions.navigationIndicesForRole(SessionService.currentUserRole);

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

  List<_NavDestination> get _drawerCoreDestinations => _destinations
      .where(
        (destination) =>
            destination.section == _NavSection.core &&
            !_mobileBottomDestinations.any(
              (item) => item.index == destination.index,
            ) &&
            _allowedIndices.contains(destination.index),
      )
      .toList();

  List<_NavDestination> get _drawerMoreDestinations => _destinations
      .where(
        (destination) =>
            destination.section == _NavSection.more &&
            _allowedIndices.contains(destination.index),
      )
      .toList();

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
            NavigationRail(
              backgroundColor: AppColors.surface,
              selectedIndex: _allowedDestinations.indexWhere(
                (d) => d.index == currentIndex,
              ),
              onDestinationSelected: (i) => setState(
                () => _selectedIndex = _allowedDestinations[i].index,
              ),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.point_of_sale_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              destinations: _allowedDestinations
                  .map(
                    (destination) => NavigationRailDestination(
                      icon: Icon(
                        destination.item.icon,
                        color: AppColors.textSecondary,
                      ),
                      selectedIcon: Icon(
                        destination.item.selectedIcon,
                        color: AppColors.primary,
                      ),
                      label: Text(destination.item.label),
                    ),
                  )
                  .toList(),
            ),
          if (isWide) const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(child: _buildScreen(currentIndex)),
        ],
      ),
      bottomNavigationBar: !isWide
          ? NavigationBar(
              backgroundColor: AppColors.surface,
              selectedIndex: mobileSelectedIndex >= 0 ? mobileSelectedIndex : 0,
              onDestinationSelected: (i) => setState(
                () => _selectedIndex = mobileBottomDestinations[i].index,
              ),
              destinations: mobileBottomDestinations
                  .map(
                    (destination) => NavigationDestination(
                      icon: Icon(destination.item.icon),
                      selectedIcon: Icon(
                        destination.item.selectedIcon,
                        color: AppColors.primary,
                      ),
                      label: destination.item.label,
                    ),
                  )
                  .toList(),
            )
          : null,
    );
  }

  Widget _buildDrawer(BuildContext context, int currentIndex) {
    final mobileBottomDestinations = _mobileBottomDestinations;

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
                  Container(
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
                ],
              ),
            ),
            const SizedBox(height: 12),
            ...mobileBottomDestinations.map(
              (destination) => _DrawerItem(
                icon: destination.item.icon,
                selectedIcon: destination.item.selectedIcon,
                label: destination.item.label,
                isSelected: currentIndex == destination.index,
                onTap: () {
                  setState(() => _selectedIndex = destination.index);
                  Navigator.pop(context);
                },
              ),
            ),
            if (_drawerCoreDestinations.isNotEmpty ||
                _drawerMoreDestinations.isNotEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Divider(color: AppColors.border),
              ),
            if (_drawerCoreDestinations.isNotEmpty)
              ..._drawerCoreDestinations.map(
                (destination) => _DrawerItem(
                  icon: destination.item.icon,
                  selectedIcon: destination.item.selectedIcon,
                  label: destination.item.label,
                  isSelected: currentIndex == destination.index,
                  onTap: () {
                    setState(() => _selectedIndex = destination.index);
                    Navigator.pop(context);
                  },
                ),
              ),
            if (_drawerMoreDestinations.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 24, top: 8, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'REPORTS & MORE',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ..._drawerMoreDestinations.map(
              (destination) => _DrawerItem(
                icon: destination.item.icon,
                selectedIcon: destination.item.selectedIcon,
                label: destination.index == 7
                    ? 'Profit & Loss'
                    : destination.item.label,
                isSelected: currentIndex == destination.index,
                onTap: () {
                  setState(() => _selectedIndex = destination.index);
                  Navigator.pop(context);
                },
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Velora POS v1.0.0',
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
      default:
        return const PosScreen();
    }
  }
}

enum _NavSection { core, more }

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
                Icon(
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
