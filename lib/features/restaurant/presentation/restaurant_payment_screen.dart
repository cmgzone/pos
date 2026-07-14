import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/services/pos_payment_service.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/stitch_kit.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/error_messages.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../gift_cards/data/gift_card_repository.dart';
import '../../loyalty/data/loyalty_repository.dart';
import '../../sales/data/sale_repository.dart';
import '../../sales/presentation/payment_checkout_dialog.dart';
import '../../settings/data/payment_method_repository.dart';
import '../../shifts/data/shift_repository.dart';
import '../data/restaurant_repository.dart';

class RestaurantPaymentScreen extends StatefulWidget {
  final String billId;
  final Map<String, dynamic>? initialBill;

  const RestaurantPaymentScreen({
    super.key,
    required this.billId,
    this.initialBill,
  });

  @override
  State<RestaurantPaymentScreen> createState() =>
      _RestaurantPaymentScreenState();
}

class _RestaurantPaymentScreenState extends State<RestaurantPaymentScreen> {
  late Future<Map<String, dynamic>?> _billFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _billFuture = widget.initialBill == null
        ? RestaurantRepository.getBill(widget.billId)
        : Future.value(widget.initialBill);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Table payment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              'Restaurant bill',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _billFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (snapshot.hasError || snapshot.data == null) {
            return EmptyStateWidget(
              icon: Icons.receipt_long_outlined,
              title: 'Bill is no longer available',
              subtitle: snapshot.hasError
                  ? AppErrorMessage.from(
                      snapshot.error!,
                      fallback: 'This bill could not be loaded.',
                    )
                  : 'It may already have been paid from another device.',
              onAction: () => Navigator.of(context).pop(),
              actionLabel: 'Back to bills',
              actionIcon: Icons.arrow_back_rounded,
            );
          }
          final bill = snapshot.data!;
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 820;
              final content = wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 6, child: _BillItemsPanel(bill: bill)),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 330,
                          child: _PaymentSummaryPanel(
                            bill: bill,
                            busy: _busy,
                            onPay: () => _takePayment(bill),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: _BillItemsPanel(bill: bill)),
                        _PaymentSummaryPanel(
                          bill: bill,
                          busy: _busy,
                          onPay: () => _takePayment(bill),
                          compact: true,
                        ),
                      ],
                    );
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 980),
                  child: Padding(
                    padding: EdgeInsets.all(wide ? 24 : 12),
                    child: content,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _takePayment(Map<String, dynamic> bill) async {
    if (_busy) return;
    final total = (bill['total'] as num? ?? 0).toDouble();
    final result = await PaymentCheckoutDialog.show(context, total: total);
    if (!mounted || result == null) return;
    setState(() => _busy = true);
    try {
      final type = result['type']?.toString() ?? '';
      final String saleId;
      if (type == 'kopesha') {
        final customer = result['customer'] as Map<String, dynamic>?;
        if (customer == null) throw Exception('Select a customer for Kopesha.');
        saleId = await RestaurantRepository.payBill(
          holdId: widget.billId,
          paymentType: 'Kopesha',
          isCashDrawer: false,
          customerId: customer['id'] as String?,
          customerName: customer['name'] as String?,
          dueDate: result['dueDate'] as String?,
          paymentMetadata: _checkoutMetadata(result),
        );
      } else if (type == 'mpesa') {
        saleId = await _completeMpesa(bill, result);
      } else if (type == 'mpesa_manual') {
        final payment = result['payment'];
        if (payment is! PosPayment || !payment.isPaid) {
          throw Exception('M-Pesa payment has not been confirmed.');
        }
        final customer = result['customer'] as Map<String, dynamic>?;
        saleId = await RestaurantRepository.payBill(
          holdId: widget.billId,
          paymentType: 'M-Pesa',
          isCashDrawer: false,
          customerId: customer?['id'] as String?,
          customerName: customer?['name'] as String?,
          paymentProvider: 'mpesa_c2b',
          paymentReference:
              payment.receiptNumber ?? payment.externalReference ?? payment.id,
          paymentStatus: 'paid',
          paymentMetadata: {
            ..._checkoutMetadata(result),
            ...payment.metadata,
            'posPaymentId': payment.id,
            'providerSaleLinkStatus': 'pending_reconcile',
          },
        );
        await _linkMpesa(payment: payment, saleId: saleId);
      } else {
        final method = result['paymentMethod'] as Map<String, dynamic>?;
        if (method == null) throw Exception('Choose a payment method.');
        final provider = PaymentMethodRepository.providerKeyFor(method);
        final isCash = provider == PaymentMethodRepository.providerCash;
        String? shiftId;
        if (isCash) {
          final access = await ShiftRepository.ensureShiftForCashHandling(
            userId: SessionService.currentUserId,
            cashierName: SessionService.currentUserName,
            role: SessionService.currentUserRole,
          );
          if (access.requiresShift && access.currentShift == null) {
            throw Exception('Open a cashier shift before taking cash.');
          }
          shiftId = access.currentShift?['id'] as String?;
        }
        final customer = result['customer'] as Map<String, dynamic>?;
        saleId = await RestaurantRepository.payBill(
          holdId: widget.billId,
          paymentType: method['name']?.toString() ?? 'Payment',
          isCashDrawer: isCash,
          shiftId: shiftId,
          amountTendered: _asDouble(result['amountTendered']) ?? total,
          changeGiven: _asDouble(result['changeGiven']) ?? 0,
          customerId: customer?['id'] as String?,
          customerName: customer?['name'] as String?,
          paymentProvider: provider == PaymentMethodRepository.providerOther
              ? null
              : provider,
          paymentStatus: 'paid',
          paymentMetadata: _checkoutMetadata(result),
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment complete. The table is now available.'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop(saleId);
    } catch (error) {
      await _refundReservations(result);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(
              error,
              fallback: 'Payment could not be completed.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<String> _completeMpesa(
    Map<String, dynamic> bill,
    Map<String, dynamic> checkout,
  ) async {
    final total = (bill['total'] as num? ?? 0).toDouble();
    final phone = checkout['phoneNumber']?.toString().trim() ?? '';
    if (phone.isEmpty) throw Exception('M-Pesa phone number is required.');
    final started = await PosPaymentService.startMpesaCheckout(
      amount: total,
      phoneNumber: phone,
      metadata: {
        'cashierId': SessionService.currentUserId,
        'cashierName': SessionService.currentUserName,
        'source': 'restaurant',
        'restaurantBillId': widget.billId,
      },
    );
    if (!mounted) throw Exception('Payment screen was closed.');
    final payment = await _waitForMpesa(started.id);
    if (payment == null || !payment.isPaid) {
      throw Exception(
        payment?.isFailed == true
            ? 'M-Pesa payment failed or was cancelled.'
            : 'M-Pesa payment is still pending.',
      );
    }
    if (!mounted) throw Exception('Payment screen was closed.');
    final confirmed = await showMpesaPaymentConfirmationDialog(
      context,
      payment: payment,
      expectedTotal: total,
      title: 'Confirm table payment',
      confirmLabel: 'Complete payment',
    );
    if (!confirmed) throw Exception('Payment confirmation was cancelled.');
    final customer = checkout['customer'] as Map<String, dynamic>?;
    final saleId = await RestaurantRepository.payBill(
      holdId: widget.billId,
      paymentType: 'M-Pesa',
      isCashDrawer: false,
      customerId: customer?['id'] as String?,
      customerName: customer?['name'] as String?,
      paymentProvider: 'mpesa',
      paymentReference:
          payment.receiptNumber ?? payment.externalReference ?? payment.id,
      paymentStatus: 'paid',
      paymentMetadata: {
        ..._checkoutMetadata(checkout),
        ...payment.metadata,
        'posPaymentId': payment.id,
        'providerSaleLinkStatus': 'pending_reconcile',
      },
    );
    await _linkMpesa(payment: payment, saleId: saleId);
    return saleId;
  }

  Future<PosPayment?> _waitForMpesa(String paymentId) async {
    PosPayment? latest;
    if (!mounted) return null;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 18),
              Expanded(child: Text('Waiting for M-Pesa confirmation…')),
            ],
          ),
        ),
      ),
    );
    try {
      for (var attempt = 0; attempt < 30; attempt += 1) {
        await Future<void>.delayed(const Duration(seconds: 3));
        latest = await PosPaymentService.fetchPayment(paymentId);
        if (latest.isPaid || latest.isFailed) return latest;
      }
      return latest;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _linkMpesa({
    required PosPayment payment,
    required String saleId,
  }) async {
    try {
      await PosPaymentService.linkSale(paymentId: payment.id, saleId: saleId);
      await SaleRepository.updatePaymentLinkStatus(
        saleId: saleId,
        status: 'linked',
      );
    } catch (error) {
      await SaleRepository.updatePaymentLinkStatus(
        saleId: saleId,
        status: 'pending_reconcile',
        error: AppErrorMessage.from(error, fallback: 'Payment link failed'),
      );
    }
  }

  Map<String, dynamic> _checkoutMetadata(Map<String, dynamic> checkout) {
    return {
      if ((checkout['loyaltyLedgerId']?.toString() ?? '').isNotEmpty)
        'loyaltyLedgerId': checkout['loyaltyLedgerId'],
      if ((checkout['loyaltyPoints'] as num? ?? 0) > 0)
        'loyaltyPointsRedeemed': checkout['loyaltyPoints'],
      if ((checkout['giftCardId']?.toString() ?? '').isNotEmpty)
        'giftCardId': checkout['giftCardId'],
      if ((checkout['giftCardCode']?.toString() ?? '').isNotEmpty)
        'giftCardCode': checkout['giftCardCode'],
      if ((checkout['giftCardAmount'] as num? ?? 0) > 0)
        'giftCardAmount': checkout['giftCardAmount'],
      if (checkout['giftCardBalanceAfter'] != null)
        'giftCardBalanceAfter': checkout['giftCardBalanceAfter'],
    };
  }

  Future<void> _refundReservations(Map<String, dynamic> checkout) async {
    final customer = checkout['customer'] as Map<String, dynamic>?;
    final ledgerId = checkout['loyaltyLedgerId']?.toString() ?? '';
    final points = (checkout['loyaltyPoints'] as num?)?.toInt() ?? 0;
    if (ledgerId.isNotEmpty && points > 0 && customer?['id'] != null) {
      try {
        await LoyaltyRepository.refundRedemption(
          ledgerId: ledgerId,
          customerId: customer!['id'] as String,
          points: points,
        );
      } catch (_) {}
    }
    final giftCardId = checkout['giftCardId']?.toString() ?? '';
    final giftAmount = (checkout['giftCardAmount'] as num?)?.toDouble() ?? 0;
    if (giftCardId.isNotEmpty && giftAmount > 0) {
      try {
        await GiftCardRepository.refundRedemption(
          id: giftCardId,
          amount: giftAmount,
        );
      } catch (_) {}
    }
  }
}

class _BillItemsPanel extends StatelessWidget {
  final Map<String, dynamic> bill;

  const _BillItemsPanel({required this.bill});

  @override
  Widget build(BuildContext context) {
    final items = (bill['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return StitchCard(
      color: context.appSurface,
      radius: AppRadius.lg,
      borderColor: context.appBorder,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill['name']?.toString() ?? 'Table bill',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${items.length} item${items.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: context.appTextSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.appBorder),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(color: context.appBorder),
              itemBuilder: (context, index) {
                final item = items[index];
                final quantity = (item['quantity'] as num? ?? 0).toDouble();
                final price = (item['unit_price'] as num? ?? 0).toDouble();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.appSurfaceHighlight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _quantity(quantity),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          item['product_name']?.toString() ?? 'Menu item',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _money(quantity * price),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
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

class _PaymentSummaryPanel extends StatelessWidget {
  final Map<String, dynamic> bill;
  final bool busy;
  final VoidCallback onPay;
  final bool compact;

  const _PaymentSummaryPanel({
    required this.bill,
    required this.busy,
    required this.onPay,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      color: context.appSurface,
      radius: AppRadius.lg,
      borderColor: context.appBorder,
      padding: EdgeInsets.all(compact ? 16 : 20),
      child: Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact) ...[
            const Text(
              'Payment summary',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Completing the final bill automatically releases the table.',
              style: TextStyle(
                color: context.appTextSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const Spacer(),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  'Amount due',
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
                    _money(bill['total']),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : onPay,
            icon: busy
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.payments_rounded, size: 19),
            label: Text(busy ? 'Completing payment…' : 'Choose payment'),
          ),
        ],
      ),
    );
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String _quantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

String _money(Object? value) {
  final amount = value is num ? value.toDouble() : 0.0;
  return '${ShopSettings.currency}${amount.toStringAsFixed(2)}';
}
