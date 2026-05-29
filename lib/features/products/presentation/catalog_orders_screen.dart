import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/catalog_order_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../widgets/empty_state_widget.dart';

class CatalogOrdersScreen extends StatefulWidget {
  const CatalogOrdersScreen({super.key});

  @override
  State<CatalogOrdersScreen> createState() => _CatalogOrdersScreenState();
}

class _CatalogOrdersScreenState extends State<CatalogOrdersScreen> {
  String _status = 'pending';
  late Future<List<CatalogOrder>> _ordersFuture;
  final Set<String> _updating = <String>{};

  @override
  void initState() {
    super.initState();
    _ordersFuture = _loadOrders();
  }

  Future<List<CatalogOrder>> _loadOrders() {
    return CatalogOrderService.fetchOrders(status: _status);
  }

  void _refresh() {
    setState(() => _ordersFuture = _loadOrders());
  }

  Future<void> _updateStatus(CatalogOrder order, String status) async {
    setState(() => _updating.add(order.id));
    try {
      await CatalogOrderService.updateStatus(orderId: order.id, status: status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order marked ${_statusLabel(status)}')),
      );
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(
              error,
              fallback: 'Could not update catalog order.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updating.remove(order.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width <= 720;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Catalog Orders'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: AppColors.surface,
            padding: EdgeInsets.fromLTRB(
              isMobile ? 16 : 24,
              0,
              isMobile ? 16 : 24,
              16,
            ),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'pending',
                  icon: Icon(Icons.pending_actions_outlined),
                  label: Text('Pending'),
                ),
                ButtonSegment(
                  value: 'accepted',
                  icon: Icon(Icons.check_circle_outline),
                  label: Text('Accepted'),
                ),
                ButtonSegment(
                  value: 'all',
                  icon: Icon(Icons.list_alt_outlined),
                  label: Text('All'),
                ),
              ],
              selected: {_status},
              onSelectionChanged: (values) {
                setState(() {
                  _status = values.first;
                  _ordersFuture = _loadOrders();
                });
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<CatalogOrder>>(
              future: _ordersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        AppErrorMessage.from(
                          snapshot.error,
                          fallback: 'Could not load catalog orders.',
                        ),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  );
                }

                final orders = snapshot.data ?? const <CatalogOrder>[];
                if (orders.isEmpty) {
                  return EmptyStateWidget(
                    icon: Icons.receipt_long_outlined,
                    title: 'No catalog orders',
                    subtitle: _status == 'pending'
                        ? 'New customer orders from the catalog link will appear here.'
                        : 'No orders found for this filter.',
                    actionLabel: 'Refresh',
                    onAction: _refresh,
                  );
                }

                return ListView.separated(
                  padding: EdgeInsets.all(isMobile ? 12 : 20),
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _CatalogOrderCard(
                    order: orders[index],
                    updating: _updating.contains(orders[index].id),
                    onStatus: (status) => _updateStatus(orders[index], status),
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

class _CatalogOrderCard extends StatelessWidget {
  final CatalogOrder order;
  final bool updating;
  final ValueChanged<String> onStatus;

  const _CatalogOrderCard({
    required this.order,
    required this.updating,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    final created = order.createdAt == null
        ? ''
        : DateFormat('MMM d, HH:mm').format(order.createdAt!.toLocal());
    final statusColor = _statusColor(order.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${order.orderNumber} - ${order.customerName}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      order.phone,
                      created,
                    ].where((part) => part.isNotEmpty).join(' - '),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              Chip(
                label: Text(_statusLabel(order.status)),
                backgroundColor: statusColor.withValues(alpha: 0.12),
                labelStyle: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (order.deliveryAddress.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _InfoLine(icon: Icons.place_outlined, text: order.deliveryAddress),
          ],
          if (order.note.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoLine(icon: Icons.notes_outlined, text: order.note),
          ],
          const SizedBox(height: 14),
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_formatQty(item.quantity)} x ${item.label}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${ShopSettings.currency}${item.lineTotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_formatQty(order.itemCount)} item${order.itemCount == 1 ? '' : 's'}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
              Text(
                '${ShopSettings.currency}${order.subtotal.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (order.status == 'pending')
                FilledButton.icon(
                  onPressed: updating ? null : () => onStatus('accepted'),
                  icon: updating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_outlined),
                  label: const Text('Accept'),
                ),
              if (order.status != 'completed')
                OutlinedButton.icon(
                  onPressed: updating ? null : () => onStatus('completed'),
                  icon: const Icon(Icons.done_all_outlined),
                  label: const Text('Complete'),
                ),
              if (order.status != 'cancelled')
                TextButton.icon(
                  onPressed: updating ? null : () => onStatus('cancelled'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'accepted':
      return 'Accepted';
    case 'completed':
      return 'Completed';
    case 'cancelled':
      return 'Cancelled';
    default:
      return 'Pending';
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'accepted':
      return AppColors.primary;
    case 'completed':
      return AppColors.success;
    case 'cancelled':
      return AppColors.error;
    default:
      return AppColors.warning;
  }
}

String _formatQty(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}
