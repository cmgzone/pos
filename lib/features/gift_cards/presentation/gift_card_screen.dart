import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_app/core/services/shop_settings.dart';
import 'package:pos_app/core/theme/app_colors.dart';
import 'package:pos_app/core/utils/error_messages.dart';

import 'package:pos_app/features/customers/data/customer_repository.dart';
import 'package:pos_app/features/customers/presentation/customer_message_dialog.dart';
import '../data/gift_card_repository.dart';

class GiftCardScreen extends StatefulWidget {
  const GiftCardScreen({super.key});

  @override
  State<GiftCardScreen> createState() => _GiftCardScreenState();
}

class _GiftCardScreenState extends State<GiftCardScreen> {
  List<Map<String, dynamic>> _cards = const [];
  Map<String, String> _customerNames = const {};
  bool _loading = true;
  String? _errorMessage;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final cards = await GiftCardRepository.getAll(
        codeQuery: _searchController.text,
      );
      final customerIds = cards
          .map((card) => card['customer_id']?.toString())
          .whereType<String>()
          .where((id) => id.trim().isNotEmpty)
          .toSet();
      final customerNames = <String, String>{};
      for (final customerId in customerIds) {
        final customer = await CustomerRepository.getById(customerId);
        final name = customer?['name']?.toString().trim();
        if (name != null && name.isNotEmpty) {
          customerNames[customerId] = name;
        }
      }
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _customerNames = customerNames;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = AppErrorMessage.from(
          e,
          fallback: AppErrorMessage.loadFailed,
        );
        _loading = false;
      });
    }
  }

  double get _totalBalance {
    var total = 0.0;
    for (final card in _cards) {
      total += (card['balance'] as num? ?? 0).toDouble();
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gift Cards'),
        actions: [
          FilledButton.icon(
            onPressed: _openCreateDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Card'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search by code',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (_) => _loadData(),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${GiftCardRepository.formatBalance(_totalBalance)} active',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadData,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                  ? _buildError()
                  : _cards.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
        const SizedBox(height: 12),
        Text(
          _errorMessage!,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _loadData, child: const Text('Retry')),
      ],
    );
  }

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(
          Icons.card_giftcard_outlined,
          size: 48,
          color: AppColors.primaryLight,
        ),
        const SizedBox(height: 12),
        Text(
          'No gift cards yet.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'Create a gift card with an initial balance, then redeem it at checkout.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: _cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final card = _cards[index];
        final isActive =
            (card['is_active'] is int
                ? card['is_active'] as int
                : int.tryParse(card['is_active']?.toString() ?? '') ?? 0) !=
            0;
        final balance = (card['balance'] as num? ?? 0).toDouble();
        final initial = (card['initial_balance'] as num? ?? 0).toDouble();
        final expiresAt = card['expires_at']?.toString();
        final customerId = card['customer_id']?.toString();
        final customerName = customerId == null || customerId.isEmpty
            ? null
            : _customerNames[customerId] ?? 'Assigned customer';
        final expired = _isExpired(expiresAt);
        final disabled = !isActive || expired;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: disabled
                            ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.08)
                            : AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.card_giftcard_rounded,
                        color: disabled ? null : AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card['code']?.toString() ?? '—',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            disabled
                                ? (expired ? 'Expired' : 'Inactive')
                                : 'Active',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: disabled
                                      ? Theme.of(context).colorScheme.error
                                      : AppColors.success,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          GiftCardRepository.formatBalance(balance),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: AppColors.primaryLight),
                        ),
                        Text(
                          'of ${GiftCardRepository.formatBalance(initial)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.person_outline,
                      label: customerName ?? 'Unassigned',
                    ),
                    if (expiresAt != null && expiresAt.isNotEmpty)
                      _InfoChip(
                        icon: Icons.event_outlined,
                        label: 'Expires ${_formatDate(expiresAt)}',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ActionChip(
                      label: 'Top Up',
                      icon: Icons.add_card_outlined,
                      onTap: () => _openTopUpDialog(card),
                    ),
                    _ActionChip(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      onTap: () => _openEditDialog(card),
                    ),
                    _ActionChip(
                      label: 'Send',
                      icon: Icons.send_outlined,
                      onTap: () => _sendGiftCard(card),
                    ),
                    _ActionChip(
                      label: 'Copy',
                      icon: Icons.copy_outlined,
                      onTap: () => _copyGiftCardCode(card),
                    ),
                    _ActionChip(
                      label: 'History',
                      icon: Icons.history_outlined,
                      onTap: () => _showHistory(card),
                    ),
                    _ActionChip(
                      label: disabled ? 'Activate' : 'Deactivate',
                      icon: disabled ? Icons.check_circle_outline : Icons.block,
                      onTap: () => _toggleActive(card, activate: disabled),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      color: Theme.of(context).colorScheme.error,
                      onPressed: () => _confirmDelete(card),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCreateDialog() async {
    final customers = await CustomerRepository.search('');
    if (!mounted) return;
    final codeController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? selectedCustomerId;
    DateTime? expiresAt;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('New Gift Card'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Card code',
                      hintText: 'e.g. GC-1001',
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'Initial balance',
                      prefixText: ShopSettings.currency,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (v) {
                      final value = double.tryParse(v ?? '');
                      if (value == null || value < 0) {
                        return 'Enter a valid amount';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _CustomerDropdown(
                    customers: customers,
                    value: selectedCustomerId,
                    onChanged: (value) {
                      setDialogState(() => selectedCustomerId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ExpiryField(
                    expiresAt: expiresAt,
                    onPick: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: expiresAt ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => expiresAt = picked);
                      }
                    },
                    onClear: () => setDialogState(() => expiresAt = null),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final navigator = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await GiftCardRepository.create(
                    code: codeController.text,
                    initialBalance: double.parse(amountController.text.trim()),
                    customerId: selectedCustomerId,
                    expiresAt: _dateOnly(expiresAt),
                    note: noteController.text,
                  );
                  if (!mounted) return;
                  navigator.pop();
                  _loadData();
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        AppErrorMessage.from(
                          e,
                          fallback: 'Could not create gift card.',
                        ),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditDialog(Map<String, dynamic> card) async {
    final customers = await CustomerRepository.search('');
    if (!mounted) return;
    final noteController = TextEditingController(
      text: card['note']?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    String? selectedCustomerId = card['customer_id']?.toString();
    if (selectedCustomerId != null && selectedCustomerId.trim().isEmpty) {
      selectedCustomerId = null;
    }
    final rawExpiry = card['expires_at']?.toString();
    DateTime? expiresAt = rawExpiry == null || rawExpiry.isEmpty
        ? null
        : DateTime.tryParse(rawExpiry);
    var isActive = _isActive(card);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Edit ${card['code']}'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isActive,
                    onChanged: (value) {
                      setDialogState(() => isActive = value);
                    },
                    title: const Text('Active'),
                  ),
                  const SizedBox(height: 8),
                  _CustomerDropdown(
                    customers: customers,
                    value: selectedCustomerId,
                    onChanged: (value) {
                      setDialogState(() => selectedCustomerId = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _ExpiryField(
                    expiresAt: expiresAt,
                    onPick: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: expiresAt ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => expiresAt = picked);
                      }
                    },
                    onClear: () => setDialogState(() => expiresAt = null),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final navigator = Navigator.of(ctx);
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await GiftCardRepository.updateStatus(
                    id: card['id'] as String,
                    isActive: isActive,
                    customerId: selectedCustomerId ?? '',
                    expiresAt: _dateOnly(expiresAt) ?? '',
                    note: noteController.text,
                  );
                  if (!mounted) return;
                  navigator.pop();
                  _loadData();
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        AppErrorMessage.from(
                          e,
                          fallback: 'Could not update gift card.',
                        ),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTopUpDialog(Map<String, dynamic> card) async {
    final amountController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Top Up ${card['code']}'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: amountController,
            decoration: InputDecoration(
              labelText: 'Amount to add',
              prefixText: ShopSettings.currency,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) {
              final value = double.tryParse(v ?? '');
              if (value == null || value <= 0) {
                return 'Enter an amount greater than zero';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final navigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await GiftCardRepository.topUp(
                  id: card['id'] as String,
                  amount: double.parse(amountController.text.trim()),
                );
                if (!mounted) return;
                navigator.pop();
                _loadData();
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      AppErrorMessage.from(
                        e,
                        fallback: 'Could not top up gift card.',
                      ),
                    ),
                  ),
                );
              }
            },
            child: const Text('Top Up'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendGiftCard(Map<String, dynamic> card) async {
    final customerId = card['customer_id']?.toString();
    if (customerId == null || customerId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assign this gift card to a customer before sending.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final customer = await CustomerRepository.getById(customerId);
    if (!mounted) return;
    if (customer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Assigned customer was not found.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final name = customer['name']?.toString() ?? 'Customer';
    final phone = customer['phone']?.toString() ?? '';
    final email = customer['email']?.toString() ?? '';
    if (phone.trim().isEmpty && email.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a phone number or email before sending.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final code = card['code']?.toString() ?? '';
    final balance = (card['balance'] as num? ?? 0).toDouble();
    final expiresAt = card['expires_at']?.toString();
    final expiryLine = expiresAt == null || expiresAt.trim().isEmpty
        ? ''
        : '\nExpires: ${_formatDate(expiresAt)}';
    final shopName = ShopSettings.shopName.trim().isEmpty
        ? 'our shop'
        : ShopSettings.shopName.trim();

    await CustomerMessageDialog.show(
      context,
      customerName: name,
      phoneNumber: phone,
      emailAddress: email,
      initialMessage:
          'Hi $name, your $shopName gift card is ready.\n'
          'Code: $code\n'
          'Balance: ${GiftCardRepository.formatBalance(balance)}'
          '$expiryLine\n'
          'Show this code at checkout. Keep it safe.',
      metadata: {
        'source': 'gift_card',
        'giftCardId': card['id'],
        'giftCardCode': code,
        'balance': balance,
      },
    );
  }

  Future<void> _copyGiftCardCode(Map<String, dynamic> card) async {
    final code = card['code']?.toString() ?? '';
    if (code.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Gift card code copied')));
  }

  Future<void> _showHistory(Map<String, dynamic> card) async {
    final transactions = await GiftCardRepository.getTransactions(
      card['id'] as String,
    );
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('History ${card['code']}'),
        content: SizedBox(
          width: 460,
          child: transactions.isEmpty
              ? const Text('No gift card activity yet.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: transactions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final txn = transactions[index];
                    final amount = (txn['amount'] as num? ?? 0).toDouble();
                    final balanceAfter = (txn['balance_after'] as num? ?? 0)
                        .toDouble();
                    final type = txn['type']?.toString() ?? 'activity';
                    final saleId = txn['sale_id']?.toString();
                    final createdAt = txn['created_at']?.toString() ?? '';
                    final amountColor = amount < 0
                        ? Theme.of(context).colorScheme.error
                        : AppColors.success;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: amountColor.withValues(alpha: 0.12),
                        child: Icon(
                          _giftCardTxnIcon(type),
                          color: amountColor,
                          size: 18,
                        ),
                      ),
                      title: Text(_giftCardTxnLabel(type)),
                      subtitle: Text(
                        [
                          if (createdAt.isNotEmpty) _formatDateTime(createdAt),
                          if (saleId != null && saleId.isNotEmpty)
                            'Sale #${saleId.substring(0, saleId.length < 8 ? saleId.length : 8)}',
                        ].join(' - '),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${amount >= 0 ? '+' : '-'}${GiftCardRepository.formatBalance(amount.abs())}',
                            style: TextStyle(
                              color: amountColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Bal ${GiftCardRepository.formatBalance(balanceAfter)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive(
    Map<String, dynamic> card, {
    required bool activate,
  }) async {
    try {
      await GiftCardRepository.updateStatus(
        id: card['id'] as String,
        isActive: activate,
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppErrorMessage.from(e, fallback: 'Update failed.')),
        ),
      );
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Gift Card'),
        content: Text('Delete card ${card['code']}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await GiftCardRepository.delete(card['id'] as String);
        _loadData();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorMessage.from(e, fallback: 'Delete failed.')),
          ),
        );
      }
    }
  }

  bool _isActive(Map<String, dynamic> card) {
    return (card['is_active'] is int
            ? card['is_active'] as int
            : int.tryParse(card['is_active']?.toString() ?? '') ?? 0) !=
        0;
  }

  String? _dateOnly(DateTime? date) {
    if (date == null) return null;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDate(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return '${date.month}/${date.day}/${date.year}';
  }

  String _formatDateTime(String raw) {
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return '${date.month}/${date.day}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  bool _isExpired(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return false;
    }
    final expiry = DateTime.tryParse(raw);
    if (expiry == null) {
      return false;
    }
    final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return expiryDay.isBefore(today);
  }

  String _giftCardTxnLabel(String type) {
    return switch (type) {
      'issue' => 'Issued',
      'top_up' => 'Top up',
      'redeem' => 'Redeemed',
      'refund' => 'Refunded',
      _ => 'Activity',
    };
  }

  IconData _giftCardTxnIcon(String type) {
    return switch (type) {
      'issue' => Icons.card_giftcard_outlined,
      'top_up' => Icons.add_card_outlined,
      'redeem' => Icons.shopping_cart_checkout_outlined,
      'refund' => Icons.undo_outlined,
      _ => Icons.history_outlined,
    };
  }
}

class _CustomerDropdown extends StatelessWidget {
  final List<Map<String, dynamic>> customers;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _CustomerDropdown({
    required this.customers,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Assigned customer',
        prefixIcon: Icon(Icons.person_outline),
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
        ...customers.map(
          (customer) => DropdownMenuItem<String?>(
            value: customer['id'] as String?,
            child: Text(customer['name']?.toString() ?? 'Customer'),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ExpiryField extends StatelessWidget {
  final DateTime? expiresAt;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _ExpiryField({
    required this.expiresAt,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final label = expiresAt == null
        ? 'No expiry'
        : '${expiresAt!.month}/${expiresAt!.day}/${expiresAt!.year}';

    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Expiry date',
        prefixIcon: Icon(Icons.event_outlined),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          TextButton(onPressed: onPick, child: const Text('Pick')),
          if (expiresAt != null)
            IconButton(
              tooltip: 'Clear expiry',
              onPressed: onClear,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
