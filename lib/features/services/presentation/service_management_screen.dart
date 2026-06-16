import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/features/app/app_shell.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/services/session_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/error_messages.dart';
import '../../customers/data/customer_repository.dart';
import '../../sales/data/cart_provider.dart';
import '../../sales/data/sale_repository.dart';
import '../../sales/presentation/payment_checkout_dialog.dart';
import '../../shifts/data/shift_preferences_service.dart';
import '../../shifts/data/shift_provider.dart';
import '../../shifts/data/shift_repository.dart';
import '../../shifts/presentation/shift_auto_open_dialog.dart';
import '../../training/widgets/training_anchor.dart';
import '../data/service_provider.dart';
import '../data/service_repository.dart';
import 'carwash_queue_screen.dart';

const _serviceFieldTypes = ['text', 'number', 'date', 'boolean', 'select'];

double _roundMoney(double value) {
  return double.parse(value.toStringAsFixed(2));
}

bool _canChargeServiceStatus(String status) {
  return status == 'ready' || status == 'completed';
}

String? _nextServiceStatus(String currentStatus) {
  switch (currentStatus) {
    case 'booked':
      return 'checked_in';
    case 'checked_in':
      return 'in_progress';
    case 'in_progress':
      return 'completed';
    case 'ready':
      return 'completed';
    default:
      return null;
  }
}

String _advanceServiceActionLabel(String status) {
  switch (status) {
    case 'booked':
      return 'Check In';
    case 'checked_in':
      return 'Start';
    case 'in_progress':
    case 'ready':
      return 'Complete';
    default:
      return 'Update';
  }
}

class ServiceManagementScreen extends ConsumerStatefulWidget {
  const ServiceManagementScreen({super.key});

  @override
  ConsumerState<ServiceManagementScreen> createState() =>
      _ServiceManagementScreenState();
}

class _ServiceManagementScreenState
    extends ConsumerState<ServiceManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  static const _tabTitles = ['Sell', 'Orders', 'Catalog', 'Reports'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(servicesProvider);
    ref.invalidate(activeServicesProvider); // POS panel service grid
    ref.invalidate(serviceOrdersProvider);
    ref.invalidate(serviceTodayOrdersProvider); // POS panel today queue
    ref.invalidate(serviceStatsProvider);
    ref.invalidate(serviceSalesByDateProvider);
  }

  bool get _showsOrderCreationAction => _tabController.index == 1;

  Future<void> _handlePrimaryAction() async {
    if (_showsOrderCreationAction) {
      final services = await ServiceRepository.getServices(activeOnly: true);
      if (!mounted) return;
      await showCreateServiceOrderDialog(context, ref, services: services);
      _refresh();
      return;
    }

    await showServiceEditorDialog(context, ref);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: !Navigator.of(context).canPop() &&
                MediaQuery.of(context).size.width <= 800
            ? IconButton(
                icon: Icon(Icons.menu),
                onPressed: () => AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        title: Text('Services'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [for (final title in _tabTitles) Tab(text: title)],
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          SizedBox(width: 8),
        ],
      ),
      body: TrainingAnchor(
        id: 'services.workspace',
        child: TabBarView(
          controller: _tabController,
          children: [
            ServicePosPanel(
              onOpenOrders: () => _tabController.animateTo(1),
              onRefresh: _refresh,
            ),
            _OrdersTab(onRefresh: _refresh),
            _CatalogTab(onRefresh: _refresh),
            _ServiceReportsTab(onRefresh: _refresh),
          ],
        ),
      ),
      floatingActionButton:
          _tabController.index == 0 || _tabController.index == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: _handlePrimaryAction,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: Icon(
                _showsOrderCreationAction ? Icons.add_task : Icons.add_business,
              ),
              label: Text(
                _showsOrderCreationAction ? 'New Order' : 'New Service',
              ),
            ),
    );
  }
}

class ServicePosPanel extends ConsumerStatefulWidget {
  final VoidCallback? onOpenOrders;
  final VoidCallback? onRefresh;

  const ServicePosPanel({super.key, this.onOpenOrders, this.onRefresh});

  @override
  ConsumerState<ServicePosPanel> createState() => _ServicePosPanelState();
}

class _ServicePosPanelState extends ConsumerState<ServicePosPanel> {
  String? _selectedCategory;
  String _serviceQuery = '';
  final TextEditingController _serviceSearchController =
      TextEditingController();

  @override
  void dispose() {
    _serviceSearchController.dispose();
    super.dispose();
  }

  void _showQuickSellSnackBar(bool success, String serviceName) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.warning_amber,
              color: Colors.white,
              size: 18,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                success
                    ? '$serviceName added to cart'
                    : 'Could not add $serviceName to cart',
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? AppColors.success : AppColors.error,
        width: 360,
      ),
    );
  }

  Future<void> _handleQuickSellService(Map<String, dynamic> service) async {
    final serviceName = service['name'] as String? ?? 'Service';
    final basePrice = (service['base_price'] as num? ?? 0).toDouble();
    final serviceId = service['id'] as String;
    final assignedStaff = ServiceRepository.defaultAssignedStaffName();

    // Create a temporary service order for quick sell
    try {
      final orderId = await ServiceRepository.createOrder(
        serviceId: serviceId,
        serviceName: serviceName,
        entryMode: 'walk_in',
        customerName: 'Walk-in Customer',
        status: 'ready', // Mark as ready for immediate checkout
        assignedStaff: assignedStaff,
        assignedStaffUserId: ServiceRepository.currentAssignedStaffUserIdFor(
          assignedStaff,
        ),
        price: basePrice,
      );

      // Add to cart
      final success = ref
          .read(cartProvider.notifier)
          .addService(
            serviceOrderId: orderId,
            serviceId: serviceId,
            serviceName: serviceName,
            price: basePrice,
          );

      _showQuickSellSnackBar(success, serviceName);

      if (success) {
        // Refresh providers
        ref.invalidate(serviceTodayOrdersProvider);
        ref.invalidate(serviceOrdersProvider);
      }
    } catch (error) {
      _showQuickSellSnackBar(false, serviceName);
    }
  }

  Future<void> _createServiceOrder({
    required List<Map<String, dynamic>> services,
    String? initialServiceId,
    bool openQueueBoardOnSuccess = false,
  }) async {
    final created = await showCreateServiceOrderDialog(
      context,
      ref,
      services: services,
      initialServiceId: initialServiceId,
      addToCartOnSuccess: false,
    );

    ref.invalidate(serviceTodayOrdersProvider);
    ref.invalidate(serviceOrdersProvider);

    if (created && openQueueBoardOnSuccess && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CarwashQueueScreen()),
      );
    }
  }

  Future<void> _handleServiceTap(
    Map<String, dynamic> service,
    List<Map<String, dynamic>> allServices,
  ) async {
    await _handleQuickSellService(service);
  }

  void _setSelectedCategory(String? category) {
    if (_selectedCategory == category) {
      return;
    }
    setState(() => _selectedCategory = category);
  }

  void _setServiceQuery(String value) {
    setState(() => _serviceQuery = value.trim().toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final servicesAsync = ref.watch(activeServicesProvider);
    final todayOrdersAsync = ref.watch(serviceTodayOrdersProvider);
    final cart = ref.watch(cartProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth;
        final isMobile = panelWidth <= 720;
        final compactHeader = panelWidth <= 520;
        final panelPadding = compactHeader ? 14.0 : 24.0;

        return Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          padding: EdgeInsets.all(panelPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, compact: compactHeader),
              SizedBox(height: 16),
              Expanded(
                child: isMobile
                    ? _buildMobileLayout(servicesAsync, todayOrdersAsync, cart)
                    : _buildDesktopLayout(
                        servicesAsync,
                        todayOrdersAsync,
                        cart,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, {required bool compact}) {
    final title = Text(
      compact ? 'Sell Service' : 'Sell Service',
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    );

    Future<void> createOrder() async {
      final services = await ServiceRepository.getServices(activeOnly: true);
      if (!mounted) return;
      await _createServiceOrder(services: services);
      widget.onRefresh?.call();
    }

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: createOrder,
          icon: Icon(Icons.add_task, size: 18),
          label: Text(compact ? 'Order' : 'New Order'),
          style: FilledButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 10 : 13,
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: widget.onOpenOrders,
          icon: Icon(Icons.assignment_outlined, size: 18),
          label: Text('Orders'),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 14,
              vertical: compact ? 10 : 13,
            ),
          ),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Expanded(child: title)]),
          SizedBox(height: 12),
          actions,
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      runAlignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [title, actions],
    );
  }

  Widget _buildServiceSearchField({required bool compact}) {
    return SizedBox(
      height: compact ? 48 : null,
      child: TextField(
        controller: _serviceSearchController,
        onChanged: _setServiceQuery,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search services...',
          prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurfaceVariant),
          suffixIcon: _serviceQuery.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _serviceSearchController.clear();
                    setState(() => _serviceQuery = '');
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildServiceCategoryChips(
    List<String> categories, {
    required bool compact,
  }) {
    return SizedBox(
      height: compact ? 38 : null,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: Text('All'),
              selected: _selectedCategory == null,
              onSelected: (_) => _setSelectedCategory(null),
            ),
            SizedBox(width: 8),
            for (final category in categories)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(category),
                  selected: _selectedCategory == category,
                  onSelected: (_) => _setSelectedCategory(category),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileServiceList(
    List<Map<String, dynamic>> displayedServices,
    List<Map<String, dynamic>> allServices,
  ) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 104),
      itemCount: displayedServices.length,
      separatorBuilder: (_, _) => SizedBox(height: 12),
      itemBuilder: (context, index) {
        final service = displayedServices[index];
        return _MobileServiceTile(
          service: service,
          onTap: () => _handleServiceTap(service, allServices),
        );
      },
    );
  }

  Widget _buildDesktopServiceGrid(
    List<Map<String, dynamic>> displayedServices,
    List<Map<String, dynamic>> allServices,
  ) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.05,
      ),
      itemCount: displayedServices.length,
      itemBuilder: (context, index) {
        final service = displayedServices[index];
        final duration = (service['duration_minutes'] as num?)?.toInt();

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _handleServiceTap(service, allServices),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
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
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.design_services_rounded,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                      if (duration != null && duration > 0)
                        _ServiceDurationBadge(duration: duration),
                    ],
                  ),
                  SizedBox(height: 14),
                  Text(
                    service['name'] as String? ?? 'Service',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    service['category'] as String? ?? 'General',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          '${ShopSettings.currency}${(service['base_price'] as num? ?? 0).toStringAsFixed(2)}',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.add_shopping_cart_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
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
  }

  Widget _buildServiceCards(
    List<Map<String, dynamic>> displayedServices,
    List<Map<String, dynamic>> allServices, {
    required bool compact,
  }) {
    if (displayedServices.isEmpty) {
      return Center(child: Text('No matching services'));
    }
    if (compact) {
      return _buildMobileServiceList(displayedServices, allServices);
    }
    return _buildDesktopServiceGrid(displayedServices, allServices);
  }

  Widget _buildMobileLayout(
    AsyncValue<List<Map<String, dynamic>>> servicesAsync,
    AsyncValue<List<Map<String, dynamic>>> todayOrdersAsync,
    List<CartItem> cart,
  ) {
    return _buildServicesGrid(servicesAsync);
  }

  Widget _buildDesktopLayout(
    AsyncValue<List<Map<String, dynamic>>> servicesAsync,
    AsyncValue<List<Map<String, dynamic>>> todayOrdersAsync,
    List<CartItem> cart,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 6, child: _buildServicesGrid(servicesAsync)),
        SizedBox(width: 24),
        Expanded(flex: 4, child: _buildTodayOrdersList(todayOrdersAsync, cart)),
      ],
    );
  }

  Widget _buildServicesGrid(
    AsyncValue<List<Map<String, dynamic>>> servicesAsync,
  ) {
    final compact = MediaQuery.sizeOf(context).width <= 520;

    return servicesAsync.when(
      data: (allServices) {
        if (allServices.isEmpty) {
          return Center(
            child: Text(
              'No active services yet. Create some in the Services module.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          );
        }

        final categories =
            allServices
                .map((service) => service['category'] as String? ?? 'General')
                .toSet()
                .toList()
              ..sort();

        final categoryServices = _selectedCategory == null
            ? allServices
            : allServices.where((service) {
                return (service['category'] as String? ?? 'General') ==
                    _selectedCategory;
              }).toList();
        final displayedServices = _serviceQuery.isEmpty
            ? categoryServices
            : categoryServices.where((service) {
                final name = service['name'] as String? ?? '';
                final category = service['category'] as String? ?? 'General';
                return name.toLowerCase().contains(_serviceQuery) ||
                    category.toLowerCase().contains(_serviceQuery);
              }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildServiceSearchField(compact: compact),
            SizedBox(height: 10),
            _buildServiceCategoryChips(categories, compact: compact),
            SizedBox(height: 14),
            Expanded(
              child: _buildServiceCards(
                displayedServices,
                allServices,
                compact: compact,
              ),
            ),
          ],
        );
      },
      loading: () => Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          AppErrorMessage.from(error, fallback: AppErrorMessage.loadFailed),
          style: TextStyle(color: AppColors.error),
        ),
      ),
    );
  }

  Widget _buildTodayOrdersList(
    AsyncValue<List<Map<String, dynamic>>> todayOrdersAsync,
    List<CartItem> cart,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(
                  Icons.today_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Today\'s Orders',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    ref.invalidate(serviceTodayOrdersProvider);
                  },
                  icon: Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: todayOrdersAsync.when(
              data: (orders) {
                if (orders.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_available_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No orders today',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Create orders to see them here',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return _buildOrderCard(order, cart);
                  },
                );
              },
              loading: () => Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    AppErrorMessage.from(
                      error,
                      fallback: AppErrorMessage.loadFailed,
                    ),
                    style: TextStyle(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, List<CartItem> cart) {
    final status = order['status'] as String? ?? 'booked';
    final serviceName = order['service_name'] as String? ?? 'Service';
    final customerName = order['customer_name'] as String? ?? 'Walk-in';
    final price = (order['price'] as num? ?? 0).toDouble();
    final orderId = order['id'] as String;
    final bayNumber = order['bay_number'] as String?;

    final statusColor = switch (status) {
      'booked' => AppColors.primaryLight,
      'checked_in' => AppColors.warning,
      'in_progress' => AppColors.primary,
      'ready' => AppColors.success,
      'completed' => AppColors.success,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };

    final statusLabel = switch (status) {
      'booked' => 'Booked',
      'checked_in' => 'Checked In',
      'in_progress' => 'In Progress',
      'ready' => 'Ready',
      'completed' => 'Completed',
      _ => status,
    };

    final canCharge = status == 'ready' || status == 'completed';
    final isInCart = cart.any((item) => item.serviceOrderId == orderId);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showServiceOrderDetailsDialog(context, ref, orderId),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isInCart
                ? AppColors.success.withValues(alpha: 0.3)
                : context.appBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    serviceName,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    customerName,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (bayNumber != null && bayNumber.isNotEmpty) ...[
                  SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Bay $bayNumber',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${ShopSettings.currency}${price.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                if (canCharge && !isInCart)
                  FilledButton.icon(
                    onPressed: () {
                      ref
                          .read(cartProvider.notifier)
                          .addService(
                            serviceOrderId: orderId,
                            serviceId: order['service_id'] as String? ?? '',
                            serviceName: serviceName,
                            price: price,
                          );
                    },
                    icon: Icon(Icons.add_shopping_cart, size: 16),
                    label: Text('Add to Cart'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                    ),
                  )
                else if (isInCart)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_cart,
                          size: 14,
                          color: AppColors.success,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'In Cart',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceDurationBadge extends StatelessWidget {
  final int duration;

  const _ServiceDurationBadge({required this.duration});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          SizedBox(width: 4),
          Text(
            '$duration min',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileServiceTile extends StatelessWidget {
  final Map<String, dynamic> service;
  final VoidCallback onTap;

  const _MobileServiceTile({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final duration = (service['duration_minutes'] as num?)?.toInt();

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.design_services_rounded,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      service['name'] as String? ?? 'Service',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          service['category'] as String? ?? 'General',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        if (duration != null && duration > 0)
                          _ServiceDurationBadge(duration: duration),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${ShopSettings.currency}${(service['base_price'] as num? ?? 0).toStringAsFixed(2)}',
                    style: TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.add_shopping_cart_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogTab extends ConsumerWidget {
  final VoidCallback onRefresh;

  const _CatalogTab({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(servicesProvider);

    return servicesAsync.when(
      data: (services) {
        if (services.isEmpty) {
          return const _EmptyState(
            icon: Icons.design_services_outlined,
            title: 'No services yet',
            subtitle:
                'Create service templates like Car Wash, Haircut, Beard Trim, or Repair.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(24),
          itemCount: services.length,
          separatorBuilder: (_, _) => SizedBox(height: 10),
          itemBuilder: (context, index) {
            final service = services[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.design_services_rounded,
                      color: AppColors.primaryLight,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'] as String? ?? 'Service',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          service['category'] as String? ?? 'General',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if ((service['description'] as String?)?.isNotEmpty ==
                            true) ...[
                          SizedBox(height: 6),
                          Text(
                            service['description'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        (service['base_price'] as num? ?? 0).toStringAsFixed(2),
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () async {
                              await showServiceEditorDialog(
                                context,
                                ref,
                                service: service,
                              );
                            },
                            icon: Icon(Icons.edit_outlined),
                            tooltip: 'Edit',
                          ),
                          IconButton(
                            onPressed: () async {
                              await ServiceRepository.deleteService(
                                service['id'] as String,
                              );
                              ref.invalidate(servicesProvider);
                              ref.invalidate(activeServicesProvider);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Service deleted'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              }
                            },
                            icon: Icon(Icons.delete_outline),
                            tooltip: 'Delete',
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text(
          AppErrorMessage.from(error, fallback: AppErrorMessage.loadFailed),
        ),
      ),
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  final VoidCallback onRefresh;

  const _OrdersTab({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(serviceOrderFilterProvider);
    final ordersAsync = ref.watch(serviceOrdersProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in const [
                  ('active', 'Active'),
                  ('today', 'Today'),
                  ('appointments', 'Appointments'),
                  ('walk_in', 'Walk-ins'),
                ])
                  ChoiceChip(
                    label: Text(item.$2),
                    selected: filter == item.$1,
                    onSelected: (_) =>
                        ref.read(serviceOrderFilterProvider.notifier).state =
                            item.$1,
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ordersAsync.when(
            data: (orders) {
              if (orders.isEmpty) {
                return const _EmptyState(
                  icon: Icons.assignment_outlined,
                  title: 'No service orders',
                  subtitle:
                      'Appointments and walk-ins will appear here once created.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: orders.length,
                separatorBuilder: (_, _) => SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final order = orders[index];
                  return _ServiceOrderTile(
                    order: order,
                    onViewDetails: () => showServiceOrderDetailsDialog(
                      context,
                      ref,
                      order['id'] as String,
                    ),
                    onAdvanceStatus: () =>
                        advanceServiceOrderStatus(ref, order),
                    onCharge: () => chargeServiceOrder(context, ref, order),
                    onDelete: () =>
                        deleteServiceOrderWithConfirmation(context, ref, order),
                  );
                },
              );
            },
            loading: () => Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Text(
                AppErrorMessage.from(
                  error,
                  fallback: AppErrorMessage.loadFailed,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceOrderTile extends StatelessWidget {
  final Map<String, dynamic> order;
  final Future<void> Function() onAdvanceStatus;
  final VoidCallback? onCharge;
  final VoidCallback? onViewDetails;
  final VoidCallback? onDelete;

  const _ServiceOrderTile({
    required this.order,
    required this.onAdvanceStatus,
    this.onCharge,
    this.onViewDetails,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'booked';
    final saleId = order['sale_id'] as String?;
    final assignedStaff = _cleanText(order['assigned_staff']);
    final bayNumber = _cleanText(order['bay_number']);
    final note = _cleanText(order['note']);
    final canAdvance = _nextServiceStatus(status) != null;
    final canCharge =
        onCharge != null &&
        (saleId == null || saleId.isEmpty) &&
        _canChargeServiceStatus(status);

    return InkWell(
      onTap: onViewDetails,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12), // Reduced from 16
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12), // Reduced from 16
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order['service_name'] as String? ?? 'Service Order',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        (order['customer_name'] as String?)?.isNotEmpty == true
                            ? order['customer_name'] as String
                            : 'Walk-in / no customer name',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(context, status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status.replaceAll('_', ' '),
                    style: TextStyle(
                      color: _statusColor(context, status),
                      fontWeight: FontWeight.w700,
                      fontSize: 11, // Reduced from 12
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order['entry_mode'] == 'appointment' ? 'Appointment' : 'Walk-in'}${(order['scheduled_at'] as String?)?.isNotEmpty == true ? ' • ${order['scheduled_at']}' : ''}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11, // Reduced from 12
                    ),
                  ),
                ),
                Text(
                  (order['price'] as num? ?? 0).toStringAsFixed(2),
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            if (assignedStaff != null || bayNumber != null || note != null) ...[
              Wrap(
                spacing: 6, // Reduced from 8
                runSpacing: 6, // Reduced from 8
                children: [
                  if (assignedStaff != null)
                    _OrderMetaChip(
                      icon: Icons.people_alt_outlined,
                      label: 'Assigned: $assignedStaff',
                    ),
                  if (bayNumber != null)
                    _OrderMetaChip(
                      icon: Icons.local_car_wash_outlined,
                      label: 'Bay $bayNumber',
                    ),
                  if (note != null)
                    _OrderMetaChip(icon: Icons.notes_outlined, label: note),
                ],
              ),
              SizedBox(height: 12),
            ],
            Wrap(
              spacing: 6, // Reduced from 10
              runSpacing: 6, // Reduced from 10
              children: [
                if (onViewDetails != null)
                  OutlinedButton.icon(
                    onPressed: onViewDetails,
                    icon: Icon(Icons.visibility_outlined, size: 18),
                    label: Text('Details'),
                  ),
                if (canAdvance)
                  OutlinedButton.icon(
                    onPressed: onAdvanceStatus,
                    icon: Icon(Icons.autorenew, size: 18),
                    label: Text(_advanceServiceActionLabel(status)),
                  ),
                if (canCharge)
                  FilledButton.icon(
                    onPressed: onCharge,
                    icon: Icon(Icons.point_of_sale, size: 18),
                    label: Text('Charge'),
                  ),
                if (onDelete != null)
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline, size: 18),
                    label: Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _OrderMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showServiceOrderDetailsDialog(
  BuildContext context,
  WidgetRef ref,
  String orderId,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Service Order Details'),
      content: _ResponsiveDialogContent(
        maxWidth: 640,
        child: FutureBuilder<Map<String, dynamic>?>(
          future: ServiceRepository.getOrderById(orderId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return SizedBox(
                height: 220,
                child: Center(
                  child: Text(
                    AppErrorMessage.from(
                      snapshot.error,
                      fallback: AppErrorMessage.loadFailed,
                    ),
                  ),
                ),
              );
            }

            final order = snapshot.data;
            if (order == null) {
              return SizedBox(
                height: 220,
                child: Center(child: Text('This service order was not found.')),
              );
            }

            return _ServiceOrderDetailsContent(
              order: order,
              onDelete: () {
                Navigator.pop(ctx);
                deleteServiceOrderWithConfirmation(context, ref, order);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Close'),
        ),
      ],
    ),
  );
}

class _OrderDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _OrderDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelText = Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          );
          final valueText = Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w600),
          );

          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, SizedBox(height: 3), valueText],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 120, child: labelText),
              SizedBox(width: 12),
              Expanded(child: valueText),
            ],
          );
        },
      ),
    );
  }
}

class _ServiceOrderDetailsContent extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback? onDelete;

  const _ServiceOrderDetailsContent({required this.order, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'booked';
    final fieldValues = List<Map<String, dynamic>>.from(
      order['field_values'] as List<dynamic>? ?? const [],
    );
    final assignedStaff = _cleanText(order['assigned_staff']);
    final bayNumber = _cleanText(order['bay_number']);
    final note = _cleanText(order['note']);
    final scheduledAt = _cleanText(order['scheduled_at']);
    final checkedInAt = _cleanText(order['checked_in_at']);
    final saleId = _cleanText(order['sale_id']);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ServiceOrderDetailsHeader(order: order, status: status),
          SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OrderMetaChip(
                icon: Icons.sell_outlined,
                label: order['entry_mode'] == 'appointment'
                    ? 'Appointment'
                    : 'Walk-in',
              ),
              _OrderMetaChip(
                icon: Icons.payments_outlined,
                label:
                    'Price ${ShopSettings.currency}${(order['price'] as num? ?? 0).toStringAsFixed(2)}',
              ),
              if (assignedStaff != null)
                _OrderMetaChip(
                  icon: Icons.people_alt_outlined,
                  label: 'Assigned: $assignedStaff',
                ),
              if (bayNumber != null)
                _OrderMetaChip(
                  icon: Icons.local_car_wash_outlined,
                  label: 'Bay $bayNumber',
                ),
              if (saleId != null)
                const _OrderMetaChip(
                  icon: Icons.receipt_long_outlined,
                  label: 'Sale linked',
                ),
            ],
          ),
          SizedBox(height: 18),
          const _DetailsSectionTitle('Order Info'),
          SizedBox(height: 10),
          _OrderDetailRow(
            label: 'Customer',
            value: _serviceOrderCustomerLabel(order),
          ),
          _OrderDetailRow(
            label: 'Assigned Staff',
            value: assignedStaff ?? 'Not assigned',
          ),
          _OrderDetailRow(
            label: 'Bay',
            value: bayNumber != null ? 'Bay $bayNumber' : 'Not set',
          ),
          _OrderDetailRow(
            label: 'Entry Mode',
            value: order['entry_mode'] == 'appointment'
                ? 'Appointment'
                : 'Walk-in',
          ),
          if (scheduledAt != null)
            _OrderDetailRow(
              label: 'Scheduled',
              value: _fmtDateTimeRaw(scheduledAt),
            ),
          if (checkedInAt != null)
            _OrderDetailRow(
              label: 'Checked In',
              value: _fmtDateTimeRaw(checkedInAt),
            ),
          _OrderDetailRow(
            label: 'Created',
            value: _fmtDateTimeRaw(order['created_at'] as String?),
          ),
          if (note != null) ...[
            SizedBox(height: 18),
            const _DetailsSectionTitle('Note'),
            SizedBox(height: 8),
            _InfoPanel(child: Text(note)),
          ],
          SizedBox(height: 18),
          const _DetailsSectionTitle('Custom Inputs'),
          SizedBox(height: 10),
          if (fieldValues.isEmpty)
            _InfoPanel(
              child: Text(
                'No custom inputs were captured for this order.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          else
            Column(
              children: fieldValues
                  .map(
                    (field) => _OrderDetailRow(
                      label: field['field_label'] as String? ?? 'Field',
                      value: _displayServiceFieldValue(field),
                    ),
                  )
                  .toList(),
            ),
          if (onDelete != null) ...[
            SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, size: 18),
                label: Text('Delete Order'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServiceOrderDetailsHeader extends StatelessWidget {
  final Map<String, dynamic> order;
  final String status;

  const _ServiceOrderDetailsHeader({required this.order, required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                order['service_name'] as String? ?? 'Service Order',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                _serviceOrderCustomerLabel(order),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _statusColor(context, status).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            status.replaceAll('_', ' '),
            style: TextStyle(
              color: _statusColor(context, status),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailsSectionTitle extends StatelessWidget {
  final String title;

  const _DetailsSectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  final Widget child;

  const _InfoPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: child,
    );
  }
}

Future<void> advanceServiceOrderStatus(
  WidgetRef ref,
  Map<String, dynamic> order,
) async {
  final current = order['status'] as String? ?? 'booked';
  final nextStatus = _nextServiceStatus(current);
  if (nextStatus == null) {
    return;
  }
  await ServiceRepository.updateOrderStatus(order['id'] as String, nextStatus);
  // Invalidate both so the Orders tab AND the POS panel queue update instantly
  ref.invalidate(serviceOrdersProvider);
  ref.invalidate(serviceTodayOrdersProvider);
}

Future<void> deleteServiceOrderWithConfirmation(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> order,
) async {
  final serviceName = order['service_name'] as String? ?? 'Service Order';
  final saleId = _cleanText(order['sale_id']);
  if (saleId != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Delete the linked sale before deleting this order.'),
        backgroundColor: AppColors.warning,
      ),
    );
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Delete Service Order?'),
      content: Text(
        'Delete "$serviceName" from service orders and reports? This will not delete the service template.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) {
    return;
  }

  try {
    await ServiceRepository.deleteOrder(order['id'] as String);
    ref.invalidate(serviceOrdersProvider);
    ref.invalidate(serviceTodayOrdersProvider);
    ref.invalidate(serviceStatsProvider);
    ref.invalidate(serviceSalesByDateProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Service order deleted'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(
              error,
              fallback:
                  'Could not delete this service order. Please try again.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

Future<void> chargeServiceOrder(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> order,
) async {
  final orderId = order['id'] as String? ?? '';
  final serviceId = order['service_id'] as String? ?? '';
  final serviceName = order['service_name'] as String? ?? 'Service Order';
  final saleId = _cleanText(order['sale_id']);
  final status = order['status'] as String? ?? 'booked';
  final price = (order['price'] as num? ?? 0).toDouble();

  if (!_validateServicePaymentRequest(
    context,
    orderId: orderId,
    serviceId: serviceId,
    saleId: saleId,
    status: status,
  )) {
    return;
  }

  final subtotal = _roundMoney(price);
  final tax = _roundMoney(subtotal * (ShopSettings.taxRate / 100));
  final total = _roundMoney(subtotal + tax);
  final checkoutResult = await PaymentCheckoutDialog.show(
    context,
    total: total,
  );
  if (!context.mounted || checkoutResult == null) {
    return;
  }

  final type = checkoutResult['type'] as String;
  final customer = checkoutResult['customer'] as Map<String, dynamic>?;
  final dueDate = checkoutResult['dueDate'] as String?;

  if (type == 'kopesha') {
    if (customer == null || dueDate == null) {
      _showServicePaymentSnackBar(
        context,
        'Customer and due date are required for Kopesha.',
        backgroundColor: AppColors.warning,
      );
      return;
    }

    await _completeServiceOrderPayment(
      context,
      ref,
      order: order,
      paymentType: 'kopesha',
      subtotal: subtotal,
      tax: tax,
      total: total,
      customerId: customer['id'] as String,
      customerName: customer['name'] as String,
      dueDate: dueDate,
    );
    return;
  }

  final paymentMethod =
      checkoutResult['paymentMethod'] as Map<String, dynamic>?;
  if (paymentMethod == null) {
    return;
  }

  final paymentName = paymentMethod['name'] as String? ?? 'Payment';
  final isCashDrawer = paymentMethod['is_cash_drawer'] == 1;

  if (isCashDrawer) {
    final shift = await _requireOpenServicePaymentShift(context);
    final requiresManagedShift = ShiftRepository.roleRequiresManagedShift(
      SessionService.currentUserRole,
    );
    if (!context.mounted || (requiresManagedShift && shift == null)) {
      return;
    }

    final cashCheckout = await _showServiceCashCheckoutDialog(
      context,
      serviceName: serviceName,
      total: total,
    );
    if (!context.mounted || cashCheckout == null) {
      return;
    }

    await _completeServiceOrderPayment(
      context,
      ref,
      order: order,
      paymentType: paymentName,
      isCashDrawer: true,
      subtotal: subtotal,
      tax: tax,
      total: total,
      shiftId: shift?['id'] as String?,
      amountTendered: cashCheckout.amountTendered,
      changeGiven: cashCheckout.changeGiven,
      customerId: customer?['id'] as String?,
      customerName: customer?['name'] as String?,
    );
    return;
  }

  await _completeServiceOrderPayment(
    context,
    ref,
    order: order,
    paymentType: paymentName,
    subtotal: subtotal,
    tax: tax,
    total: total,
    customerId: customer?['id'] as String?,
    customerName: customer?['name'] as String?,
  );
}

bool _validateServicePaymentRequest(
  BuildContext context, {
  required String orderId,
  required String serviceId,
  required String? saleId,
  required String status,
}) {
  if (orderId.isEmpty || serviceId.isEmpty) {
    _showServicePaymentSnackBar(
      context,
      'This service order is missing payment data.',
      backgroundColor: AppColors.error,
    );
    return false;
  }

  if (saleId != null) {
    _showServicePaymentSnackBar(
      context,
      'This service order is already paid.',
      backgroundColor: AppColors.warning,
    );
    return false;
  }

  if (!_canChargeServiceStatus(status)) {
    _showServicePaymentSnackBar(
      context,
      'Complete the service before charging.',
      backgroundColor: AppColors.warning,
    );
    return false;
  }

  return true;
}

Future<Map<String, dynamic>?> _requireOpenServicePaymentShift(
  BuildContext context,
) async {
  final userId = currentShiftActorId();
  final role = SessionService.currentUserRole;
  final cashierName = ShiftRepository.normalizeActorName(
    SessionService.currentUserName,
  );
  final access = await ShiftRepository.resolveCurrentShift(userId: userId);
  if (access.autoClosedShift != null && context.mounted) {
    _showServicePaymentSnackBar(
      context,
      'Your previous-day shift was auto-closed before this cash payment.',
      backgroundColor: AppColors.warning,
    );
  }
  if (access.currentShift != null ||
      !ShiftRepository.roleRequiresManagedShift(role)) {
    return access.currentShift;
  }
  if (!context.mounted) {
    return null;
  }

  final suggestedOpeningCash = await ShiftPreferencesService.getLastOpeningCash(
    userId,
  );
  if (!context.mounted) {
    return null;
  }

  final opening = await showShiftAutoOpenDialog(
    context,
    transactionLabel: 'service payment',
    suggestedOpeningCash: suggestedOpeningCash,
  );
  if (!context.mounted || opening == null) {
    return null;
  }

  final shift = await ShiftRepository.openShift(
    userId: userId,
    cashierName: cashierName,
    openingCash: opening.openingCash,
    note: opening.note ?? 'Auto-opened on first service cash payment.',
  );
  await ShiftPreferencesService.saveLastOpeningCash(
    userId,
    opening.openingCash,
  );
  if (context.mounted) {
    _showServicePaymentSnackBar(
      context,
      'A new shift was auto-opened for this cash payment.',
      backgroundColor: AppColors.success,
    );
  }
  return shift;
}

Future<_ServiceCashCheckoutResult?> _showServiceCashCheckoutDialog(
  BuildContext context, {
  required String serviceName,
  required double total,
}) async {
  final controller = TextEditingController(text: total.toStringAsFixed(2));
  String? errorText;

  final result = await showDialog<_ServiceCashCheckoutResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        final tenderedAmount = double.tryParse(controller.text.trim()) ?? 0;
        final hasEnoughCash = tenderedAmount + 0.001 >= total;
        final changeGiven = hasEnoughCash ? tenderedAmount - total : 0.0;

        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Cash Payment'),
          content: _ResponsiveDialogContent(
            maxWidth: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceName,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 12),
                Text(
                  'Total: ${ShopSettings.currency}${total.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: AppColors.success,
                  ),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) {
                    setDialogState(() {
                      errorText = null;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'Cash received',
                    prefixText: ShopSettings.currency,
                    errorText: errorText,
                  ),
                ),
                SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      controller.text = total.toStringAsFixed(2);
                      setDialogState(() {
                        errorText = null;
                      });
                    },
                    icon: Icon(Icons.restart_alt),
                    label: Text('Use Exact Amount'),
                  ),
                ),
                SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: hasEnoughCash
                        ? AppColors.primaryLight.withValues(alpha: 0.08)
                        : AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        hasEnoughCash
                            ? Icons.reply_outlined
                            : Icons.warning_amber_rounded,
                        color: hasEnoughCash
                            ? AppColors.primaryLight
                            : AppColors.warning,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              hasEnoughCash
                                  ? 'Change Returned'
                                  : 'More Cash Needed',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: hasEnoughCash
                                    ? AppColors.primaryLight
                                    : AppColors.warning,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              '${ShopSettings.currency}${(hasEnoughCash ? changeGiven : total - tenderedAmount).toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final parsed = double.tryParse(controller.text.trim());
                if (parsed == null) {
                  setDialogState(() {
                    errorText = 'Enter a valid cash amount';
                  });
                  return;
                }
                if (parsed + 0.001 < total) {
                  setDialogState(() {
                    errorText = 'Cash received must cover the sale total';
                  });
                  return;
                }
                Navigator.pop(
                  ctx,
                  _ServiceCashCheckoutResult(
                    amountTendered: parsed,
                    changeGiven: parsed - total,
                  ),
                );
              },
              icon: Icon(Icons.check_circle_outline),
              label: Text('Complete Payment'),
            ),
          ],
        );
      },
    ),
  );

  controller.dispose();
  return result;
}

Future<void> _completeServiceOrderPayment(
  BuildContext context,
  WidgetRef ref, {
  required Map<String, dynamic> order,
  required String paymentType,
  bool isCashDrawer = false,
  required double subtotal,
  required double tax,
  required double total,
  String? shiftId,
  double? amountTendered,
  double? changeGiven,
  String? customerId,
  String? customerName,
  String? dueDate,
}) async {
  final orderId = order['id'] as String;
  final serviceId = order['service_id'] as String;
  final serviceName = order['service_name'] as String? ?? 'Service Order';
  final price = (order['price'] as num? ?? 0).toDouble();

  try {
    final saleId = await SaleRepository.createSale(
      totalAmount: total,
      tax: tax,
      discount: 0,
      paymentType: paymentType,
      isCashDrawer: isCashDrawer,
      userId: SessionService.currentUserId.isNotEmpty
          ? SessionService.currentUserId
          : 'admin',
      shiftId: shiftId,
      items: [
        {
          'line_type': 'service',
          'product_id': 'service:$orderId',
          'product_name': serviceName,
          'unit_price': price,
          'unit_cost': 0.0,
          'quantity': 1.0,
          'unit': 'job',
          'sale_to_stock_factor': 1.0,
          'stock_unit': 'job',
          'service_order_id': orderId,
          'service_id': serviceId,
        },
      ],
      amountTendered: amountTendered,
      changeGiven: changeGiven,
      customerId: customerId,
      customerName: customerName,
      dueDate: dueDate,
    );

    await ServiceRepository.attachSaleToOrder(orderId, saleId);
    ref.read(cartProvider.notifier).removeProduct('service:$orderId');
    ref.invalidate(serviceOrdersProvider);
    ref.invalidate(serviceTodayOrdersProvider);
    ref.invalidate(serviceStatsProvider);
    ref.invalidate(serviceSalesByDateProvider);
    invalidateShiftProviders(ref);

    if (context.mounted) {
      _showServicePaymentSuccessDialog(
        context,
        saleId: saleId,
        serviceName: serviceName,
        subtotal: subtotal,
        tax: tax,
        total: total,
        paymentType: paymentType,
        customerName: customerName,
        amountTendered: amountTendered ?? 0,
        changeGiven: changeGiven ?? 0,
        isCashDrawer: isCashDrawer,
        dueDate: dueDate,
      );
    }
  } catch (error) {
    if (context.mounted) {
      _showServicePaymentSnackBar(
        context,
        AppErrorMessage.withContext(
          error,
          prefix: 'Could not complete service payment.',
          fallback: AppErrorMessage.paymentFailed,
        ),
        backgroundColor: AppColors.error,
      );
    }
  }
}

void _showServicePaymentSuccessDialog(
  BuildContext context, {
  required String saleId,
  required String serviceName,
  required double subtotal,
  required double tax,
  required double total,
  required String paymentType,
  String? customerName,
  double amountTendered = 0,
  double changeGiven = 0,
  bool isCashDrawer = false,
  String? dueDate,
}) {
  final isCredit = paymentType.toLowerCase() == 'kopesha';

  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: const [
          Icon(Icons.check_circle, color: AppColors.success, size: 30),
          SizedBox(width: 12),
          Text('Payment Complete'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            serviceName,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          SizedBox(height: 12),
          Text(
            'Total: ${ShopSettings.currency}${total.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.success,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Subtotal: ${ShopSettings.currency}${subtotal.toStringAsFixed(2)}',
          ),
          Text('Tax: ${ShopSettings.currency}${tax.toStringAsFixed(2)}'),
          Text('Payment: ${_paymentMethodDisplayName(paymentType)}'),
          if (isCashDrawer) ...[
            Text(
              'Cash Received: ${ShopSettings.currency}${amountTendered.toStringAsFixed(2)}',
            ),
            Text(
              'Change Returned: ${ShopSettings.currency}${changeGiven.toStringAsFixed(2)}',
            ),
          ],
          if (customerName != null) Text('Customer: $customerName'),
          if (isCredit && dueDate != null) Text('Due Date: $dueDate'),
          SizedBox(height: 10),
          Text(
            'Sale ID: ${saleId.substring(0, 8)}...',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Done'),
        ),
      ],
    ),
  );
}

void _showServicePaymentSnackBar(
  BuildContext context,
  String message, {
  required Color backgroundColor,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: backgroundColor,
    ),
  );
}

String _paymentMethodDisplayName(String paymentType) {
  final normalized = paymentType.trim();
  if (normalized.toLowerCase() == 'kopesha') {
    return 'Kopesha';
  }
  if (normalized.isEmpty) {
    return 'Payment';
  }
  return normalized;
}

class _ServiceCashCheckoutResult {
  final double amountTendered;
  final double changeGiven;

  const _ServiceCashCheckoutResult({
    required this.amountTendered,
    required this.changeGiven,
  });
}

Future<void> showServiceEditorDialog(
  BuildContext context,
  WidgetRef ref, {
  Map<String, dynamic>? service,
}) async {
  final existingFields = service == null
      ? <Map<String, dynamic>>[]
      : await ServiceRepository.getFieldsForService(service['id'] as String);
  if (!context.mounted) {
    return;
  }

  final nameController = TextEditingController(
    text: service?['name'] as String? ?? '',
  );
  final categoryController = TextEditingController(
    text: service?['category'] as String? ?? '',
  );
  final descriptionController = TextEditingController(
    text: service?['description'] as String? ?? '',
  );
  final priceController = TextEditingController(
    text: ((service?['base_price'] as num?) ?? 0).toString(),
  );
  final durationController = TextEditingController(
    text: (service?['duration_minutes'] as int?)?.toString() ?? '',
  );
  var isActive = (service?['is_active'] as num? ?? 1) == 1;
  final drafts = existingFields
      .map((field) => _FieldDraft.fromMap(field))
      .toList(growable: true);
  if (drafts.isEmpty) {
    drafts.add(_FieldDraft());
  }
  var isSaving = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(service == null ? 'Create Service' : 'Edit Service'),
        content: _ResponsiveDialogContent(
          maxWidth: 720,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Service Name',
                  prefixIcon: Icon(Icons.design_services_outlined),
                ),
              ),
              SizedBox(height: 12),
              _ResponsiveFormRow(
                children: [
                  TextField(
                    controller: categoryController,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                  ),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Base Price',
                      prefixIcon: Icon(Icons.payments_outlined),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              _ResponsiveFormRow(
                children: [
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Duration Minutes',
                      prefixIcon: Icon(Icons.schedule_outlined),
                    ),
                  ),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (value) =>
                        setDialogState(() => isActive = value),
                    title: Text('Active'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              SizedBox(height: 18),
              const _DialogSectionTitle('Custom Fields'),
              SizedBox(height: 10),
              ...List.generate(drafts.length, (index) {
                final draft = drafts[index];
                return _ServiceFieldDraftCard(
                  draft: draft,
                  canDelete: drafts.length > 1,
                  onTypeChanged: (value) =>
                      setDialogState(() => draft.fieldType = value),
                  onRequiredChanged: (value) =>
                      setDialogState(() => draft.isRequired = value),
                  onDelete: () => setDialogState(() {
                    final removed = drafts.removeAt(index);
                    removed.dispose();
                  }),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setDialogState(() => drafts.add(_FieldDraft())),
                  icon: Icon(Icons.add, size: 18),
                  label: Text('Add Field'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: isSaving ? null : () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: isSaving
                ? null
                : () async {
                    if (nameController.text.trim().isEmpty) {
                      _showServiceDialogSnackBar(
                        context,
                        'Service name is required',
                      );
                      return;
                    }

                    setDialogState(() => isSaving = true);
                    try {
                      final fields = _buildServiceEditorFields(drafts);

                      if (service == null) {
                        await ServiceRepository.createService(
                          name: nameController.text,
                          category: categoryController.text,
                          description: descriptionController.text,
                          basePrice:
                              double.tryParse(priceController.text.trim()) ?? 0,
                          durationMinutes: int.tryParse(
                            durationController.text.trim(),
                          ),
                          isActive: isActive,
                          fields: fields,
                        );
                      } else {
                        await ServiceRepository.updateService(
                          id: service['id'] as String,
                          name: nameController.text,
                          category: categoryController.text,
                          description: descriptionController.text,
                          basePrice:
                              double.tryParse(priceController.text.trim()) ?? 0,
                          durationMinutes: int.tryParse(
                            durationController.text.trim(),
                          ),
                          isActive: isActive,
                          fields: fields,
                        );
                      }

                      ref.invalidate(servicesProvider);
                      ref.invalidate(activeServicesProvider);
                      if (context.mounted) {
                        Navigator.pop(ctx);
                      }
                    } catch (error) {
                      if (context.mounted) {
                        _showServiceDialogSnackBar(
                          context,
                          AppErrorMessage.from(
                            error,
                            fallback: AppErrorMessage.saveFailed,
                          ),
                        );
                      }
                      setDialogState(() => isSaving = false);
                    }
                  },
            child: isSaving
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(service == null ? 'Create Service' : 'Save Changes'),
          ),
        ],
      ),
    ),
  );

  nameController.dispose();
  categoryController.dispose();
  descriptionController.dispose();
  priceController.dispose();
  durationController.dispose();
  for (final draft in drafts) {
    draft.dispose();
  }
}

Future<bool> showCreateServiceOrderDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<Map<String, dynamic>> services,
  String? initialServiceId,
  bool addToCartOnSuccess = false,
}) async {
  if (services.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Create a service template first'),
        backgroundColor: AppColors.warning,
      ),
    );
    return false;
  }

  final customers = await CustomerRepository.search('');
  if (!context.mounted) {
    return false;
  }
  String selectedServiceId =
      initialServiceId ?? services.first['id'] as String? ?? '';
  String entryMode = 'walk_in';
  String? selectedCustomerId;
  String? selectedCustomerName;
  DateTime? pickedSchedule;
  String? selectedBay;
  final baysCount = ShopSettings.carwashBaysCount;
  final assignedStaffController = TextEditingController(
    text: ServiceRepository.defaultAssignedStaffName(),
  );
  final priceController = TextEditingController();
  final noteController = TextEditingController();
  var isSaving = false;

  List<Map<String, dynamic>> currentFields =
      await ServiceRepository.getFieldsForService(selectedServiceId);
  if (!context.mounted) {
    return false;
  }
  final valueControllers = <String, TextEditingController>{};
  void resetFieldControllers(List<Map<String, dynamic>> fields) {
    for (final controller in valueControllers.values) {
      controller.dispose();
    }
    valueControllers.clear();
    for (final field in fields) {
      valueControllers[field['id'] as String] = TextEditingController();
    }
  }

  resetFieldControllers(currentFields);
  final initialService = services.firstWhere(
    (service) => service['id'] == selectedServiceId,
    orElse: () => services.first,
  );
  priceController.text = ((initialService['base_price'] as num?) ?? 0)
      .toStringAsFixed(2);

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setDialogState) {
        final selectedService = services.firstWhere(
          (service) => service['id'] == selectedServiceId,
          orElse: () => services.first,
        );

        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Create Service Order'),
          content: _ResponsiveDialogContent(
            maxWidth: 680,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedServiceId,
                  decoration: InputDecoration(
                    labelText: 'Service',
                    prefixIcon: Icon(Icons.design_services_outlined),
                  ),
                  items: services
                      .map(
                        (service) => DropdownMenuItem(
                          value: service['id'] as String,
                          child: Text(service['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    final fields = await ServiceRepository.getFieldsForService(
                      value,
                    );
                    if (!context.mounted) return;
                    setDialogState(() {
                      selectedServiceId = value;
                      currentFields = fields;
                      resetFieldControllers(fields);
                      final service = services.firstWhere(
                        (item) => item['id'] == value,
                        orElse: () => services.first,
                      );
                      priceController.text =
                          ((service['base_price'] as num?) ?? 0)
                              .toStringAsFixed(2);
                    });
                  },
                ),
                SizedBox(height: 12),
                _CustomerSelectionField(
                  selectedCustomerName: selectedCustomerName,
                  onTap: () async {
                    final picked = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder: (ctx) => _CustomerPickerDialog(
                        customers: customers,
                        selectedId: selectedCustomerId,
                      ),
                    );
                    if (picked == null) return;
                    setDialogState(() {
                      if (picked['id'] == null) {
                        selectedCustomerId = null;
                        selectedCustomerName = null;
                      } else {
                        selectedCustomerId = picked['id'] as String?;
                        selectedCustomerName = picked['name'] as String?;
                      }
                    });
                  },
                ),
                SizedBox(height: 12),
                _ResponsiveFormRow(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: entryMode,
                      decoration: InputDecoration(
                        labelText: 'Entry Mode',
                        prefixIcon: Icon(Icons.merge_type_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'walk_in',
                          child: Text('Walk-in'),
                        ),
                        DropdownMenuItem(
                          value: 'appointment',
                          child: Text('Appointment'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => entryMode = value);
                      },
                    ),
                    _ScheduleSelectionField(
                      entryMode: entryMode,
                      pickedSchedule: pickedSchedule,
                      onTap: () async {
                        final now = DateTime.now();
                        final date = await showDatePicker(
                          context: context,
                          initialDate: pickedSchedule ?? now,
                          firstDate: DateTime(now.year - 1),
                          lastDate: DateTime(now.year + 3),
                        );
                        if (date == null || !context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: pickedSchedule != null
                              ? TimeOfDay.fromDateTime(pickedSchedule!)
                              : TimeOfDay.now(),
                        );
                        if (time == null) return;
                        setDialogState(() {
                          pickedSchedule = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                        });
                      },
                      onClear: pickedSchedule == null
                          ? null
                          : () => setDialogState(() => pickedSchedule = null),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _ResponsiveFormRow(
                  children: [
                    TextField(
                      controller: assignedStaffController,
                      decoration: InputDecoration(
                        labelText: 'Assigned Staff',
                        prefixIcon: Icon(Icons.people_alt_outlined),
                      ),
                    ),
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Price',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _BaySelectionField(
                  baysCount: baysCount,
                  selectedBay: selectedBay,
                  onChanged: (bay) => setDialogState(() => selectedBay = bay),
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
                if (currentFields.isNotEmpty) ...[
                  SizedBox(height: 18),
                  const _DialogSectionTitle('Custom Inputs'),
                  SizedBox(height: 10),
                  ...currentFields.map((field) {
                    final fieldId = field['id'] as String;
                    return _ServiceOrderCustomFieldInput(
                      field: field,
                      controller: valueControllers[fieldId]!,
                      onChanged: (value) {
                        setDialogState(() {
                          valueControllers[fieldId]!.text = value ?? '';
                          if (value != null && value.isNotEmpty) {
                            final priceMap =
                                field['price_map'] as Map<String, double>?;
                            final mapped = priceMap?[value];
                            if (mapped != null && mapped > 0) {
                              priceController.text = mapped.toStringAsFixed(2);
                            }
                          }
                        });
                      },
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (selectedServiceId.isEmpty) return;
                      final serviceName =
                          selectedService['name'] as String? ?? '';
                      if (serviceName.trim().isEmpty) return;

                      final missingField = _firstMissingRequiredServiceField(
                        currentFields,
                        valueControllers,
                      );
                      if (missingField != null) {
                        _showServiceDialogSnackBar(
                          context,
                          '${missingField['label']} is required',
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      try {
                        final scheduleIso = pickedSchedule?.toIso8601String();
                        final orderId = await ServiceRepository.createOrder(
                          serviceId: selectedServiceId,
                          serviceName: serviceName,
                          customerId: selectedCustomerId,
                          customerName: selectedCustomerName,
                          entryMode: entryMode,
                          scheduledAt: entryMode == 'appointment'
                              ? scheduleIso
                              : null,
                          checkedInAt: entryMode == 'walk_in'
                              ? (scheduleIso ??
                                    DateTime.now().toIso8601String())
                              : null,
                          status: entryMode == 'appointment'
                              ? 'booked'
                              : 'checked_in',
                          assignedStaff: assignedStaffController.text,
                          assignedStaffUserId:
                              ServiceRepository.currentAssignedStaffUserIdFor(
                                assignedStaffController.text,
                              ),
                          bayNumber: selectedBay,
                          price:
                              double.tryParse(priceController.text.trim()) ?? 0,
                          note: noteController.text,
                          fieldValues: _buildServiceOrderFieldValues(
                            currentFields,
                            valueControllers,
                          ),
                        );

                        ref.invalidate(serviceOrdersProvider);
                        if (addToCartOnSuccess) {
                          ref
                              .read(cartProvider.notifier)
                              .addService(
                                serviceOrderId: orderId,
                                serviceId: selectedServiceId,
                                serviceName: serviceName,
                                price:
                                    double.tryParse(
                                      priceController.text.trim(),
                                    ) ??
                                    0,
                              );
                        }
                        if (context.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      } catch (error) {
                        if (context.mounted) {
                          _showServiceDialogSnackBar(
                            context,
                            AppErrorMessage.from(
                              error,
                              fallback: AppErrorMessage.saveFailed,
                            ),
                          );
                        }
                        setDialogState(() => isSaving = false);
                      }
                    },
              child: isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Create Order'),
            ),
          ],
        );
      },
    ),
  );

  assignedStaffController.dispose();
  priceController.dispose();
  noteController.dispose();
  for (final controller in valueControllers.values) {
    controller.dispose();
  }

  return result == true;
}

class _FieldDraft {
  final TextEditingController labelController;
  final TextEditingController optionsController;
  final TextEditingController priceMapController;
  String fieldType;
  bool isRequired;

  _FieldDraft({
    String label = '',
    this.fieldType = 'text',
    List<String> options = const [],
    List<String> pricesText = const [],
    this.isRequired = false,
  }) : labelController = TextEditingController(text: label),
       optionsController = TextEditingController(text: options.join(', ')),
       priceMapController = TextEditingController(text: pricesText.join(', '));

  factory _FieldDraft.fromMap(Map<String, dynamic> field) {
    final options = (field['options'] as List<dynamic>? ?? [])
        .map((o) => o.toString())
        .toList();
    final priceMap = (field['price_map'] as Map<String, double>?) ?? {};
    final pricesText = options.map((o) {
      final p = priceMap[o];
      return (p != null && p > 0) ? p.toStringAsFixed(0) : '';
    }).toList();
    return _FieldDraft(
      label: field['label'] as String? ?? '',
      fieldType: field['field_type'] as String? ?? 'text',
      options: options,
      pricesText: pricesText,
      isRequired: (field['is_required'] as num? ?? 0) == 1,
    );
  }

  List<String> get options => optionsController.text
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();

  /// Parallel price list matching options order. Null entry = no price for that option.
  List<double?> get prices => priceMapController.text
      .split(',')
      .map((v) => double.tryParse(v.trim()))
      .toList();

  void dispose() {
    labelController.dispose();
    optionsController.dispose();
    priceMapController.dispose();
  }
}

class _DialogSectionTitle extends StatelessWidget {
  final String title;

  const _DialogSectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }
}

class _ResponsiveDialogContent extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const _ResponsiveDialogContent({required this.maxWidth, required this.child});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final width = math.max(240.0, math.min(maxWidth, size.width - 96));
    final maxHeight = math.max(260.0, size.height * 0.72);

    return SizedBox(
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: viewInsets.bottom > 0 ? 12 : 0),
          child: child,
        ),
      ),
    );
  }
}

class _ResponsiveFormRow extends StatelessWidget {
  final List<Widget> children;

  const _ResponsiveFormRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1) SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _ServiceFieldDraftCard extends StatelessWidget {
  final _FieldDraft draft;
  final bool canDelete;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<bool> onRequiredChanged;
  final VoidCallback onDelete;

  const _ServiceFieldDraftCard({
    required this.draft,
    required this.canDelete,
    required this.onTypeChanged,
    required this.onRequiredChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        children: [
          _ResponsiveFormRow(
            children: [
              TextField(
                controller: draft.labelController,
                decoration: InputDecoration(labelText: 'Field Label'),
              ),
              DropdownButtonFormField<String>(
                initialValue: draft.fieldType,
                decoration: InputDecoration(labelText: 'Type'),
                items: _serviceFieldTypes
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    onTypeChanged(value);
                  }
                },
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: canDelete ? onDelete : null,
              icon: Icon(Icons.delete_outline),
              tooltip: 'Delete field',
            ),
          ),
          SizedBox(height: 10),
          _ResponsiveFormRow(
            children: [
              TextField(
                controller: draft.optionsController,
                decoration: InputDecoration(
                  labelText: 'Select Options (comma separated)',
                ),
              ),
              CheckboxListTile(
                value: draft.isRequired,
                onChanged: (value) => onRequiredChanged(value ?? false),
                title: Text('Required'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          if (draft.fieldType == 'select') ...[
            SizedBox(height: 8),
            TextField(
              controller: draft.priceMapController,
              decoration: InputDecoration(
                labelText: 'Price per option (optional, comma-separated)',
                hintText: 'e.g. 300, 500, 400',
                prefixIcon: Icon(Icons.price_change_outlined),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerSelectionField extends StatelessWidget {
  final String? selectedCustomerName;
  final Future<void> Function() onTap;

  const _CustomerSelectionField({
    required this.selectedCustomerName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Customer',
          prefixIcon: Icon(Icons.person_search_outlined),
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          selectedCustomerName ?? 'Walk-in / no customer',
          style: TextStyle(
            color: selectedCustomerName != null
                ? null
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ScheduleSelectionField extends StatelessWidget {
  final String entryMode;
  final DateTime? pickedSchedule;
  final Future<void> Function() onTap;
  final VoidCallback? onClear;

  const _ScheduleSelectionField({
    required this.entryMode,
    required this.pickedSchedule,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: entryMode == 'appointment'
              ? 'Appointment Date & Time'
              : 'Check-in Time',
          prefixIcon: Icon(Icons.calendar_month_outlined),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  icon: Icon(Icons.clear, size: 18),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          pickedSchedule != null
              ? _fmtDateTime(pickedSchedule!)
              : 'Tap to pick date & time',
          style: TextStyle(
            color: pickedSchedule != null ? null : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _BaySelectionField extends StatelessWidget {
  final int baysCount;
  final String? selectedBay;
  final ValueChanged<String?> onChanged;

  const _BaySelectionField({
    required this.baysCount,
    required this.selectedBay,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Bay:',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          ChoiceChip(
            label: Text('None'),
            selected: selectedBay == null,
            onSelected: (_) => onChanged(null),
          ),
          ...List.generate(baysCount, (index) {
            final bay = '${index + 1}';
            return ChoiceChip(
              label: Text('Bay $bay'),
              selected: selectedBay == bay,
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              onSelected: (_) => onChanged(bay),
            );
          }),
        ],
      ),
    );
  }
}

class _ServiceOrderCustomFieldInput extends StatelessWidget {
  final Map<String, dynamic> field;
  final TextEditingController controller;
  final ValueChanged<String?> onChanged;

  const _ServiceOrderCustomFieldInput({
    required this.field,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final type = field['field_type'] as String? ?? 'text';
    if (type == 'select') {
      final options = (field['options'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: controller.text.isEmpty ? null : controller.text,
          decoration: InputDecoration(labelText: field['label'] as String),
          items: options
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: onChanged,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: type == 'number'
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: field['label'] as String,
          hintText: type == 'date' ? 'YYYY-MM-DD HH:MM' : null,
        ),
      ),
    );
  }
}

List<Map<String, dynamic>> _buildServiceEditorFields(List<_FieldDraft> drafts) {
  return drafts
      .where((draft) => draft.labelController.text.trim().isNotEmpty)
      .toList()
      .asMap()
      .entries
      .map(
        (entry) => {
          'label': entry.value.labelController.text.trim(),
          'field_type': entry.value.fieldType,
          'options': entry.value.options,
          'prices': entry.value.prices,
          'is_required': entry.value.isRequired,
          'sort_order': entry.key,
        },
      )
      .toList();
}

Map<String, dynamic>? _firstMissingRequiredServiceField(
  List<Map<String, dynamic>> fields,
  Map<String, TextEditingController> valueControllers,
) {
  for (final field in fields) {
    final isRequired = (field['is_required'] as num? ?? 0) == 1;
    final controller = valueControllers[field['id'] as String]!;
    if (isRequired && controller.text.trim().isEmpty) {
      return field;
    }
  }
  return null;
}

List<Map<String, dynamic>> _buildServiceOrderFieldValues(
  List<Map<String, dynamic>> currentFields,
  Map<String, TextEditingController> valueControllers,
) {
  return currentFields
      .map(
        (field) => {
          'field_id': field['id'],
          'field_label': field['label'],
          'field_type': field['field_type'],
          'value_text': valueControllers[field['id'] as String]!.text,
        },
      )
      .toList();
}

void _showServiceDialogSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.error,
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

Color _statusColor(BuildContext context, String status) {
  switch (status) {
    case 'booked':
      return AppColors.primary;
    case 'checked_in':
      return AppColors.warning;
    case 'in_progress':
      return AppColors.primaryLight;
    case 'ready':
      return AppColors.success;
    case 'completed':
      return AppColors.success;
    case 'paid':
      return Theme.of(context).colorScheme.onSurfaceVariant;
    default:
      return AppColors.error;
  }
}

// ── Date formatter helper ────────────────────────────────────────────────
String _fmtDateTime(DateTime dt) {
  final months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final ampm = dt.hour < 12 ? 'AM' : 'PM';
  final min = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $hour:$min $ampm';
}

String _fmtDateTimeRaw(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  try {
    return _fmtDateTime(DateTime.parse(raw).toLocal());
  } catch (_) {
    return raw;
  }
}

// ── Customer picker dialog ────────────────────────────────────────────
String? _cleanText(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

String _serviceOrderCustomerLabel(Map<String, dynamic> order) {
  return (order['customer_name'] as String?)?.isNotEmpty == true
      ? order['customer_name'] as String
      : 'Walk-in / no customer name';
}

String _reportCustomerLabel(Map<String, dynamic> order) {
  return (order['customer_name'] as String?)?.isNotEmpty == true
      ? order['customer_name'] as String
      : 'Walk-in';
}

String _displayServiceFieldValue(Map<String, dynamic> field) {
  final fieldType = (field['field_type'] as String? ?? 'text').trim();
  final value = _cleanText(field['value_text']);
  if (value == null) {
    return 'Not provided';
  }

  switch (fieldType) {
    case 'boolean':
      final normalized = value.toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return 'Yes';
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return 'No';
      }
      return value;
    case 'date':
      return _fmtDateTimeRaw(value);
    default:
      return value;
  }
}

class _CustomerPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> customers;
  final String? selectedId;

  const _CustomerPickerDialog({required this.customers, this.selectedId});

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _search = TextEditingController();
  late List<Map<String, dynamic>> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.customers;
    _search.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _search.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? widget.customers
          : widget.customers.where((c) {
              final name = (c['name'] as String? ?? '').toLowerCase();
              final phone = (c['phone'] as String? ?? '').toLowerCase();
              return name.contains(q) || phone.contains(q);
            }).toList();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Select Customer'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: math.max(
          240.0,
          math.min(400.0, MediaQuery.sizeOf(context).width - 96),
        ),
        height: math.min(480.0, MediaQuery.sizeOf(context).height * 0.62),
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by name or phone…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  // Walk-in option
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.directions_walk,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text('Walk-in / No customer'),
                    selected: widget.selectedId == null,
                    selectedTileColor: AppColors.primary.withValues(
                      alpha: 0.08,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () =>
                        Navigator.pop(context, <String, dynamic>{'id': null}),
                  ),
                  SizedBox(height: 6),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No customers found',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    )
                  else
                    ..._filtered.map((c) {
                      final id = c['id'] as String?;
                      final name = c['name'] as String? ?? '?';
                      final phone = c['phone'] as String? ?? '';
                      final initials = name.trim().isNotEmpty
                          ? name.trim()[0].toUpperCase()
                          : '?';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.15,
                            ),
                            child: Text(
                              initials,
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(name),
                          subtitle: phone.isNotEmpty ? Text(phone) : null,
                          selected: id == widget.selectedId,
                          selectedTileColor: AppColors.primary.withValues(
                            alpha: 0.08,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          onTap: () => Navigator.pop(context, c),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
      ],
    );
  }
}

// ── Service Reports Tab ───────────────────────────────────────────────
class _ServiceReportsTab extends ConsumerWidget {
  final VoidCallback onRefresh;
  const _ServiceReportsTab({required this.onRefresh});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(serviceStatsProvider);
    final selectedSalesDate = ref.watch(serviceSalesDateProvider);
    final salesByDateAsync = ref.watch(serviceSalesByDateProvider);
    return statsAsync.when(
      loading: () => Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          AppErrorMessage.from(e, fallback: AppErrorMessage.loadFailed),
        ),
      ),
      data: (stats) {
        final totalOrders = (stats['total_orders'] as num? ?? 0).toInt();
        final activeCount = (stats['active_count'] as num? ?? 0).toInt();
        final todayCount = (stats['today_count'] as num? ?? 0).toInt();
        final todayRevenue = (stats['today_revenue'] as num? ?? 0).toDouble();
        final totalRevenue = (stats['total_revenue'] as num? ?? 0).toDouble();
        final bookedCount = (stats['booked_count'] as num? ?? 0).toInt();
        final checkedInCount = (stats['checked_in_count'] as num? ?? 0).toInt();
        final inProgressCount = (stats['in_progress_count'] as num? ?? 0)
            .toInt();
        final completedCount = (stats['completed_count'] as num? ?? 0).toInt();
        final upcomingAppts = (stats['upcoming_appointments'] as num? ?? 0)
            .toInt();
        final topServices = stats['top_services'] as List<dynamic>? ?? [];
        final recentOrders = stats['recent_orders'] as List<dynamic>? ?? [];

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _StatsRow(
              cards: [
                _StatCardData(
                  label: 'Total Orders',
                  value: '$totalOrders',
                  icon: Icons.receipt_long_outlined,
                  color: AppColors.primary,
                ),
                _StatCardData(
                  label: 'Active Now',
                  value: '$activeCount',
                  icon: Icons.pending_actions_outlined,
                  color: AppColors.warning,
                ),
                _StatCardData(
                  label: 'Upcoming Appts',
                  value: '$upcomingAppts',
                  icon: Icons.event_outlined,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ],
            ),
            SizedBox(height: 12),
            _StatsRow(
              cards: [
                _StatCardData(
                  label: 'Today Orders',
                  value: '$todayCount',
                  icon: Icons.today_outlined,
                  color: AppColors.primaryLight,
                ),
                _StatCardData(
                  label: "Today's Revenue",
                  value: todayRevenue.toStringAsFixed(2),
                  icon: Icons.attach_money,
                  color: AppColors.success,
                ),
                _StatCardData(
                  label: 'Total Revenue',
                  value: totalRevenue.toStringAsFixed(2),
                  icon: Icons.monetization_on_outlined,
                  color: AppColors.success,
                ),
              ],
            ),
            SizedBox(height: 24),
            _ServiceSalesByDateSection(
              selectedDate: selectedSalesDate,
              salesAsync: salesByDateAsync,
              onPickDate: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedSalesDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked == null) {
                  return;
                }
                ref.read(serviceSalesDateProvider.notifier).state = DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                );
              },
            ),
            SizedBox(height: 24),
            _SectionHeader(title: 'Pipeline Status', onRefresh: onRefresh),
            SizedBox(height: 12),
            _ReportCard(
              child: Column(
                children: [
                  _PipelineRow('Booked', bookedCount, AppColors.primary),
                  _PipelineRow('Checked In', checkedInCount, AppColors.warning),
                  _PipelineRow(
                    'In Progress',
                    inProgressCount,
                    AppColors.primaryLight,
                  ),
                  _PipelineRow('Completed', completedCount, AppColors.success),
                ],
              ),
            ),
            SizedBox(height: 24),
            const _SectionHeader(title: 'Top Services'),
            SizedBox(height: 12),
            if (topServices.isEmpty)
              const _EmptyState(
                icon: Icons.bar_chart_outlined,
                title: 'No data yet',
                subtitle: 'Service order stats will appear here.',
              )
            else
              _TopServicesSection(topServices: topServices),
            SizedBox(height: 24),
            const _SectionHeader(title: 'Recent Orders'),
            SizedBox(height: 12),
            if (recentOrders.isEmpty)
              const _EmptyState(
                icon: Icons.history_outlined,
                title: 'No orders yet',
                subtitle: 'Recent service orders will show here.',
              )
            else
              _RecentOrdersSection(recentOrders: recentOrders, ref: ref),
            SizedBox(height: 32),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCardData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _StatsRow extends StatelessWidget {
  final List<_StatCardData> cards;

  const _StatsRow({required this.cards});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < cards.length; index++) ...[
          _StatCard(
            label: cards[index].label,
            value: cards[index].value,
            icon: cards[index].icon,
            color: cards[index].color,
          ),
          if (index != cards.length - 1) SizedBox(width: 12),
        ],
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _ReportCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: child,
    );
  }
}

class _ServiceSalesByDateSection extends StatelessWidget {
  final DateTime selectedDate;
  final AsyncValue<Map<String, dynamic>> salesAsync;
  final VoidCallback onPickDate;

  const _ServiceSalesByDateSection({
    required this.selectedDate,
    required this.salesAsync,
    required this.onPickDate,
  });

  String get _dateLabel =>
      '${selectedDate.month}/${selectedDate.day}/${selectedDate.year}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _SectionHeader(title: 'Service Sales')),
            OutlinedButton.icon(
              onPressed: onPickDate,
              icon: Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(_dateLabel),
            ),
          ],
        ),
        SizedBox(height: 12),
        salesAsync.when(
          loading: () => const _ReportCard(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _ReportCard(
            child: Text(
              AppErrorMessage.from(error, fallback: AppErrorMessage.loadFailed),
              style: TextStyle(color: AppColors.error),
            ),
          ),
          data: (data) {
            final saleCount = (data['sale_count'] as num? ?? 0).toInt();
            final revenue = (data['revenue'] as num? ?? 0).toDouble();
            final paymentMethods =
                data['payment_methods'] as List<dynamic>? ?? const [];
            final services = data['services'] as List<dynamic>? ?? const [];
            final recentSales =
                data['recent_sales'] as List<dynamic>? ?? const [];

            if (saleCount == 0) {
              return const _EmptyState(
                icon: Icons.point_of_sale_outlined,
                title: 'No service sales',
                subtitle:
                    'Paid service sales for the selected date appear here.',
              );
            }

            return _ReportCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MiniMetric(
                        label: 'Paid Sales',
                        value: '$saleCount',
                        icon: Icons.receipt_long_outlined,
                        color: AppColors.primary,
                      ),
                      _MiniMetric(
                        label: 'Revenue',
                        value:
                            '${ShopSettings.currency}${revenue.toStringAsFixed(2)}',
                        icon: Icons.payments_outlined,
                        color: AppColors.success,
                      ),
                    ],
                  ),
                  if (paymentMethods.isNotEmpty) ...[
                    SizedBox(height: 18),
                    Text(
                      'Payment Methods',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    ...paymentMethods.map((item) {
                      final row = item as Map<String, dynamic>;
                      return _ReportValueRow(
                        label: _paymentMethodDisplayName(
                          row['payment_type'] as String? ?? 'Payment',
                        ),
                        value:
                            '${ShopSettings.currency}${(row['revenue'] as num? ?? 0).toDouble().toStringAsFixed(2)}',
                      );
                    }),
                  ],
                  if (services.isNotEmpty) ...[
                    SizedBox(height: 18),
                    Text(
                      'Services Sold',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    ...services.map((item) {
                      final row = item as Map<String, dynamic>;
                      return _ReportValueRow(
                        label: row['service_name'] as String? ?? 'Service',
                        value:
                            '${ShopSettings.currency}${(row['revenue'] as num? ?? 0).toDouble().toStringAsFixed(2)}',
                      );
                    }),
                  ],
                  if (recentSales.isNotEmpty) ...[
                    SizedBox(height: 18),
                    Text(
                      'Recent Service Sales',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 8),
                    ...recentSales.map((item) {
                      final row = item as Map<String, dynamic>;
                      return _ReportValueRow(
                        label: row['service_name'] as String? ?? 'Service',
                        value: _fmtDateTimeRaw(row['created_at'] as String?),
                      );
                    }),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReportValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(width: 12),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TopServicesSection extends StatelessWidget {
  final List<dynamic> topServices;

  const _TopServicesSection({required this.topServices});

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      child: Column(
        children: topServices.map((item) {
          final service = item as Map<String, dynamic>;
          final name = service['service_name'] as String? ?? '—';
          final count = (service['order_count'] as num? ?? 0).toInt();
          final revenue = (service['revenue'] as num? ?? 0).toDouble();

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.design_services_rounded,
                    color: AppColors.primaryLight,
                    size: 18,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '$count orders',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  revenue.toStringAsFixed(2),
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _RecentOrdersSection extends StatelessWidget {
  final List<dynamic> recentOrders;
  final WidgetRef ref;

  const _RecentOrdersSection({required this.recentOrders, required this.ref});

  @override
  Widget build(BuildContext context) {
    return _ReportCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: recentOrders.asMap().entries.map((entry) {
          final isLast = entry.key == recentOrders.length - 1;
          final order = entry.value as Map<String, dynamic>;
          return Column(
            children: [
              _RecentOrderTile(order: order, ref: ref),
              if (!isLast)
                Divider(
                  height: 1,
                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                  indent: 36,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  final Map<String, dynamic> order;
  final WidgetRef ref;

  const _RecentOrderTile({required this.order, required this.ref});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'booked';
    final scheduledAt = order['scheduled_at'] as String?;
    final assignedStaff = _cleanText(order['assigned_staff']);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _statusColor(context, status),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order['service_name'] as String? ?? '—',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  _reportCustomerLabel(order),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                if (assignedStaff != null)
                  Text(
                    'Assigned: $assignedStaff',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                if (scheduledAt?.isNotEmpty == true)
                  Text(
                    _fmtDateTimeRaw(scheduledAt),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                (order['price'] as num? ?? 0).toStringAsFixed(2),
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _statusColor(context, status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status.replaceAll('_', ' '),
                  style: TextStyle(
                    color: _statusColor(context, status),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: 6),
              IconButton(
                icon: Icon(Icons.visibility_outlined, size: 18),
                tooltip: 'View details',
                onPressed: () => showServiceOrderDetailsDialog(
                  context,
                  ref,
                  order['id'] as String,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onRefresh;

  const _SectionHeader({required this.title, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        Spacer(),
        if (onRefresh != null)
          IconButton(
            icon: Icon(Icons.refresh, size: 18),
            onPressed: onRefresh,
            tooltip: 'Refresh',
          ),
      ],
    );
  }
}

class _PipelineRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _PipelineRow(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
