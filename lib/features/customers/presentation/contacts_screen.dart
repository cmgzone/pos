import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/sync_controller.dart';
import '../../../core/services/messaging_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/error_messages.dart';
import '../../../widgets/smart_import_preview_dialog.dart';
import '../../../widgets/overlay_notice.dart';
import '../../gift_cards/data/gift_card_repository.dart';
import '../../purchases/data/purchase_repository.dart';
import '../data/customer_import_service.dart';
import '../data/customer_repository.dart';
import 'customer_account_screen.dart';
import 'customer_message_dialog.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;
  bool _isImportingCustomers = false;

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
    _searchDebounce?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _load();
    });
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

  Future<void> _importCustomersFromFile() async {
    if (_isImportingCustomers) {
      return;
    }
    setState(() => _isImportingCustomers = true);

    CustomerImportResult? result;
    Object? importError;
    try {
      result = await CustomerImportService.pickAndImportCustomers(
        confirmPlan: (plan) => showSmartImportPreviewDialog(
          context,
          plan: plan,
          title: 'Piki AI Customer Import Check',
          actionLabel: 'Import Customers',
          minimumRequirements: const ['Customers only need a name column.'],
          optionalColumns: const ['phone', 'email'],
          defaultsNote:
              'Blank phone and email cells are allowed. Existing customers are matched by phone, email, or name when available.',
        ),
      );
    } catch (error) {
      importError = error;
    } finally {
      if (mounted) {
        setState(() => _isImportingCustomers = false);
      }
    }

    if (!mounted) {
      return;
    }

    if (importError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.withContext(
              importError,
              prefix: 'Could not import customers.',
              fallback:
                  'Use an .xlsx or .csv file with at least a name column. Phone and email are optional.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (result == null) {
      return;
    }
    final importResult = result;

    await _load();
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Customer Import Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${importResult.created} customer${importResult.created == 1 ? '' : 's'} created'
              '${importResult.fileName == null ? '' : ' from ${importResult.fileName}'}.',
            ),
            if (importResult.updated > 0) ...[
              SizedBox(height: AppSpacing.sm),
              Text(
                '${importResult.updated} existing customer${importResult.updated == 1 ? '' : 's'} updated.',
              ),
            ],
            if (importResult.skipped > 0) ...[
              SizedBox(height: AppSpacing.sm),
              Text(
                '${importResult.skipped} row${importResult.skipped == 1 ? '' : 's'} skipped.',
                style: TextStyle(color: AppColors.warning),
              ),
            ],
            if (importResult.errors.isNotEmpty) ...[
              SizedBox(height: AppSpacing.md),
              Text(
                'Check these rows:',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              ...importResult.errors.map(
                (error) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Done'),
          ),
        ],
      ),
    );
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text('Edit Customer'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Customer Name *',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                SizedBox(height: 14),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone Number (WhatsApp / SMS)',
                    prefixIcon: Icon(Icons.phone_outlined),
                    helperText: 'Used for WhatsApp and SMS messaging',
                  ),
                ),
                SizedBox(height: 14),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
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
              child: Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        AppOverlayNotice.showSnackBar(
                          context,
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
                          AppOverlayNotice.showSnackBar(
                            context,
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
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.check, size: 18),
              label: Text('Save'),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text('Edit Supplier'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Supplier Name *',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number (WhatsApp / SMS)',
                      prefixIcon: Icon(Icons.phone_outlined),
                      helperText: 'Used for WhatsApp and SMS messaging',
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: addressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
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
              child: Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        AppOverlayNotice.showSnackBar(
                          context,
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
                          AppOverlayNotice.showSnackBar(
                            context,
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
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.check, size: 18),
              label: Text('Save'),
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
    final balance =
        (contact['balance'] as num?)?.toDouble() ??
        (contact['outstanding_balance'] as num?)?.toDouble() ??
        0;
    final points = (contact['loyalty_points'] as num?)?.toInt() ?? 0;
    final isCustomer =
        contact.containsKey('loyalty_points') ||
        contact.containsKey('balance') ||
        contact.containsKey('outstanding_balance');
    var giftCardBalance = 0.0;

    if (isCustomer) {
      final customerId = contact['id'] as String?;
      if (customerId != null && customerId.trim().isNotEmpty) {
        try {
          final cards = await GiftCardRepository.getAll(
            customerId: customerId,
            activeOnly: true,
          );
          giftCardBalance = cards.fold<double>(
            0,
            (sum, card) => sum + ((card['balance'] as num?)?.toDouble() ?? 0),
          );
        } catch (_) {
          giftCardBalance = 0;
        }
      }
    }

    String message;
    if (balance > 0) {
      message = MessagingService.balanceReminder(
        customerName: name,
        balance: '${ShopSettings.currency}${balance.toStringAsFixed(2)}',
      );
    } else {
      message = 'Hi $name, thank you for your business with us!';
    }

    final balanceLines = <String>[
      if (points > 0) 'Loyalty balance: $points pts.',
      if (giftCardBalance > 0)
        'Gift card balance: ${GiftCardRepository.formatBalance(giftCardBalance)}.',
    ];
    if (balanceLines.isNotEmpty) {
      message = '$message\n${balanceLines.join('\n')}';
    }

    if (!mounted) return;
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          title: Text('Create Supplier'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Supplier Name *',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: addressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
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
              child: Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        AppOverlayNotice.showSnackBar(
                          context,
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
                          AppOverlayNotice.showSnackBar(
                            context,
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
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.check, size: 18),
              label: Text('Save Supplier'),
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
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && next != previous && mounted) {
          _load();
        }
      },
    );

    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text('Contacts'),
        actions: [
          if (_tabController.index == 0)
            IconButton(
              tooltip: 'Import Customers',
              onPressed: _isImportingCustomers
                  ? null
                  : _importCustomersFromFile,
              icon: _isImportingCustomers
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.upload_file_outlined),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryLight,
          labelColor: AppColors.primaryLight,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
          tabs: [
            Tab(
              icon: Icon(Icons.people_outline, size: 20),
              text: 'Customers (${_customers.length})',
            ),
            Tab(
              icon: Icon(Icons.storefront_outlined, size: 20),
              text: 'Suppliers (${_suppliers.length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name, phone, or email…',
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
                          _load();
                        },
                      ),
              ),
            ),
          ),

          // Tab content
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
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
        icon: Icon(Icons.person_add_alt_1),
        label: Text(
          _tabController.index == 0 ? 'Add Customer' : 'Add Supplier',
        ),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        100,
      ),
      itemCount: _customers.length,
      separatorBuilder: (_, _) => SizedBox(height: 10),
      itemBuilder: (context, index) {
        final c = _customers[index];
        final balance = (c['balance'] as num?)?.toDouble() ?? 0;
        final points = (c['loyalty_points'] as num?)?.toInt() ?? 0;
        final hasPhone = _hasPhone(c);

        return _ContactCard(
          name: c['name'] as String? ?? 'Customer',
          contactLine: _contactLine(c),
          hasPhone: hasPhone,
          icon: Icons.person_outline_rounded,
          iconColor: hasPhone
              ? AppColors.primaryLight
              : Theme.of(context).colorScheme.onSurfaceVariant,
          trailing: _buildCustomerTrailing(balance: balance, points: points),
          onEdit: () => _editCustomer(c),
          onMessage: () => _messageContact(c),
          isMobile: isMobile,
        );
      },
    );
  }

  Widget _buildCustomerTrailing({
    required double balance,
    required int points,
  }) {
    final badges = <Widget>[];
    if (balance > 0) {
      badges.add(
        _BalanceBadge(
          label: 'Balance',
          value: '${ShopSettings.currency}${balance.toStringAsFixed(2)}',
          color: AppColors.warning,
        ),
      );
    }
    if (points > 0) {
      badges.add(
        _BalanceBadge(
          label: 'Points',
          value: '$points',
          color: AppColors.success,
        ),
      );
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: badges
          .map(
            (badge) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: badge,
            ),
          )
          .toList(),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        100,
      ),
      itemCount: _suppliers.length,
      separatorBuilder: (_, _) => SizedBox(height: 10),
      itemBuilder: (context, index) {
        final s = _suppliers[index];
        final totalSpend = (s['total_spend'] as num?)?.toDouble() ?? 0;
        final hasPhone = _hasPhone(s);

        return _ContactCard(
          name: s['name'] as String? ?? 'Supplier',
          contactLine: _contactLine(s),
          hasPhone: hasPhone,
          icon: Icons.storefront_outlined,
          iconColor: hasPhone
              ? AppColors.success
              : Theme.of(context).colorScheme.onSurfaceVariant,
          trailing: totalSpend > 0
              ? _BalanceBadge(
                  label: 'Total Spend',
                  value:
                      '${ShopSettings.currency}${totalSpend.toStringAsFixed(2)}',
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
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Icon(icon, size: 36, color: AppColors.primaryLight),
            ),
            SizedBox(height: AppSpacing.xl),
            Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              textAlign: TextAlign.center,
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: hasPhone
              ? context.appBorder
              : AppColors.warning.withValues(alpha: 0.35),
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
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      if (!hasPhone) ...[
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: AppColors.warning.withValues(alpha: 0.9),
                        ),
                        SizedBox(width: AppSpacing.xs),
                      ],
                      Expanded(
                        child: Text(
                          contactLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasPhone
                                ? Theme.of(context).colorScheme.onSurfaceVariant
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
        if (trailing != null) ...[SizedBox(height: AppSpacing.md), trailing!],
        SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, size: 16),
                label: Text('Edit'),
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton.icon(
                onPressed: onMessage,
                icon: Icon(Icons.message_outlined, size: 16),
                label: Text('Message'),
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
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  if (!hasPhone) ...[
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: AppColors.warning.withValues(alpha: 0.9),
                    ),
                    SizedBox(width: AppSpacing.xs),
                  ],
                  Expanded(
                    child: Text(
                      contactLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasPhone
                            ? Theme.of(context).colorScheme.onSurfaceVariant
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
        if (trailing != null) ...[SizedBox(width: 14), trailing!],
        SizedBox(width: 14),
        IconButton(
          onPressed: onEdit,
          tooltip: 'Edit',
          icon: Icon(Icons.edit_outlined, size: 20),
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        SizedBox(width: AppSpacing.xs),
        IconButton(
          onPressed: onMessage,
          tooltip: 'WhatsApp / SMS',
          icon: Icon(Icons.message_outlined, size: 20),
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
        borderRadius: BorderRadius.circular(AppRadius.md),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.sm),
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
          SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
