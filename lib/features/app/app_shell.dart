import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/database_service.dart';
import '../../core/services/app_version_service.dart';
import '../../core/services/device_notification_service.dart';
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
import '../customers/presentation/kopesha_screen.dart';
import '../invoices/presentation/customer_invoices_screen.dart';
import '../products/presentation/catalog_orders_screen.dart';
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
import '../settings/presentation/subscription_plans_section.dart';
import '../shifts/presentation/shift_management_screen.dart';
import 'dashboard_screen.dart';
import '../../widgets/beautiful_icon.dart';

class AppShell extends ConsumerStatefulWidget {
  final int initialIndex;

  const AppShell({super.key, this.initialIndex = defaultInitialIndex});

  static const int defaultInitialIndex = 5;
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
  final Map<int, Widget> _screenCache = <int, Widget>{};
  String _trainingPromptUserId = '';
  bool _subscriptionPromptShown = false;
  bool _setupPromptShown = false;
  bool _desktopRailCollapsed = false;
  Set<String> _seenNotificationIds = const <String>{};
  Set<String> _deviceNotifiedIds = const <String>{};
  bool _deviceNotificationBusy = false;
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
      index: 18,
      section: _NavSection.reports,
      item: _NavItem(
        icon: Icons.contacts_outlined,
        selectedIcon: Icons.contacts_rounded,
        label: 'Contacts',
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

  static const _mobileBottomDefaults = [5, 0, 1, 17];
  static const _fallbackNavigationIndex = 9;
  static const _posIndex = 0;
  static const _servicesIndex = 11;

  bool get _isServiceOnlyAccount =>
      !SessionService.canUseProductPos && SessionService.canUseServicePos;

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
    if (SessionService.canAccessFeature(UserAccessProfile.featureKopesha) ||
        SessionService.canAccessFeature(UserAccessProfile.featurePurchases)) {
      indices.add(18);
    }
    final allowed = indices
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
    if (_isServiceOnlyAccount &&
        (index == AppShell.defaultInitialIndex || index == _posIndex)) {
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
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _selectedIndex = _initialIndexForCurrentAccount(widget.initialIndex);
    }
  }

  void _selectIndex(int index) {
    final target = _normalizeNavigationIndex(index);
    if (!_allowedIndices.contains(target) || _selectedIndex == target) {
      return;
    }
    setState(() => _selectedIndex = target);
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
          destinationIndex: 9,
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
      }
    } catch (_) {
      // Update checks should never block app startup.
    }
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
                            onTap: notification.destinationIndex == null
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
                            trailing: notification.destinationIndex == null
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
                                  hoverColor: theme.brightness == Brightness.dark
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
                  alpha: 0.1,
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
    final allowed = _allowedIndices.toSet();
    _screenCache.removeWhere((index, _) => !allowed.contains(index));
    _screenCache.putIfAbsent(currentIndex, () => _buildScreen(currentIndex));

    final cachedIndices = _screenCache.keys.toList(growable: false)..sort();
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final index in cachedIndices)
          Offstage(
            offstage: index != currentIndex,
            child: TickerMode(
              enabled: index == currentIndex,
              child: KeyedSubtree(
                key: ValueKey('shell-screen-$index'),
                child: _screenCache[index]!,
              ),
            ),
          ),
      ],
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
  }) : id = id ?? '$title|$message';
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
