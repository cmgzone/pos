import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/error_messages.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/presentation/customer_account_screen.dart';
import '../../settings/data/payment_method_provider.dart';

class CustomerCheckoutDialog extends ConsumerStatefulWidget {
  final double total;

  const CustomerCheckoutDialog({super.key, required this.total});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required double total,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => CustomerCheckoutDialog(total: total),
    );
  }

  @override
  ConsumerState<CustomerCheckoutDialog> createState() =>
      _CustomerCheckoutDialogState();
}

class _CustomerCheckoutDialogState
    extends ConsumerState<CustomerCheckoutDialog> {
  final _searchController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic>? _selectedCustomer;
  bool _isLoading = true;
  bool _showCreateForm = false;
  bool _isCreating = false;
  DateTime _selectedDueDate = DateTime.now().add(const Duration(days: 14));
  Map<String, dynamic>? _selectedPaymentMethod;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
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

  Future<void> _createCustomer() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer name is required for Kopesha'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final customerId = await CustomerRepository.create(
        name: name,
        phone: _phoneController.text,
        email: _emailController.text,
      );
      final created = await CustomerRepository.getById(customerId);
      await _loadCustomers(_searchController.text);
      if (!mounted) return;

      setState(() {
        _selectedCustomer = created;
        _showCreateForm = false;
        _nameController.clear();
        _phoneController.clear();
        _emailController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.withContext(
              e,
              prefix: 'Could not create customer.',
              fallback: AppErrorMessage.saveFailed,
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
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
      _showCreateForm = false;
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

  @override
  Widget build(BuildContext context) {
    final currentBalance =
        (_selectedCustomer?['balance'] as num?)?.toDouble() ?? 0;
    final projectedBalance = currentBalance + widget.total;
    final viewportHeight = MediaQuery.of(context).size.height;
    final contentHeight = math
        .max(320, math.min(520, viewportHeight - 240))
        .toDouble();

    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.all(24),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      title: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              color: AppColors.primaryLight,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kopesha Checkout'),
                SizedBox(height: 4),
                Text(
                  'Assign this credit sale to a customer',
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
      content: SizedBox(
        width: 560,
        height: contentHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
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
                            Icons.payments_outlined,
                            color: AppColors.primaryLight,
                          ),
                          SizedBox(width: 12),
                          Column(
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
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Payment Method',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 10),
                    Consumer(
                      builder: (context, ref, child) {
                        final methodsAsync = ref.watch(
                          activePaymentMethodsProvider,
                        );
                        return methodsAsync.when(
                          data: (methods) {
                            if (methods.isEmpty) {
                              return Text(
                                'No active payment methods.',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              );
                            }
                            if (_selectedPaymentMethod == null &&
                                methods.isNotEmpty) {
                              // Keep a real default selection once methods load.
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() {
                                    _selectedPaymentMethod = methods.first;
                                  });
                                }
                              });
                            }
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: methods.map((m) {
                                final isSelected =
                                    _selectedPaymentMethod?['id'] == m['id'];
                                return _DueDateChip(
                                  label: m['name'],
                                  selected: isSelected,
                                  onTap: () => setState(
                                    () => _selectedPaymentMethod = m,
                                  ),
                                );
                              }).toList(),
                            );
                          },
                          loading: () => const CircularProgressIndicator(),
                          error: (e, st) => Text(
                            AppErrorMessage.from(
                              e,
                              fallback: AppErrorMessage.loadFailed,
                            ),
                          ),
                        );
                      },
                    ),
                    if (_selectedPaymentMethod?['name']?.toLowerCase() ==
                        'kopesha') ...[
                      SizedBox(height: 18),
                      Text(
                        'Kopesha Due Date',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _DueDateChip(
                            label: '7 Days',
                            selected: _matchesPreset(7),
                            onTap: () => _setDueInDays(7),
                          ),
                          _DueDateChip(
                            label: '14 Days',
                            selected: _matchesPreset(14),
                            onTap: () => _setDueInDays(14),
                          ),
                          _DueDateChip(
                            label: '30 Days',
                            selected: _matchesPreset(30),
                            onTap: () => _setDueInDays(30),
                          ),
                          OutlinedButton.icon(
                            onPressed: _pickCustomDueDate,
                            icon: Icon(Icons.event_outlined, size: 18),
                            label: Text(_dueDateLabel(_selectedDueDate)),
                          ),
                        ],
                      ),
                    ],
                    SizedBox(height: 18),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Choose Customer (Optional unless Kopesha)',
                            style: TextStyle(fontWeight: FontWeight.w600),
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
                    if (_showCreateForm) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'Customer Name *',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _phoneController,
                                    decoration: InputDecoration(
                                      labelText: 'Phone',
                                      prefixIcon: Icon(Icons.phone_outlined),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 14),
                                Expanded(
                                  child: TextField(
                                    controller: _emailController,
                                    decoration: InputDecoration(
                                      labelText: 'Email',
                                      prefixIcon: Icon(Icons.email_outlined),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isCreating ? null : _createCustomer,
                                icon: _isCreating
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(Icons.person_add_alt_1, size: 18),
                                label: Text('Create Customer'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                    if (_selectedCustomer != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Selected: ${_selectedCustomer!['name']}',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Balance after this sale: ${ShopSettings.currency}${projectedBalance.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                child: _isLoading
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : _customers.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 40,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                              SizedBox(height: 12),
                              Text('No customers found'),
                              SizedBox(height: 6),
                              Text(
                                'Create one now to record this Kopesha sale.',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.9),
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: _customers.length,
                        separatorBuilder: (_, _) => SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final customer = _customers[index];
                          final isSelected =
                              customer['id'] == _selectedCustomer?['id'];
                          final balance =
                              (customer['balance'] as num?)?.toDouble() ?? 0;

                          return Material(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : context.appSurface,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _selectedCustomer = customer),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(14),
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
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.18,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.person,
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                    SizedBox(width: 12),
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
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            [
                                                  customer['phone'] as String?,
                                                  customer['email'] as String?,
                                                ]
                                                .where(
                                                  (value) =>
                                                      value != null &&
                                                      value.isNotEmpty,
                                                )
                                                .join(' | ')
                                                .ifEmpty('No contact added'),
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
                                    SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Outstanding',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontSize: 11,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          '${ShopSettings.currency}${balance.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: balance > 0
                                                ? AppColors.warning
                                                : AppColors.success,
                                            fontWeight: FontWeight.w700,
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
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            final isKopesha =
                _selectedPaymentMethod?['name']?.toLowerCase() == 'kopesha';
            if (isKopesha && _selectedCustomer == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Customer is required for Kopesha'),
                  backgroundColor: AppColors.warning,
                ),
              );
              return;
            }
            if (_selectedPaymentMethod == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please select a payment method'),
                  backgroundColor: AppColors.warning,
                ),
              );
              return;
            }
            Navigator.pop(context, {
              'customer': _selectedCustomer,
              'dueDate': _dueDateStorage(_selectedDueDate),
              'paymentMethod': _selectedPaymentMethod,
            });
          },
          icon: Icon(Icons.check_circle_outline, size: 18),
          label: Text('Complete Checkout'),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
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
