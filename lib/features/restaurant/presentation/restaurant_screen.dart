import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/category_icon_utils.dart';
import '../../../widgets/empty_state_widget.dart';
import '../data/restaurant_repository.dart';
import 'restaurant_payment_screen.dart';

enum _RestaurantSection { floor, kitchen, bills }

class RestaurantScreen extends ConsumerStatefulWidget {
  final bool embeddedInAppShell;

  const RestaurantScreen({super.key, this.embeddedInAppShell = false});

  @override
  ConsumerState<RestaurantScreen> createState() => _RestaurantScreenState();
}

class _RestaurantScreenState extends ConsumerState<RestaurantScreen> {
  late Future<List<Map<String, dynamic>>> _tablesFuture;
  late Future<List<Map<String, dynamic>>> _billsFuture;
  _RestaurantSection _section = _RestaurantSection.floor;
  String _selectedArea = 'All areas';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    if (!mounted) return;
    _tablesFuture = RestaurantRepository.getTables();
    _billsFuture = RestaurantRepository.getBills();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && previous != next && mounted) _reload();
      },
    );

    final compact = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      appBar: widget.embeddedInAppShell
          ? null
          : AppBar(
              toolbarHeight: compact ? 60 : 68,
              titleSpacing: 4,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    compact ? 'Dining room' : 'Restaurant service',
                    style: TextStyle(
                      fontSize: compact ? 18 : 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.45,
                    ),
                  ),
                  if (!compact)
                    Text(
                      'Tables, kitchen pace and bills in one service flow',
                      style: TextStyle(
                        color: context.appTextSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Refresh service',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                if (_section == _RestaurantSection.floor)
                  Padding(
                    padding: EdgeInsets.only(right: compact ? 4 : 12),
                    child: compact
                        ? IconButton.filledTonal(
                            tooltip: 'Add table',
                            onPressed: _addTable,
                            icon: const Icon(Icons.add_rounded),
                          )
                        : FilledButton.icon(
                            onPressed: _addTable,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add table'),
                          ),
                  ),
              ],
            ),
      body: Column(
        children: [
          _buildSectionBar(compact),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: switch (_section) {
                _RestaurantSection.floor => _buildFloor(),
                _RestaurantSection.kitchen => _buildKitchen(),
                _RestaurantSection.bills => _buildBills(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBar(bool compact) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 24,
        compact ? 10 : 14,
        compact ? 12 : 24,
        compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: context.appSurface,
        border: Border(bottom: BorderSide(color: context.appBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SectionButton(
                    label: 'Floor plan',
                    icon: Icons.table_restaurant_rounded,
                    selected: _section == _RestaurantSection.floor,
                    onTap: () =>
                        setState(() => _section = _RestaurantSection.floor),
                  ),
                  const SizedBox(width: 8),
                  _SectionButton(
                    label: 'Kitchen board',
                    icon: Icons.soup_kitchen_rounded,
                    selected: _section == _RestaurantSection.kitchen,
                    onTap: () =>
                        setState(() => _section = _RestaurantSection.kitchen),
                  ),
                  const SizedBox(width: 8),
                  _SectionButton(
                    label: 'Bills',
                    icon: Icons.receipt_long_rounded,
                    selected: _section == _RestaurantSection.bills,
                    onTap: () =>
                        setState(() => _section = _RestaurantSection.bills),
                  ),
                ],
              ),
            ),
          ),
          if (widget.embeddedInAppShell) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh service',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
            if (_section == _RestaurantSection.floor)
              compact
                  ? IconButton.filledTonal(
                      tooltip: 'Add table',
                      onPressed: _addTable,
                      icon: const Icon(Icons.add_rounded),
                    )
                  : FilledButton.icon(
                      onPressed: _addTable,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add table'),
                    ),
          ],
        ],
      ),
    );
  }

  Widget _buildFloor() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: const ValueKey('restaurant-floor'),
      future: _tablesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return EmptyStateWidget(
            icon: Icons.cloud_off_rounded,
            title: 'Floor plan could not load',
            subtitle: _cleanError(snapshot.error!),
            onAction: _reload,
            actionLabel: 'Try again',
            actionIcon: Icons.refresh_rounded,
          );
        }

        final tables = snapshot.data ?? const <Map<String, dynamic>>[];
        if (tables.isEmpty) {
          return EmptyStateWidget(
            icon: Icons.table_restaurant_rounded,
            title: 'Build your dining room',
            subtitle:
                'Create tables by room or terrace. Orders will stay attached to each table from greeting to payment.',
            onAction: _addTable,
            actionLabel: 'Add first table',
          );
        }

        final areas =
            tables
                .map((table) => (table['area']?.toString().trim()).orEmpty)
                .where((area) => area.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        final selectedArea =
            _selectedArea == 'All areas' || areas.contains(_selectedArea)
            ? _selectedArea
            : 'All areas';
        final visible = selectedArea == 'All areas'
            ? tables
            : tables
                  .where((table) => table['area']?.toString() == selectedArea)
                  .toList();
        final occupied = tables.where(_hasActiveOrder).length;
        final available = tables.length - occupied;
        final covers = tables.fold<int>(
          0,
          (sum, table) =>
              sum + (_hasActiveOrder(table) ? _asInt(table['guest_count']) : 0),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 700;
            final padding = compact ? 12.0 : 24.0;
            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(padding, padding, padding, 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ServiceStat(
                        label: 'In service',
                        value: '$occupied',
                        icon: Icons.room_service_rounded,
                        color: AppColors.warning,
                      ),
                      _ServiceStat(
                        label: 'Available',
                        value: '$available',
                        icon: Icons.check_circle_rounded,
                        color: AppColors.success,
                      ),
                      _ServiceStat(
                        label: 'Covers',
                        value: '$covers',
                        icon: Icons.groups_rounded,
                        color: AppColors.secondary,
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    scrollDirection: Axis.horizontal,
                    itemCount: areas.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final area = index == 0 ? 'All areas' : areas[index - 1];
                      return FilterChip(
                        label: Text(area),
                        selected: selectedArea == area,
                        onSelected: (_) => setState(() => _selectedArea = area),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.fromLTRB(padding, 0, padding, padding),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 265,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: compact ? 1.28 : 1.42,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) =>
                        _buildTableCard(visible[index]),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTableCard(Map<String, dynamic> table) {
    final hasOrder = _hasActiveOrder(table);
    final checkout = table['status']?.toString() == 'checkout';
    final accent = checkout
        ? AppColors.secondary
        : hasOrder
        ? AppColors.warning
        : AppColors.success;
    final items = _items(table);
    final ready = items.where((item) => item['status'] == 'ready').length;

    return Material(
      color: context.appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: hasOrder ? accent.withValues(alpha: .38) : context.appBorder,
          width: hasOrder ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openTable(table),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .11),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(Icons.table_restaurant_rounded, color: accent),
                  ),
                  const Spacer(),
                  _StatusPill(
                    label: checkout
                        ? 'Payment'
                        : hasOrder
                        ? 'In service'
                        : 'Open',
                    color: accent,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                table['name']?.toString() ?? 'Table',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.35,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                hasOrder
                    ? '${table['order_no'] ?? ''} · ${_asInt(table['guest_count'])} guests'
                    : '${table['area'] ?? 'Dining room'} · ${_asInt(table['seats'])} seats',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.appTextSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasOrder ? _money(table['total']) : 'Start an order',
                      style: TextStyle(
                        color: hasOrder ? context.appTextPrimary : accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (ready > 0)
                    Text(
                      '$ready ready',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    )
                  else
                    Icon(Icons.arrow_forward_rounded, size: 18, color: accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKitchen() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: const ValueKey('restaurant-kitchen'),
      future: _tablesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return EmptyStateWidget(
            icon: Icons.cloud_off_rounded,
            title: 'Kitchen board could not load',
            subtitle: _cleanError(snapshot.error!),
            onAction: _reload,
            actionLabel: 'Try again',
          );
        }

        final tickets = <_KitchenTicket>[];
        for (final table in snapshot.data ?? const <Map<String, dynamic>>[]) {
          for (final item in _items(table)) {
            final status = item['status']?.toString() ?? 'draft';
            if (status == 'pending' ||
                status == 'preparing' ||
                status == 'ready') {
              tickets.add(_KitchenTicket(table: table, item: item));
            }
          }
        }
        if (tickets.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.soup_kitchen_rounded,
            title: 'Kitchen is clear',
            subtitle:
                'New items appear here only after the server sends them from a table order.',
            positiveTone: true,
          );
        }

        final groups = <String, List<_KitchenTicket>>{
          'pending': tickets
              .where((ticket) => ticket.status == 'pending')
              .toList(),
          'preparing': tickets
              .where((ticket) => ticket.status == 'preparing')
              .toList(),
          'ready': tickets.where((ticket) => ticket.status == 'ready').toList(),
        };

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 880) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _KitchenLane(
                        title: 'New',
                        subtitle: 'Waiting to start',
                        color: AppColors.warning,
                        tickets: groups['pending']!,
                        onAdvance: _advanceKitchen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _KitchenLane(
                        title: 'Cooking',
                        subtitle: 'On the line',
                        color: AppColors.warning,
                        tickets: groups['preparing']!,
                        onAdvance: _advanceKitchen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _KitchenLane(
                        title: 'Ready',
                        subtitle: 'Run to table',
                        color: AppColors.success,
                        tickets: groups['ready']!,
                        onAdvance: _advanceKitchen,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _KitchenMobileGroup(
                  title: 'New',
                  color: AppColors.warning,
                  tickets: groups['pending']!,
                  onAdvance: _advanceKitchen,
                ),
                _KitchenMobileGroup(
                  title: 'Cooking',
                  color: AppColors.warning,
                  tickets: groups['preparing']!,
                  onAdvance: _advanceKitchen,
                ),
                _KitchenMobileGroup(
                  title: 'Ready',
                  color: AppColors.success,
                  tickets: groups['ready']!,
                  onAdvance: _advanceKitchen,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBills() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: const ValueKey('restaurant-bills'),
      future: _billsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError) {
          return EmptyStateWidget(
            icon: Icons.cloud_off_rounded,
            title: 'Bills could not load',
            subtitle: _cleanError(snapshot.error!),
            onAction: _reload,
            actionLabel: 'Try again',
          );
        }
        final bills = snapshot.data ?? const <Map<String, dynamic>>[];
        if (bills.isEmpty) {
          return const EmptyStateWidget(
            icon: Icons.receipt_long_rounded,
            title: 'No tables waiting to pay',
            subtitle:
                'When a server closes a table, its bill moves here for payment without leaving restaurant service.',
            positiveTone: true,
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 700 ? 12.0 : 24.0;
            return GridView.builder(
              padding: EdgeInsets.all(padding),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 390,
                mainAxisExtent: 178,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: bills.length,
              itemBuilder: (context, index) {
                final bill = bills[index];
                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: context.appSurface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: context.appBorder),
                    boxShadow: context.appPanelShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.receipt_long_rounded,
                            color: AppColors.secondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              bill['name']?.toString() ?? 'Table bill',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _StatusPill(
                            label: 'Ready to pay',
                            color: AppColors.secondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _money(bill['total']),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () =>
                              _takeBillPayment(bill['id'] as String),
                          icon: const Icon(Icons.payments_rounded, size: 18),
                          label: const Text('Take payment'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openTable(Map<String, dynamic> table) async {
    if (table['status']?.toString() == 'checkout') {
      setState(() => _section = _RestaurantSection.bills);
      _message('This table is already waiting for payment.');
      return;
    }
    try {
      var orderId = table['order_id']?.toString() ?? '';
      if (orderId.isEmpty) {
        final guests = await _askGuestCount(
          _asInt(table['seats']).clamp(1, 50),
        );
        if (guests == null) return;
        orderId = await RestaurantRepository.openOrder(
          tableId: table['id'] as String,
          guests: guests,
        );
      }
      final current = await RestaurantRepository.getTable(
        table['id'] as String,
      );
      if (!mounted || current == null) return;
      final showBills = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => RestaurantOrderScreen(
            tableId: table['id'] as String,
            orderId: orderId,
            tableName: current['name']?.toString() ?? 'Table',
          ),
        ),
      );
      if (mounted && showBills == true) {
        setState(() => _section = _RestaurantSection.bills);
      }
      _reload();
    } catch (error) {
      _message(error, error: true);
    }
  }

  Future<int?> _askGuestCount(int suggested) {
    var guests = suggested;
    return showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Seat this table'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How many guests?',
                style: TextStyle(color: context.appTextSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.outlined(
                    onPressed: guests > 1
                        ? () => setDialogState(() => guests -= 1)
                        : null,
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  SizedBox(
                    width: 82,
                    child: Text(
                      '$guests',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: guests < 50
                        ? () => setDialogState(() => guests += 1)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, guests),
              child: const Text('Open table'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addTable() async {
    final name = TextEditingController();
    final area = TextEditingController();
    final seats = TextEditingController(text: '2');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a table'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Table name',
                  hintText: 'For example: T12',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: area,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Room or area',
                  hintText: 'Main room, terrace, upstairs…',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: seats,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Seats'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add table'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await RestaurantRepository.addTable(
          name: name.text,
          area: area.text,
          seats: int.tryParse(seats.text) ?? 2,
        );
        _reload();
      } catch (error) {
        _message(error, error: true);
      }
    }
    name.dispose();
    area.dispose();
    seats.dispose();
  }

  Future<void> _advanceKitchen(_KitchenTicket ticket) async {
    const next = {
      'pending': 'preparing',
      'preparing': 'ready',
      'ready': 'served',
    };
    try {
      await RestaurantRepository.updateKitchenStatus(
        orderId: ticket.table['order_id'] as String,
        itemId: ticket.item['id'] as String,
        status: next[ticket.status] ?? 'preparing',
      );
      _reload();
    } catch (error) {
      _message(error, error: true);
    }
  }

  Future<void> _takeBillPayment(String holdId) async {
    await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RestaurantPaymentScreen(billId: holdId),
      ),
    );
    _reload();
  }

  bool _hasActiveOrder(Map<String, dynamic> table) =>
      (table['order_id']?.toString() ?? '').isNotEmpty;

  void _message(Object value, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_cleanError(value)),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }
}

class RestaurantOrderScreen extends ConsumerStatefulWidget {
  final String tableId;
  final String orderId;
  final String tableName;
  final Map<String, dynamic>? initialTable;
  final List<Map<String, dynamic>>? initialMenu;

  const RestaurantOrderScreen({
    super.key,
    required this.tableId,
    required this.orderId,
    required this.tableName,
    this.initialTable,
    this.initialMenu,
  });

  @override
  ConsumerState<RestaurantOrderScreen> createState() =>
      _RestaurantOrderScreenState();
}

class _RestaurantOrderScreenState extends ConsumerState<RestaurantOrderScreen> {
  late Future<_OrderWorkspaceData> _workspaceFuture;
  String _query = '';
  String _category = 'All';
  bool _busy = false;
  bool _mobileTicket = false;

  @override
  void initState() {
    super.initState();
    final initialTable = widget.initialTable;
    final initialMenu = widget.initialMenu;
    _workspaceFuture = initialTable != null && initialMenu != null
        ? Future.value(
            _OrderWorkspaceData(table: initialTable, menu: initialMenu),
          )
        : _loadWorkspace();
  }

  Future<_OrderWorkspaceData> _loadWorkspace() async {
    final table = await RestaurantRepository.getTable(widget.tableId);
    if (table == null) throw Exception('Table order no longer exists.');
    final menu = await RestaurantRepository.getMenuItems();
    return _OrderWorkspaceData(table: table, menu: menu);
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _workspaceFuture = _loadWorkspace());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && previous != next) _reload();
      },
    );
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.tableName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              'Active table order',
              style: TextStyle(
                color: context.appTextSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh order',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<_OrderWorkspaceData>(
        future: _workspaceFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return EmptyStateWidget(
              icon: Icons.error_outline_rounded,
              title: 'Order could not load',
              subtitle: _cleanError(snapshot.error ?? 'Unknown error'),
              onAction: _reload,
              actionLabel: 'Try again',
            );
          }
          final data = snapshot.data!;
          return LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 980) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildMenu(data.menu, wide: true)),
                    Container(
                      width: 410,
                      decoration: BoxDecoration(
                        color: context.appSurface,
                        border: Border(
                          left: BorderSide(color: context.appBorder),
                        ),
                      ),
                      child: _buildTicket(data.table),
                    ),
                  ],
                );
              }

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    color: context.appSurface,
                    child: Row(
                      children: [
                        Expanded(
                          child: _MobileOrderTab(
                            icon: Icons.restaurant_menu_rounded,
                            label: 'Menu',
                            selected: !_mobileTicket,
                            onTap: () => setState(() => _mobileTicket = false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MobileOrderTab(
                            icon: Icons.receipt_long_rounded,
                            label: 'Order (${_items(data.table).length})',
                            selected: _mobileTicket,
                            onTap: () => setState(() => _mobileTicket = true),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _mobileTicket
                        ? _buildTicket(data.table)
                        : _buildMenu(data.menu, wide: false),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMenu(List<Map<String, dynamic>> menu, {required bool wide}) {
    final categories = menu.map(_menuSection).toSet().toList()..sort();
    if (_category != 'All' && !categories.contains(_category)) {
      _category = 'All';
    }
    final needle = _query.trim().toLowerCase();
    final visible = menu.where((item) {
      final categoryMatch =
          _category == 'All' || _menuSection(item) == _category;
      final searchMatch =
          needle.isEmpty ||
          (item['name']?.toString().toLowerCase().contains(needle) ?? false) ||
          _menuSection(item).toLowerCase().contains(needle);
      return categoryMatch && searchMatch;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 14, wide ? 24 : 12, 12),
          color: context.appSurface,
          child: wide
              ? Row(
                  children: [
                    const Expanded(child: _MenuHeading()),
                    SizedBox(width: 330, child: _menuSearch()),
                    const SizedBox(width: 10),
                    _addMenuButton(compact: true),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(child: _MenuHeading()),
                        _addMenuButton(compact: true),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _menuSearch(),
                  ],
                ),
        ),
        if (menu.isNotEmpty)
          Container(
            height: 48,
            color: context.appSurface,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 24 : 12,
                vertical: 3,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: categories.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final category = index == 0 ? 'All' : categories[index - 1];
                return FilterChip(
                  selected: _category == category,
                  label: Text(category),
                  onSelected: (_) => setState(() => _category = category),
                );
              },
            ),
          ),
        Expanded(
          child: menu.isEmpty
              ? EmptyStateWidget(
                  icon: Icons.ramen_dining_rounded,
                  title: 'Your restaurant menu is empty',
                  subtitle:
                      'Create dishes and drinks here. Retail catalog items stay out unless they are deliberately added to the restaurant menu.',
                  onAction: _createMenuItem,
                  actionLabel: 'Create first menu item',
                  actionIcon: Icons.add_rounded,
                )
              : visible.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.search_off_rounded,
                  title: 'No menu items found',
                  subtitle: 'Try another dish name or menu section.',
                  compact: true,
                )
              : GridView.builder(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 24 : 12,
                    12,
                    wide ? 24 : 12,
                    wide ? 24 : 12,
                  ),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: wide ? 235 : 190,
                    childAspectRatio: wide ? 1.05 : .92,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, index) =>
                      _buildMenuCard(visible[index]),
                ),
        ),
      ],
    );
  }

  Widget _menuSearch() => TextField(
    onChanged: (value) => setState(() => _query = value),
    decoration: const InputDecoration(
      hintText: 'Find a dish or drink',
      prefixIcon: Icon(Icons.search_rounded),
      isDense: true,
    ),
  );

  Widget _addMenuButton({required bool compact}) => compact
      ? IconButton.filledTonal(
          tooltip: 'Create menu item',
          onPressed: _busy ? null : _createMenuItem,
          icon: const Icon(Icons.add_rounded),
        )
      : FilledButton.icon(
          onPressed: _busy ? null : _createMenuItem,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Menu item'),
        );

  Widget _buildMenuCard(Map<String, dynamic> item) {
    final section = _menuSection(item);
    return Material(
      color: context.appSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: context.appBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : () => _addItem(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _MenuArtwork(item: item)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name']?.toString() ?? 'Menu item',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    section,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.appTextSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _money(item['price']),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicket(Map<String, dynamic> table) {
    final items = _items(table);
    final draftCount = items.where((item) => item['status'] == 'draft').length;
    final total = (table['total'] as num? ?? 0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order ${table['order_no'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_asInt(table['guest_count'])} guests · ${items.length} line${items.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: context.appTextSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                label: draftCount > 0
                    ? '$draftCount unsent'
                    : 'Kitchen updated',
                color: draftCount > 0 ? AppColors.warning : AppColors.success,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: context.appBorder),
        Expanded(
          child: items.isEmpty
              ? const EmptyStateWidget(
                  icon: Icons.room_service_outlined,
                  title: 'Start the table order',
                  subtitle:
                      'Choose dishes from the menu. Nothing reaches the kitchen until you send it.',
                  compact: true,
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _buildTicketItem(items[index]),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: context.appSurface,
            border: Border(top: BorderSide(color: context.appBorder)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Table total',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.appTextSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        _money(total),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (draftCount > 0)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _sendToKitchen,
                    icon: const Icon(Icons.soup_kitchen_rounded, size: 18),
                    label: Text('Send $draftCount to kitchen'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy || items.isEmpty
                        ? null
                        : () => _checkout(table),
                    icon: const Icon(Icons.receipt_long_rounded, size: 18),
                    label: const Text('Prepare bill'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTicketItem(Map<String, dynamic> item) {
    final quantity = (item['quantity'] as num? ?? 0).toDouble();
    final price = (item['unit_price'] as num? ?? 0).toDouble();
    final status = item['status']?.toString() ?? 'draft';
    final editable = status == 'draft';
    final color = _kitchenStatusColor(status);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appSurfaceHighlight.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item['product_name']?.toString() ?? 'Menu item',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(label: _kitchenStatusLabel(status), color: color),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (editable) ...[
                _QuantityButton(
                  icon: quantity <= 1
                      ? Icons.delete_outline_rounded
                      : Icons.remove_rounded,
                  onTap: _busy ? null : () => _setQuantity(item, quantity - 1),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    _quantityLabel(quantity),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _QuantityButton(
                  icon: Icons.add_rounded,
                  onTap: _busy ? null : () => _setQuantity(item, quantity + 1),
                ),
              ] else
                Text(
                  '${_quantityLabel(quantity)} × ${_money(price)}',
                  style: TextStyle(
                    color: context.appTextSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              const Spacer(),
              Text(
                _money(quantity * price),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addItem(Map<String, dynamic> item) => _mutate(() async {
    await RestaurantRepository.addProduct(
      orderId: widget.orderId,
      product: item,
    );
  });

  Future<void> _setQuantity(Map<String, dynamic> item, double quantity) =>
      _mutate(() async {
        await RestaurantRepository.updateItemQuantity(
          orderId: widget.orderId,
          itemId: item['id'] as String,
          quantity: quantity,
        );
      });

  Future<void> _sendToKitchen() => _mutate(() async {
    final sent = await RestaurantRepository.sendToKitchen(widget.orderId);
    if (sent > 0) {
      _message('$sent item${sent == 1 ? '' : 's'} sent to the kitchen.');
    }
  });

  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _workspaceFuture = _loadWorkspace();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _message(error, error: true);
    }
  }

  Future<void> _checkout(Map<String, dynamic> table) async {
    final parts = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Prepare table bill'),
        children: [1, 2, 3, 4]
            .map(
              (count) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, count),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(count == 1 ? 'One bill' : '$count equal bills'),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (parts == null || _busy) return;
    setState(() => _busy = true);
    try {
      final holds = await RestaurantRepository.prepareBill(
        table: table,
        splitCount: parts,
      );
      if (!mounted) return;
      _message(
        '${holds.length} bill${holds.length == 1 ? '' : 's'} ready for payment.',
      );
      if (holds.length == 1) {
        final billItems = List<Map<String, dynamic>>.from(
          table['items'] as List<dynamic>? ?? const [],
        );
        final billTotal = billItems.fold<double>(
          0,
          (sum, item) =>
              sum +
              ((item['quantity'] as num?)?.toDouble() ?? 0) *
                  ((item['unit_price'] as num?)?.toDouble() ?? 0),
        );
        setState(() => _busy = false);
        final saleId = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => RestaurantPaymentScreen(
              billId: holds.single,
              initialBill: {
                'id': holds.single,
                'name': '${table['name'] ?? widget.tableName} · Bill 1/1',
                'source': 'restaurant',
                'source_ref': widget.orderId,
                'subtotal': billTotal,
                'tax': 0.0,
                'discount': 0.0,
                'total': billTotal,
                'items': billItems,
              },
            ),
          ),
        );
        if (!mounted) return;
        // A cancelled payment stays in the Bills queue; a completed payment
        // releases the table and returns the cashier to the floor.
        Navigator.of(context).pop(saleId == null);
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _message(error, error: true);
    }
  }

  Future<void> _createMenuItem() async {
    final name = TextEditingController();
    final price = TextEditingController();
    final section = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create menu item'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Dish or drink name',
                  hintText: 'For example: Grilled tilapia',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Menu price',
                  prefixText: ShopSettings.currency,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: section,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Menu section',
                  hintText: 'Mains, drinks, dessert…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'name': name.text,
              'price': price.text,
              'section': section.text,
            }),
            child: const Text('Create item'),
          ),
        ],
      ),
    );
    name.dispose();
    price.dispose();
    section.dispose();
    if (result == null) return;
    final amount = double.tryParse(result['price']?.trim() ?? '');
    if ((result['name']?.trim() ?? '').isEmpty ||
        amount == null ||
        amount < 0) {
      _message('Enter a menu item name and a valid price.', error: true);
      return;
    }
    await _mutate(() async {
      await RestaurantRepository.createMenuItem(
        name: result['name']!,
        price: amount,
        section: result['section'],
      );
    });
  }

  void _message(Object value, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_cleanError(value)),
        backgroundColor: error ? AppColors.error : AppColors.success,
      ),
    );
  }
}

class _SectionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SectionButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.appTextPrimary : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? context.appSurface : context.appTextSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? context.appSurface : context.appTextPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ServiceStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.appBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 9),
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: context.appTextSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: .1,
        ),
      ),
    );
  }
}

class _KitchenTicket {
  final Map<String, dynamic> table;
  final Map<String, dynamic> item;

  const _KitchenTicket({required this.table, required this.item});

  String get status => item['status']?.toString() ?? 'pending';
}

class _KitchenLane extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final List<_KitchenTicket> tickets;
  final ValueChanged<_KitchenTicket> onAdvance;

  const _KitchenLane({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.tickets,
    required this.onAdvance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.appSurfaceHighlight.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: context.appTextSecondary,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(label: '${tickets.length}', color: color),
              ],
            ),
          ),
          Divider(height: 1, color: context.appBorder),
          Expanded(
            child: tickets.isEmpty
                ? Center(
                    child: Text(
                      'Nothing here',
                      style: TextStyle(
                        color: context.appTextSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: tickets.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _KitchenTicketCard(
                      ticket: tickets[index],
                      color: color,
                      onAdvance: onAdvance,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _KitchenMobileGroup extends StatelessWidget {
  final String title;
  final Color color;
  final List<_KitchenTicket> tickets;
  final ValueChanged<_KitchenTicket> onAdvance;

  const _KitchenMobileGroup({
    required this.title,
    required this.color,
    required this.tickets,
    required this.onAdvance,
  });

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Text(
                  '${tickets.length}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          ...tickets.map(
            (ticket) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _KitchenTicketCard(
                ticket: ticket,
                color: color,
                onAdvance: onAdvance,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KitchenTicketCard extends StatelessWidget {
  final _KitchenTicket ticket;
  final Color color;
  final ValueChanged<_KitchenTicket> onAdvance;

  const _KitchenTicketCard({
    required this.ticket,
    required this.color,
    required this.onAdvance,
  });

  @override
  Widget build(BuildContext context) {
    final quantity = (ticket.item['quantity'] as num? ?? 0).toDouble();
    final action = switch (ticket.status) {
      'pending' => 'Start',
      'preparing' => 'Mark ready',
      _ => 'Served',
    };
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _quantityLabel(quantity),
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ticket.item['product_name']?.toString() ?? 'Menu item',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Icon(
                Icons.table_restaurant_rounded,
                size: 15,
                color: context.appTextSecondary,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  ticket.table['name']?.toString() ?? 'Table',
                  style: TextStyle(
                    color: context.appTextSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.tonal(
                onPressed: () => onAdvance(ticket),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: Text(action),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuHeading extends StatelessWidget {
  const _MenuHeading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Restaurant menu',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Tap an item to add it to this table',
          style: TextStyle(color: context.appTextSecondary, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _MenuArtwork extends StatelessWidget {
  final Map<String, dynamic> item;

  const _MenuArtwork({required this.item});

  @override
  Widget build(BuildContext context) {
    final source = item['image_url']?.toString().trim() ?? '';
    Widget? image;
    if (source.startsWith('http://') || source.startsWith('https://')) {
      image = Image.network(
        source,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    } else if (source.isNotEmpty && File(source).existsSync()) {
      image = Image.file(
        File(source),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, _, _) => _fallback(context),
      );
    }
    return ColoredBox(
      color: context.appSurfaceHighlight,
      child: image ?? _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    final section = _menuSection(item);
    final tone = _sectionColor(section);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tone.withValues(alpha: context.isDarkMode ? .28 : .16),
            tone.withValues(alpha: context.isDarkMode ? .12 : .05),
          ],
        ),
      ),
      child: Center(
        child: Icon(CategoryIconUtils.iconFor(section), color: tone, size: 34),
      ),
    );
  }
}

class _MobileOrderTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MobileOrderTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.appTextPrimary : context.appSurfaceHighlight,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? context.appSurface : context.appTextSecondary,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? context.appSurface
                        : context.appTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
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

class _QuantityButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _QuantityButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton.outlined(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        icon: Icon(icon, size: 16),
      ),
    );
  }
}

class _OrderWorkspaceData {
  final Map<String, dynamic> table;
  final List<Map<String, dynamic>> menu;

  const _OrderWorkspaceData({required this.table, required this.menu});
}

extension on String? {
  String get orEmpty => this ?? '';
}

List<Map<String, dynamic>> _items(Map<String, dynamic> table) {
  return (table['items'] as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

String _menuSection(Map<String, dynamic> item) {
  final value = item['category_name']?.toString().trim() ?? '';
  return value.isEmpty ? "Chef's menu" : value;
}

Color _sectionColor(String section) {
  final colors = <Color>[
    AppColors.primary,
    AppColors.secondary,
    AppColors.warning,
    AppColors.orangeDeep,
    AppColors.metricMonth,
    AppColors.metricStaff,
  ];
  return colors[section.toLowerCase().hashCode.abs() % colors.length];
}

Color _kitchenStatusColor(String status) => switch (status) {
  'pending' => AppColors.warning,
  'preparing' => AppColors.warning,
  'ready' || 'served' => AppColors.success,
  _ => AppColors.secondary,
};

String _kitchenStatusLabel(String status) => switch (status) {
  'draft' => 'Not sent',
  'pending' => 'New',
  'preparing' => 'Cooking',
  'ready' => 'Ready',
  'served' => 'Served',
  _ => status,
};

String _quantityLabel(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

int _asInt(Object? value) => (value as num?)?.toInt() ?? 0;

String _money(Object? value) {
  final amount = (value as num? ?? 0).toDouble();
  return '${ShopSettings.currency}${amount.toStringAsFixed(2)}';
}

String _cleanError(Object value) =>
    value.toString().replaceFirst('Exception: ', '').trim();
