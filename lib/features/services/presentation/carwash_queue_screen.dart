import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../data/service_repository.dart';

// ─── Queue Board Screen ───────────────────────────────────────────────────────
class CarwashQueueScreen extends ConsumerStatefulWidget {
  const CarwashQueueScreen({super.key});

  @override
  ConsumerState<CarwashQueueScreen> createState() => _CarwashQueueScreenState();
}

class _CarwashQueueScreenState extends ConsumerState<CarwashQueueScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  Timer? _timer;
  int _baysCount = 4;

  @override
  void initState() {
    super.initState();
    _baysCount = ShopSettings.carwashBaysCount;
    _load();
    // Auto-refresh every 20 seconds
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final orders = await ServiceRepository.getOrders(filter: 'active');
    if (mounted) {
      setState(() {
        _orders = orders;
        _loading = false;
      });
    }
  }

  // Status flow helper (avoids importing service_management_screen to prevent
  // circular imports; carwash_queue_screen is imported there).
  static const _statusFlow = [
    'booked', 'checked_in', 'in_progress', 'completed', 'paid', 'cancelled',
  ];

  Future<void> _advanceStatus(Map<String, dynamic> order) async {
    final current = order['status'] as String? ?? 'booked';
    if (current == 'ready') {
      await ServiceRepository.updateOrderStatus(
        order['id'] as String,
        'completed',
      );
      await _load();
      return;
    }
    final idx = _statusFlow.indexOf(current);
    if (idx < 0 || idx >= _statusFlow.length - 1) return;
    await ServiceRepository.updateOrderStatus(
        order['id'] as String, _statusFlow[idx + 1]);
    await _load();
  }

  // Returns orders assigned to a given bay (null = unassigned)
  List<Map<String, dynamic>> _ordersForBay(String? bay) {
    if (bay == null) {
      return _orders
          .where((o) =>
              (o['bay_number'] as String?)?.isEmpty != false &&
              o['status'] != 'completed' &&
              o['status'] != 'paid' &&
              o['status'] != 'cancelled')
          .toList();
    }
    return _orders
        .where((o) =>
            o['bay_number'] == bay &&
            o['status'] != 'completed' &&
            o['status'] != 'paid' &&
            o['status'] != 'cancelled')
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.car_repair, color: AppColors.secondary, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('Queue Board'),
          ],
        ),
        actions: [
          // Bay count adjuster
          Row(
            children: [
              const Text('Bays:', style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: _baysCount <= 1
                    ? null
                    : () async {
                        await ShopSettings.setCarwashBaysCount(_baysCount - 1);
                        setState(() => _baysCount--);
                      },
              ),
              Text(
                '$_baysCount',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: _baysCount >= 20
                    ? null
                    : () async {
                        await ShopSettings.setCarwashBaysCount(_baysCount + 1);
                        setState(() => _baysCount++);
                      },
              ),
              const SizedBox(width: 8),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Legend bar
                Container(
                  color: AppColors.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  child: Row(
                    children: [
                      _LegendDot('Booked', AppColors.primary),
                      const SizedBox(width: 16),
                      _LegendDot('Checked In', AppColors.warning),
                      const SizedBox(width: 16),
                      _LegendDot('In Progress', AppColors.primaryLight),
                      const SizedBox(width: 16),
                      _LegendDot('Ready', AppColors.secondary),
                      const Spacer(),
                      Text(
                        '${_orders.length} active order${_orders.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Bay grid
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 320,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _baysCount + 1, // +1 for "Unassigned"
                    itemBuilder: (context, index) {
                      if (index == _baysCount) {
                        // Unassigned queue
                        final unassigned = _ordersForBay(null);
                        return _UnassignedCard(
                          orders: unassigned,
                          onOrderTap: (order) =>
                              _showAssignBaySheet(context, order),
                          onRefresh: _load,
                        );
                      }
                      final bayLabel = '${index + 1}';
                      final bayOrders = _ordersForBay(bayLabel);
                      return _BayCard(
                        bayNumber: bayLabel,
                        orders: bayOrders,
                        onAdvance: (order) => _advanceStatus(order),
                        onClearBay: bayOrders.isNotEmpty
                            ? (order) async {
                                await ServiceRepository.updateOrderBay(
                                    order['id'] as String, null);
                                await _load();
                              }
                            : null,
                        onOrderTap: (order) =>
                            _showAssignBaySheet(context, order),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _showAssignBaySheet(
      BuildContext context, Map<String, dynamic> order) async {
    final bays = List.generate(_baysCount, (i) => '${i + 1}');
    final current = order['bay_number'] as String?;

    final picked = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assign Bay — ${order['service_name'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              (order['customer_name'] as String?)?.isNotEmpty == true
                  ? order['customer_name'] as String
                  : 'Walk-in',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                // Clear bay option
                ChoiceChip(
                  label: const Text('No Bay'),
                  selected: current == null || current.isEmpty,
                  onSelected: (_) => Navigator.pop(ctx, ''),
                ),
                ...bays.map((b) => ChoiceChip(
                      label: Text('Bay $b'),
                      selected: current == b,
                      selectedColor: AppColors.primary.withValues(alpha: 0.2),
                      onSelected: (_) => Navigator.pop(ctx, b),
                    )),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (picked == null) return; // dismissed
    await ServiceRepository.updateOrderBay(
      order['id'] as String,
      picked.isEmpty ? null : picked,
    );
    await _load();
  }
}

// ─── Bay Card ─────────────────────────────────────────────────────────────────
class _BayCard extends StatelessWidget {
  final String bayNumber;
  final List<Map<String, dynamic>> orders;
  final Future<void> Function(Map<String, dynamic>) onAdvance;
  final void Function(Map<String, dynamic>)? onClearBay;
  final void Function(Map<String, dynamic>) onOrderTap;

  const _BayCard({
    required this.bayNumber,
    required this.orders,
    required this.onAdvance,
    required this.onOrderTap,
    this.onClearBay,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = orders.isEmpty;
    final order = isEmpty ? null : orders.first;
    final status = order?['status'] as String? ?? '';
    final statusColor = isEmpty ? AppColors.success : _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isEmpty
              ? AppColors.success.withValues(alpha: 0.3)
              : statusColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: isEmpty ? 0.06 : 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Icon(
                  isEmpty ? Icons.local_car_wash_outlined : Icons.car_repair,
                  color: statusColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Bay $bayNumber',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: statusColor,
                  ),
                ),
                const Spacer(),
                if (!isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status.replaceAll('_', ' '),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ── Body
          Expanded(
            child: isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: AppColors.success, size: 36),
                        SizedBox(height: 8),
                        Text(
                          'Available',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order!['service_name'] as String? ?? '—',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (order['customer_name'] as String?)?.isNotEmpty ==
                                  true
                              ? order['customer_name'] as String
                              : 'Walk-in',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        // Elapsed time
                        _ElapsedTime(
                          checkedInAt: order['checked_in_at'] as String?,
                          createdAt: order['created_at'] as String?,
                          durationMinutes: (order['service_duration_minutes']
                                  as num?)
                              ?.toInt(),
                        ),
                        const Spacer(),
                        // Price
                        Text(
                          (order['price'] as num? ?? 0).toStringAsFixed(2),
                          style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          // ── Actions
          if (!isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () => onAdvance(order!),
                      child: const Text('Next', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    tooltip: 'Move bay',
                    onPressed: () => onOrderTap(order!),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.08),
                      minimumSize: const Size(32, 32),
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

// ─── Unassigned Card ──────────────────────────────────────────────────────────
class _UnassignedCard extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final void Function(Map<String, dynamic>) onOrderTap;
  final VoidCallback onRefresh;

  const _UnassignedCard({
    required this.orders,
    required this.onOrderTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: orders.isEmpty
              ? AppColors.border
              : AppColors.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(
                  alpha: orders.isEmpty ? 0.04 : 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Icon(Icons.pending_outlined,
                    color: orders.isEmpty
                        ? AppColors.textSecondary
                        : AppColors.warning,
                    size: 18),
                const SizedBox(width: 8),
                Text(
                  'Queue',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: orders.isEmpty
                        ? AppColors.textSecondary
                        : AppColors.warning,
                  ),
                ),
                const Spacer(),
                if (orders.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${orders.length} waiting',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: orders.isEmpty
                ? const Center(
                    child: Text(
                      'No orders waiting',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: orders.length,
                    separatorBuilder: (context, idx) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final o = orders[i];
                      final status = o['status'] as String? ?? 'booked';
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onOrderTap(o),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _statusColor(status)
                                .withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _statusColor(status)
                                  .withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      o['service_name'] as String? ?? '—',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      (o['customer_name'] as String?)
                                                  ?.isNotEmpty ==
                                              true
                                          ? o['customer_name'] as String
                                          : 'Walk-in',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios,
                                  size: 12,
                                  color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Elapsed time widget ──────────────────────────────────────────────────────
class _ElapsedTime extends StatefulWidget {
  final String? checkedInAt;
  final String? createdAt;
  final int? durationMinutes;

  const _ElapsedTime({this.checkedInAt, this.createdAt, this.durationMinutes});

  @override
  State<_ElapsedTime> createState() => _ElapsedTimeState();
}

class _ElapsedTimeState extends State<_ElapsedTime> {
  Timer? _tick;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _update();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _update());
  }

  void _update() {
    final raw = widget.checkedInAt ?? widget.createdAt;
    if (raw == null) return;
    try {
      final start = DateTime.parse(raw).toLocal();
      if (mounted) setState(() => _elapsed = DateTime.now().difference(start));
    } catch (_) {}
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mins = _elapsed.inMinutes;
    final hours = _elapsed.inHours;
    final label = hours > 0
        ? '${hours}h ${mins % 60}m'
        : '${mins}m';
    final limit = widget.durationMinutes;
    final isOvertime = limit != null && mins > limit;

    return Row(
      children: [
        Icon(
          Icons.timer_outlined,
          size: 13,
          color: isOvertime ? AppColors.error : AppColors.textSecondary,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isOvertime ? AppColors.error : AppColors.textSecondary,
            fontWeight: isOvertime ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
        if (isOvertime) ...[
          const SizedBox(width: 4),
          const Text(
            'OVERTIME',
            style: TextStyle(
              color: AppColors.error,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Legend dot ───────────────────────────────────────────────────────────────
class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendDot(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'booked':       return AppColors.primary;
    case 'checked_in':   return AppColors.warning;
    case 'in_progress':  return AppColors.primaryLight;
    case 'ready':        return AppColors.secondary;
    case 'completed':    return AppColors.success;
    case 'paid':         return AppColors.textSecondary;
    default:             return AppColors.error;
  }
}
