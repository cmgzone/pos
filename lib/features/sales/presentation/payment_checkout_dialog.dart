import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/pos_payment_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
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

  @override
  void initState() {
    super.initState();
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
    Navigator.pop(context, {
      'type': 'other',
      'paymentMethod': paymentMethod,
      'customer': _selectedCustomer,
    });
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
      return AppColors.secondary;
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
      backgroundColor: AppColors.surface,
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
            child: const Icon(
              Icons.payments_outlined,
              color: AppColors.primaryLight,
            ),
          ),
          const SizedBox(width: 14),
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
                const SizedBox(height: 4),
                Text(
                  'Choose how the customer will pay',
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
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
                      const Icon(
                        Icons.shopping_cart_outlined,
                        color: AppColors.primaryLight,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sale Total',
                              style: TextStyle(
                                color: AppColors.textSecondary,
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
                const SizedBox(height: 20),
                const Text(
                  'Payment Methods',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 12),
                if (_isLoadingMpesa)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                paymentMethodsAsync.when(
                  data: (methods) {
                    if (methods.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No active payment methods. Please configure payment methods in Settings.',
                          style: TextStyle(color: AppColors.textSecondary),
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
                                  final methodName = (method['name'] as String)
                                      .toLowerCase();
                                  if (!methodName.contains('mpesa') &&
                                      !methodName.contains('m-pesa')) {
                                    _manualMpesaPollTimer?.cancel();
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        // M-Pesa dynamic phone field
                        if (isMpesaSelected) ...[
                          if (_mpesaConfig?.active == true)
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondary.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: AppColors.secondary.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _mpesaPhoneController,
                                    keyboardType: TextInputType.phone,
                                    decoration: InputDecoration(
                                      labelText:
                                          '${_mpesaConfig!.providerLabel} phone',
                                      prefixIcon: const Icon(
                                        Icons.phone_android_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
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
                                  const Icon(
                                    Icons.error_outline,
                                    color: AppColors.error,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _mpesaConfig?.message ??
                                          'M-Pesa integration is not active.',
                                      style: const TextStyle(
                                        color: AppColors.error,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
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
                          const SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Text(
                    AppErrorMessage.from(
                      e,
                      fallback: AppErrorMessage.loadFailed,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 16),

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
                          : AppColors.textPrimary,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _openCreateAccountScreen,
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: const Text('Add Customer'),
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
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _openCreateAccountScreen,
                        icon: const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('Add Customer'),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),

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
                        const Icon(
                          Icons.check_circle,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selected: ${_selectedCustomer!['name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Current balance: ${ShopSettings.currency}${currentBalance.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
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
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.textSecondary,
                      ),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _loadCustomers();
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    height: isCompact ? 180 : 220,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceHighlight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
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
                                    color: AppColors.textSecondary.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'No customers found',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
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
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
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
                                    : AppColors.surface,
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
                                            : AppColors.border,
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
                                          child: const Icon(
                                            Icons.person,
                                            color: AppColors.primaryLight,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                customer['name'] as String? ??
                                                    'Unnamed Customer',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
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
                                                style: const TextStyle(
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Text(
                                              'Balance',
                                              style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 10,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
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
            child: const Text('Cancel'),
          ),
        ),
        if (_selectedMethod != null)
          SizedBox(
            width: isCompact ? double.infinity : null,
            child: ElevatedButton.icon(
              onPressed: () {
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
              },
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
                'Pay with ${_selectedMethod!['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
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
              : AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 2 : 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? color : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
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
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
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
                  color: AppColors.secondary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: AppColors.secondary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'M-Pesa Auto-Match',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Amount: ${ShopSettings.currency}${total.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'Customer pays $merchant. For Paybill, use account $checkoutCode. For Till, keep this screen open or enter the M-Pesa code.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            checkoutCode,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: referenceController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'M-Pesa code',
              hintText: 'Example: QJD83K92JS',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: isChecking ? null : onWait,
                icon: isChecking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_outlined, size: 18),
                label: const Text('Wait for payment'),
              ),
              OutlinedButton.icon(
                onPressed: isChecking ? null : onCheckCode,
                icon: const Icon(Icons.search_outlined, size: 18),
                label: const Text('Check code'),
              ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: 10),
            Text(
              status!,
              style: const TextStyle(
                color: AppColors.textSecondary,
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
        const Text(
          'Due Date',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
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
              icon: const Icon(Icons.event_outlined, size: 18),
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
              : AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.warning : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.warning : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
