import 'package:flutter/material.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../customers/data/customer_repository.dart';
import '../../customers/presentation/customer_account_screen.dart';

class CustomerCheckoutDialog extends StatefulWidget {
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
  State<CustomerCheckoutDialog> createState() => _CustomerCheckoutDialogState();
}

class _CustomerCheckoutDialogState extends State<CustomerCheckoutDialog> {
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
          content: Text('Could not create customer: $e'),
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
    final dialogHeight = MediaQuery.of(context).size.height * 0.72;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: AppColors.primaryLight,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Kopesha Checkout'),
                const SizedBox(height: 4),
                Text(
                  'Assign this credit sale to a customer',
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
      content: SizedBox(
        width: 560,
        height: dialogHeight > 560 ? 560 : dialogHeight,
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
                    Icons.payments_outlined,
                    color: AppColors.primaryLight,
                  ),
                  const SizedBox(width: 12),
                  Column(
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
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Kopesha Due Date',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
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
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(_dueDateLabel(_selectedDueDate)),
                ),
              ],
            ),
            const SizedBox(height: 18),
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
            Row(
              children: [
                const Text(
                  'Choose Customer',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _openCreateAccountScreen,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Add Customer'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_showCreateForm) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Customer Name *',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isCreating ? null : _createCustomer,
                        icon: _isCreating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.person_add_alt_1, size: 18),
                        label: const Text('Create Customer'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Balance after this sale: ${ShopSettings.currency}${projectedBalance.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: _isLoading
                    ? const Center(
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
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text('No customers found'),
                              const SizedBox(height: 6),
                              Text(
                                'Create one now to record this Kopesha sale.',
                                style: TextStyle(
                                  color: AppColors.textSecondary.withValues(
                                    alpha: 0.9,
                                  ),
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
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final customer = _customers[index];
                          final isSelected =
                              customer['id'] == _selectedCustomer?['id'];
                          final balance =
                              (customer['balance'] as num?)?.toDouble() ?? 0;

                          return Material(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : AppColors.surface,
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
                                        : AppColors.border,
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
                                      child: const Icon(
                                        Icons.person,
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
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
                                            ),
                                          ),
                                          const SizedBox(height: 4),
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
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        const Text(
                                          'Outstanding',
                                          style: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
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
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _selectedCustomer == null
              ? null
              : () => Navigator.pop(context, {
                  'customer': _selectedCustomer,
                  'dueDate': _dueDateStorage(_selectedDueDate),
                }),
          icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
          label: const Text('Use For Kopesha'),
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
