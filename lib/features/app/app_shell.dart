import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/database_service.dart';
import '../../core/services/app_version_service.dart';
import '../../core/services/device_notification_service.dart';
import '../../core/services/external_app_launcher.dart';
import '../../core/services/session_service.dart';
import '../../core/services/shop_settings.dart';
import '../../core/services/branch_service.dart';
import '../../core/services/sync_controller.dart';
import '../../core/services/sync_settings_service.dart';
import '../../core/services/license_service.dart';
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
import 'dashboard_screen.dart';
import '../../widgets/beautiful_icon.dart';

class AppShell extends ConsumerStatefulWidget {
  final int initialIndex;

  const AppShell({super.key, this.initialIndex = defaultInitialIndex});

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
  bool _moduleHeroPrecached = false;
  AppVersionInfo? _appVersionInfo;

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

  bool get _isServiceOnlyAccount =>
      !SessionService.canUseProductPos && SessionService.canUseServicePos;

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
    if (_isServiceOnlyAccount && index == _posIndex) {
      return _servicesIndex;
    }
    return index;
  }

  int _initialIndexForCurrentAccount(int index) {
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
          ),
        );
      }
    }

    addModule(
      id: 'retail_pos',
      title: 'Retail POS',
      subtitle: 'Checkout, orders, sales, and customer balances.',
      icon: Icons.point_of_sale_rounded,
      accent: AppColors.primary,
      indexes: indexesForBusiness(const [0, 17, 4, 19, 20, 6, 18, 10]),
      coreIndexes: const [0, 17, 4, 19, 20, 6, 18, 10],
      enabled: SessionService.canUseProductPos,
    );
    addModule(
      id: 'services',
      title: 'Services',
      subtitle: 'Service desk, queues, quotes, and customer work.',
      icon: Icons.design_services_rounded,
      accent: const Color(0xFF8E4EC6),
      indexes: indexesForBusiness(const [11, 4, 19, 20, 18, 10]),
      coreIndexes: const [11, 4, 19, 20, 18, 10],
      enabled: SessionService.canUseServicePos,
    );
    addModule(
      id: 'restaurant',
      title: 'Restaurant',
      subtitle: 'Tables, kitchen flow, orders, and delivery.',
      icon: Icons.restaurant_rounded,
      accent: const Color(0xFFE1762F),
      indexes: indexesForBusiness(const [29, 0, 17, 33, 18, 4, 10]),
      coreIndexes: const [29, 0, 17, 33, 18, 4, 10],
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
          accent: AppColors.primary,
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
    _selectedIndex = _initialIndexForCurrentAccount(widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSeenNotifications();
      _loadDeviceNotificationIds();
      _loadAppVersionNotice();
      _showStartupPrompts();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_moduleHeroPrecached) return;
    _moduleHeroPrecached = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        precacheImage(
          const AssetImage('assets/images/module_launcher_hero.png'),
          context,
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _selectedIndex = _initialIndexForCurrentAccount(widget.initialIndex);
      _navigationHistory.clear();
    }
  }

  void _selectIndex(int index) {
    final target = _normalizeNavigationIndex(index);
    final current = _currentIndex;
    if (!_allowedIndices.contains(target) || current == target) {
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

  void _showNotificationsSheet() {
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

    if (appVersion?.hasUpdate == true) {
      notifications.add(
        _AppNotification(
          id: 'app_update_${appVersion!.latestVersion}',
          icon: Icons.system_update_alt_outlined,
          color: AppColors.primaryLight,
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
          color: AppColors.primaryLight,
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
                  preferredSize: const Size.fromHeight(48),
                  child: _ModuleNavigationBar(
                    moduleLabel: _moduleLabelForIndex(moduleCurrentIndex),
                    hasBackDestination: _hasBackDestination,
                    onBack: _goBack,
                    onModules: () => _selectIndex(35),
                  ),
                ),
          body: _buildScreenStack(moduleCurrentIndex),
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
                                    'assets/images/logo.png',
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
              child: _buildScreenStack(currentIndex),
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
                      'assets/images/logo.png',
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

  Widget _buildScreenStack(int currentIndex) {
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
        child: _buildScreen(currentIndex),
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
        return const RestaurantScreen();
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
        );
      default:
        return const PosScreen();
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
  final bool hasBackDestination;
  final VoidCallback onBack;
  final VoidCallback onModules;

  const _ModuleNavigationBar({
    required this.moduleLabel,
    required this.hasBackDestination,
    required this.onBack,
    required this.onModules,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
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
              const SizedBox(width: 2),
              TextButton.icon(
                onPressed: onModules,
                icon: const Icon(Icons.grid_view_rounded, size: 18),
                label: const Text('Modules'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 1,
                height: 20,
                color: theme.colorScheme.outlineVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  moduleLabel,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
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

class _BusinessModule {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<_NavDestination> destinations;
  final List<int> coreDestinationIndexes;

  const _BusinessModule({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.destinations,
    required this.coreDestinationIndexes,
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

  const _ModuleLauncherScreen({
    required this.businessModules,
    required this.onSelect,
  });

  @override
  State<_ModuleLauncherScreen> createState() => _ModuleLauncherScreenState();
}

class _ModuleLauncherScreenState extends State<_ModuleLauncherScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
  }

  @override
  void dispose() {
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
    if (_activeModuleId != null && _activeModule == null) {
      _activeModuleId = null;
    }
  }

  void _openBusinessModule(_BusinessModule module) {
    setState(() => _activeModuleId = module.id);
    _entranceController.forward(from: 0);
  }

  void _returnToBusinessModules() {
    setState(() => _activeModuleId = null);
    _entranceController.forward(from: 0);
  }

  Widget _buildBusinessModuleRoot(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              sliver: SliverToBoxAdapter(
                child: _ModuleLauncherRootHeader(
                  onOpenSettings: () => widget.onSelect(9),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              sliver: SliverToBoxAdapter(
                child: _AnimatedModuleHero(controller: _entranceController),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BUSINESS MODULES',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Your plan and business type decide what is available.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
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
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 166,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
              ),
            ),
          ],
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
    final coreDestinations = activeModule.destinations
        .where(
          (destination) =>
              activeModule.coreDestinationIndexes.contains(destination.index),
        )
        .toList(growable: false);
    final sharedDestinations = activeModule.destinations
        .where(
          (destination) =>
              !activeModule.coreDestinationIndexes.contains(destination.index),
        )
        .toList(growable: false);
    final featureGroups = <_FeatureGridGroup>[
      if (coreDestinations.isNotEmpty)
        _FeatureGridGroup(
          title: 'CORE FEATURES',
          subtitle: 'Day-to-day tools for this business type.',
          destinations: coreDestinations,
        ),
      if (sharedDestinations.isNotEmpty)
        _FeatureGridGroup(
          title: 'SHARED TOOLS',
          subtitle: 'Inventory, insights, and management for this business.',
          destinations: sharedDestinations,
        ),
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              sliver: SliverToBoxAdapter(
                child: _fadeSlide(
                  begin: 0,
                  end: 0.28,
                  offsetY: -0.08,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back to business modules',
                        onPressed: _returnToBusinessModules,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 42,
                          height: 42,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 42,
                            height: 42,
                            color: theme.colorScheme.primary,
                            child: const Icon(
                              Icons.point_of_sale_rounded,
                              color: Colors.white,
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
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              sliver: SliverToBoxAdapter(
                child: _AnimatedModuleHero(controller: _entranceController),
              ),
            ),
            for (final group in featureGroups) ...[
              if (group.destinations.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final destination = group.destinations[index];
                      final overallIndex = activeModule.destinations.indexOf(
                        destination,
                      );
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
                          maxCrossAxisExtent: 190,
                          mainAxisExtent: 148,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                        ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModuleLauncherRootHeader extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const _ModuleLauncherRootHeader({required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Image.asset(
            'assets/images/logo.png',
            width: 42,
            height: 42,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 42,
              height: 42,
              color: theme.colorScheme.primary,
              child: const Icon(
                Icons.point_of_sale_rounded,
                color: Colors.white,
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
                ShopSettings.shopName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                '${SessionService.currentUserName} · ${RolePermissions.label(SessionService.currentUserRole)}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_outlined),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final module = widget.module;
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
                    ? module.accent.withValues(alpha: 0.76)
                    : theme.colorScheme.outline.withValues(alpha: 0.6),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: module.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(module.icon, color: module.accent),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: module.accent,
                      size: 18,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  module.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${module.destinations.length} features available',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
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

class _AnimatedModuleHero extends StatelessWidget {
  final AnimationController controller;

  const _AnimatedModuleHero({required this.controller});

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.08, 0.54, curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 218,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/module_launcher_hero.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.centerRight,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        const Color(0xFF0C1125).withValues(alpha: 0.98),
                        const Color(0xFF10132D).withValues(alpha: 0.83),
                        const Color(0xFF10132D).withValues(alpha: 0.08),
                      ],
                      stops: const [0, 0.48, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Your workspace',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Everything you need\nfor today’s trade.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Choose a module to get started.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.destination.item.selectedIcon,
                    color: accent,
                  ),
                ),
                const Spacer(),
                Text(
                  widget.destination.item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Open module',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
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
