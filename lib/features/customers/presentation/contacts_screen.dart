import 'package:flutter/material.dart';

import '../../../core/services/messaging_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../purchases/data/purchase_repository.dart';
import '../data/customer_repository.dart';
import 'customer_account_screen.dart';
import 'customer_message_dialog.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _searchController.clear();
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final query = _searchController.text.trim();
    final customers = await CustomerRepository.search(query);
    final suppliers = await PurchaseRepository.getSuppliers();
    if (!mounted) return;

    final filteredSuppliers = query.isEmpty
        ? suppliers
        : suppliers.where((s) {
            final name = (s['name'] as String? ?? '').toLowerCase();
            final phone = (s['phone'] as String? ?? '').toLowerCase();
            final email = (s['email'] as String? ?? '').toLowerCase();
            final q = query.toLowerCase();
            return name.contains(q) || phone.contains(q) || email.contains(q);
          }).toList();

    setState(() {
      _customers = customers;
      _suppliers = filteredSuppliers;
      _isLoading = false;
    });
  }

  String _contactLine(Map<String, dynamic> contact) {
    final parts = [
      contact['phone'] as String?,
      contact['email'] as String?,
    ].where((v) => v != null && v.isNotEmpty).cast<String>();
    return parts.isEmpty ? 'No contact details' : parts.join(' · ');
  }

  bool _hasPhone(Map<String, dynamic> contact) {
    final phone = contact['phone'] as String? ?? '';
    return phone.trim().isNotEmpty;
  }

  // ─── Edit Customer ──────────────────────────────────────────────────

  Future<void> _editCustomer(Map<String, dynamic> customer) async {
    final nameController = TextEditingController(
      text: customer['name'] as String? ?? '',
    );
    final phoneController = TextEditingController(
      text: customer['phone'] as String? ?? '',
    );
    final emailController = TextEditingController(
      text: customer['email'] as String? ?? '',
    );
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Edit Customer'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name *',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number (WhatsApp / SMS)',
                    prefixIcon: Icon(Icons.phone_outlined),
                    helperText: 'Used for WhatsApp and SMS messaging',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Customer name is required'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await CustomerRepository.update(
                          id: customer['id'] as String,
                          name: nameController.text,
                          phone: phoneController.text,
                          email: emailController.text,
                        );
                        if (context.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppErrorMessage.from(
                                  e,
                                  fallback: AppErrorMessage.saveFailed,
                                ),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();

    if (saved == true && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer updated'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // ─── Edit Supplier ──────────────────────────────────────────────────

  Future<void> _editSupplier(Map<String, dynamic> supplier) async {
    final nameController = TextEditingController(
      text: supplier['name'] as String? ?? '',
    );
    final phoneController = TextEditingController(
      text: supplier['phone'] as String? ?? '',
    );
    final emailController = TextEditingController(
      text: supplier['email'] as String? ?? '',
    );
    final addressController = TextEditingController(
      text: supplier['address'] as String? ?? '',
    );
    final noteController = TextEditingController(
      text: supplier['note'] as String? ?? '',
    );
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Edit Supplier'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Supplier Name *',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number (WhatsApp / SMS)',
                      prefixIcon: Icon(Icons.phone_outlined),
                      helperText: 'Used for WhatsApp and SMS messaging',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: addressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Supplier name is required'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await PurchaseRepository.updateSupplier(
                          id: supplier['id'] as String,
                          name: nameController.text,
                          phone: phoneController.text,
                          email: emailController.text,
                          address: addressController.text,
                          note: noteController.text,
                        );
                        if (context.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppErrorMessage.from(
                                  e,
                                  fallback: AppErrorMessage.saveFailed,
                                ),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    addressController.dispose();
    noteController.dispose();

    if (saved == true && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supplier updated'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // ─── Message Contact ────────────────────────────────────────────────

  Future<void> _messageContact(Map<String, dynamic> contact) async {
    final name = contact['name'] as String? ?? 'Contact';
    final phone = contact['phone'] as String? ?? '';
    final email = contact['email'] as String? ?? '';
    final balance = (contact['balance'] as num?)?.toDouble() ??
        (contact['outstanding_balance'] as num?)?.toDouble() ??
        0;

    String message;
    if (balance > 0) {
      message = MessagingService.balanceReminder(
        customerName: name,
        balance: '${ShopSettings.currency}${balance.toStringAsFixed(2)}',
      );
    } else {
      message = 'Hi $name, thank you for your business with us!';
    }

    await CustomerMessageDialog.show(
      context,
      customerName: name,
      phoneNumber: phone,
      emailAddress: email,
      initialMessage: message,
      metadata: {'source': 'contacts_screen', 'contactId': contact['id']},
    );
  }

  // ─── Create New Supplier (inline dialog) ────────────────────────────

  Future<void> _showAddSupplierDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final noteController = TextEditingController();
    bool isSaving = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Create Supplier'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Supplier Name *',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: addressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Supplier name is required'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      try {
                        await PurchaseRepository.createSupplier(
                          name: nameController.text,
                          phone: phoneController.text,
                          email: emailController.text,
                          address: addressController.text,
                          note: noteController.text,
                        );
                        if (context.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppErrorMessage.from(
                                  e,
                                  fallback: AppErrorMessage.saveFailed,
                                ),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => isSaving = false);
                      }
                    },
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('Save Supplier'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    addressController.dispose();
    noteController.dispose();

    if (created == true && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supplier created'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // ─── Create Customer ────────────────────────────────────────────────

  Future<void> _openCreateCustomerScreen() async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const CustomerAccountScreen()),
    );

    if (created == null || !mounted) return;

    _searchController.clear();
    await _load();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${created['name']} account created'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('Contacts'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryLight,
          labelColor: AppColors.primaryLight,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: [
            Tab(
              icon: const Icon(Icons.people_outline, size: 20),
              text: 'Customers (${_customers.length})',
            ),
            Tab(
              icon: const Icon(Icons.storefront_outlined, size: 20),
              text: 'Suppliers (${_suppliers.length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or email…',
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
                          _load();
                        },
                      ),
              ),
            ),
          ),

          // Tab content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCustomerList(isMobile),
                      _buildSupplierList(isMobile),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _openCreateCustomerScreen();
          } else {
            _showAddSupplierDialog();
          }
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(_tabController.index == 0 ? 'Add Customer' : 'Add Supplier'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  // ─── Customer List ──────────────────────────────────────────────────

  Widget _buildCustomerList(bool isMobile) {
    if (_customers.isEmpty) {
      return _emptyState(
        icon: Icons.people_outline,
        title: 'No customers yet',
        subtitle: 'Tap "Add Customer" to create your first customer contact.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _customers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final c = _customers[index];
        final balance = (c['balance'] as num?)?.toDouble() ?? 0;
        final hasPhone = _hasPhone(c);

        return _ContactCard(
          name: c['name'] as String? ?? 'Customer',
          contactLine: _contactLine(c),
          hasPhone: hasPhone,
          icon: Icons.person_outline_rounded,
          iconColor: hasPhone ? AppColors.primaryLight : AppColors.textSecondary,
          trailing: balance > 0
              ? _BalanceBadge(
                  label: 'Balance',
                  value: '${ShopSettings.currency}${balance.toStringAsFixed(2)}',
                  color: AppColors.warning,
                )
              : null,
          onEdit: () => _editCustomer(c),
          onMessage: () => _messageContact(c),
          isMobile: isMobile,
        );
      },
    );
  }

  // ─── Supplier List ──────────────────────────────────────────────────

  Widget _buildSupplierList(bool isMobile) {
    if (_suppliers.isEmpty) {
      return _emptyState(
        icon: Icons.storefront_outlined,
        title: 'No suppliers yet',
        subtitle: 'Tap "Add Supplier" to create your first supplier contact.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: _suppliers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final s = _suppliers[index];
        final totalSpend = (s['total_spend'] as num?)?.toDouble() ?? 0;
        final hasPhone = _hasPhone(s);

        return _ContactCard(
          name: s['name'] as String? ?? 'Supplier',
          contactLine: _contactLine(s),
          hasPhone: hasPhone,
          icon: Icons.storefront_outlined,
          iconColor: hasPhone ? AppColors.success : AppColors.textSecondary,
          trailing: totalSpend > 0
              ? _BalanceBadge(
                  label: 'Total Spend',
                  value: '${ShopSettings.currency}${totalSpend.toStringAsFixed(2)}',
                  color: AppColors.primaryLight,
                )
              : null,
          onEdit: () => _editSupplier(s),
          onMessage: () => _messageContact(s),
          isMobile: isMobile,
        );
      },
    );
  }

  // ─── Empty State ────────────────────────────────────────────────────

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 36, color: AppColors.primaryLight),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary.withValues(alpha: 0.9),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Contact Card Widget ──────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  final String name;
  final String contactLine;
  final bool hasPhone;
  final IconData icon;
  final Color iconColor;
  final Widget? trailing;
  final VoidCallback onEdit;
  final VoidCallback onMessage;
  final bool isMobile;

  const _ContactCard({
    required this.name,
    required this.contactLine,
    required this.hasPhone,
    required this.icon,
    required this.iconColor,
    this.trailing,
    required this.onEdit,
    required this.onMessage,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasPhone ? AppColors.border : AppColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: isMobile ? _buildMobile(context) : _buildDesktop(context),
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _avatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (!hasPhone) ...[
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: AppColors.warning.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          contactLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasPhone
                                ? AppColors.textSecondary
                                : AppColors.warning,
                            fontSize: 12,
                            fontWeight: hasPhone
                                ? FontWeight.normal
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (trailing != null) ...[
          const SizedBox(height: 12),
          trailing!,
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: onMessage,
                icon: const Icon(Icons.message_outlined, size: 16),
                label: const Text('Message'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Row(
      children: [
        _avatar(),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (!hasPhone) ...[
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: AppColors.warning.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      contactLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasPhone
                            ? AppColors.textSecondary
                            : AppColors.warning,
                        fontSize: 12,
                        fontWeight: hasPhone
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 14),
          trailing!,
        ],
        const SizedBox(width: 14),
        IconButton(
          onPressed: onEdit,
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_outlined, size: 20),
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 4),
        IconButton(
          onPressed: onMessage,
          tooltip: 'WhatsApp / SMS',
          icon: const Icon(Icons.message_outlined, size: 20),
          color: AppColors.primaryLight,
        ),
      ],
    );
  }

  Widget _avatar() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: iconColor, size: 22),
    );
  }
}

// ─── Balance Badge ────────────────────────────────────────────────────────────

class _BalanceBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _BalanceBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
