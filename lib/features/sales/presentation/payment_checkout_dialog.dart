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
import '../../settings/data/payment_method_provider.dart';

class PaymentCheckoutDialog extends ConsumerStatefulWidget {
  final double total;

  const PaymentCheckoutDialog({super.key, required this.total});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required double total,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => PaymentCheckoutDialog(total: total),
    );
  }

  @override
  ConsumerState<PaymentCheckoutDialog> createState() =>
      _PaymentCheckoutDialogState();
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

  @override
  void initState() {
    super.initState();
    _cashReceivedController.text = widget.total.toStringAsFixed(2);
    _loadCustomers();
    _loadMpesaConfig();
  }

  @override
  void dispose() {
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
  }

  Future<void> _openCreateAccountScreen() async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const CustomerAccountScreen()),
    );

    if (created == null || !mounted) return;

    await _loadCustomers(_searchController.text);
    if (!mounted) return;

    setState(() {
      _selectedCustomer = created;
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
    });
  }

  void _handleOtherPaymentCheckout(Map<String, dynamic> paymentMethod) {
    final isCashDrawer = _isCashMethod(paymentMethod);
    double? amountTendered;
    double? changeGiven;
    if (isCashDrawer) {
      amountTendered =
          double.tryParse(_cashReceivedController.text.trim()) ?? 0.0;
      if (amountTendered + 0.001 < widget.total) {
        setState(() => _cashError = 'Cash received must cover the sale total');
        return;
      }
      changeGiven = amountTendered - widget.total;
    }
    Navigator.pop(context, {
      'type': 'other',
      'paymentMethod': paymentMethod,
      'customer': _selectedCustomer,
      'amountTendered': amountTendered,
      'changeGiven': changeGiven,
    });
  }

  bool _isCashMethod(Map<String, dynamic>? method) {
    if (method == null) return false;
    final isDrawer = method['is_cash_drawer'] == 1;
    final name = (method['name'] as String? ?? '').toLowerCase();
    return isDrawer || name.contains('cash');
  }

  ({double tendered, double change, bool hasEnoughCash}) _cashSummary() {
    final tendered =
        double.tryParse(_cashReceivedController.text.trim()) ?? 0.0;
    final hasEnough = tendered + 0.001 >= widget.total;
    final change = hasEnough ? tendered - widget.total : 0.0;
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
      final payment = await PosPaymentService.matchManualMpesa(
        referenceCode: referenceCode.isEmpty ? null : referenceCode,
        phoneNumber: phoneNumber.isEmpty ? null : phoneNumber,
        amount: widget.total,
        checkoutCode: _manualMpesaCheckoutCode,
      );
      if (!mounted) return;

      if (payment != null && payment.isPaid) {
        _manualMpesaPollTimer?.cancel();
        Navigator.pop(context, {
          'type': 'mpesa_manual',
          'payment': payment,
          'checkoutCode': _manualMpesaCheckoutCode,
          'customer': _selectedCustomer,
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
    final name = (method['name'] as String).toLowerCase();
    if (method['is_credit'] == 1 || name.contains('kopesha')) {
      return Icons.account_balance_wallet_outlined;
    }
    if (method['is_cash_drawer'] == 1 || name.contains('cash')) {
      return Icons.payments_outlined;
    }
    if (name.contains('mpesa') || name.contains('m-pesa')) {
      return Icons.phone_android_outlined;
    }
    if (name.contains('card')) {
      return Icons.credit_card_outlined;
    }
    if (name.contains('bank') || name.contains('transfer')) {
      return Icons.account_balance_outlined;
    }
    return Icons.payment_outlined;
  }

  Color _getPaymentColor(Map<String, dynamic> method) {
    final name = (method['name'] as String).toLowerCase();
    if (method['is_credit'] == 1 || name.contains('kopesha')) {
      return AppColors.warning;
    }
    if (method['is_cash_drawer'] == 1 || name.contains('cash')) {
      return AppColors.success;
    }
    if (name.contains('mpesa') || name.contains('m-pesa')) {
      return Theme.of(context).colorScheme.secondary;
    }
    if (name.contains('card')) {
      return AppColors.primaryLight;
    }
    if (name.contains('bank') || name.contains('transfer')) {
      return AppColors.primary;
    }
    return AppColors.primary;
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
                              'Sale Total',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              '${ShopSettings.currency}${widget.total.toStringAsFixed(2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: isCompact ? 20 : 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
                      (m) => m['is_cash_drawer'] == 1,
                      orElse: () => methods.first,
                    );

                    final isKopeshaSelected =
                        _selectedMethod?['is_credit'] == 1;
                    final isMpesaSelected =
                        _selectedMethod != null &&
                        (() {
                          final name = (_selectedMethod!['name'] as String)
                              .toLowerCase();
                          return name.contains('mpesa') ||
                              name.contains('m-pesa');
                        })();
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
                                  final methodName = (method['name'] as String)
                                      .toLowerCase();
                                  if (!methodName.contains('mpesa') &&
                                      !methodName.contains('m-pesa')) {
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
                    _selectedMethod?['is_credit'] == 1
                        ? 'Customer (Required for Kopesha)'
                        : 'Customer (Optional)',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _selectedMethod?['is_credit'] == 1
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
                          _selectedMethod?['is_credit'] == 1
                              ? 'Customer (Required for Kopesha)'
                              : 'Customer (Optional)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: _selectedMethod?['is_credit'] == 1
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
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, size: 18),
                          onPressed: () =>
                              setState(() => _selectedCustomer = null),
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
                                  onTap: () => setState(() {
                                    _selectedCustomer = customer;
                                    final phone = customer['phone'] as String?;
                                    if (_mpesaPhoneController.text
                                            .trim()
                                            .isEmpty &&
                                        phone != null &&
                                        phone.trim().isNotEmpty) {
                                      _mpesaPhoneController.text = phone.trim();
                                    }
                                  }),
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
            onPressed: () => Navigator.pop(context),
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
                          final isKopesha = _selectedMethod!['is_credit'] == 1;
                          final isMpesa = (_selectedMethod!['name'] as String)
                              .toLowerCase();
                          if (isKopesha) {
                            _handleKopeshaCheckout();
                          } else if (isMpesa.contains('mpesa') ||
                              isMpesa.contains('m-pesa')) {
                            _handleMpesaCheckout();
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
