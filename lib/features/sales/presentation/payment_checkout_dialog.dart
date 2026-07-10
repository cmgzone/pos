import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/pos_payment_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/error_messages.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/presentation/customer_account_screen.dart';
import '../../loyalty/data/loyalty_repository.dart';
import '../../gift_cards/data/gift_card_repository.dart';
import '../../sales/data/cart_provider.dart';
import '../../settings/data/payment_method_provider.dart';
import '../../settings/data/payment_method_repository.dart';
import 'barcode_scanner.dart';

class PaymentCheckoutDialog extends ConsumerStatefulWidget {
  final double total;

  const PaymentCheckoutDialog({super.key, required this.total});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required double total,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PaymentCheckoutDialog(total: total),
    );
  }

  @override
  ConsumerState<PaymentCheckoutDialog> createState() =>
      _PaymentCheckoutDialogState();
}

Future<bool> showMpesaPaymentConfirmationDialog(
  BuildContext context, {
  required PosPayment payment,
  required double expectedTotal,
  String title = 'Confirm M-Pesa Payment',
  String confirmLabel = 'Confirm Sale',
}) async {
  final payerName = _mpesaPayerName(payment);
  final phoneNumber = _mpesaPhoneNumber(payment);
  final reference = _mpesaReference(payment);
  final billRef = _mpesaMetadataText(payment, const [
    'billRefNumber',
    'BillRefNumber',
    'AccountReference',
  ]);
  final paidAmount = _mpesaPaidAmount(payment, expectedTotal);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      final isCompact = media.size.width < 560;
      return AlertDialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 40,
          vertical: isCompact ? 12 : 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.verified_outlined, color: AppColors.success),
            SizedBox(width: 12),
            Expanded(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.68),
          child: SizedBox(
            width: isCompact ? media.size.width - 56 : 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          payerName ?? 'Name not supplied by M-Pesa',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isCompact ? 20 : 24,
                            fontWeight: FontWeight.w900,
                            color: payerName == null
                                ? Theme.of(ctx).colorScheme.onSurfaceVariant
                                : AppColors.success,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          payerName == null
                              ? 'Confirm using phone, amount, and M-Pesa code.'
                              : 'Confirm this is the customer paying.',
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 14),
                  _MpesaPaymentDetailRow(
                    icon: Icons.payments_outlined,
                    label: 'Paid Amount',
                    value:
                        '${ShopSettings.currency}${paidAmount.toStringAsFixed(2)}',
                  ),
                  _MpesaPaymentDetailRow(
                    icon: Icons.receipt_long_outlined,
                    label: 'M-Pesa Code',
                    value: reference,
                  ),
                  if (phoneNumber != null)
                    _MpesaPaymentDetailRow(
                      icon: Icons.phone_android_outlined,
                      label: 'Phone',
                      value: phoneNumber,
                    ),
                  if (billRef != null)
                    _MpesaPaymentDetailRow(
                      icon: Icons.tag_outlined,
                      label: 'Account',
                      value: billRef,
                    ),
                  if ((paidAmount - expectedTotal).abs() > 0.01) ...[
                    SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Sale total is ${ShopSettings.currency}${expectedTotal.toStringAsFixed(2)}. Check this amount before confirming.',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Not This Payment'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: Icon(Icons.check_circle_outline),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            label: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result == true;
}

String? _mpesaPayerName(PosPayment payment) {
  final explicit = _mpesaMetadataText(payment, const [
    'customerName',
    'CustomerName',
    'payerName',
    'PayerName',
  ]);
  if (explicit != null) return explicit;

  final raw = _metadataMap(payment.metadata['rawPayload']);
  final nested = _metadataMap(payment.metadata['metadata']);
  final first = _firstNonEmpty([
    _mapText(raw, 'FirstName'),
    _mapText(nested, 'FirstName'),
  ]);
  final middle = _firstNonEmpty([
    _mapText(raw, 'MiddleName'),
    _mapText(nested, 'MiddleName'),
  ]);
  final last = _firstNonEmpty([
    _mapText(raw, 'LastName'),
    _mapText(nested, 'LastName'),
  ]);
  final combined = [
    first,
    middle,
    last,
  ].where((part) => part != null && part.trim().isNotEmpty).join(' ');
  return combined.trim().isEmpty ? null : combined.trim();
}

String? _mpesaPhoneNumber(PosPayment payment) {
  return _firstNonEmpty([
    payment.phoneNumber,
    _mpesaMetadataText(payment, const [
      'phoneNumber',
      'PhoneNumber',
      'MSISDN',
      'phone_number',
    ]),
  ]);
}

String _mpesaReference(PosPayment payment) {
  return _firstNonEmpty([
        payment.receiptNumber,
        _mpesaMetadataText(payment, const [
          'mpesaReceiptNumber',
          'MpesaReceiptNumber',
          'TransID',
          'TransactionCode',
        ]),
        payment.externalReference,
      ]) ??
      payment.id;
}

double _mpesaPaidAmount(PosPayment payment, double fallback) {
  if (payment.amountMinor > 0) {
    return payment.amountMinor / 100;
  }
  final rawAmount = _mpesaMetadataText(payment, const [
    'amount',
    'Amount',
    'TransAmount',
  ]);
  return double.tryParse(rawAmount ?? '') ?? fallback;
}

String? _mpesaMetadataText(PosPayment payment, List<String> keys) {
  final maps = <Map<dynamic, dynamic>>[
    payment.metadata,
    if (_metadataMap(payment.metadata['metadata']) != null)
      _metadataMap(payment.metadata['metadata'])!,
    if (_metadataMap(payment.metadata['rawPayload']) != null)
      _metadataMap(payment.metadata['rawPayload'])!,
  ];
  for (final map in maps) {
    for (final key in keys) {
      final value = _mapText(map, key);
      if (value != null) return value;
    }
  }
  return null;
}

Map<dynamic, dynamic>? _metadataMap(Object? value) {
  return value is Map ? value : null;
}

String? _mapText(Map<dynamic, dynamic>? map, String key) {
  if (map == null) return null;
  Object? value = map[key];
  if (value == null) {
    for (final entry in map.entries) {
      if (entry.key.toString().toLowerCase() == key.toLowerCase()) {
        value = entry.value;
        break;
      }
    }
  }
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final clean = value?.trim();
    if (clean != null && clean.isNotEmpty) return clean;
  }
  return null;
}

class _PaymentCheckoutDialogState extends ConsumerState<PaymentCheckoutDialog> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _mpesaPhoneController = TextEditingController();
  final _mpesaReferenceController = TextEditingController();
  final _cashReceivedController = TextEditingController();
  late final String _manualMpesaCheckoutCode =
      'PK-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}';

  List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic>? _selectedCustomer;
  bool _isLoading = true;
  PosMpesaConfig? _mpesaConfig;
  bool _isLoadingMpesa = true;
  bool _isManualMpesaMatching = false;
  String? _manualMpesaStatus;
  Timer? _manualMpesaPollTimer;
  DateTime _selectedDueDate = DateTime.now().add(const Duration(days: 14));
  Map<String, dynamic>? _selectedMethod;
  String? _cashError;

  // Loyalty redemption state
  late double _discountBefore;
  double _loyaltyDiscount = 0;
  int _loyaltyPoints = 0;
  String? _loyaltyLedgerId;
  String? _loyaltyCustomerId;
  bool _loyaltyCompleted = false;
  bool _loyaltyRefunded = false;
  int? _customerPoints;
  Map<String, dynamic>? _loyaltyPreview;
  bool _isLoadingPoints = false;

  @override
  void initState() {
    super.initState();
    _cashReceivedController.text = widget.total.toStringAsFixed(2);
    _discountBefore = ref.read(discountProvider);
    _loadCustomers();
    _loadMpesaConfig();
  }

  double get _effectiveTotal =>
      (widget.total - _loyaltyDiscount).clamp(0, widget.total);

  Future<void> _loadCustomerPoints() async {
    final customer = _selectedCustomer;
    if (customer == null) {
      setState(() {
        _customerPoints = null;
        _loyaltyPreview = null;
      });
      return;
    }
    setState(() => _isLoadingPoints = true);
    try {
      final preview = await LoyaltyRepository.getRedemptionPreview(
        customer['id'] as String,
      );
      if (!mounted) return;
      setState(() {
        _customerPoints = preview['available'] as int? ?? 0;
        _loyaltyPreview = preview;
        _isLoadingPoints = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingPoints = false);
    }
  }

  void _selectCustomer(Map<String, dynamic> customer) {
    // Reset any pending loyalty redemption when the customer changes.
    _clearLoyaltyRedemption();
    setState(() => _selectedCustomer = customer);
    final phone = customer['phone'] as String?;
    if (_mpesaPhoneController.text.trim().isEmpty &&
        phone != null &&
        phone.trim().isNotEmpty) {
      _mpesaPhoneController.text = phone.trim();
    }
    _loadCustomerPoints();
  }

  Map<String, dynamic> get _loyaltyResult {
    if (_loyaltyLedgerId == null) return const <String, dynamic>{};
    _loyaltyCompleted = true;
    return {
      'loyaltyLedgerId': _loyaltyLedgerId,
      'loyaltyPoints': _loyaltyPoints,
    };
  }

  /// Reverses a redemption if the checkout was cancelled before the sale was
  /// completed. Safe to call multiple times; only runs once per redemption.
  Future<void> _refundPendingLoyalty() async {
    final ledgerId = _loyaltyLedgerId;
    final customerId = _loyaltyCustomerId;
    final points = _loyaltyPoints;
    if (ledgerId == null ||
        customerId == null ||
        points <= 0 ||
        _loyaltyRefunded ||
        _loyaltyCompleted) {
      return;
    }
    _loyaltyRefunded = true;
    try {
      await LoyaltyRepository.refundRedemption(
        ledgerId: ledgerId,
        customerId: customerId,
        points: points,
      );
    } catch (_) {
      // Best-effort: the unlinked ledger entry remains and the customer keeps
      // their points until a later reconcile; nothing else to do here.
    }
  }

  void _clearLoyaltyRedemption() {
    final prevLedgerId = _loyaltyLedgerId;
    final prevCustomerId = _loyaltyCustomerId;
    final prevPoints = _loyaltyPoints;
    final hadDiscount = _loyaltyDiscount > 0;

    _loyaltyDiscount = 0;
    _loyaltyPoints = 0;
    _loyaltyLedgerId = null;
    _loyaltyCustomerId = null;

    if (hadDiscount) {
      ref.read(discountProvider.notifier).state = _discountBefore;
    }

    // If a redemption was previously created for another customer, reverse it
    // so points are never left deducted without a completed sale.
    if (prevLedgerId != null &&
        prevCustomerId != null &&
        prevPoints > 0 &&
        !_loyaltyCompleted &&
        !_loyaltyRefunded) {
      unawaited(
        LoyaltyRepository.refundRedemption(
          ledgerId: prevLedgerId,
          customerId: prevCustomerId,
          points: prevPoints,
        ).catchError((_) {}),
      );
    }
  }

  Future<void> _openRedeemDialog() async {
    final customer = _selectedCustomer;
    final preview = _loyaltyPreview;
    if (customer == null || preview == null) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _RedeemPointsDialog(
        available: preview['available'] as int? ?? 0,
        minRedemption: preview['minRedemption'] as int? ?? 0,
        factor: (preview['factor'] as num?)?.toDouble() ?? 1,
      ),
    );
    if (!mounted || result == null) return;

    final points = result['points'] as int;
    if (points <= 0) return;

    setState(() => _isLoadingPoints = true);
    try {
      final redemption = await LoyaltyRepository.redeemPoints(
        customerId: customer['id'] as String,
        points: points,
      );
      if (!mounted) return;
      final discount = (redemption['discount'] as num?)?.toDouble() ?? 0;
      final ledgerId = redemption['ledgerId'] as String;
      setState(() {
        _loyaltyPoints = points;
        _loyaltyDiscount = discount;
        _loyaltyLedgerId = ledgerId;
        _loyaltyCustomerId = customer['id'] as String?;
        _customerPoints = (_customerPoints ?? 0) - points;
        _isLoadingPoints = false;
      });
      // Reflect the discount on the cart total immediately.
      ref.read(discountProvider.notifier).state = _discountBefore + discount;
      if (_isCashMethod(_selectedMethod)) {
        _cashReceivedController.text = _effectiveTotal.toStringAsFixed(2);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingPoints = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(e, fallback: 'Could not redeem points.'),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  void dispose() {
    _refundPendingLoyalty();
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _mpesaPhoneController.dispose();
    _mpesaReferenceController.dispose();
    _cashReceivedController.dispose();
    _manualMpesaPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMpesaConfig() async {
    try {
      final config = await PosPaymentService.fetchMpesaConfig();
      if (!mounted) return;
      setState(() {
        _mpesaConfig = config;
        _isLoadingMpesa = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMpesa = false);
    }
  }

  Future<void> _loadCustomers([String query = '']) async {
    setState(() => _isLoading = true);
    final customers = await CustomerRepository.search(query);
    if (!mounted) return;

    Map<String, dynamic>? selected = _selectedCustomer;
    if (selected != null) {
      final selectedId = selected['id'];
      final refreshed = customers
          .where((customer) => customer['id'] == selectedId)
          .toList();
      if (refreshed.isNotEmpty) {
        selected = refreshed.first;
      }
    }

    setState(() {
      _customers = customers;
      _selectedCustomer = selected;
      _isLoading = false;
    });
    if (selected != null) {
      _loadCustomerPoints();
    }
  }

  Future<void> _openCreateAccountScreen() async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const CustomerAccountScreen()),
    );

    if (created == null || !mounted) return;

    await _loadCustomers(_searchController.text);
    if (!mounted) return;

    _selectCustomer(created);
    setState(() {
      _nameController.clear();
      _phoneController.clear();
      _emailController.clear();
    });
  }

  void _setDueInDays(int days) {
    final now = DateTime.now();
    setState(() {
      _selectedDueDate = DateTime(now.year, now.month, now.day + days);
    });
  }

  Future<void> _pickCustomDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;

    setState(() {
      _selectedDueDate = DateTime(picked.year, picked.month, picked.day);
    });
  }

  DateTime get _today =>
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  bool _matchesPreset(int days) =>
      _selectedDueDate.difference(_today).inDays == days;

  String _dueDateLabel(DateTime date) =>
      '${date.month}/${date.day}/${date.year}';

  String _dueDateStorage(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  void _handleKopeshaCheckout() {
    if (_selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a customer for Kopesha'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    Navigator.pop(context, {
      'type': 'kopesha',
      'customer': _selectedCustomer,
      'dueDate': _dueDateStorage(_selectedDueDate),
      ..._loyaltyResult,
    });
  }

  void _handleOtherPaymentCheckout(Map<String, dynamic> paymentMethod) {
    final isCashDrawer = _isCashMethod(paymentMethod);
    double? amountTendered;
    double? changeGiven;
    if (isCashDrawer) {
      amountTendered =
          double.tryParse(_cashReceivedController.text.trim()) ?? 0.0;
      if (amountTendered + 0.001 < _effectiveTotal) {
        setState(() => _cashError = 'Cash received must cover the sale total');
        return;
      }
      changeGiven = amountTendered - _effectiveTotal;
    }
    Navigator.pop(context, {
      'type': 'other',
      'paymentMethod': paymentMethod,
      'customer': _selectedCustomer,
      'amountTendered': amountTendered,
      'changeGiven': changeGiven,
      ..._loyaltyResult,
    });
  }

  bool _isCashMethod(Map<String, dynamic>? method) {
    if (method == null) return false;
    return PaymentMethodRepository.providerKeyFor(method) ==
        PaymentMethodRepository.providerCash;
  }

  Future<void> _handleGiftCardCheckout() async {
    final codeController = TextEditingController();
    final amountDue = _effectiveTotal;
    final amountController = TextEditingController(
      text: amountDue.toStringAsFixed(2),
    );
    final formKey = GlobalKey<FormState>();
    Map<String, dynamic>? card;
    double balance = 0;
    Future<void> lookupGiftCard(String code, StateSetter setDialogState) async {
      final found = await GiftCardRepository.getByCode(code);
      if (!mounted) return;
      setDialogState(() {
        card = found;
        balance = (found?['balance'] as num? ?? 0).toDouble();
      });
    }

    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Redeem Gift Card'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: codeController,
                  decoration: InputDecoration(
                    labelText: 'Gift card code',
                    hintText: 'e.g. GC-1001',
                    suffixIcon: IconButton(
                      tooltip: 'Scan gift card',
                      icon: const Icon(Icons.qr_code_scanner_outlined),
                      onPressed: () async {
                        final code = await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (_) => const BarcodeScannerScreen(
                              allowQr: true,
                              title: 'Scan Gift Card',
                            ),
                          ),
                        );
                        if (code == null || code.trim().isEmpty) return;
                        codeController.text = code.trim();
                        await lookupGiftCard(code, setDialogState);
                      },
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                  onChanged: (value) {
                    unawaited(lookupGiftCard(value, setDialogState));
                  },
                ),
                const SizedBox(height: 12),
                if (card != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Available balance: ${GiftCardRepository.formatBalance(balance)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Gift card must cover the full amount due: ${GiftCardRepository.formatBalance(amountDue)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: 'Amount to redeem',
                    prefixText: ShopSettings.currency,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    final value = double.tryParse(v ?? '');
                    if (value == null || value <= 0) {
                      return 'Enter an amount greater than zero';
                    }
                    if (card == null) return 'Enter a valid card code';
                    if (value > balance + 0.001) {
                      return 'Exceeds card balance';
                    }
                    if (value > amountDue + 0.001) {
                      return 'Exceeds amount due';
                    }
                    if (value < amountDue - 0.001) {
                      return 'Gift card must cover the full amount due';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final amount = double.parse(amountController.text.trim());
                  final remaining = balance - amount;
                  Navigator.of(ctx).pop({
                    'cardId': card!['id'],
                    'code': card!['code'],
                    'amount': amount,
                    'balanceBefore': balance,
                    'balanceAfter': remaining < 0 ? 0.0 : remaining,
                  });
                }
              },
              child: const Text('Redeem'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;
    try {
      final cardId = result['cardId'] as String;
      final amount = (result['amount'] as num).toDouble();
      await GiftCardRepository.redeem(id: cardId, amount: amount);
      final updatedCard = await GiftCardRepository.getById(cardId);
      final balanceAfter =
          (updatedCard?['balance'] as num?)?.toDouble() ??
          (result['balanceAfter'] as num?)?.toDouble();
      if (!mounted) return;
      Navigator.pop(context, {
        'type': 'other',
        'paymentMethod': _selectedMethod,
        'customer': _selectedCustomer,
        'giftCardId': cardId,
        'giftCardCode': result['code'],
        'giftCardAmount': amount,
        'giftCardBalanceAfter': balanceAfter,
        ..._loyaltyResult,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(e, fallback: 'Gift card redemption failed.'),
          ),
        ),
      );
    }
  }

  bool _isKopeshaMethod(Map<String, dynamic>? method) {
    if (method == null) return false;
    return PaymentMethodRepository.providerKeyFor(method) ==
        PaymentMethodRepository.providerKopesha;
  }

  bool _isMpesaMethod(Map<String, dynamic>? method) {
    if (method == null) return false;
    return PaymentMethodRepository.providerKeyFor(method) ==
        PaymentMethodRepository.providerMpesa;
  }

  bool _isGiftCardMethod(Map<String, dynamic>? method) {
    if (method == null) return false;
    return PaymentMethodRepository.providerKeyFor(method) ==
        PaymentMethodRepository.providerGiftCard;
  }

  ({double tendered, double change, bool hasEnoughCash}) _cashSummary() {
    final tendered =
        double.tryParse(_cashReceivedController.text.trim()) ?? 0.0;
    final hasEnough = tendered + 0.001 >= _effectiveTotal;
    final change = hasEnough ? tendered - _effectiveTotal : 0.0;
    return (tendered: tendered, change: change, hasEnoughCash: hasEnough);
  }

  void _handleMpesaCheckout() {
    final config = _mpesaConfig;
    if (config?.active != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(config?.message ?? 'M-Pesa is not active.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    final phone = _mpesaPhoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter the customer M-Pesa phone number'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    Navigator.pop(context, {
      'type': 'mpesa',
      'phoneNumber': phone,
      'customer': _selectedCustomer,
      ..._loyaltyResult,
    });
  }

  void _startManualMpesaPolling() {
    final config = _mpesaConfig;
    if (config?.active != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(config?.message ?? 'M-Pesa is not active.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    _manualMpesaPollTimer?.cancel();
    setState(() {
      _manualMpesaStatus =
          'Waiting for payment to ${config!.merchantShortcode ?? 'your M-Pesa account'}...';
    });
    _matchManualMpesa(silent: true);
    _manualMpesaPollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _matchManualMpesa(silent: true),
    );
  }

  Future<void> _matchManualMpesa({bool silent = false}) async {
    if (_isManualMpesaMatching) return;
    final referenceCode = _mpesaReferenceController.text.trim();
    final phoneNumber = _mpesaPhoneController.text.trim();
    setState(() {
      _isManualMpesaMatching = true;
      if (!silent) {
        _manualMpesaStatus = 'Checking M-Pesa payment...';
      }
    });

    try {
      final previewPayment = await PosPaymentService.matchManualMpesa(
        referenceCode: referenceCode.isEmpty ? null : referenceCode,
        phoneNumber: phoneNumber.isEmpty ? null : phoneNumber,
        amount: widget.total,
        checkoutCode: _manualMpesaCheckoutCode,
        previewOnly: true,
      );
      if (!mounted) return;

      if (previewPayment != null) {
        _manualMpesaPollTimer?.cancel();
        setState(() {
          _manualMpesaStatus =
              'M-Pesa payment found. Review the payer details.';
        });
        final confirmed = await showMpesaPaymentConfirmationDialog(
          context,
          payment: previewPayment,
          expectedTotal: widget.total,
          title: 'Confirm Manual M-Pesa',
          confirmLabel: 'Confirm Sale',
        );
        if (!mounted) return;
        if (!confirmed) {
          setState(() {
            _manualMpesaStatus =
                'Matched M-Pesa payment was not accepted. Check the code or wait for another payment.';
          });
          return;
        }

        setState(() {
          _manualMpesaStatus = 'Confirming M-Pesa payment...';
        });
        final payment = await PosPaymentService.matchManualMpesa(
          referenceCode: previewPayment.receiptNumber ?? referenceCode,
          phoneNumber: phoneNumber.isEmpty ? null : phoneNumber,
          amount: widget.total,
          checkoutCode: _manualMpesaCheckoutCode,
        );
        if (!mounted) return;
        if (payment == null || !payment.isPaid) {
          setState(() {
            _manualMpesaStatus =
                'That M-Pesa payment could not be confirmed. Try checking again.';
          });
          return;
        }
        Navigator.pop(context, {
          'type': 'mpesa_manual',
          'payment': payment,
          'checkoutCode': _manualMpesaCheckoutCode,
          'customer': _selectedCustomer,
          ..._loyaltyResult,
        });
        return;
      }

      setState(() {
        _manualMpesaStatus = referenceCode.isEmpty
            ? 'No payment found yet. Keep this open while the customer pays.'
            : 'That M-Pesa code was not found for this sale yet.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _manualMpesaStatus = AppErrorMessage.withContext(
          error,
          prefix: 'Manual M-Pesa check failed.',
          fallback: AppErrorMessage.paymentFailed,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isManualMpesaMatching = false);
      }
    }
  }

  IconData _getPaymentIcon(Map<String, dynamic> method) {
    return switch (PaymentMethodRepository.providerKeyFor(method)) {
      PaymentMethodRepository.providerKopesha =>
        Icons.account_balance_wallet_outlined,
      PaymentMethodRepository.providerCash => Icons.payments_outlined,
      PaymentMethodRepository.providerMpesa => Icons.phone_android_outlined,
      PaymentMethodRepository.providerCard => Icons.credit_card_outlined,
      PaymentMethodRepository.providerBankTransfer =>
        Icons.account_balance_outlined,
      PaymentMethodRepository.providerGiftCard => Icons.card_giftcard_outlined,
      _ => Icons.payment_outlined,
    };
  }

  Color _getPaymentColor(Map<String, dynamic> method) {
    return switch (PaymentMethodRepository.providerKeyFor(method)) {
      PaymentMethodRepository.providerKopesha => AppColors.warning,
      PaymentMethodRepository.providerCash => AppColors.success,
      PaymentMethodRepository.providerMpesa => Theme.of(
        context,
      ).colorScheme.secondary,
      PaymentMethodRepository.providerCard => AppColors.primaryLight,
      PaymentMethodRepository.providerGiftCard => AppColors.fuchsia,
      _ => AppColors.primary,
    };
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isCompact = media.size.width < 560;
    final maxContentHeight = media.size.height * (isCompact ? 0.68 : 0.7);
    final currentBalance =
        (_selectedCustomer?['balance'] as num?)?.toDouble() ?? 0;
    final paymentMethodsAsync = ref.watch(activePaymentMethodsProvider);

    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 40,
        vertical: isCompact ? 12 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: EdgeInsets.fromLTRB(
        isCompact ? 16 : 24,
        isCompact ? 16 : 24,
        isCompact ? 16 : 24,
        0,
      ),
      contentPadding: EdgeInsets.all(isCompact ? 16 : 24),
      actionsPadding: EdgeInsets.fromLTRB(
        isCompact ? 16 : 24,
        0,
        isCompact ? 16 : 24,
        isCompact ? 16 : 24,
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      title: Row(
        children: [
          Container(
            width: isCompact ? 40 : 44,
            height: isCompact ? 40 : 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.payments_outlined, color: AppColors.primaryLight),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Payment Method',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: isCompact ? 18 : null),
                ),
                SizedBox(height: 4),
                Text(
                  'Choose how the customer will pay',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxContentHeight),
        child: SizedBox(
          width: isCompact ? media.size.width - 56 : 600,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shopping_cart_outlined,
                        color: AppColors.primaryLight,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _loyaltyDiscount > 0
                                  ? 'Sale Total (after loyalty)'
                                  : 'Sale Total',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '${ShopSettings.currency}${_effectiveTotal.toStringAsFixed(2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isCompact ? 20 : 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_loyaltyDiscount > 0) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(
                                    alpha: 0.14,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Loyalty -${ShopSettings.currency}${_loyaltyDiscount.toStringAsFixed(2)} ($_loyaltyPoints pts)',
                                  style: TextStyle(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  'Payment Methods',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                SizedBox(height: 12),
                if (_isLoadingMpesa)
                  Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                paymentMethodsAsync.when(
                  data: (methods) {
                    if (methods.isEmpty) {
                      return Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No active payment methods. Please configure payment methods in Settings.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }

                    // Initialize default selection to Cash or first method
                    _selectedMethod ??= methods.firstWhere(
                      (m) => _isCashMethod(m),
                      orElse: () => methods.first,
                    );

                    final isKopeshaSelected = _isKopeshaMethod(_selectedMethod);
                    final isMpesaSelected = _isMpesaMethod(_selectedMethod);
                    final isCashSelected = _isCashMethod(_selectedMethod);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GridView.count(
                          crossAxisCount: isCompact ? 1 : 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: isCompact ? 4.7 : 3.4,
                          children: methods.map((method) {
                            final isSelected =
                                _selectedMethod?['id'] == method['id'];
                            final icon = _getPaymentIcon(method);
                            final color = _getPaymentColor(method);
                            return _PaymentMethodButton(
                              name: method['name'],
                              icon: icon,
                              color: color,
                              isSelected: isSelected,
                              onTap: () {
                                setState(() {
                                  _selectedMethod = method;
                                  _cashError = null;
                                  if (!_isMpesaMethod(method)) {
                                    _manualMpesaPollTimer?.cancel();
                                  }
                                  if (_isCashMethod(method) &&
                                      _cashReceivedController.text
                                          .trim()
                                          .isEmpty) {
                                    _cashReceivedController.text = widget.total
                                        .toStringAsFixed(2);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        SizedBox(height: 16),

                        // M-Pesa dynamic phone field
                        if (isMpesaSelected) ...[
                          if (_mpesaConfig?.active == true)
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .secondary
                                          .withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _mpesaPhoneController,
                                    keyboardType: TextInputType.phone,
                                    decoration: InputDecoration(
                                      labelText:
                                          '${_mpesaConfig!.providerLabel} phone',
                                      prefixIcon: Icon(
                                        Icons.phone_android_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: 12),
                                _ManualMpesaSection(
                                  shortcode: _mpesaConfig!.merchantShortcode,
                                  checkoutCode: _manualMpesaCheckoutCode,
                                  total: widget.total,
                                  referenceController:
                                      _mpesaReferenceController,
                                  status: _manualMpesaStatus,
                                  isChecking: _isManualMpesaMatching,
                                  onWait: _startManualMpesaPolling,
                                  onCheckCode: () =>
                                      _matchManualMpesa(silent: false),
                                ),
                              ],
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.error.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: AppColors.error,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _mpesaConfig?.message ??
                                          'M-Pesa integration is not active.',
                                      style: TextStyle(
                                        color: AppColors.error,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          SizedBox(height: 12),
                        ],

                        // Kopesha dynamic due date picker
                        if (isKopeshaSelected) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppColors.warning.withValues(alpha: 0.2),
                              ),
                            ),
                            child: _KopeshaSection(
                              selectedDueDate: _selectedDueDate,
                              onSetDueInDays: _setDueInDays,
                              onPickCustomDueDate: _pickCustomDueDate,
                              matchesPreset: _matchesPreset,
                              dueDateLabel: _dueDateLabel,
                            ),
                          ),
                          SizedBox(height: 12),
                        ],

                        // Cash tendered / change section
                        if (isCashSelected) ...[
                          _CashChangeSection(
                            total: widget.total,
                            controller: _cashReceivedController,
                            errorText: _cashError,
                            onChanged: (value) {
                              setState(() {
                                _cashError = null;
                              });
                            },
                          ),
                          SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                  loading: () => Center(child: CircularProgressIndicator()),
                  error: (e, st) => Text(
                    AppErrorMessage.from(
                      e,
                      fallback: AppErrorMessage.loadFailed,
                    ),
                  ),
                ),
                SizedBox(height: 20),
                Divider(),
                SizedBox(height: 16),

                // Customer Header
                if (isCompact) ...[
                  Text(
                    _isKopeshaMethod(_selectedMethod)
                        ? 'Customer (Required for Kopesha)'
                        : 'Customer (Optional)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _isKopeshaMethod(_selectedMethod)
                          ? AppColors.warning
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _openCreateAccountScreen,
                      icon: Icon(Icons.person_add_alt_1, size: 18),
                      label: Text('Add Customer'),
                    ),
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isKopeshaMethod(_selectedMethod)
                              ? 'Customer (Required for Kopesha)'
                              : 'Customer (Optional)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: _isKopeshaMethod(_selectedMethod)
                                ? AppColors.warning
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _openCreateAccountScreen,
                        icon: Icon(Icons.person_add_alt_1, size: 18),
                        label: Text('Add Customer'),
                      ),
                    ],
                  ),
                SizedBox(height: 10),

                // If selected: show selected customer card. Else: show search field and search results list.
                if (_selectedCustomer != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: AppColors.success),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selected: ${_selectedCustomer!['name']}',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Current balance: ${ShopSettings.currency}${currentBalance.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              if (_customerPoints != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.loyalty_outlined,
                                      size: 14,
                                      color: AppColors.success,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Loyalty: ${_customerPoints!} pts',
                                      style: TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_customerPoints != null &&
                            _customerPoints! > 0 &&
                            (_loyaltyPreview?['configured'] == true))
                          TextButton(
                            onPressed: _isLoadingPoints
                                ? null
                                : _openRedeemDialog,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Redeem'),
                          ),
                        IconButton(
                          icon: Icon(Icons.close, size: 18),
                          onPressed: () {
                            _clearLoyaltyRedemption();
                            setState(() => _selectedCustomer = null);
                          },
                          tooltip: 'Clear selection',
                        ),
                      ],
                    ),
                  )
                else ...[
                  TextField(
                    controller: _searchController,
                    onChanged: _loadCustomers,
                    decoration: InputDecoration(
                      hintText: 'Search customer by name, phone, or email',
                      prefixIcon: Icon(
                        Icons.search,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _loadCustomers();
                              },
                            ),
                    ),
                  ),
                  SizedBox(height: 14),
                  Container(
                    height: isCompact ? 180 : 220,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    child: _isLoading
                        ? Center(child: CircularProgressIndicator())
                        : _customers.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    size: 32,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.5),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'No customers found',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.all(12),
                            itemCount: _customers.length,
                            separatorBuilder: (_, _) => SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final customer = _customers[index];
                              final isSelected =
                                  customer['id'] == _selectedCustomer?['id'];
                              final balance =
                                  (customer['balance'] as num?)?.toDouble() ??
                                  0;

                              return Material(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: 0.12)
                                    : context.appSurface,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  onTap: () => _selectCustomer(customer),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.primaryLight
                                            : context.appBorder,
                                        width: isSelected ? 1.4 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 36,
                                          height: 36,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.18,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.person,
                                            color: AppColors.primaryLight,
                                            size: 20,
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                customer['name'] as String? ??
                                                    'Unnamed Customer',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                [
                                                      customer['phone']
                                                          as String?,
                                                      customer['email']
                                                          as String?,
                                                    ]
                                                    .where(
                                                      (value) =>
                                                          value != null &&
                                                          value.isNotEmpty,
                                                    )
                                                    .join(' | ')
                                                    .ifEmpty(
                                                      'No contact added',
                                                    ),
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Balance',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                fontSize: 10,
                                              ),
                                            ),
                                            SizedBox(height: 2),
                                            Text(
                                              '${ShopSettings.currency}${balance.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                color: balance > 0
                                                    ? AppColors.warning
                                                    : AppColors.success,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12,
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
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        SizedBox(
          width: isCompact ? double.infinity : null,
          child: TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await _refundPendingLoyalty();
              if (!mounted) return;
              navigator.pop();
            },
            child: Text('Cancel'),
          ),
        ),
        if (_selectedMethod != null) ...[
          Builder(
            builder: (ctx) {
              final isCashMethod = _isCashMethod(_selectedMethod);
              final cash = _cashSummary();
              final canPay = !isCashMethod || cash.hasEnoughCash;
              return SizedBox(
                width: isCompact ? double.infinity : null,
                child: ElevatedButton.icon(
                  onPressed: canPay
                      ? () {
                          if (_isKopeshaMethod(_selectedMethod)) {
                            _handleKopeshaCheckout();
                          } else if (_isMpesaMethod(_selectedMethod)) {
                            _handleMpesaCheckout();
                          } else if (_isGiftCardMethod(_selectedMethod)) {
                            _handleGiftCardCheckout();
                          } else {
                            _handleOtherPaymentCheckout(_selectedMethod!);
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getPaymentColor(_selectedMethod!),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(_getPaymentIcon(_selectedMethod!), size: 18),
                  label: Text(
                    canPay
                        ? 'Pay with ${_selectedMethod!['name']}'
                        : 'Need ${ShopSettings.currency}${(widget.total - cash.tendered).toStringAsFixed(2)} more',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _CashChangeSection extends StatefulWidget {
  final double total;
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const _CashChangeSection({
    required this.total,
    required this.controller,
    this.errorText,
    this.onChanged,
  });

  @override
  State<_CashChangeSection> createState() => _CashChangeSectionState();
}

class _CashChangeSectionState extends State<_CashChangeSection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _CashChangeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
    widget.onChanged?.call(widget.controller.text);
  }

  ({double tendered, double change, bool hasEnoughCash}) _compute() {
    final tendered = double.tryParse(widget.controller.text.trim()) ?? 0.0;
    final hasEnough = tendered + 0.001 >= widget.total;
    final change = hasEnough ? tendered - widget.total : 0.0;
    return (tendered: tendered, change: change, hasEnoughCash: hasEnough);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cash = _compute();
    final accent = cash.hasEnoughCash ? AppColors.success : AppColors.warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceHighlight.withValues(alpha: 0.5)
            : Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.errorText != null
              ? AppColors.error.withValues(alpha: 0.5)
              : (isDark
                        ? AppColors.darkBorder
                        : Theme.of(context).colorScheme.outline)
                    .withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.payments_outlined,
                size: 18,
                color: isDark
                    ? AppColors.darkAccent
                    : Theme.of(context).colorScheme.primary,
              ),
              SizedBox(width: 8),
              Text(
                'Cash Received',
                style: TextStyle(
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          TextField(
            controller: widget.controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: false,
            onChanged: widget.onChanged,
            style: TextStyle(
              color: isDark
                  ? AppColors.darkTextPrimary
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: isDark
                  ? AppColors.darkSurface
                  : Theme.of(context).colorScheme.surface,
              prefixText: ShopSettings.currency,
              hintText: widget.total.toStringAsFixed(2),
              errorText: widget.errorText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark
                      ? AppColors.darkAccent
                      : Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
          SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  cash.hasEnoughCash
                      ? Icons.reply_outlined
                      : Icons.warning_amber_rounded,
                  size: 18,
                  color: accent,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cash.hasEnoughCash
                            ? 'Change to Return'
                            : 'More Cash Needed',
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '${ShopSettings.currency}${(cash.hasEnoughCash ? cash.change : widget.total - cash.tendered).toStringAsFixed(2)}',
                        style: TextStyle(
                          color: accent,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (cash.hasEnoughCash && cash.change > 0) ...[
            SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    widget.controller.text = widget.total.toStringAsFixed(2),
                icon: Icon(Icons.restart_alt, size: 16),
                label: Text('Use Exact Amount'),
                style: TextButton.styleFrom(
                  foregroundColor: isDark
                      ? AppColors.darkTextSecondary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentMethodButton extends StatelessWidget {
  final String name;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodButton({
    required this.name,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : context.appSurfaceHighlight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : context.appBorder,
            width: isSelected ? 2 : 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? color
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              size: 20,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: isSelected
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected) Icon(Icons.check_circle, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}

class _MpesaPaymentDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MpesaPaymentDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                SelectableText(
                  value,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualMpesaSection extends StatelessWidget {
  final String? shortcode;
  final String checkoutCode;
  final double total;
  final TextEditingController referenceController;
  final String? status;
  final bool isChecking;
  final VoidCallback onWait;
  final VoidCallback onCheckCode;

  const _ManualMpesaSection({
    required this.shortcode,
    required this.checkoutCode,
    required this.total,
    required this.referenceController,
    required this.status,
    required this.isChecking,
    required this.onWait,
    required this.onCheckCode,
  });

  @override
  Widget build(BuildContext context) {
    final merchant = shortcode?.trim().isNotEmpty == true
        ? shortcode!.trim()
        : 'your M-Pesa Till or Paybill';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.secondary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  color: Theme.of(context).colorScheme.secondary,
                  size: 19,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'M-Pesa Auto-Match',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            'Amount: ${ShopSettings.currency}${total.toStringAsFixed(2)}',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          SizedBox(height: 4),
          Text(
            'Customer pays $merchant. For Paybill, use account $checkoutCode. For Till, keep this screen open or enter the M-Pesa code.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          SizedBox(height: 12),
          SelectableText(
            checkoutCode,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 12),
          TextField(
            controller: referenceController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'M-Pesa code',
              hintText: 'Example: QJD83K92JS',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: isChecking ? null : onWait,
                icon: isChecking
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.sync_outlined, size: 18),
                label: Text('Wait for payment'),
              ),
              OutlinedButton.icon(
                onPressed: isChecking ? null : onCheckCode,
                icon: Icon(Icons.search_outlined, size: 18),
                label: Text('Check code'),
              ),
            ],
          ),
          if (status != null) ...[
            SizedBox(height: 10),
            Text(
              status!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KopeshaSection extends StatelessWidget {
  final DateTime selectedDueDate;
  final Function(int) onSetDueInDays;
  final VoidCallback onPickCustomDueDate;
  final bool Function(int) matchesPreset;
  final String Function(DateTime) dueDateLabel;

  const _KopeshaSection({
    required this.selectedDueDate,
    required this.onSetDueInDays,
    required this.onPickCustomDueDate,
    required this.matchesPreset,
    required this.dueDateLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Due Date',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _DueDateChip(
              label: '7 Days',
              selected: matchesPreset(7),
              onTap: () => onSetDueInDays(7),
            ),
            _DueDateChip(
              label: '14 Days',
              selected: matchesPreset(14),
              onTap: () => onSetDueInDays(14),
            ),
            _DueDateChip(
              label: '30 Days',
              selected: matchesPreset(30),
              onTap: () => onSetDueInDays(30),
            ),
            OutlinedButton.icon(
              onPressed: onPickCustomDueDate,
              icon: Icon(Icons.event_outlined, size: 18),
              label: Text(dueDateLabel(selectedDueDate)),
            ),
          ],
        ),
      ],
    );
  }
}

class _DueDateChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DueDateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.warning.withValues(alpha: 0.16)
              : context.appSurfaceHighlight,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.warning : context.appBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? AppColors.warning
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _RedeemPointsDialog extends StatefulWidget {
  final int available;
  final int minRedemption;
  final double factor;

  const _RedeemPointsDialog({
    required this.available,
    required this.minRedemption,
    required this.factor,
  });

  @override
  State<_RedeemPointsDialog> createState() => _RedeemPointsDialogState();
}

class _RedeemPointsDialogState extends State<_RedeemPointsDialog> {
  late final TextEditingController _pointsController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.available > widget.minRedemption
        ? widget.available
        : widget.minRedemption;
    _pointsController = TextEditingController(
      text: initial > 0 ? initial.toString() : '',
    );
  }

  @override
  void dispose() {
    _pointsController.dispose();
    super.dispose();
  }

  void _save() {
    final points = int.tryParse(_pointsController.text.trim()) ?? 0;
    if (points <= 0) {
      setState(() => _error = 'Enter a valid number of points.');
      return;
    }
    if (points > widget.available) {
      setState(
        () => _error = 'This customer only has ${widget.available} points.',
      );
      return;
    }
    if (points < widget.minRedemption) {
      setState(
        () => _error =
            'A minimum of ${widget.minRedemption} points is required to redeem.',
      );
      return;
    }
    Navigator.of(context).pop({'points': points});
  }

  @override
  Widget build(BuildContext context) {
    final maxDiscount = widget.available * widget.factor;
    return AlertDialog(
      title: const Text('Redeem Loyalty Points'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.loyalty_outlined,
                    size: 18,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Available: ${widget.available} pts'
                      '${maxDiscount > 0 ? '  (up to ${ShopSettings.currency}${maxDiscount.toStringAsFixed(2)})' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pointsController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
              ),
              decoration: InputDecoration(
                labelText: 'Points to redeem',
                hintText: 'e.g. ${widget.available}',
                prefixIcon: const Icon(Icons.stars_outlined),
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Redeem')),
      ],
    );
  }
}
