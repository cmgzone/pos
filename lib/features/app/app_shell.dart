import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/database_service.dart';
import '../../core/services/app_version_service.dart';
import '../../core/services/device_notification_service.dart';
import '../../core/services/external_app_launcher.dart';
import '../../core/services/session_service.dart';
import '../../core/services/shop_settings.dart';
import '../../core/services/storefront_brand_service.dart';
import '../../core/services/branch_service.dart';
import '../../core/utils/error_messages.dart';
import '../../core/services/sync_controller.dart';
import '../../core/services/sync_settings_service.dart';
import '../../core/services/sync_service.dart';
import '../../core/services/cloud_auth_service.dart';
import '../../core/services/local_business_reset_service.dart';
import '../../core/services/license_service.dart';
import '../../core/services/platform_notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../agent/data/piki_models.dart';
import '../agent/data/piki_proactive_service.dart';
import '../agent/data/piki_provider.dart';
import '../agent/presentation/piki_agent_screen.dart';
import '../training/application/training_controller.dart';
import '../training/presentation/training_hub_screen.dart';
import '../training/widgets/training_anchor.dart';
import '../customers/presentation/contacts_screen.dart';
import '../customers/presentation/customer_groups_screen.dart';
import '../customers/presentation/kopesha_screen.dart';
import '../invoices/presentation/customer_invoices_screen.dart';
import '../loyalty/presentation/loyalty_screen.dart';
import '../marketing/presentation/sms_campaign_screen.dart';
import '../gift_cards/presentation/gift_card_screen.dart';
import '../promotions/presentation/promotion_screen.dart';
import '../products/presentation/catalog_orders_screen.dart';
import '../products/presentation/category_management_screen.dart';
import '../products/presentation/product_list_screen.dart';
import '../products/presentation/serial_tracking_screen.dart';
import '../products/presentation/stock_list_screen.dart';
import '../products/presentation/stocktake_screen.dart';
import '../products/presentation/stock_transfer_screen.dart';
import '../products/presentation/wastage_screen.dart';
import '../restaurant/presentation/restaurant_screen.dart';
import '../attendance/presentation/attendance_screen.dart';
import '../delivery/presentation/delivery_screen.dart';
import '../purchases/presentation/purchase_management_screen.dart';
import '../purchases/presentation/purchase_approval_screen.dart';
import '../reports/presentation/profit_loss_screen.dart';
import '../reports/presentation/reports_screen.dart';
import '../reports/presentation/advanced_bi_screen.dart';
import '../sales/presentation/pos_screen.dart';
import '../sales/presentation/quotations_screen.dart';
import '../sales/presentation/sales_history_screen.dart';
import '../services/presentation/service_management_screen.dart';
import '../settings/presentation/audit_log_screen.dart';
import '../settings/presentation/branch_management_screen.dart';
import '../settings/presentation/custom_roles_screen.dart';
import '../settings/presentation/settings_screen.dart';
import '../settings/presentation/subscription_plans_section.dart';
import '../shifts/presentation/shift_management_screen.dart';
import '../storefront/presentation/online_store_screen.dart';
import '../auth/data/auth_password_service.dart';
import '../auth/data/user_repository.dart';
import 'dashboard_screen.dart';
import '../../widgets/beautiful_icon.dart';
import '../../widgets/piki_mark.dart';
import '../../widgets/stitch_kit.dart';

class AppShell extends ConsumerStatefulWidget {
  final int initialIndex;
  final bool runStartupTasks;

  const AppShell({
    super.key,
    this.initialIndex = defaultInitialIndex,
    this.runStartupTasks = true,
  });

  static const int defaultInitialIndex = 35;
  static final GlobalKey<ScaffoldState> scaffoldKey =
      GlobalKey<ScaffoldState>();
  static final GlobalKey<AppShellState> shellKey = GlobalKey<AppShellState>();

  static void selectIndex(int index) {
    shellKey.currentState?._selectIndex(index);
  }

  static void showNotificationsSheet(BuildContext context) {
    shellKey.currentState?._showNotificationsSheet();
  }

  @override
  ConsumerState<AppShell> createState() => AppShellState();
}

class AppShellState extends ConsumerState<AppShell> {
  late int _selectedIndex;
  final List<int> _navigationHistory = <int>[];
  String _trainingPromptUserId = '';
  bool _subscriptionPromptShown = false;
  bool _setupPromptShown = false;
  // Retained for the legacy adaptive shell kept below the module-launcher
  // branch; the active navigation experience never renders that rail.
  bool _desktopRailCollapsed = false;
  Set<String> _seenNotificationIds = const <String>{};
  Set<String> _deviceNotifiedIds = const <String>{};
  bool _deviceNotificationBusy = false;
  bool _appUpdatePromptScheduled = false;
  OnlineStoreSection _onlineStoreInitialSection = OnlineStoreSection.overview;
  int _onlineStoreNavigationRevision = 0;
  AppVersionInfo? _appVersionInfo;
  List<PlatformNotification> _platformNotifications =
      const <PlatformNotification>[];

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
      index: 36,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.storefront_outlined,
        selectedIcon: Icons.storefront_rounded,
        label: 'Online Store',
      ),
    ),
    _NavDestination(
      index: 17,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.assignment_outlined,
        selectedIcon: Icons.assignment_rounded,
        label: 'Orders',
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
      index: 19,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.request_quote_outlined,
        selectedIcon: Icons.request_quote_rounded,
        label: 'Invoices',
      ),
    ),
    _NavDestination(
      index: 20,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.format_quote_outlined,
        selectedIcon: Icons.format_quote_rounded,
        label: 'Quotations',
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
      index: 25,
      section: _NavSection.inventory,
      item: _NavItem(
        icon: Icons.qr_code_2_outlined,
        selectedIcon: Icons.qr_code_2_rounded,
        label: 'Serials',
      ),
    ),
    _NavDestination(
      index: 26,
      section: _NavSection.inventory,
      item: _NavItem(
        icon: Icons.playlist_add_check_outlined,
        selectedIcon: Icons.playlist_add_check_rounded,
        label: 'Stocktake',
      ),
    ),
    _NavDestination(
      index: 28,
      section: _NavSection.inventory,
      item: _NavItem(
        icon: Icons.delete_sweep_outlined,
        selectedIcon: Icons.delete_sweep_rounded,
        label: 'Wastage',
      ),
    ),
    _NavDestination(
      index: 29,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.restaurant_outlined,
        selectedIcon: Icons.restaurant_rounded,
        label: 'Restaurant',
      ),
    ),
    _NavDestination(
      index: 30,
      section: _NavSection.main,
      item: _NavItem(
        icon: Icons.timer_outlined,
        selectedIcon: Icons.timer_rounded,
        label: 'Attendance',
      ),
    ),
    _NavDestination(
      index: 31,
      section: _NavSection.reports,
      item: _NavItem(
        icon: Icons.groups_outlined,
        selectedIcon: Icons.groups_rounded,
        label: 'Customer Groups',
      ),
    ),
    _NavDestination(
      index: 32,
      section: _NavSection.inventory,
      item: _NavItem(
        icon: Icons.approval_outlined,
        selectedIcon: Icons.approval_rounded,
        label: 'Approvals',
      ),
    ),
    _NavDestination(
      index: 33,
      section: _NavSection.inventory,
      item: _NavItem(
        icon: Icons.local_shipping_outlined,
        selectedIcon: Icons.local_shipping_rounded,
        label: 'Delivery',
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
      index: 34,
      section: _NavSection.reports,
      item: _NavItem(
        icon: Icons.query_stats_outlined,
        selectedIcon: Icons.query_stats_rounded,
        label: 'BI Dashboard',
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
      index: 18,
      section: _NavSection.reports,
      item: _NavItem(
        icon: Icons.contacts_outlined,
        selectedIcon: Icons.contacts_rounded,
        label: 'Contacts',
      ),
    ),
    _NavDestination(
      index: 27,
      section: _NavSection.reports,
      item: _NavItem(
        icon: Icons.sms_outlined,
        selectedIcon: Icons.sms_rounded,
        label: 'Campaigns',
      ),
    ),
    _NavDestination(
      index: 21,
      section: _NavSection.reports,
      item: _NavItem(
        icon: Icons.loyalty_outlined,
        selectedIcon: Icons.loyalty_rounded,
        label: 'Loyalty',
      ),
    ),
    _NavDestination(
      index: 22,
      section: _NavSection.reports,
      item: _NavItem(
        icon: Icons.card_giftcard_outlined,
        selectedIcon: Icons.card_giftcard_rounded,
        label: 'Gift Cards',
      ),
    ),
    _NavDestination(
      index: 23,
      section: _NavSection.reports,
      item: _NavItem(
        icon: Icons.local_offer_outlined,
        selectedIcon: Icons.local_offer_rounded,
        label: 'Promos',
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
    _NavDestination(
      index: 24,
      section: _NavSection.system,
      item: _NavItem(
        icon: Icons.admin_panel_settings_outlined,
        selectedIcon: Icons.admin_panel_settings_rounded,
        label: 'Roles',
      ),
    ),
  ];

  static const _mobileBottomDefaults = [5, 0, 1, 17];
  static const _fallbackNavigationIndex = 9;
  static const _posIndex = 0;
  static const _servicesIndex = 11;
  static const _restaurantIndex = 29;

  bool get _isServiceOnlyAccount =>
      !SessionService.canUseProductPos && SessionService.canUseServicePos;

  bool get _isRestaurantAccount => SessionService.isRestaurantMode;

  // The module launcher replaces persistent side navigation. Keeping this as
  // a getter leaves room for an embedded/kiosk shell to override later.
  bool get _usesModuleLauncherNavigation => true;

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
    if (SessionService.canUseProductPos &&
        (SessionService.canAccessFeature(UserAccessProfile.featurePos) ||
            SessionService.canAccessFeature(UserAccessProfile.featureSales) ||
            SessionService.canAccessFeature(
              UserAccessProfile.featureProducts,
            ))) {
      indices.add(17);
    }
    if (SessionService.canAccessFeature(UserAccessProfile.featureProducts) ||
        SessionService.canAccessFeature(UserAccessProfile.featurePos) ||
        SessionService.canAccessFeature(UserAccessProfile.featureSales) ||
        SessionService.canAccessFeature(UserAccessProfile.featureReports)) {
      indices.add(36);
    }
    if (SessionService.canAccessFeature(UserAccessProfile.featureSales)) {
      indices.add(19);
    }
    if (SessionService.canAccessFeature(UserAccessProfile.featureSales) &&
        ShopSettings.quotationsEnabled) {
      indices.add(20);
    }
    if (SessionService.canAccessFeature(UserAccessProfile.featureKopesha) ||
        SessionService.canAccessFeature(UserAccessProfile.featurePurchases)) {
      indices.add(18);
    }
    final role = RolePermissions.normalizeRole(SessionService.currentUserRole);
    if (SessionService.canAccessFeature(UserAccessProfile.featureReports) &&
        (role == RolePermissions.admin || role == RolePermissions.manager)) {
      indices.add(34);
    }
    indices.add(35);
    final allowed = indices
        .where(
          (index) =>
              index != 24 ||
              RolePermissions.canManageUsers(SessionService.currentUserRole),
        )
        .where(_isAllowedForCurrentSellingMode)
        .where(_isAllowedBySubscription)
        .toSet()
        .toList();
    if (allowed.isEmpty) {
      return const [_fallbackNavigationIndex];
    }
    return allowed;
  }

  bool _isAllowedForCurrentSellingMode(int index) {
    if (_isRestaurantAccount &&
        (index == _posIndex || index == _servicesIndex)) {
      return false;
    }
    if (_isServiceOnlyAccount && index == _posIndex) {
      return false;
    }
    return true;
  }

  bool _isAllowedBySubscription(int index) {
    final feature = UserAccessProfile.featureForNavigationIndex(index);
    return feature == null ||
        LicenseService.currentSnapshot.allowsFeature(feature);
  }

  int _normalizeNavigationIndex(int index) {
    if (index == 17) {
      return 36;
    }
    if (_isRestaurantAccount && index == _posIndex) {
      return _restaurantIndex;
    }
    if (_isServiceOnlyAccount && index == _posIndex) {
      return _servicesIndex;
    }
    return index;
  }

  int _initialIndexForCurrentAccount(int index) {
    if (_isRestaurantAccount && index == _posIndex) {
      return _restaurantIndex;
    }
    if (_isServiceOnlyAccount && index == _posIndex) {
      return _servicesIndex;
    }
    return _normalizeNavigationIndex(index);
  }

  int get _currentIndex {
    final normalized = _normalizeNavigationIndex(_selectedIndex);
    return _allowedIndices.contains(normalized)
        ? normalized
        : _allowedIndices.first;
  }

  List<_NavDestination> get _allowedDestinations => _destinations
      .where((destination) => _allowedIndices.contains(destination.index))
      .toList();

  List<_BusinessModule> get _businessModules {
    final allowed = _allowedDestinations;
    const sharedIndexes = <int>[
      5,
      36,
      1,
      12,
      2,
      3,
      15,
      25,
      26,
      28,
      32,
      8,
      34,
      7,
      6,
      27,
      21,
      22,
      23,
      31,
      9,
      13,
      14,
      24,
      30,
      16,
    ];

    List<_NavDestination> entriesFor(List<int> indexes) => allowed
        .where((destination) => indexes.contains(destination.index))
        .toList(growable: false);
    List<int> indexesForBusiness(List<int> coreIndexes) => [
      ...coreIndexes,
      ...sharedIndexes,
    ];

    final modules = <_BusinessModule>[];
    void addModule({
      required String id,
      required String title,
      required String subtitle,
      required IconData icon,
      required Color accent,
      required List<int> indexes,
      required List<int> coreIndexes,
      required bool enabled,
      int? directDestinationIndex,
      String? readinessLabel,
    }) {
      final destinations = entriesFor(indexes);
      if (enabled && destinations.isNotEmpty) {
        modules.add(
          _BusinessModule(
            id: id,
            title: title,
            subtitle: subtitle,
            icon: icon,
            accent: accent,
            destinations: destinations,
            coreDestinationIndexes: coreIndexes,
            directDestinationIndex: directDestinationIndex,
            readinessLabel: readinessLabel,
          ),
        );
      }
    }

    addModule(
      id: 'retail_pos',
      title: 'Retail POS',
      subtitle: 'Checkout, online store, sales, and customer balances.',
      icon: Icons.point_of_sale_rounded,
      accent: Theme.of(context).colorScheme.primary,
      indexes: indexesForBusiness(const [0, 36, 4, 19, 20, 6, 18, 10]),
      coreIndexes: const [0, 36, 4, 19, 20, 6, 18, 10],
      enabled: SessionService.canUseProductPos,
    );
    addModule(
      id: 'services',
      title: 'Services',
      subtitle: 'Service desk, queues, quotes, and customer work.',
      icon: Icons.design_services_rounded,
      accent: Theme.of(context).colorScheme.primary,
      indexes: indexesForBusiness(const [11, 36, 4, 19, 20, 18, 10]),
      coreIndexes: const [11, 36, 4, 19, 20, 18, 10],
      enabled: SessionService.canUseServicePos,
    );
    addModule(
      id: 'restaurant',
      title: 'Restaurant',
      subtitle: 'Tables, kitchen flow, orders, and delivery.',
      icon: Icons.restaurant_rounded,
      accent: Theme.of(context).colorScheme.primary,
      indexes: const [29],
      coreIndexes: const [29],
      directDestinationIndex: 29,
      readinessLabel: 'Floor, kitchen & bills ready',
      enabled: SessionService.canAccessFeature(
        UserAccessProfile.featureRestaurantMode,
      ),
    );
    if (modules.isEmpty && allowed.isNotEmpty) {
      modules.add(
        _BusinessModule(
          id: 'workspace',
          title: 'My workspace',
          subtitle: 'Modules available to this account.',
          icon: Icons.apps_rounded,
          accent: Theme.of(context).colorScheme.primary,
          destinations: allowed,
          coreDestinationIndexes: allowed
              .map((destination) => destination.index)
              .toList(growable: false),
        ),
      );
    }
    return modules;
  }

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
    if (widget.initialIndex == 17) {
      _onlineStoreInitialSection = OnlineStoreSection.orders;
    }
    _selectedIndex = _initialIndexForCurrentAccount(widget.initialIndex);
    if (widget.runStartupTasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSeenNotifications();
        _loadDeviceNotificationIds();
        _loadAppVersionNotice();
        _loadPlatformNotifications();
        _showStartupPrompts();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      if (widget.initialIndex == 17) {
        _onlineStoreInitialSection = OnlineStoreSection.orders;
      }
      _selectedIndex = _initialIndexForCurrentAccount(widget.initialIndex);
      _navigationHistory.clear();
    }
  }

  void _selectIndex(int index) {
    if (index == 17) {
      _onlineStoreInitialSection = OnlineStoreSection.orders;
      _onlineStoreNavigationRevision += 1;
    } else if (index == 36) {
      _onlineStoreInitialSection = OnlineStoreSection.overview;
      _onlineStoreNavigationRevision += 1;
    }
    final target = _normalizeNavigationIndex(index);
    final current = _currentIndex;
    if (!_allowedIndices.contains(target)) {
      return;
    }
    if (current == target) {
      setState(() {});
      return;
    }
    _navigationHistory.add(current);
    if (_navigationHistory.length > 24) {
      _navigationHistory.removeAt(0);
    }
    setState(() => _selectedIndex = target);
  }

  bool _goBack() {
    final allowed = _allowedIndices.toSet();
    while (_navigationHistory.isNotEmpty) {
      final previous = _navigationHistory.removeLast();
      if (previous != _currentIndex && allowed.contains(previous)) {
        setState(() => _selectedIndex = previous);
        return true;
      }
    }
    if (_currentIndex != 35 && allowed.contains(35)) {
      setState(() => _selectedIndex = 35);
      return true;
    }
    return false;
  }

  bool get _hasBackDestination {
    final allowed = _allowedIndices.toSet();
    return _navigationHistory.any(
      (index) => index != _currentIndex && allowed.contains(index),
    );
  }

  String _moduleLabelForIndex(int index) {
    for (final destination in _destinations) {
      if (destination.index == index) {
        return destination.item.label;
      }
    }
    return 'Module';
  }

  Future<void> _showNotificationsSheet() async {
    await _loadPlatformNotifications();
    if (!mounted) return;
    final syncState = ref.read(syncControllerProvider);
    final List<PikiProactiveInsight> pikiInsights =
        _canLoadPikiNotifications(syncState)
        ? ref.read(pikiProactiveInsightsProvider).valueOrNull ??
              const <PikiProactiveInsight>[]
        : const <PikiProactiveInsight>[];
    _showNotifications(syncState, pikiInsights: pikiInsights);
  }

  bool _canLoadPikiNotifications(SyncState syncState) {
    final license = syncState.licenseSnapshot;
    return SessionService.canAccessFeature(
          UserAccessProfile.featureProactivePiki,
        ) &&
        (license.accessStatus == LicenseAccessStatus.active ||
            license.accessStatus == LicenseAccessStatus.grace) &&
        license.entitlements.features.contains(
          UserAccessProfile.featureProactivePiki,
        );
  }

  List<_AppNotification> _buildNotifications(
    SyncState syncState, {
    List<PikiProactiveInsight> pikiInsights = const [],
  }) {
    final notifications = <_AppNotification>[];
    final license = syncState.licenseSnapshot;
    final appVersion = _appVersionInfo;

    for (final notification in _platformNotifications) {
      notifications.add(
        _AppNotification(
          id: 'platform_${notification.id}',
          icon: _platformNotificationIcon(notification.severity),
          color: _platformNotificationColor(notification.severity),
          title: notification.title,
          message: notification.message,
          severity: notification.severity == 'critical'
              ? _AppNotificationSeverity.critical
              : notification.severity == 'warning'
              ? _AppNotificationSeverity.warning
              : _AppNotificationSeverity.info,
          deviceNotify: notification.severity == 'critical',
        ),
      );
    }

    if (appVersion?.hasUpdate == true) {
      notifications.add(
        _AppNotification(
          id: 'app_update_${appVersion!.latestVersion}',
          icon: Icons.system_update_alt_outlined,
          color: Theme.of(context).colorScheme.primary,
          title: 'App update available',
          message: appVersion.releaseNotes.trim().isEmpty
              ? 'Version ${appVersion.latestVersion} is ready to install.'
              : appVersion.releaseNotes,
          opensUpdate: true,
          severity: appVersion.isRequiredUpdate
              ? _AppNotificationSeverity.critical
              : _AppNotificationSeverity.info,
          deviceNotify: appVersion.isRequiredUpdate,
        ),
      );
    }

    switch (license.accessStatus) {
      case LicenseAccessStatus.grace:
        notifications.add(
          _AppNotification(
            icon: Icons.schedule_outlined,
            color: AppColors.warning,
            title: 'Subscription renewal due',
            message:
                license.detail ??
                'Renew the subscription before the grace period ends.',
            destinationIndex: 9,
            severity: _AppNotificationSeverity.warning,
          ),
        );
      case LicenseAccessStatus.expired:
        notifications.add(
          _AppNotification(
            icon: Icons.lock_clock_outlined,
            color: AppColors.error,
            title: 'Subscription expired',
            message:
                license.detail ??
                'Renew the subscription to record sales and make changes.',
            destinationIndex: 9,
            severity: _AppNotificationSeverity.critical,
            deviceNotify: true,
          ),
        );
      case LicenseAccessStatus.invalid:
        notifications.add(
          _AppNotification(
            icon: Icons.gpp_bad_outlined,
            color: AppColors.error,
            title: 'License needs attention',
            message:
                license.detail ??
                'Reconnect this device to refresh the subscription license.',
            destinationIndex: 9,
            severity: _AppNotificationSeverity.critical,
            deviceNotify: true,
          ),
        );
      case LicenseAccessStatus.localOnly:
      case LicenseAccessStatus.active:
        break;
    }

    if (syncState.isConfigured && !syncState.isOnline) {
      notifications.add(
        const _AppNotification(
          icon: Icons.cloud_off_outlined,
          color: AppColors.warning,
          title: 'Device is offline',
          message:
              'Changes stay on this device until the internet connection returns.',
          destinationIndex: 9,
        ),
      );
    } else if (syncState.lastError?.trim().isNotEmpty == true) {
      notifications.add(
        _AppNotification(
          icon: Icons.sync_problem_outlined,
          color: AppColors.error,
          title: 'Cloud sync failed',
          message: syncState.lastError!,
          destinationIndex: 9,
          severity: _AppNotificationSeverity.critical,
          deviceNotify: true,
        ),
      );
    }

    final issueCount = syncState.conflictCount + syncState.errorCount;
    if (issueCount > 0) {
      notifications.add(
        _AppNotification(
          icon: Icons.warning_amber_rounded,
          color: AppColors.error,
          title: 'Sync issues need review',
          message:
              '$issueCount sync issue${issueCount == 1 ? '' : 's'} need attention in Settings.',
          destinationIndex: 9,
          severity: _AppNotificationSeverity.critical,
          deviceNotify: true,
        ),
      );
    }
    if (syncState.pendingChanges > 0) {
      notifications.add(
        _AppNotification(
          icon: Icons.cloud_upload_outlined,
          color: AppColors.warning,
          title: 'Changes waiting to sync',
          message:
              '${syncState.pendingChanges} local change${syncState.pendingChanges == 1 ? '' : 's'} still need to upload.',
          destinationIndex: 9,
        ),
      );
    }
    if (syncState.remoteChanges > 0) {
      notifications.add(
        _AppNotification(
          icon: Icons.cloud_download_outlined,
          color: Theme.of(context).colorScheme.primary,
          title: 'Cloud updates available',
          message:
              '${syncState.remoteChanges} cloud update${syncState.remoteChanges == 1 ? '' : 's'} are ready to download.',
          destinationIndex: 9,
        ),
      );
    }
    for (final insight in pikiInsights) {
      notifications.add(
        _AppNotification(
          icon: _pikiInsightIcon(insight.kind),
          color: _pikiSeverityColor(insight.severity),
          title: 'Piki: ${insight.title}',
          message: insight.body,
          destinationIndex: 16,
          pikiInsight: insight,
          severity: insight.severity.toLowerCase() == 'high'
              ? _AppNotificationSeverity.critical
              : _AppNotificationSeverity.warning,
          deviceNotify: insight.severity.toLowerCase() == 'high',
        ),
      );
    }
    return notifications;
  }

  Future<void> _loadPlatformNotifications() async {
    final items = await PlatformNotificationService.fetchNotifications();
    if (!mounted) return;
    setState(() => _platformNotifications = items);
  }

  Color _platformNotificationColor(String severity) {
    switch (severity) {
      case 'critical':
        return AppColors.error;
      case 'warning':
        return AppColors.warning;
      case 'success':
        return AppColors.success;
      default:
        return AppColors.primaryLight;
    }
  }

  IconData _platformNotificationIcon(String severity) {
    switch (severity) {
      case 'critical':
        return Icons.priority_high_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'success':
        return Icons.check_circle_outline_rounded;
      default:
        return Icons.campaign_outlined;
    }
  }

  Color _pikiSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return AppColors.error;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.primaryLight;
    }
  }

  Future<void> _loadSeenNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _seenNotificationIds =
          prefs.getStringList('seen_app_notifications_v1')?.toSet() ??
          const <String>{};
    });
  }

  Future<void> _loadDeviceNotificationIds() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
      return;
    }
    setState(() {
      _deviceNotifiedIds =
          prefs
              .getStringList('device_notified_app_notifications_v1')
              ?.toSet() ??
          const <String>{};
    });
  }

  Future<void> _loadAppVersionNotice() async {
    try {
      final info = await AppVersionService.fetch();
      if (mounted) {
        setState(() => _appVersionInfo = info);
        if (info?.hasUpdate == true) {
          _queueAppUpdatePrompt(info!);
        }
      }
    } catch (_) {
      // Update checks should never block app startup.
    }
  }

  void _queueAppUpdatePrompt(AppVersionInfo info) {
    if (_appUpdatePromptScheduled) {
      return;
    }
    _appUpdatePromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final dismissedVersion = prefs.getString(
        'dismissed_app_update_version_v1',
      );
      if (!info.isRequiredUpdate && dismissedVersion == info.latestVersion) {
        return;
      }
      if (!mounted) {
        return;
      }
      await _showAppUpdateDialog(info);
    });
  }

  Future<void> _showAppUpdateDialog(AppVersionInfo info) async {
    final theme = Theme.of(context);
    final title = info.isRequiredUpdate ? 'Update required' : 'Update Piki POS';
    final message = info.releaseNotes.trim().isEmpty
        ? 'Version ${info.latestVersion} is ready to install.'
        : info.releaseNotes.trim();
    await showDialog<void>(
      context: context,
      barrierDismissible: !info.isRequiredUpdate,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(
            Icons.system_update_alt_rounded,
            color: info.isRequiredUpdate ? AppColors.error : AppColors.primary,
          ),
          title: Text(title),
          content: Text(message),
          actions: [
            if (!info.isRequiredUpdate)
              TextButton(
                onPressed: () async {
                  final navigator = Navigator.of(dialogContext);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(
                    'dismissed_app_update_version_v1',
                    info.latestVersion,
                  );
                  if (navigator.canPop()) {
                    navigator.pop();
                  }
                },
                child: const Text('Later'),
              ),
            FilledButton.icon(
              onPressed: () async {
                final navigator = Navigator.of(dialogContext);
                final opened = await _openAppUpdateDownload(info);
                if (opened && !info.isRequiredUpdate && navigator.canPop()) {
                  navigator.pop();
                }
              },
              icon: const Icon(Icons.download_rounded),
              label: Text(
                info.platform == 'android' ? 'Download APK' : 'Download update',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: info.isRequiredUpdate
                    ? AppColors.error
                    : theme.colorScheme.primary,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _openAppUpdateDownload([AppVersionInfo? info]) async {
    final release = info ?? _appVersionInfo;
    final uri = release?.downloadUri;
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Update download link is not ready.')),
        );
      }
      return false;
    }
    final opened = await ExternalAppLauncher.launch(uri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the update download.')),
      );
    }
    return opened;
  }

  Future<void> _markNotificationsSeen(
    List<_AppNotification> notifications,
  ) async {
    final ids = notifications.map((item) => item.id).toSet();
    if (ids.isEmpty) {
      return;
    }
    final next = {..._seenNotificationIds, ...ids};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'seen_app_notifications_v1',
      next.take(200).toList(),
    );
    if (mounted) {
      setState(() => _seenNotificationIds = next);
    }
  }

  int _unseenNotificationCount(List<_AppNotification> notifications) {
    return notifications
        .where(
          (notification) => !_seenNotificationIds.contains(notification.id),
        )
        .length;
  }

  void _queueDeviceNotifications(List<_AppNotification> notifications) {
    final pending = notifications
        .where(
          (notification) =>
              notification.deviceNotify &&
              !_deviceNotifiedIds.contains(notification.id) &&
              !_seenNotificationIds.contains(notification.id),
        )
        .toList(growable: false);
    if (pending.isEmpty || _deviceNotificationBusy) {
      return;
    }
    _deviceNotificationBusy = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sendDeviceNotifications(pending);
    });
  }

  Future<void> _sendDeviceNotifications(
    List<_AppNotification> notifications,
  ) async {
    if (notifications.isEmpty) {
      _deviceNotificationBusy = false;
      return;
    }
    await DeviceNotificationService.requestPermissionIfNeeded();
    final nextIds = {..._deviceNotifiedIds};
    for (final notification in notifications.take(3)) {
      await DeviceNotificationService.showImportant(
        id: notification.id,
        title: notification.title,
        body: notification.message,
      );
      nextIds.add(notification.id);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'device_notified_app_notifications_v1',
      nextIds.take(200).toList(),
    );
    _deviceNotificationBusy = false;
    if (mounted) {
      setState(() => _deviceNotifiedIds = nextIds);
    }
  }

  IconData _pikiInsightIcon(String kind) {
    switch (kind) {
      case 'low_stock':
        return Icons.inventory_2_outlined;
      case 'expiry_risk':
        return Icons.event_busy_outlined;
      case 'sales_drop':
        return Icons.trending_down_outlined;
      case 'open_shift':
        return Icons.timer_outlined;
      case 'customer_debt':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.auto_awesome_outlined;
    }
  }

  Future<void> _refreshPikiNotifications() async {
    final syncState = ref.read(syncControllerProvider);
    final insights = await PikiProactiveService.fetchInsights(
      forceRefresh: syncState.isOnline,
      allowNetwork: syncState.isOnline,
    );
    ref.invalidate(pikiProactiveInsightsProvider);
    if (!mounted) {
      return;
    }
    await _showNotifications(syncState, pikiInsights: insights);
  }

  void _showConnectivityNotification(SyncState? previous, SyncState next) {
    if (!mounted ||
        previous == null ||
        !next.isConfigured ||
        previous.isOnline == next.isOnline) {
      return;
    }
    final message = next.isOnline
        ? next.pendingChanges > 0
              ? 'Back online. Syncing ${next.pendingChanges} saved change${next.pendingChanges == 1 ? '' : 's'}.'
              : 'Back online. Cloud sync is available again.'
        : 'You are offline. Changes stay on this device and will sync when the connection returns.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: next.isOnline
              ? AppColors.success
              : AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _openNotification(
    BuildContext sheetContext,
    _AppNotification notification,
  ) {
    Navigator.pop(sheetContext);
    final insight = notification.pikiInsight;
    if (insight != null) {
      final tool = insight.action['tool']?.toString().replaceAll('_', ' ');
      ref.read(pikiInsightProvider.notifier).state = PikiInsightData(
        text: '${insight.title}: ${insight.body}',
        details: [
          insight.body,
          if (tool != null && tool.isNotEmpty) 'Suggested Piki tool: $tool',
        ],
      );
    }
    final destinationIndex = notification.destinationIndex;
    if (destinationIndex != null) {
      _selectIndex(destinationIndex);
      return;
    }
    if (notification.opensUpdate) {
      _openAppUpdateDownload();
    }
  }

  Future<void> _showNotifications(
    SyncState syncState, {
    List<PikiProactiveInsight> pikiInsights = const [],
  }) async {
    final notifications = _buildNotifications(
      syncState,
      pikiInsights: pikiInsights,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final sheetTheme = Theme.of(sheetContext);
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Notifications',
                          style: sheetTheme.textTheme.titleLarge,
                        ),
                      ),
                      if (notifications.isNotEmpty)
                        TextButton(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _selectIndex(9);
                          },
                          child: const Text('Open Settings'),
                        ),
                      if (_canLoadPikiNotifications(syncState) &&
                          syncState.isOnline)
                        IconButton(
                          tooltip: 'Refresh Piki alerts',
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _refreshPikiNotifications();
                          },
                          icon: const Icon(Icons.auto_awesome_outlined),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (notifications.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.notifications_none_rounded,
                              size: 36,
                              color: AppColors.success,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'You are all caught up.',
                              style: sheetTheme.textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: notifications.length,
                        separatorBuilder: (_, _) => Divider(
                          color: sheetTheme.colorScheme.outline,
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final notification = notifications[index];
                          return ListTile(
                            onTap: !notification.canOpen
                                ? null
                                : () => _openNotification(
                                    sheetContext,
                                    notification,
                                  ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 6,
                            ),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: notification.color.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                notification.icon,
                                color: notification.color,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              notification.title,
                              style: sheetTheme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(notification.message),
                            trailing: !notification.canOpen
                                ? null
                                : const Icon(Icons.chevron_right_rounded),
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
    await _markNotificationsSeen(notifications);
  }

  Widget _buildNotificationIcon(
    List<_AppNotification> notifications, {
    Color? color,
  }) {
    final theme = Theme.of(context);
    final count = _unseenNotificationCount(notifications);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          count == 0
              ? Icons.notifications_none_rounded
              : Icons.notifications_rounded,
          color: color,
        ),
        if (count > 0)
          Positioned(
            right: -8,
            top: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                count > 9 ? '9+' : '$count',
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showStartupPrompts() async {
    await _maybeShowSubscriptionPrompt();
    if (mounted) {
      await _maybeShowSetupChecklistPrompt();
    }
    if (mounted) {
      await _maybeShowTrainingPrompt();
    }
  }

  Future<void> _maybeShowSetupChecklistPrompt() async {
    if (_setupPromptShown ||
        !RolePermissions.canManageOperationalSettings(
          SessionService.currentUserRole,
        )) {
      return;
    }
    _setupPromptShown = true;
    await SyncSettingsService.init();
    final businessKey = SyncSettingsService.localBusinessId.isEmpty
        ? SessionService.currentUserId
        : SyncSettingsService.localBusinessId;
    final prefs = await SharedPreferences.getInstance();
    final dismissedKey = 'setup_checklist_dismissed_$businessKey';
    if (prefs.getBool(dismissedKey) == true) {
      return;
    }

    final checklist = await _loadSetupChecklist();
    if (!mounted || checklist.every((item) => item.done)) {
      await prefs.setBool(dismissedKey, true);
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        return AlertDialog(
          icon: Icon(
            Icons.checklist_rounded,
            color: dialogTheme.colorScheme.primary,
          ),
          title: const Text('Finish shop setup'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: checklist
                  .map(
                    (item) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        item.done
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: item.done
                            ? AppColors.success
                            : dialogTheme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(item.title),
                      subtitle: Text(item.subtitle),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'dismiss'),
              child: const Text('Later'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'orders'),
              child: const Text('Open Orders'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'settings'),
              child: const Text('Open Setup'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }
    if (action == 'dismiss') {
      await prefs.setBool(dismissedKey, true);
      return;
    }
    if (action == 'orders') {
      _selectIndex(17);
      return;
    }
    if (action == 'settings') {
      _selectIndex(9);
    }
  }

  Future<List<_SetupChecklistItem>> _loadSetupChecklist() async {
    final productCount = await _countRows('products');
    final serviceCount = await _countRows('services');
    final staffCount = await _countRows('users');
    return [
      _SetupChecklistItem(
        title: 'Business profile and currency',
        subtitle: '${ShopSettings.shopName} - ${ShopSettings.currency}',
        done:
            ShopSettings.isConfigured &&
            ShopSettings.currency.trim().isNotEmpty,
      ),
      _SetupChecklistItem(
        title: 'Add your first product or service',
        subtitle: '$productCount products, $serviceCount services',
        done: productCount > 0 || serviceCount > 0,
      ),
      _SetupChecklistItem(
        title: 'Publish catalog QR or order link',
        subtitle: 'Open Orders to share the customer catalog.',
        done: false,
      ),
      _SetupChecklistItem(
        title: 'Add staff accounts',
        subtitle: '$staffCount team member${staffCount == 1 ? '' : 's'}',
        done: staffCount > 1,
      ),
      _SetupChecklistItem(
        title: 'Sync and backup',
        subtitle: SyncSettingsService.lastSyncAt == null
            ? 'Not synced yet'
            : 'Last synced ${SyncSettingsService.lastSyncAt}',
        done: SyncSettingsService.lastSyncAt != null,
      ),
    ];
  }

  Future<int> _countRows(String table) async {
    try {
      final rows = await DatabaseService.rawQuery(
        'SELECT COUNT(*) AS count FROM $table WHERE deleted_at IS NULL',
      );
      return (rows.first['count'] as num? ?? 0).toInt();
    } catch (_) {
      return 0;
    }
  }

  Future<void> _maybeShowSubscriptionPrompt() async {
    final license = LicenseService.currentSnapshot;
    final status = license.accessStatus;
    if (_subscriptionPromptShown ||
        (status != LicenseAccessStatus.grace &&
            status != LicenseAccessStatus.expired)) {
      return;
    }
    _subscriptionPromptShown = true;

    final isExpired = status == LicenseAccessStatus.expired;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          isExpired ? Icons.lock_clock_outlined : Icons.schedule_outlined,
          color: isExpired ? AppColors.error : AppColors.warning,
        ),
        title: Text(
          isExpired ? 'Subscription expired' : 'Subscription renewal due',
        ),
        content: Text(
          isExpired
              ? '${license.detail ?? 'Your subscription has expired.'}\n\n'
                    'You can still view existing data, but recording sales and '
                    'other changes is paused until you renew.'
              : '${license.detail ?? 'Your subscription is in its grace period.'}\n\n'
                    'You can keep working temporarily. Renew now to avoid the '
                    'app becoming read-only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'later'),
            child: Text(isExpired ? 'Continue read-only' : 'Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'plans'),
            child: const Text('View plans'),
          ),
        ],
      ),
    );

    if (!mounted || action != 'plans') {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _SubscriptionPlansPage()),
    );
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
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
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
                          color: dialogTheme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.school_outlined,
                          color: dialogTheme.colorScheme.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Training Hub',
                          style: dialogTheme.textTheme.titleMedium?.copyWith(
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
                  Text(
                    'Guided tours only show modules for enabled features.',
                    style: dialogTheme.textTheme.bodySmall?.copyWith(
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
        );
      },
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
    final syncState = ref.watch(syncControllerProvider);
    ref.listen<SyncState>(
      syncControllerProvider,
      _showConnectivityNotification,
    );
    final List<PikiProactiveInsight> pikiInsights =
        _canLoadPikiNotifications(syncState)
        ? ref.watch(pikiProactiveInsightsProvider).valueOrNull ??
              const <PikiProactiveInsight>[]
        : const <PikiProactiveInsight>[];
    final notifications = _buildNotifications(
      syncState,
      pikiInsights: pikiInsights,
    );
    _queueDeviceNotifications(notifications);
    final moduleCurrentIndex = _currentIndex;
    if (_usesModuleLauncherNavigation) {
      final theme = Theme.of(context);
      return PopScope<Object?>(
        canPop: moduleCurrentIndex == 35 && !_hasBackDestination,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goBack();
        },
        child: Scaffold(
          key: AppShell.scaffoldKey,
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: moduleCurrentIndex == 35
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(62),
                  child: _ModuleNavigationBar(
                    moduleLabel: _moduleLabelForIndex(moduleCurrentIndex),
                    useBusinessBrand: moduleCurrentIndex == 0,
                    primaryControl:
                        moduleCurrentIndex == 0 &&
                            ShopSettings.quotationsEnabled
                        ? const PosModeTabBar(
                            key: ValueKey('pos-mode-tabs'),
                            compact: true,
                          )
                        : null,
                    hasBackDestination: _hasBackDestination,
                    onBack: _goBack,
                    onModules: () => _selectIndex(35),
                    onNotifications: _showNotificationsSheet,
                    notificationIcon: _buildNotificationIcon(
                      notifications,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    contextualAction: moduleCurrentIndex == 0
                        ? const PikiPosVoiceAction(
                            key: ValueKey('pos-header-piki-auto-listen'),
                          )
                        : null,
                  ),
                ),
          body: _buildScreenStack(moduleCurrentIndex, notifications),
        ),
      );
    }
    final windowWidth = MediaQuery.of(context).size.width;
    final isWide = windowWidth > 800;
    final canExtendRail = windowWidth >= 1040;
    final isExpandedRail = canExtendRail && !_desktopRailCollapsed;
    final theme = Theme.of(context);
    final currentIndex = _currentIndex;
    final mobileBottomDestinations = _mobileBottomDestinations;
    final mobileSelectedIndex = mobileBottomDestinations.indexWhere(
      (destination) => destination.index == currentIndex,
    );

    return Scaffold(
      key: AppShell.scaffoldKey,
      backgroundColor: theme.scaffoldBackgroundColor,
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
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(
                        right: BorderSide(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                    ),
                    child: TrainingAnchor(
                      id: 'shell.navigation',
                      child: NavigationRail(
                        minWidth: 76,
                        minExtendedWidth: 220,
                        extended: isExpandedRail,
                        backgroundColor: Colors.transparent,
                        indicatorColor: theme.colorScheme.primary.withValues(
                          alpha: 0.1,
                        ),
                        selectedIndex: _allowedDestinations.indexWhere(
                          (d) => d.index == currentIndex,
                        ),
                        onDestinationSelected: (i) =>
                            _selectIndex(_allowedDestinations[i].index),
                        labelType: isExpandedRail
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        leading: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: Image.asset(
                                    PikiMark.assetPath,
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          borderRadius: BorderRadius.circular(
                                            15,
                                          ),
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
                              ),
                              const SizedBox(height: 12),
                              _BranchPill(
                                compact: true,
                                onTap: () => _selectIndex(13),
                              ),
                              const SizedBox(height: 10),
                              IconButton(
                                tooltip: 'Notifications',
                                onPressed: () => _showNotifications(
                                  syncState,
                                  pikiInsights: pikiInsights,
                                ),
                                icon: _buildNotificationIcon(
                                  notifications,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (canExtendRail) ...[
                                const SizedBox(height: 8),
                                IconButton(
                                  tooltip: isExpandedRail
                                      ? 'Collapse sidebar'
                                      : 'Expand sidebar',
                                  onPressed: () {
                                    setState(
                                      () => _desktopRailCollapsed =
                                          !_desktopRailCollapsed,
                                    );
                                  },
                                  icon: Icon(
                                    isExpandedRail
                                        ? Icons.chevron_left_rounded
                                        : Icons.chevron_right_rounded,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        destinations: _allowedDestinations
                            .map(
                              (destination) => NavigationRailDestination(
                                icon: BeautifulIcon(
                                  destination.item.icon,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  hoverColor:
                                      theme.brightness == Brightness.dark
                                      ? Colors.white
                                      : theme.colorScheme.primary,
                                ),
                                selectedIcon: BeautifulIcon(
                                  destination.item.selectedIcon,
                                  color: theme.colorScheme.primary,
                                  hoverColor: theme.colorScheme.primary,
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
            ),
          Expanded(
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: _buildScreenStack(currentIndex, notifications),
            ),
          ),
        ],
      ),
      bottomNavigationBar: !isWide
          ? TrainingAnchor(
              id: 'shell.navigation',
              child: NavigationBar(
                backgroundColor: theme.colorScheme.surface,
                indicatorColor: theme.colorScheme.primary.withValues(
                  alpha: 0.06,
                ),
                selectedIndex: mobileSelectedIndex >= 0
                    ? mobileSelectedIndex
                    : mobileBottomDestinations.length,
                onDestinationSelected: (i) {
                  if (i == mobileBottomDestinations.length) {
                    AppShell.scaffoldKey.currentState?.openDrawer();
                    return;
                  }
                  _selectIndex(mobileBottomDestinations[i].index);
                },
                destinations: [
                  ...mobileBottomDestinations.map(
                    (destination) => NavigationDestination(
                      icon: BeautifulIcon(
                        destination.item.icon,
                        hoverColor: theme.brightness == Brightness.dark
                            ? Colors.white
                            : theme.colorScheme.primary,
                      ),
                      selectedIcon: BeautifulIcon(
                        destination.item.selectedIcon,
                        color: theme.colorScheme.primary,
                        hoverColor: theme.colorScheme.primary,
                      ),
                      label: destination.item.label,
                    ),
                  ),
                  NavigationDestination(
                    icon: BeautifulIcon(
                      Icons.grid_view_rounded,
                      hoverColor: theme.brightness == Brightness.dark
                          ? Colors.white
                          : theme.colorScheme.primary,
                    ),
                    selectedIcon: BeautifulIcon(
                      Icons.grid_view_rounded,
                      color: theme.colorScheme.primary,
                      hoverColor: theme.colorScheme.primary,
                    ),
                    label: 'More',
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildDrawer(BuildContext context, int currentIndex) {
    final syncState = ref.watch(syncControllerProvider);
    final theme = Theme.of(context);

    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outline),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      PikiMark.assetPath,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.point_of_sale_rounded,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    ShopSettings.shopName,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${SessionService.currentUserName} • ${RolePermissions.label(SessionService.currentUserRole)}',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
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
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
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
                                _selectIndex(destination.index);
                                Navigator.pop(context);
                              },
                            ),
                          ),
                        ];
                      })(),
                    if (_switchableBusinesses.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: ListTile(
                          leading: const Icon(Icons.swap_horiz),
                          title: const Text('Switch business'),
                          onTap: () {
                            Navigator.pop(context);
                            _openSwitchBusinessDialog(context);
                          },
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Piki POS v1.0.0',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.5,
                  ),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _switchableBusinesses {
    final currentBusinessId = SyncSettingsService.localBusinessId;
    return SyncSettingsService.myBusinesses
        .where(
          (business) => (business['id']?.toString() ?? '') != currentBusinessId,
        )
        .toList();
  }

  Future<void> _openSwitchBusinessDialog(BuildContext context) async {
    final businesses = _switchableBusinesses;
    if (businesses.isEmpty) return;

    final passwordController = TextEditingController();
    String? selectedId = businesses.first['id']?.toString();
    var isSwitching = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Switch business'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioGroup<String>(
                      groupValue: selectedId,
                      onChanged: (value) {
                        if (isSwitching || value == null) return;
                        setDialogState(() => selectedId = value);
                      },
                      child: Column(
                        children: businesses.map((business) {
                          final id = business['id']?.toString() ?? '';
                          final name = business['name']?.toString() ?? id;
                          return RadioListTile<String>(
                            value: id,
                            title: Text(name),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Cloud password',
                        hintText: 'Re-enter your password to switch',
                      ),
                    ),
                    if (dialogError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          dialogError!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSwitching
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSwitching
                      ? null
                      : () async {
                          final password = passwordController.text;
                          if (password.isEmpty) {
                            setDialogState(
                              () => dialogError = 'Enter your password.',
                            );
                            return;
                          }
                          final target = businesses.firstWhere(
                            (b) => b['id']?.toString() == selectedId,
                            orElse: () => businesses.first,
                          );
                          setDialogState(() {
                            isSwitching = true;
                            dialogError = null;
                          });
                          try {
                            await _performSwitch(
                              businessId: target['id']?.toString() ?? '',
                              password: password,
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (error) {
                            setDialogState(() {
                              isSwitching = false;
                              dialogError = AppErrorMessage.from(
                                error,
                                fallback: 'Could not switch business.',
                              );
                            });
                          }
                        },
                  child: isSwitching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Switch'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _performSwitch({
    required String businessId,
    required String password,
  }) async {
    final backendUrl = SyncSettingsService.backendUrl;
    if (backendUrl.isEmpty) {
      throw Exception('Cloud backend is not configured on this device.');
    }
    await LocalBusinessResetService.prepareForBusinessSwitch();
    final deviceId = await SyncSettingsService.getOrCreateDeviceId();
    final email = SessionService.currentUserEmail;

    final response = await CloudAuthService.loginOnline(
      backendUrl: backendUrl,
      email: email,
      password: password,
      deviceId: deviceId,
      businessId: businessId,
    );

    await LocalBusinessResetService.clearForBusinessSwitch();
    await CloudAuthService.persistCloudResponse(response);
    final localUser = await UserRepository.upsertCloudAuthenticatedUser(
      cloudUser: response.user,
      fallbackEmail: email,
      passwordHash: AuthPasswordService.hashPassword(password),
    );
    await SessionService.signIn(localUser);

    if (!mounted) return;
    _showSwitchProgress();
    try {
      await SyncService.syncNow(forceFullPull: true, onProgress: (_) {});
      await SyncSettingsService.setLocalBusinessId(businessId);
    } finally {
      if (mounted) _hideSwitchProgress();
    }

    if (mounted) {
      setState(() {});
      ref.invalidate(syncControllerProvider);
    }
  }

  void _showSwitchProgress() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Switching business and syncing...')),
    );
  }

  void _hideSwitchProgress() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  Widget _buildScreenStack(
    int currentIndex,
    List<_AppNotification> notifications,
  ) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 110),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.012, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey('shell-screen-$currentIndex'),
        child: _buildScreen(currentIndex, notifications),
      ),
    );
  }

  Widget _buildScreen(int index, List<_AppNotification> notifications) {
    switch (index) {
      case 0:
        return const PosScreen(embeddedInAppShell: true);
      case 1:
        return ProductListScreen(onOpenCatalogOrders: () => _selectIndex(17));
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
      case 17:
        return CatalogOrdersScreen(onOpenPos: () => _selectIndex(0));
      case 18:
        return const ContactsScreen();
      case 19:
        return const CustomerInvoicesScreen();
      case 20:
        return const QuotationsScreen();
      case 21:
        return const LoyaltyScreen();
      case 22:
        return const GiftCardScreen();
      case 23:
        return const PromotionScreen();
      case 24:
        return const CustomRolesScreen();
      case 25:
        return const SerialTrackingScreen();
      case 26:
        return const StocktakeScreen();
      case 27:
        return const SmsCampaignScreen();
      case 28:
        return const WastageScreen();
      case 29:
        return const RestaurantScreen(embeddedInAppShell: true);
      case 30:
        return const AttendanceScreen();
      case 31:
        return const CustomerGroupsScreen();
      case 32:
        return const PurchaseApprovalScreen();
      case 33:
        return const DeliveryScreen();
      case 34:
        return const AdvancedBiScreen();
      case 35:
        return _ModuleLauncherScreen(
          businessModules: _businessModules,
          onSelect: _selectIndex,
          onNotifications: _showNotificationsSheet,
          notificationIcon: _buildNotificationIcon(notifications),
        );
      case 36:
        return OnlineStoreScreen(
          embeddedInAppShell: true,
          initialSection: _onlineStoreInitialSection,
          navigationRevision: _onlineStoreNavigationRevision,
          onOpenPos: () => _selectIndex(_normalizeNavigationIndex(0)),
        );
      default:
        return const PosScreen(embeddedInAppShell: true);
    }
  }

  Widget _buildDrawerBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final surfaceTint = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.08);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: surfaceTint,
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

enum _AppNotificationSeverity { info, warning, critical }

class _AppNotification {
  final String id;
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final int? destinationIndex;
  final PikiProactiveInsight? pikiInsight;
  final _AppNotificationSeverity severity;
  final bool deviceNotify;
  final bool opensUpdate;

  const _AppNotification({
    String? id,
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    this.destinationIndex,
    this.pikiInsight,
    this.severity = _AppNotificationSeverity.info,
    this.deviceNotify = false,
    this.opensUpdate = false,
  }) : id = id ?? '$title|$message';

  bool get canOpen =>
      destinationIndex != null || pikiInsight != null || opensUpdate;
}

class _SetupChecklistItem {
  final String title;
  final String subtitle;
  final bool done;

  const _SetupChecklistItem({
    required this.title,
    required this.subtitle,
    required this.done,
  });
}

class _SubscriptionPlansPage extends StatelessWidget {
  const _SubscriptionPlansPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription plans')),
      body: SubscriptionPlansSection(
        fullPage: true,
        onOpenApp: () => Navigator.of(context).pop(),
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
        final theme = Theme.of(context);
        final currentId = BranchService.currentBranchId;
        final branches = snapshot.data ?? const <Map<String, dynamic>>[];
        final current = branches.where((b) => b['id'] == currentId).firstOrNull;
        final name = (current?['name'] as String?)?.trim().isNotEmpty == true
            ? current!['name'] as String
            : 'Main Branch';
        return Material(
          color: theme.colorScheme.surfaceContainerHighest,
          shape: StadiumBorder(
            side: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.8),
            ),
          ),
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
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      compact ? (current?['code'] as String? ?? 'MAIN') : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
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

class _ModuleNavigationBar extends StatelessWidget {
  final String moduleLabel;
  final bool useBusinessBrand;
  final Widget? primaryControl;
  final bool hasBackDestination;
  final VoidCallback onBack;
  final VoidCallback onModules;
  final VoidCallback onNotifications;
  final Widget notificationIcon;
  final Widget? contextualAction;

  const _ModuleNavigationBar({
    required this.moduleLabel,
    this.useBusinessBrand = false,
    this.primaryControl,
    required this.hasBackDestination,
    required this.onBack,
    required this.onModules,
    required this.onNotifications,
    required this.notificationIcon,
    this.contextualAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Container(
            key: const ValueKey('module-navigation-bar'),
            height: 62,
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth < 500 ? 6 : 14,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.7),
                ),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: hasBackDestination
                      ? 'Back to previous module'
                      : 'Back to modules',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                ),
                SizedBox(width: constraints.maxWidth < 360 ? 2 : 4),
                if (useBusinessBrand)
                  _BusinessHeaderLogo(
                    size: constraints.maxWidth < 360 ? 30 : 34,
                  )
                else
                  const PikiMark(size: 34),
                SizedBox(width: primaryControl == null ? 11 : 8),
                if (primaryControl != null)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: primaryControl!,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          moduleLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (constraints.maxWidth >= 410)
                          Text(
                            'Piki workspace',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                SizedBox(width: constraints.maxWidth < 360 ? 2 : 8),
                if (contextualAction != null) ...[
                  contextualAction!,
                  const SizedBox(width: 2),
                ],
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: onNotifications,
                  icon: notificationIcon,
                ),
                if (constraints.maxWidth >= 430)
                  OutlinedButton.icon(
                    onPressed: onModules,
                    icon: const Icon(Icons.grid_view_rounded, size: 17),
                    label: const Text('All modules'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
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

class _BusinessHeaderLogo extends StatefulWidget {
  final double size;

  const _BusinessHeaderLogo({required this.size});

  @override
  State<_BusinessHeaderLogo> createState() => _BusinessHeaderLogoState();
}

class _BusinessHeaderLogoState extends State<_BusinessHeaderLogo> {
  late final Future<StorefrontBrandSettings> _brandSettings;

  @override
  void initState() {
    super.initState();
    _brandSettings = StorefrontBrandService.fetchSettings().catchError(
      (_) => StorefrontBrandSettings.empty(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shopName = ShopSettings.shopName.trim();
    final initial = shopName.isEmpty ? 'S' : shopName.characters.first;

    return Semantics(
      image: true,
      label: '$shopName logo',
      child: Container(
        key: const ValueKey('business-header-logo'),
        width: widget.size,
        height: widget.size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(widget.size * 0.24),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Text(
                initial.toUpperCase(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            FutureBuilder<StorefrontBrandSettings>(
              future: _brandSettings,
              builder: (context, snapshot) {
                final logoUrl = snapshot.data?.logoUrl.trim() ?? '';
                if (logoUrl.isEmpty) return const SizedBox.shrink();
                return Image.network(
                  logoUrl,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                );
              },
            ),
          ],
        ),
      ),
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

/// Soft, structured colour tokens for a single retail module card.
///
/// Light values are the curated pastel palette. [forTheme] derives calm,
/// low-contrast surfaces for dark mode so the launcher stays professional
/// instead of glowing.
class _RetailModuleColors {
  const _RetailModuleColors({
    required this.background,
    required this.iconBackground,
    required this.iconColor,
    required this.border,
  });

  final Color background;
  final Color iconBackground;
  final Color iconColor;
  final Color border;

  _RetailModuleColors forTheme(ThemeData theme) {
    if (theme.brightness != Brightness.dark) return this;
    final surface = theme.colorScheme.surface;
    final tint = iconColor;
    return _RetailModuleColors(
      background: Color.lerp(surface, tint, 0.12)!,
      iconBackground: Color.lerp(surface, tint, 0.24)!,
      iconColor: Color.lerp(tint, Colors.white, 0.18)!,
      border: Color.lerp(surface, tint, 0.34)!,
    );
  }
}

/// Presentation metadata for a retail module destination.
///
/// This is display-only: it never changes routes, permissions, or business
/// logic. Search matches against [keywords] in addition to the module label.
class _RetailModuleStyle {
  const _RetailModuleStyle({
    required this.description,
    required this.keywords,
    required this.colors,
    this.emphasized = false,
  });

  final String description;
  final List<String> keywords;
  final _RetailModuleColors colors;
  final bool emphasized;
}

const _retailModuleStyles = <int, _RetailModuleStyle>{
  0: _RetailModuleStyle(
    description: 'Start a new sale',
    keywords: ['sell', 'checkout', 'pos', 'sale', 'register', 'cashier'],
    colors: _RetailModuleColors(
      background: Color(0xFFFFF1F3),
      iconBackground: Color(0xFFFFDDE5),
      iconColor: Color(0xFFE65372),
      border: Color(0xFFF7D9E0),
    ),
    emphasized: true,
  ),
  36: _RetailModuleStyle(
    description: 'Manage your storefront',
    keywords: ['store', 'online', 'web', 'shop', 'ecommerce', 'catalog'],
    colors: _RetailModuleColors(
      background: Color(0xFFF6F0FF),
      iconBackground: Color(0xFFEBDDFF),
      iconColor: Color(0xFF8058C7),
      border: Color(0xFFE8DBF8),
    ),
    emphasized: true,
  ),
  5: _RetailModuleStyle(
    description: 'View business performance',
    keywords: ['dashboard', 'metrics', 'overview', 'performance', 'home'],
    colors: _RetailModuleColors(
      background: Color(0xFFEEF4FF),
      iconBackground: Color(0xFFDDE9FF),
      iconColor: Color(0xFF4F7FD8),
      border: Color(0xFFDCE7F8),
    ),
    emphasized: true,
  ),
  4: _RetailModuleStyle(
    description: 'Review completed sales',
    keywords: ['sell', 'sales', 'receipts', 'orders', 'history', 'completed'],
    colors: _RetailModuleColors(
      background: Color(0xFFFFF4EC),
      iconBackground: Color(0xFFFFE4D2),
      iconColor: Color(0xFFD97835),
      border: Color(0xFFF5E0D1),
    ),
    emphasized: true,
  ),
  19: _RetailModuleStyle(
    description: 'Create and manage invoices',
    keywords: ['invoice', 'bill', 'billing', 'document', 'account'],
    colors: _RetailModuleColors(
      background: Color(0xFFFFF8E8),
      iconBackground: Color(0xFFFFEFC7),
      iconColor: Color(0xFFB98622),
      border: Color(0xFFF3E5C1),
    ),
  ),
  20: _RetailModuleStyle(
    description: 'Prepare customer quotations',
    keywords: ['quote', 'quotation', 'estimate', 'proposal', 'customer'],
    colors: _RetailModuleColors(
      background: Color(0xFFFFF0F5),
      iconBackground: Color(0xFFFFDCE8),
      iconColor: Color(0xFFC65A83),
      border: Color(0xFFF3D9E3),
    ),
  ),
  6: _RetailModuleStyle(
    description: 'Manage customer credit',
    keywords: ['kopesha', 'credit', 'loan', 'balance', 'debt', 'customer'],
    colors: _RetailModuleColors(
      background: Color(0xFFEEF8FF),
      iconBackground: Color(0xFFDCEFFF),
      iconColor: Color(0xFF3E8DBF),
      border: Color(0xFFD6E9F5),
    ),
  ),
  10: _RetailModuleStyle(
    description: 'Manage cashier shifts',
    keywords: ['shift', 'cashier', 'till', 'session', 'clock'],
    colors: _RetailModuleColors(
      background: Color(0xFFF4F1FF),
      iconBackground: Color(0xFFE7DFFF),
      iconColor: Color(0xFF7359C5),
      border: Color(0xFFE4DDF5),
    ),
  ),
  1: _RetailModuleStyle(
    description: 'Manage products and prices',
    keywords: ['product', 'item', 'price', 'stock', 'catalog', 'inventory'],
    colors: _RetailModuleColors(
      background: Color(0xFFEEF9F1),
      iconBackground: Color(0xFFDDF2E3),
      iconColor: Color(0xFF3D9561),
      border: Color(0xFFD7EBDC),
    ),
  ),
  12: _RetailModuleStyle(
    description: 'Check available inventory',
    keywords: ['stock', 'inventory', 'on hand', 'availability', 'list'],
    colors: _RetailModuleColors(
      background: Color(0xFFEDF9F8),
      iconBackground: Color(0xFFD9F1EE),
      iconColor: Color(0xFF2C8F86),
      border: Color(0xFFD3EAE7),
    ),
  ),
  2: _RetailModuleStyle(
    description: 'Organize product groups',
    keywords: ['category', 'group', 'collection', 'tag', 'classify'],
    colors: _RetailModuleColors(
      background: Color(0xFFF2F7FF),
      iconBackground: Color(0xFFDFEBFF),
      iconColor: Color(0xFF527FC9),
      border: Color(0xFFDCE6F5),
    ),
  ),
  3: _RetailModuleStyle(
    description: 'Record supplier purchases',
    keywords: ['purchase', 'supplier', 'buy', 'restock', 'grn', 'order'],
    colors: _RetailModuleColors(
      background: Color(0xFFFFF9ED),
      iconBackground: Color(0xFFFFF0CB),
      iconColor: Color(0xFFB58926),
      border: Color(0xFFF1E4C4),
    ),
  ),
  15: _RetailModuleStyle(
    description: 'Move stock between locations',
    keywords: [
      'transfer',
      'move',
      'branch',
      'location',
      'stock',
      'interbranch',
    ],
    colors: _RetailModuleColors(
      background: Color(0xFFEEF8FF),
      iconBackground: Color(0xFFDCEFFF),
      iconColor: Color(0xFF3F91C8),
      border: Color(0xFFD6E9F5),
    ),
  ),
  25: _RetailModuleStyle(
    description: 'Track serialized products',
    keywords: ['serial', 'imei', 'track', 'warranty', 'stock'],
    colors: _RetailModuleColors(
      background: Color(0xFFFFF2F1),
      iconBackground: Color(0xFFFFDCD9),
      iconColor: Color(0xFFCA635D),
      border: Color(0xFFF1DAD7),
    ),
  ),
  26: _RetailModuleStyle(
    description: 'Count and reconcile stock',
    keywords: ['stocktake', 'count', 'reconcile', 'audit', 'physical', 'stock'],
    colors: _RetailModuleColors(
      background: Color(0xFFF2F8F3),
      iconBackground: Color(0xFFDDEEDF),
      iconColor: Color(0xFF4F8D5B),
      border: Color(0xFFDCE8DE),
    ),
  ),
  28: _RetailModuleStyle(
    description: 'Record damaged or lost stock',
    keywords: ['wastage', 'waste', 'damage', 'loss', 'spoilage', 'stock'],
    colors: _RetailModuleColors(
      background: Color(0xFFFFF3EE),
      iconBackground: Color(0xFFFFE1D5),
      iconColor: Color(0xFFC86C48),
      border: Color(0xFFF1DDD4),
    ),
  ),
  18: _RetailModuleStyle(
    description: 'Manage customer contacts',
    keywords: ['customer', 'contact', 'client', 'people', 'directory'],
    colors: _RetailModuleColors(
      background: Color(0xFFF2F7FF),
      iconBackground: Color(0xFFDFEBFF),
      iconColor: Color(0xFF527FC9),
      border: Color(0xFFDCE6F5),
    ),
  ),
  31: _RetailModuleStyle(
    description: 'Create and send SMS campaigns',
    keywords: ['sms', 'campaign', 'marketing', 'message', 'promo', 'broadcast'],
    colors: _RetailModuleColors(
      background: Color(0xFFF6F0FF),
      iconBackground: Color(0xFFEBDDFF),
      iconColor: Color(0xFF8058C7),
      border: Color(0xFFE8DBF8),
    ),
  ),
  21: _RetailModuleStyle(
    description: 'Reward loyal customers',
    keywords: ['loyalty', 'rewards', 'points', 'members', 'customer'],
    colors: _RetailModuleColors(
      background: Color(0xFFFFF0F5),
      iconBackground: Color(0xFFFFDCE8),
      iconColor: Color(0xFFC65A83),
      border: Color(0xFFF3D9E3),
    ),
  ),
  22: _RetailModuleStyle(
    description: 'Sell and redeem gift cards',
    keywords: ['gift', 'card', 'voucher', 'redeem', 'customer'],
    colors: _RetailModuleColors(
      background: Color(0xFFEEF8FF),
      iconBackground: Color(0xFFDCEFFF),
      iconColor: Color(0xFF3E8DBF),
      border: Color(0xFFD6E9F5),
    ),
  ),
  27: _RetailModuleStyle(
    description: 'Reach customers by email and SMS',
    keywords: ['campaign', 'marketing', 'email', 'sms', 'promo', 'audience'],
    colors: _RetailModuleColors(
      background: Color(0xFFF4F1FF),
      iconBackground: Color(0xFFE7DFFF),
      iconColor: Color(0xFF7359C5),
      border: Color(0xFFE4DDF5),
    ),
  ),
  8: _RetailModuleStyle(
    description: 'Explore sales and trend reports',
    keywords: ['report', 'analytics', 'sales', 'trend', 'insight'],
    colors: _RetailModuleColors(
      background: Color(0xFFEEF4FF),
      iconBackground: Color(0xFFDDE9FF),
      iconColor: Color(0xFF4F7FD8),
      border: Color(0xFFDCE7F8),
    ),
  ),
  34: _RetailModuleStyle(
    description: 'Analyse business intelligence',
    keywords: ['bi', 'dashboard', 'analytics', 'intelligence', 'kpi'],
    colors: _RetailModuleColors(
      background: Color(0xFFEDF9F8),
      iconBackground: Color(0xFFD9F1EE),
      iconColor: Color(0xFF2C8F86),
      border: Color(0xFFD3EAE7),
    ),
  ),
  7: _RetailModuleStyle(
    description: 'Review profit and loss',
    keywords: ['pnl', 'profit', 'loss', 'finance', 'report'],
    colors: _RetailModuleColors(
      background: Color(0xFFF2F8F3),
      iconBackground: Color(0xFFDDEEDF),
      iconColor: Color(0xFF4F8D5B),
      border: Color(0xFFDCE8DE),
    ),
  ),
  30: _RetailModuleStyle(
    description: 'Track staff attendance',
    keywords: ['attendance', 'staff', 'time', 'clock', 'roster'],
    colors: _RetailModuleColors(
      background: Color(0xFFF2F7FF),
      iconBackground: Color(0xFFDFEBFF),
      iconColor: Color(0xFF527FC9),
      border: Color(0xFFDCE6F5),
    ),
  ),
  9: _RetailModuleStyle(
    description: 'Configure shop settings',
    keywords: ['settings', 'config', 'preferences', 'setup', 'options'],
    colors: _RetailModuleColors(
      background: Color(0xFFF6F7F9),
      iconBackground: Color(0xFFE7EAEF),
      iconColor: Color(0xFF5A6470),
      border: Color(0xFFE2E5EA),
    ),
  ),
  13: _RetailModuleStyle(
    description: 'Manage branches and outlets',
    keywords: ['branch', 'outlet', 'location', 'store', 'multi'],
    colors: _RetailModuleColors(
      background: Color(0xFFF2F7FF),
      iconBackground: Color(0xFFDFEBFF),
      iconColor: Color(0xFF527FC9),
      border: Color(0xFFDCE6F5),
    ),
  ),
  14: _RetailModuleStyle(
    description: 'Review audit logs',
    keywords: ['audit', 'log', 'history', 'security', 'trail'],
    colors: _RetailModuleColors(
      background: Color(0xFFF4F1FF),
      iconBackground: Color(0xFFE7DFFF),
      iconColor: Color(0xFF7359C5),
      border: Color(0xFFE4DDF5),
    ),
  ),
  24: _RetailModuleStyle(
    description: 'Manage roles and permissions',
    keywords: ['role', 'permission', 'access', 'user', 'admin'],
    colors: _RetailModuleColors(
      background: Color(0xFFFFF0F5),
      iconBackground: Color(0xFFFFDCE8),
      iconColor: Color(0xFFC65A83),
      border: Color(0xFFF3D9E3),
    ),
  ),
  16: _RetailModuleStyle(
    description: 'Ask Piki AI for help',
    keywords: ['ai', 'assistant', 'piki', 'help', 'automation'],
    colors: _RetailModuleColors(
      background: Color(0xFFEEF4FF),
      iconBackground: Color(0xFFDDE9FF),
      iconColor: Color(0xFF4F7FD8),
      border: Color(0xFFDCE7F8),
    ),
  ),
  17: _RetailModuleStyle(
    description: 'Review customer orders',
    keywords: ['order', 'orders', 'fulfilment', 'customer', 'sales'],
    colors: _RetailModuleColors(
      background: Color(0xFFEEF9F1),
      iconBackground: Color(0xFFDDF2E3),
      iconColor: Color(0xFF3D9561),
      border: Color(0xFFD7EBDC),
    ),
  ),
  11: _RetailModuleStyle(
    description: 'Manage service bookings',
    keywords: ['service', 'booking', 'appointment', 'job', 'ticket'],
    colors: _RetailModuleColors(
      background: Color(0xFFF6F0FF),
      iconBackground: Color(0xFFEBDDFF),
      iconColor: Color(0xFF8058C7),
      border: Color(0xFFE8DBF8),
    ),
  ),
  29: _RetailModuleStyle(
    description: 'Run the restaurant floor',
    keywords: ['restaurant', 'table', 'kitchen', 'dining', 'order'],
    colors: _RetailModuleColors(
      background: Color(0xFFFFF1F3),
      iconBackground: Color(0xFFFFDDE5),
      iconColor: Color(0xFFE65372),
      border: Color(0xFFF7D9E0),
    ),
  ),
  32: _RetailModuleStyle(
    description: 'Approve pending requests',
    keywords: ['approval', 'approve', 'pending', 'request', 'review'],
    colors: _RetailModuleColors(
      background: Color(0xFFF4F1FF),
      iconBackground: Color(0xFFE7DFFF),
      iconColor: Color(0xFF7359C5),
      border: Color(0xFFE4DDF5),
    ),
  ),
  33: _RetailModuleStyle(
    description: 'Track deliveries and dispatch',
    keywords: ['delivery', 'dispatch', 'shipping', 'logistics', 'track'],
    colors: _RetailModuleColors(
      background: Color(0xFFEDF9F8),
      iconBackground: Color(0xFFD9F1EE),
      iconColor: Color(0xFF2C8F86),
      border: Color(0xFFD3EAE7),
    ),
  ),
};

/// Shorter descriptions used only on narrow mobile cards so text never wraps
/// awkwardly. Titles are never shortened.
const _retailMobileDescriptions = <int, String>{
  0: 'Start a new sale',
  36: 'Manage your store',
  5: 'Business overview',
  4: 'Review sales',
  19: 'Manage invoices',
  20: 'Create quotations',
  6: 'Manage customer credit',
  10: 'Manage cashier shifts',
  1: 'Manage products',
  12: 'View available stock',
  2: 'Organize products',
  3: 'Record purchases',
  15: 'Move stock',
  25: 'Track serial numbers',
  26: 'Count stock',
  28: 'Record stock losses',
  18: 'Manage customer contacts',
  31: 'Send SMS campaigns',
  21: 'Reward loyal customers',
  22: 'Sell gift cards',
  27: 'Reach customers',
  8: 'Explore reports',
  34: 'Analyse intelligence',
  7: 'Review profit & loss',
  30: 'Track attendance',
  9: 'Configure settings',
  13: 'Manage branches',
  14: 'Review audit logs',
  24: 'Manage roles',
  16: 'Ask Piki AI',
  17: 'Review orders',
  11: 'Manage services',
  29: 'Run the floor',
  32: 'Approve requests',
  33: 'Track deliveries',
};

class _BusinessModule {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<_NavDestination> destinations;
  final List<int> coreDestinationIndexes;
  final int? directDestinationIndex;
  final String? readinessLabel;

  const _BusinessModule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.destinations,
    required this.coreDestinationIndexes,
    this.directDestinationIndex,
    this.readinessLabel,
  });
}

class _FeatureGridGroup {
  final String title;
  final String subtitle;
  final List<_NavDestination> destinations;

  const _FeatureGridGroup({
    required this.title,
    required this.subtitle,
    required this.destinations,
  });
}

class _ModuleLauncherScreen extends StatefulWidget {
  final List<_BusinessModule> businessModules;
  final ValueChanged<int> onSelect;
  final VoidCallback onNotifications;
  final Widget notificationIcon;

  const _ModuleLauncherScreen({
    required this.businessModules,
    required this.onSelect,
    required this.onNotifications,
    required this.notificationIcon,
  });

  @override
  State<_ModuleLauncherScreen> createState() => _ModuleLauncherScreenState();
}

class _ModuleLauncherScreenState extends State<_ModuleLauncherScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final TextEditingController _moduleSearchController;
  late final FocusNode _moduleSearchFocusNode;
  String _moduleSearchQuery = '';
  bool _compactLayout = false;
  // Session-local recents. No persistence: kept lightweight and in-memory so
  // the launcher never introduces a database migration.
  final List<int> _recentDestinationIndexes = <int>[];

  @override
  void initState() {
    super.initState();
    _moduleSearchController = TextEditingController();
    _moduleSearchFocusNode = FocusNode();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
    if (widget.businessModules.length == 1 &&
        widget.businessModules.single.directDestinationIndex == null) {
      _activeModuleId = widget.businessModules.single.id;
    }
  }

  @override
  void dispose() {
    _moduleSearchController.dispose();
    _moduleSearchFocusNode.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Widget _fadeSlide({
    required double begin,
    required double end,
    required double offsetY,
    required Widget child,
  }) {
    final animation = CurvedAnimation(
      parent: _entranceController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, offsetY),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  String? _activeModuleId;

  _BusinessModule? get _activeModule {
    final id = _activeModuleId;
    if (id == null) return null;
    for (final module in widget.businessModules) {
      if (module.id == id) return module;
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant _ModuleLauncherScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.businessModules.length == 1 &&
        widget.businessModules.single.directDestinationIndex == null) {
      _activeModuleId = widget.businessModules.single.id;
    } else if (_activeModuleId != null && _activeModule == null) {
      _activeModuleId = null;
    }
  }

  void _openBusinessModule(_BusinessModule module) {
    final directDestinationIndex = module.directDestinationIndex;
    if (directDestinationIndex != null) {
      _recordRecent(directDestinationIndex);
      widget.onSelect(directDestinationIndex);
      return;
    }
    setState(() {
      _activeModuleId = module.id;
      _moduleSearchQuery = '';
      _moduleSearchController.clear();
    });
    _entranceController.forward(from: 0);
  }

  void _recordRecent(int index) {
    if (!mounted) return;
    setState(() {
      _recentDestinationIndexes
        ..remove(index)
        ..insert(0, index);
      if (_recentDestinationIndexes.length > 5) {
        _recentDestinationIndexes.length = 5;
      }
    });
  }

  void _returnToBusinessModules() {
    setState(() {
      _activeModuleId = null;
      _moduleSearchQuery = '';
      _moduleSearchController.clear();
    });
    _entranceController.forward(from: 0);
  }

  void _clearModuleSearch() {
    _moduleSearchController.clear();
    if (_moduleSearchQuery.isEmpty) return;
    setState(() => _moduleSearchQuery = '');
  }

  double _pageInset(double width) {
    if (width < 600) return 16;
    if (width < 1248) return 24;
    return (width - 1200) / 2;
  }

  Widget _buildBusinessModuleRoot(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final inset = _pageInset(constraints.maxWidth);
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 18, inset, 10),
                  sliver: SliverToBoxAdapter(
                    child: _ModuleLauncherRootHeader(
                      onOpenSettings: () => widget.onSelect(9),
                      onNotifications: widget.onNotifications,
                      notificationIcon: widget.notificationIcon,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 14, inset, 22),
                  sliver: SliverToBoxAdapter(
                    child: _AnimatedModuleHero(controller: _entranceController),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, 14),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StitchSectionHeader(
                          eyebrow: 'Choose your workspace',
                          title: 'Start where today\'s work is happening.',
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, 32),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final module = widget.businessModules[index];
                      final start = (0.34 + index * 0.045)
                          .clamp(0.34, 0.78)
                          .toDouble();
                      return _fadeSlide(
                        begin: start,
                        end: (start + 0.22).clamp(0.56, 1).toDouble(),
                        offsetY: 0.10,
                        child: _BusinessModuleTile(
                          module: module,
                          onTap: () => _openBusinessModule(module),
                        ),
                      );
                    }, childCount: widget.businessModules.length),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 390,
                          mainAxisExtent: 158,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                        ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeModule = _activeModule;
    if (activeModule == null) {
      return _buildBusinessModuleRoot(context);
    }
    final theme = Theme.of(context);
    final remaining = {
      for (final destination in activeModule.destinations)
        destination.index: destination,
    };
    List<_NavDestination> takeDestinations(List<int> indexes) {
      final destinations = <_NavDestination>[];
      for (final index in indexes) {
        final destination = remaining.remove(index);
        if (destination != null) destinations.add(destination);
      }
      return destinations;
    }

    _FeatureGridGroup? group({
      required String title,
      required String subtitle,
      required List<int> indexes,
    }) {
      final destinations = takeDestinations(indexes);
      if (destinations.isEmpty) return null;
      return _FeatureGridGroup(
        title: title,
        subtitle: subtitle,
        destinations: destinations,
      );
    }

    final startIndexes = switch (activeModule.id) {
      'services' => const [11, 36, 5, 4],
      'retail_pos' => const [0, 36, 5, 4],
      _ => const [5],
    };
    final featureGroups = <_FeatureGridGroup?>[
      group(
        title: 'START HERE',
        subtitle: 'The fastest path through today\'s work.',
        indexes: startIndexes,
      ),
      group(
        title: 'SELL & GET PAID',
        subtitle: 'Sales records, documents, balances, and shifts.',
        indexes: const [0, 11, 4, 19, 20, 6, 10],
      ),
      group(
        title: 'STOCK & SUPPLY',
        subtitle: 'Products, purchasing, stock control, and fulfilment.',
        indexes: const [1, 12, 2, 3, 15, 25, 26, 28, 32, 33],
      ),
      group(
        title: 'CUSTOMERS & GROWTH',
        subtitle: 'Customer records, retention, and marketing.',
        indexes: const [18, 31, 27, 21, 22, 23],
      ),
      group(
        title: 'INSIGHTS',
        subtitle: 'Performance, trends, and profitability.',
        indexes: const [8, 34, 7],
      ),
      group(
        title: 'MANAGE BUSINESS',
        subtitle: 'Team, branches, settings, controls, and Piki.',
        indexes: const [30, 9, 13, 14, 24, 16],
      ),
      if (remaining.isNotEmpty)
        _FeatureGridGroup(
          title: 'MORE TOOLS',
          subtitle: 'Additional features available to your account.',
          destinations: remaining.values.toList(growable: false),
        ),
    ].whereType<_FeatureGridGroup>().toList(growable: false);
    final isRetailModule = activeModule.id == 'retail_pos';
    final normalizedQuery = _moduleSearchQuery.trim().toLowerCase();
    final visibleFeatureGroups = !isRetailModule || normalizedQuery.isEmpty
        ? featureGroups
        : featureGroups
              .map((group) {
                final groupMatches = group.title.toLowerCase().contains(
                  normalizedQuery,
                );
                final matches = groupMatches
                    ? group.destinations
                    : group.destinations
                          .where((destination) {
                            final style =
                                _retailModuleStyles[destination.index];
                            final haystack = <String>[
                              destination.item.label.toLowerCase(),
                              if (style != null)
                                style.description.toLowerCase(),
                              if (style != null)
                                style.keywords.join(' ').toLowerCase(),
                            ].join(' ');
                            return haystack.contains(normalizedQuery);
                          })
                          .toList(growable: false);
                return _FeatureGridGroup(
                  title: group.title,
                  subtitle: group.subtitle,
                  destinations: matches,
                );
              })
              .where((group) => group.destinations.isNotEmpty)
              .toList(growable: false);
    final visibleModuleCount = visibleFeatureGroups.fold<int>(
      0,
      (count, group) => count + group.destinations.length,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final inset = _pageInset(constraints.maxWidth);
            if (isRetailModule) {
              return _buildRetailModuleScaffold(
                context,
                theme,
                constraints.maxWidth,
                inset,
                visibleFeatureGroups,
                normalizedQuery,
                visibleModuleCount,
              );
            }
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 18, inset, 10),
                  sliver: SliverToBoxAdapter(
                    child: _fadeSlide(
                      begin: 0,
                      end: 0.28,
                      offsetY: -0.08,
                      child: Row(
                        children: [
                          if (widget.businessModules.length > 1)
                            IconButton(
                              tooltip: 'Back to business workspaces',
                              onPressed: _returnToBusinessModules,
                              icon: const Icon(Icons.arrow_back_rounded),
                            )
                          else
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: activeModule.accent.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                              ),
                              child: Icon(
                                activeModule.icon,
                                color: activeModule.accent,
                                size: 20,
                              ),
                            ),
                          const SizedBox(width: 8),
                          const PikiMark(size: 42),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activeModule.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  activeModule.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Notifications',
                            onPressed: widget.onNotifications,
                            icon: widget.notificationIcon,
                          ),
                          IconButton(
                            tooltip: 'Settings',
                            onPressed: () => widget.onSelect(9),
                            icon: const Icon(Icons.settings_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(inset, 14, inset, 22),
                  sliver: SliverToBoxAdapter(
                    child: isRetailModule
                        ? _fadeSlide(
                            begin: 0.08,
                            end: 0.42,
                            offsetY: 0.06,
                            child: _RetailModuleSearch(
                              controller: _moduleSearchController,
                              query: _moduleSearchQuery,
                              resultCount: visibleModuleCount,
                              focusNode: _moduleSearchFocusNode,
                              compact: false,
                              onChanged: (value) =>
                                  setState(() => _moduleSearchQuery = value),
                              onClear: _clearModuleSearch,
                              onToggleCompact: () {},
                            ),
                          )
                        : _AnimatedModuleHero(controller: _entranceController),
                  ),
                ),
                if (isRetailModule &&
                    normalizedQuery.isNotEmpty &&
                    visibleFeatureGroups.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(inset, 26, inset, 48),
                    sliver: const SliverToBoxAdapter(
                      child: _RetailModuleSearchEmptyState(),
                    ),
                  ),
                for (final group in visibleFeatureGroups) ...[
                  if (group.destinations.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 0, inset, 14),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.title,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              group.subtitle,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (group.destinations.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(inset, 0, inset, 30),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final destination = group.destinations[index];
                          final overallIndex = activeModule.destinations
                              .indexOf(destination);
                          final start = (0.34 + overallIndex * 0.027)
                              .clamp(0.34, 0.78)
                              .toDouble();
                          return _fadeSlide(
                            begin: start,
                            end: (start + 0.22).clamp(0.56, 1).toDouble(),
                            offsetY: 0.10,
                            child: _ModuleTile(
                              destination: destination,
                              onTap: () => widget.onSelect(destination.index),
                            ),
                          );
                        }, childCount: group.destinations.length),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 250,
                              mainAxisExtent: 116,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                            ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRetailModuleScaffold(
    BuildContext context,
    ThemeData theme,
    double maxWidth,
    double inset,
    List<_FeatureGridGroup> featureGroups,
    String normalizedQuery,
    int visibleModuleCount,
  ) {
    final hasQuery = normalizedQuery.isNotEmpty;
    final contentMaxWidth = 1240.0;
    final effectiveInset = maxWidth > contentMaxWidth + 64
        ? (maxWidth - contentMaxWidth) / 2
        : inset;
    final recentDestinations = _recentDestinationIndexes
        .map(
          (index) => widget.businessModules
              .expand((module) => module.destinations)
              .firstWhere(
                (destination) => destination.index == index,
                orElse: () => _NavDestination(
                  index: index,
                  section: _NavSection.main,
                  item: _NavItem(
                    icon: Icons.circle,
                    selectedIcon: Icons.circle,
                    label: '',
                  ),
                ),
              ),
        )
        .where(
          (destination) => featureGroups.any(
            (group) => group.destinations.contains(destination),
          ),
        )
        .toList(growable: false);

    final gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: _compactLayout ? 200 : 252,
      mainAxisExtent: _compactLayout ? 80 : 104,
      mainAxisSpacing: _compactLayout ? 10 : 14,
      crossAxisSpacing: _compactLayout ? 10 : 14,
    );

    List<Widget> sectionSlivers(_FeatureGridGroup group) {
      if (group.destinations.isEmpty) return const <Widget>[];
      return [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(effectiveInset, 16, effectiveInset, 12),
          sliver: SliverToBoxAdapter(
            child: _RetailModuleSectionHeader(
              title: group.title,
              subtitle: group.subtitle,
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(effectiveInset, 0, effectiveInset, 4),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) {
              final destination = group.destinations[index];
              final start = (0.34 + index * 0.03).clamp(0.34, 0.78).toDouble();
              return _fadeSlide(
                begin: start,
                end: (start + 0.22).clamp(0.56, 1).toDouble(),
                offsetY: 0.10,
                child: _RetailModuleCard(
                  destination: destination,
                  compact: _compactLayout,
                  onTap: () {
                    _recordRecent(destination.index);
                    widget.onSelect(destination.index);
                  },
                ),
              );
            }, childCount: group.destinations.length),
            gridDelegate: gridDelegate,
          ),
        ),
      ];
    }

    final isMobile = maxWidth < 600;

    if (isMobile) {
      return _buildRetailMobileScaffold(
        context: context,
        theme: theme,
        maxWidth: maxWidth,
        featureGroups: featureGroups,
        recentDestinations: recentDestinations,
        hasQuery: hasQuery,
        visibleModuleCount: visibleModuleCount,
      );
    }

    final desktopBody = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(effectiveInset, 22, effectiveInset, 8),
          sliver: SliverToBoxAdapter(
            child: _RetailModulesHeader(onCustomize: _onCustomizeModules),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(effectiveInset, 14, effectiveInset, 14),
          sliver: SliverToBoxAdapter(
            child: _RetailModuleSearch(
              controller: _moduleSearchController,
              query: _moduleSearchQuery,
              resultCount: visibleModuleCount,
              focusNode: _moduleSearchFocusNode,
              compact: _compactLayout,
              onChanged: (value) => setState(() => _moduleSearchQuery = value),
              onClear: _clearModuleSearch,
              onToggleCompact: () =>
                  setState(() => _compactLayout = !_compactLayout),
            ),
          ),
        ),
        if (hasQuery && featureGroups.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              effectiveInset,
              24,
              effectiveInset,
              48,
            ),
            sliver: const SliverToBoxAdapter(
              child: _RetailModuleSearchEmptyState(),
            ),
          )
        else ...<Widget>[
          if (!hasQuery && recentDestinations.isNotEmpty) ...[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                effectiveInset,
                6,
                effectiveInset,
                12,
              ),
              sliver: SliverToBoxAdapter(
                child: _RetailModuleSectionHeader(
                  title: 'RECENT',
                  subtitle: 'Modules you opened this session.',
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                effectiveInset,
                0,
                effectiveInset,
                8,
              ),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final destination = recentDestinations[index];
                  return _RetailModuleCard(
                    destination: destination,
                    compact: _compactLayout,
                    emphasized: false,
                    onTap: () {
                      _recordRecent(destination.index);
                      widget.onSelect(destination.index);
                    },
                  );
                }, childCount: recentDestinations.length),
                gridDelegate: gridDelegate,
              ),
            ),
          ],
          for (final group in featureGroups) ...sectionSlivers(group),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _FocusModuleSearchIntent(),
        },
        child: Actions(
          dispatcher: ActionDispatcher(),
          actions: <Type, Action<Intent>>{
            _FocusModuleSearchIntent: CallbackAction<_FocusModuleSearchIntent>(
              onInvoke: (_) {
                _moduleSearchFocusNode.requestFocus();
                return null;
              },
            ),
          },
          child: SafeArea(child: desktopBody),
        ),
      ),
    );
  }

  Widget _buildRetailMobileScaffold({
    required BuildContext context,
    required ThemeData theme,
    required double maxWidth,
    required List<_FeatureGridGroup> featureGroups,
    required List<_NavDestination> recentDestinations,
    required bool hasQuery,
    required int visibleModuleCount,
  }) {
    const pagePadding = 16.0;
    const gridSpacing = 12.0;
    final cardWidth = (maxWidth - pagePadding * 2 - gridSpacing) / 2;
    final cardHeight = (cardWidth * 1.1).clamp(150.0, 180.0);

    final mobileGridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: gridSpacing,
      mainAxisSpacing: gridSpacing,
      mainAxisExtent: cardHeight,
    );

    List<Widget> mobileSectionSlivers(_FeatureGridGroup group) {
      if (group.destinations.isEmpty) return const <Widget>[];
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(pagePadding, 26, pagePadding, 12),
          sliver: SliverToBoxAdapter(
            child: _RetailModuleSectionHeader(
              title: group.title,
              subtitle: group.subtitle,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(pagePadding, 0, pagePadding, 4),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) {
              final destination = group.destinations[index];
              final start = (0.34 + index * 0.03).clamp(0.34, 0.78).toDouble();
              return _fadeSlide(
                begin: start,
                end: (start + 0.22).clamp(0.56, 1).toDouble(),
                offsetY: 0.10,
                child: _MobileRetailModuleCard(
                  destination: destination,
                  onTap: () {
                    _recordRecent(destination.index);
                    widget.onSelect(destination.index);
                  },
                ),
              );
            }, childCount: group.destinations.length),
            gridDelegate: mobileGridDelegate,
          ),
        ),
      ];
    }

    final slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(pagePadding, 20, pagePadding, 8),
        sliver: SliverToBoxAdapter(
          child: _RetailModulesHeader(onCustomize: _onCustomizeModules),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(pagePadding, 14, pagePadding, 14),
        sliver: SliverToBoxAdapter(
          child: _RetailModuleSearch(
            controller: _moduleSearchController,
            query: _moduleSearchQuery,
            resultCount: visibleModuleCount,
            focusNode: _moduleSearchFocusNode,
            compact: false,
            showShortcut: false,
            hintText: 'Search modules...',
            onChanged: (value) => setState(() => _moduleSearchQuery = value),
            onClear: _clearModuleSearch,
            onToggleCompact: () {},
          ),
        ),
      ),
      if (hasQuery && featureGroups.isEmpty)
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(pagePadding, 24, pagePadding, 48),
          sliver: SliverToBoxAdapter(child: _RetailModuleSearchEmptyState()),
        )
      else ...<Widget>[
        if (!hasQuery && recentDestinations.isNotEmpty) ...[
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(pagePadding, 6, pagePadding, 12),
            sliver: SliverToBoxAdapter(
              child: _RetailModuleSectionHeader(
                title: 'RECENT',
                subtitle: 'Modules you opened this session.',
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(pagePadding, 0, pagePadding, 8),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((context, index) {
                final destination = recentDestinations[index];
                return _MobileRetailModuleCard(
                  destination: destination,
                  onTap: () {
                    _recordRecent(destination.index);
                    widget.onSelect(destination.index);
                  },
                );
              }, childCount: recentDestinations.length),
              gridDelegate: mobileGridDelegate,
            ),
          ),
        ],
        for (final group in featureGroups) ...mobileSectionSlivers(group),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _FocusModuleSearchIntent(),
        },
        child: Actions(
          dispatcher: ActionDispatcher(),
          actions: <Type, Action<Intent>>{
            _FocusModuleSearchIntent: CallbackAction<_FocusModuleSearchIntent>(
              onInvoke: (_) {
                _moduleSearchFocusNode.requestFocus();
                return null;
              },
            ),
          },
          child: SafeArea(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: slivers,
            ),
          ),
        ),
      ),
    );
  }

  void _onCustomizeModules(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Module customization is coming soon.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

class _FocusModuleSearchIntent extends Intent {
  const _FocusModuleSearchIntent();
}

class _ModuleLauncherRootHeader extends StatelessWidget {
  final VoidCallback onOpenSettings;
  final VoidCallback onNotifications;
  final Widget notificationIcon;

  const _ModuleLauncherRootHeader({
    required this.onOpenSettings,
    required this.onNotifications,
    required this.notificationIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const PikiMark(size: 46),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ShopSettings.shopName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${SessionService.currentUserName} · ${RolePermissions.label(SessionService.currentUserRole)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Notifications',
          onPressed: onNotifications,
          icon: notificationIcon,
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: onOpenSettings,
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }
}

class _BusinessModuleTile extends StatefulWidget {
  final _BusinessModule module;
  final VoidCallback onTap;

  const _BusinessModuleTile({required this.module, required this.onTap});

  @override
  State<_BusinessModuleTile> createState() => _BusinessModuleTileState();
}

class _BusinessModuleTileState extends State<_BusinessModuleTile> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final module = widget.module;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.985 : (_hovered ? 1.004 : 1),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: _hovered
                    ? module.accent.withValues(alpha: 0.045)
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: _pressed || _hovered
                      ? module.accent.withValues(alpha: 0.62)
                      : theme.colorScheme.outline.withValues(alpha: 0.72),
                ),
                boxShadow: const [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: module.accent.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Icon(
                          module.icon,
                          color: module.accent,
                          size: 20,
                        ),
                      ),
                      const Spacer(),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _hovered
                              ? module.accent
                              : module.accent.withValues(alpha: 0.11),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_outward_rounded,
                          color: _hovered ? Colors.white : module.accent,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    module.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    module.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 9),
                  Text(
                    module.readinessLabel ??
                        '${module.destinations.length} tools ready',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: module.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.25,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RetailModuleSearch extends StatefulWidget {
  final TextEditingController controller;
  final String query;
  final int resultCount;
  final FocusNode focusNode;
  final bool compact;
  final bool showShortcut;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onToggleCompact;

  const _RetailModuleSearch({
    required this.controller,
    required this.query,
    required this.resultCount,
    required this.focusNode,
    required this.compact,
    this.showShortcut = true,
    this.hintText = 'Search modules or actions...',
    required this.onChanged,
    required this.onClear,
    required this.onToggleCompact,
  });

  @override
  State<_RetailModuleSearch> createState() => _RetailModuleSearchState();
}

class _RetailModuleSearchState extends State<_RetailModuleSearch> {
  late final FocusNode _keyboardFocusNode;

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final focusNode = widget.focusNode;
    final onChanged = widget.onChanged;
    final onClear = widget.onClear;
    final onToggleCompact = widget.onToggleCompact;
    final compact = widget.compact;
    final query = widget.query;
    final resultCount = widget.resultCount;
    final showShortcut = widget.showShortcut;
    final hintText = widget.hintText;
    final hasQuery = query.trim().isNotEmpty;
    final isWide = MediaQuery.sizeOf(context).width > 720;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: KeyboardListener(
                focusNode: _keyboardFocusNode,
                onKeyEvent: (event) {
                  if (event.logicalKey == LogicalKeyboardKey.escape &&
                      (hasQuery || focusNode.hasFocus)) {
                    onClear();
                    if (focusNode.hasFocus) focusNode.unfocus();
                  }
                },
                child: Semantics(
                  textField: true,
                  label: 'Search retail modules',
                  child: TextField(
                    key: const ValueKey('retail-module-search-field'),
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: hintText,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: hasQuery
                          ? IconButton(
                              tooltip: 'Clear module search',
                              onPressed: onClear,
                              icon: const Icon(Icons.close_rounded),
                            )
                          : showShortcut
                          ? Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: IgnorePointer(
                                child: _RetailShortcutHint(),
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 17,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (isWide) ...[
              const SizedBox(width: 12),
              _RetailLayoutToggle(compact: compact, onToggle: onToggleCompact),
            ],
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: hasQuery
              ? Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(
                    resultCount == 1
                        ? '1 module found'
                        : '$resultCount modules found',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _RetailShortcutHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMac =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isMac ? '⌘ K' : 'Ctrl + K',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _RetailLayoutToggle extends StatelessWidget {
  final bool compact;
  final VoidCallback onToggle;

  const _RetailLayoutToggle({required this.compact, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = [
      (label: 'Grid', icon: Icons.grid_view_rounded, active: !compact),
      (label: 'Compact', icon: Icons.view_agenda_rounded, active: compact),
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            for (final segment in segments)
              _RetailLayoutSegment(
                label: segment.label,
                icon: segment.icon,
                active: segment.active,
                onTap: onToggle,
              ),
          ],
        ),
      ),
    );
  }
}

class _RetailLayoutSegment extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _RetailLayoutSegment({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  State<_RetailLayoutSegment> createState() => _RetailLayoutSegmentState();
}

class _RetailLayoutSegmentState extends State<_RetailLayoutSegment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.active
                  ? activeColor.withValues(alpha: 0.12)
                  : (_hovered
                        ? theme.colorScheme.surfaceContainerHighest
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: widget.active
                      ? activeColor
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: widget.active
                        ? activeColor
                        : theme.colorScheme.onSurfaceVariant,
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

class _RetailModulesHeader extends StatelessWidget {
  final void Function(BuildContext) onCustomize;

  const _RetailModulesHeader({required this.onCustomize});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width > 640;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Retail Modules',
                style: TextStyle(
                  fontSize: isWide ? 30 : 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage sales, stock, customers, payments and business operations.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: isWide ? 15 : 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (isWide) ...[
          const SizedBox(width: 16),
          _RetailCustomizeButton(onCustomize: onCustomize),
        ],
      ],
    );
  }
}

class _RetailCustomizeButton extends StatefulWidget {
  final void Function(BuildContext) onCustomize;

  const _RetailCustomizeButton({required this.onCustomize});

  @override
  State<_RetailCustomizeButton> createState() => _RetailCustomizeButtonState();
}

class _RetailCustomizeButtonState extends State<_RetailCustomizeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Reorder, pin or hide modules',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => widget.onCustomize(context),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _hovered
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Customize modules',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RetailModuleSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _RetailModuleSectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _RetailModuleSearchEmptyState extends StatelessWidget {
  const _RetailModuleSearchEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 34,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No retail modules found',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Try another name or task, such as “sales”, “stock”, or “invoice”.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetailModuleCard extends StatefulWidget {
  final _NavDestination destination;
  final bool compact;
  final bool emphasized;
  final VoidCallback onTap;

  const _RetailModuleCard({
    required this.destination,
    this.compact = false,
    this.emphasized = false,
    required this.onTap,
  });

  @override
  State<_RetailModuleCard> createState() => _RetailModuleCardState();
}

class _RetailModuleCardState extends State<_RetailModuleCard> {
  bool _hovered = false;
  bool _pressed = false;

  _RetailModuleColors _colorsFor(BuildContext context) {
    final style = _retailModuleStyles[widget.destination.index];
    if (style != null) return style.colors.forTheme(Theme.of(context));
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return _RetailModuleColors(
      background: theme.colorScheme.surface,
      iconBackground: accent.withValues(alpha: 0.12),
      iconColor: accent,
      border: theme.colorScheme.outline.withValues(alpha: 0.6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _retailModuleStyles[widget.destination.index];
    final colors = _colorsFor(context);
    final title = widget.destination.item.label;
    final description = style?.description ?? 'Open module';
    final emphasized =
        widget.emphasized || (style?.emphasized == true && !widget.compact);

    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w700,
      fontSize: emphasized ? 16 : 15,
      letterSpacing: -0.2,
    );
    final descriptionStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: widget.compact ? 12 : 13,
    );

    final card = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.985 : (_hovered ? 1.004 : 1),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            focusColor: colors.iconColor.withValues(alpha: 0.1),
            hoverColor: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 14 : 18,
                vertical: widget.compact ? 12 : 18,
              ),
              decoration: BoxDecoration(
                color: _hovered
                    ? Color.lerp(colors.background, colors.iconColor, 0.07)
                    : colors.background,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(
                  color: _hovered || _pressed
                      ? colors.iconColor.withValues(alpha: 0.6)
                      : colors.border,
                  width: _hovered || _pressed ? 1.5 : 1,
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: colors.iconColor.withValues(alpha: 0.14),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: widget.compact ? 36 : 42,
                    height: widget.compact ? 36 : 42,
                    decoration: BoxDecoration(
                      color: colors.iconBackground,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(
                      widget.destination.item.selectedIcon,
                      color: colors.iconColor,
                      size: widget.compact ? 19 : 22,
                    ),
                  ),
                  SizedBox(width: widget.compact ? 12 : 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        if (!widget.compact) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: descriptionStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.only(left: _hovered ? 3 : 0),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: widget.compact ? 16 : 18,
                      color: _hovered
                          ? colors.iconColor
                          : theme.colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.4,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(button: true, label: '$title. $description', child: card);
  }
}

class _MobileRetailModuleCard extends StatefulWidget {
  final _NavDestination destination;
  final VoidCallback onTap;

  const _MobileRetailModuleCard({
    required this.destination,
    required this.onTap,
  });

  @override
  State<_MobileRetailModuleCard> createState() =>
      _MobileRetailModuleCardState();
}

class _MobileRetailModuleCardState extends State<_MobileRetailModuleCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _retailModuleStyles[widget.destination.index];
    final colors =
        style?.colors.forTheme(theme) ??
        _RetailModuleColors(
          background: theme.colorScheme.surface,
          iconBackground: theme.colorScheme.primary.withValues(alpha: 0.12),
          iconColor: theme.colorScheme.primary,
          border: theme.colorScheme.outline.withValues(alpha: 0.6),
        );
    final title = widget.destination.item.label;
    final description =
        _retailMobileDescriptions[widget.destination.index] ??
        style?.description ??
        'Open module';

    final card = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.985 : (_hovered ? 1.004 : 1),
        child: Material(
          color: _hovered
              ? Color.lerp(colors.background, colors.iconColor, 0.07)
              : colors.background,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            focusColor: colors.iconColor.withValues(alpha: 0.1),
            hoverColor: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(
                  color: _hovered || _pressed
                      ? colors.iconColor.withValues(alpha: 0.6)
                      : colors.border,
                  width: _hovered || _pressed ? 1.5 : 1,
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: colors.iconColor.withValues(alpha: 0.14),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: colors.iconBackground,
                          borderRadius: BorderRadius.circular(AppRadius.md + 4),
                        ),
                        child: Icon(
                          widget.destination.item.selectedIcon,
                          color: colors.iconColor,
                          size: 22,
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: _hovered
                            ? colors.iconColor
                            : theme.colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.4,
                              ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(button: true, label: '$title. $description', child: card);
  }
}

class _AnimatedModuleHero extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedModuleHero({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final animation = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.08, 0.54, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            const height = 144.0;
            return ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.76),
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      right: compact ? -24 : 24,
                      top: compact ? 8 : 6,
                      child: Opacity(
                        opacity: theme.brightness == Brightness.dark
                            ? 0.08
                            : 0.045,
                        child: PikiMark(
                          size: compact ? 138 : 120,
                          radius: compact ? 30 : 26,
                        ),
                      ),
                    ),
                    Positioned(
                      right: compact ? 18 : 174,
                      bottom: compact ? 16 : 20,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: const BoxDecoration(
                          color: AppColors.signal,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            theme.colorScheme.surface,
                            theme.colorScheme.surface,
                            theme.colorScheme.surface.withValues(alpha: 0.7),
                          ],
                          stops: const [0, 0.58, 1],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(compact ? 18 : 22),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: compact ? 310 : 590,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.sm,
                                  ),
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.18,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 7,
                                      height: 7,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: AppColors.signal,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 7),
                                    Text(
                                      'READY FOR TRADE',
                                      style: TextStyle(
                                        color: theme
                                            .colorScheme
                                            .onPrimaryContainer,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.9,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: compact ? 10 : 12),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Today at a glance',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontSize: compact ? 22 : 26,
                                    height: 1.08,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.7,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Choose a workspace to sell, restock, or review performance.',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: compact ? 12 : 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 14 * (1 - animation.value)),
          child: Transform.scale(
            scale: 0.975 + (0.025 * animation.value),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ModuleTile extends StatefulWidget {
  final _NavDestination destination;
  final VoidCallback onTap;

  const _ModuleTile({required this.destination, required this.onTap});

  @override
  State<_ModuleTile> createState() => _ModuleTileState();
}

class _ModuleTileState extends State<_ModuleTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return AnimatedScale(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      scale: _pressed ? 0.975 : 1,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (pressed) => setState(() => _pressed = pressed),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: _pressed
                    ? accent.withValues(alpha: 0.72)
                    : theme.colorScheme.outline.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    widget.destination.item.selectedIcon,
                    color: accent,
                    size: 19,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.destination.item.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Open module',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer
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
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  hoverColor: theme.brightness == Brightness.dark
                      ? Colors.white
                      : theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
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
