import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_app/features/app/app_shell.dart';

import '../../../core/services/catalog_order_service.dart';
import '../../../core/services/branch_service.dart';
import '../../../core/services/messaging_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../widgets/compact_header_actions.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../sales/data/cart_provider.dart';
import '../../customers/presentation/customer_message_dialog.dart';
import '../../training/widgets/training_anchor.dart';
import '../../services/data/service_repository.dart';
import '../data/product_repository.dart';
import '../data/product_variant_repository.dart';

class CatalogOrdersScreen extends ConsumerStatefulWidget {
  final VoidCallback? onOpenPos;

  const CatalogOrdersScreen({super.key, this.onOpenPos});

  @override
  ConsumerState<CatalogOrdersScreen> createState() =>
      _CatalogOrdersScreenState();
}

class _CatalogOrdersScreenState extends ConsumerState<CatalogOrdersScreen> {
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

  Future<void> _requestPayment(CatalogOrder order) async {
    if (_updating.contains(order.id)) {
      return;
    }
    setState(() => _updating.add(order.id));
    try {
      final result = await CatalogOrderService.requestPayment(
        orderId: order.id,
        sendViaApi: false,
      );
      final message =
          result['message']?.toString() ??
          MessagingService.receiptMessage(
            customerName: order.customerName,
            saleId: order.orderNumber,
            amount:
                '${ShopSettings.currency}${order.subtotal.toStringAsFixed(2)}',
          );
      if (!mounted) {
        return;
      }
      _refresh();
      await CustomerMessageDialog.show(
        context,
        customerName: order.customerName,
        phoneNumber: result['recipient']?.toString() ?? order.phone,
        initialMessage: message,
        metadata: {
          'source': 'catalog_payment_request',
          'orderId': order.id,
          'orderNumber': order.orderNumber,
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(
              error,
              fallback: 'Could not request payment for this order.',
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

  Future<void> _acceptAndCheckout(CatalogOrder order) async {
    if (_updating.contains(order.id)) {
      return;
    }

    if (order.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This catalog order has no items to checkout.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final cart = ref.read(cartProvider);
    if (cart.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Replace current cart?'),
          content: Text(
            'Loading this order will clear the items currently in checkout.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Replace'),
            ),
          ],
        ),
      );
      if (!mounted) {
        return;
      }
      if (replace != true) {
        return;
      }
    }

    setState(() => _updating.add(order.id));
    final previousItems = ref
        .read(cartProvider)
        .map((item) => item.toHeldItem())
        .toList(growable: false);
    final previousDiscount = ref.read(discountProvider);
    final previousBranchId = BranchService.currentBranchId;
    var branchChanged = false;

    try {
      if (order.branchId != previousBranchId) {
        await BranchService.setCurrentBranch(order.branchId);
        branchChanged = true;
      }
      final lines = await _prepareCheckoutLines(order);
      final cartNotifier = ref.read(cartProvider.notifier);
      cartNotifier.clear();
      ref.read(discountProvider.notifier).state = 0;

      for (final line in lines) {
        if (line.isService) {
          final added = cartNotifier.addService(
            serviceOrderId: line.serviceOrderId!,
            serviceId: line.serviceId!,
            serviceName: line.serviceName!,
            price: line.price!,
          );
          if (!added) {
            throw Exception('${line.item.label} is already in checkout.');
          }
          continue;
        }

        final added = cartNotifier.addProduct(
          line.product!,
          variant: line.variant,
        );
        if (!added) {
          throw Exception('Not enough stock for ${line.item.label}.');
        }

        final cartKey = _cartKeyFor(line.product!, line.variant);
        final quantitySet = cartNotifier.setQuantity(
          cartKey,
          line.item.quantity,
        );
        if (!quantitySet) {
          throw Exception(
            'Not enough stock to load ${_formatQty(line.item.quantity)} x ${line.item.label}.',
          );
        }
      }

      if (order.status != 'accepted') {
        await CatalogOrderService.updateStatus(
          orderId: order.id,
          status: 'accepted',
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order #${order.orderNumber} is loaded in checkout.'),
        ),
      );
      _refresh();
      widget.onOpenPos?.call();
    } catch (error) {
      if (branchChanged) {
        await BranchService.setCurrentBranch(previousBranchId);
      }
      ref.read(cartProvider.notifier).restoreHeldItems(previousItems);
      ref.read(discountProvider.notifier).state = previousDiscount;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(
              error,
              fallback: 'Could not load this order into checkout.',
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

  Future<List<_CheckoutLine>> _prepareCheckoutLines(CatalogOrder order) async {
    final lines = <_CheckoutLine>[];
    for (final item in order.items) {
      if (item.isService) {
        final serviceId = item.serviceId.trim().isNotEmpty
            ? item.serviceId.trim()
            : item.productId.trim().replaceFirst(RegExp(r'^service:'), '');
        if (serviceId.isEmpty) {
          throw Exception('${item.label} is not linked to a POS service.');
        }
        final service = await ServiceRepository.getServiceById(serviceId);
        if (service == null) {
          throw Exception('${item.label} is no longer in services.');
        }
        final quantity = item.quantity <= 0 ? 1.0 : item.quantity;
        final price = item.lineTotal > 0
            ? item.lineTotal
            : item.unitPrice * quantity;
        final orderId = await ServiceRepository.createOrder(
          serviceId: serviceId,
          serviceName: item.productName,
          customerName: order.customerName,
          entryMode: 'online_catalog',
          status: 'ready',
          price: price,
          note:
              'Catalog order #${order.orderNumber}${quantity == 1 ? '' : ' - ${_formatQty(quantity)} requested'}',
        );
        lines.add(
          _CheckoutLine.service(
            serviceOrderId: orderId,
            serviceId: serviceId,
            serviceName: quantity == 1
                ? item.productName
                : '${item.productName} x ${_formatQty(quantity)}',
            price: price,
            item: item,
          ),
        );
        continue;
      }

      if (item.productId.trim().isEmpty) {
        throw Exception('${item.label} is not linked to a POS product.');
      }

      final product = await ProductRepository.getById(item.productId);
      if (product == null) {
        throw Exception('${item.label} is no longer in products.');
      }

      Map<String, dynamic>? variant;
      if (item.variantId.trim().isNotEmpty) {
        variant = await ProductVariantRepository.getById(item.variantId);
        if (variant == null) {
          throw Exception('${item.label} variant is no longer available.');
        }
      }

      lines.add(
        _CheckoutLine.product(product: product, variant: variant, item: item),
      );
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(syncControllerProvider.select((sync) => sync.dataVersion), (
      previous,
      next,
    ) {
      if (previous != null && previous != next && mounted) {
        _refresh();
      }
    });

    final isMobile = MediaQuery.sizeOf(context).width <= 720;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        leading:
            !Navigator.of(context).canPop() &&
                MediaQuery.of(context).size.width <= 800
            ? IconButton(
                icon: Icon(Icons.menu),
                onPressed: () =>
                    AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        title: Text(
          'Catalog Orders',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          CompactHeaderIconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: Icons.refresh_outlined,
          ),
          SizedBox(width: 6),
        ],
      ),
      body: TrainingAnchor(
        id: 'orders.workspace',
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surface,
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
            Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<CatalogOrder>>(
                future: _ordersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
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
                          style: TextStyle(color: AppColors.error),
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
                    separatorBuilder: (_, _) => SizedBox(height: 12),
                    itemBuilder: (context, index) => _CatalogOrderCard(
                      order: orders[index],
                      updating: _updating.contains(orders[index].id),
                      onStatus: (status) =>
                          _updateStatus(orders[index], status),
                      onPaymentRequest: () => _requestPayment(orders[index]),
                      onCheckout: () => _acceptAndCheckout(orders[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogOrderCard extends StatelessWidget {
  final CatalogOrder order;
  final bool updating;
  final ValueChanged<String> onStatus;
  final VoidCallback onPaymentRequest;
  final VoidCallback onCheckout;

  const _CatalogOrderCard({
    required this.order,
    required this.updating,
    required this.onStatus,
    required this.onPaymentRequest,
    required this.onCheckout,
  });

  @override
  Widget build(BuildContext context) {
    final created = order.createdAt == null
        ? ''
        : DateFormat('MMM d, HH:mm').format(order.createdAt!.toLocal());
    final statusColor = _statusColor(context, order.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    [
                      order.phone,
                      created,
                    ].where((part) => part.isNotEmpty).join(' - '),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
            SizedBox(height: 12),
            _InfoLine(icon: Icons.place_outlined, text: order.deliveryAddress),
          ],
          SizedBox(height: 8),
          _InfoLine(
            icon: Icons.store_outlined,
            text: 'Branch: ${order.branchName}',
          ),
          SizedBox(height: 8),
          _InfoLine(
            icon: order.fulfillmentMethod == 'pickup'
                ? Icons.storefront_outlined
                : Icons.local_shipping_outlined,
            text: order.fulfillmentMethod == 'pickup'
                ? 'Pickup order'
                : 'Delivery order',
          ),
          if (order.note.trim().isNotEmpty) ...[
            SizedBox(height: 8),
            _InfoLine(icon: Icons.notes_outlined, text: order.note),
          ],
          SizedBox(height: 14),
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_formatQty(item.quantity)} x ${item.label}',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${ShopSettings.currency}${item.lineTotal.toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_formatQty(order.itemCount)} item${order.itemCount == 1 ? '' : 's'}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              Text(
                '${ShopSettings.currency}${order.subtotal.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (order.status == 'pending' || order.status == 'accepted')
                FilledButton.icon(
                  onPressed: updating ? null : onCheckout,
                  icon: updating
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.point_of_sale_outlined),
                  label: Text(
                    order.status == 'pending'
                        ? 'Accept & Checkout'
                        : 'Load Checkout',
                  ),
                ),
              if (order.status == 'pending')
                OutlinedButton.icon(
                  onPressed: updating ? null : () => onStatus('accepted'),
                  icon: Icon(Icons.check_outlined),
                  label: Text('Accept Only'),
                ),
              if (order.status == 'accepted' ||
                  order.status == 'payment_requested')
                OutlinedButton.icon(
                  onPressed: updating ? null : onPaymentRequest,
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Request Payment'),
                ),
              if (order.status != 'fulfilled')
                OutlinedButton.icon(
                  onPressed: updating ? null : () => onStatus('fulfilled'),
                  icon: Icon(Icons.done_all_outlined),
                  label: Text('Fulfill'),
                ),
              if (order.status != 'rejected' && order.status == 'pending')
                TextButton.icon(
                  onPressed: updating ? null : () => onStatus('rejected'),
                  icon: Icon(Icons.block_outlined),
                  label: Text('Reject'),
                ),
              if (order.status != 'cancelled')
                TextButton.icon(
                  onPressed: updating ? null : () => onStatus('cancelled'),
                  icon: Icon(Icons.cancel_outlined),
                  label: Text('Cancel'),
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
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _CheckoutLine {
  final Map<String, dynamic>? product;
  final Map<String, dynamic>? variant;
  final String? serviceOrderId;
  final String? serviceId;
  final String? serviceName;
  final double? price;
  final CatalogOrderItem item;

  bool get isService => serviceOrderId != null;

  const _CheckoutLine.product({
    required this.product,
    required this.variant,
    required this.item,
  }) : serviceOrderId = null,
       serviceId = null,
       serviceName = null,
       price = null;

  const _CheckoutLine.service({
    required this.serviceOrderId,
    required this.serviceId,
    required this.serviceName,
    required this.price,
    required this.item,
  }) : product = null,
       variant = null;
}

String _cartKeyFor(
  Map<String, dynamic> product,
  Map<String, dynamic>? variant,
) {
  final productId = product['id']?.toString() ?? '';
  final variantId = variant?['id']?.toString();
  return variantId == null || variantId.isEmpty
      ? productId
      : '${productId}_$variantId';
}

String _statusLabel(String status) {
  switch (status) {
    case 'accepted':
      return 'Accepted';
    case 'payment_requested':
      return 'Payment Requested';
    case 'fulfilled':
      return 'Fulfilled';
    case 'completed':
      return 'Fulfilled';
    case 'rejected':
      return 'Rejected';
    case 'cancelled':
      return 'Cancelled';
    default:
      return 'Pending';
  }
}

Color _statusColor(BuildContext context, String status) {
  switch (status) {
    case 'accepted':
      return AppColors.primary;
    case 'payment_requested':
      return Theme.of(context).colorScheme.secondary;
    case 'fulfilled':
    case 'completed':
      return AppColors.success;
    case 'rejected':
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
