import 'package:flutter/material.dart';
import 'package:pos_app/core/services/shop_settings.dart';
import 'package:pos_app/core/theme/app_colors.dart';
import 'package:pos_app/core/utils/error_messages.dart';
import 'package:pos_app/features/app/app_shell.dart';
import '../data/gift_card_repository.dart';

class GiftCardScreen extends StatefulWidget {
  const GiftCardScreen({super.key});

  @override
  State<GiftCardScreen> createState() => _GiftCardScreenState();
}

class _GiftCardScreenState extends State<GiftCardScreen> {
  List<Map<String, dynamic>> _cards = const [];
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
      if (!mounted) return;
      setState(() {
        _cards = cards;
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
        leading: !Navigator.of(context).canPop() &&
                MediaQuery.of(context).size.width <= 800
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () =>
                    AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
        const Icon(Icons.card_giftcard_outlined, size: 48, color: AppColors.primaryLight),
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
        final isActive = (card['is_active'] is int
                ? card['is_active'] as int
                : int.tryParse(card['is_active']?.toString() ?? '') ?? 0) !=
            0;
        final balance = (card['balance'] as num? ?? 0).toDouble();
        final initial = (card['initial_balance'] as num? ?? 0).toDouble();
        final expiresAt = card['expires_at']?.toString();
        final expired = expiresAt != null &&
            expiresAt.isNotEmpty &&
            (DateTime.tryParse(expiresAt)?.isBefore(DateTime.now()) ?? false);
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
                            ? Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.08)
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
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: disabled
                                      ? Theme.of(context)
                                          .colorScheme
                                          .error
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
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.primaryLight,
                          ),
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
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _ActionChip(
                      label: 'Top Up',
                      icon: Icons.add_card_outlined,
                      onTap: () => _openTopUpDialog(card),
                    ),
                    const SizedBox(width: 8),
                    _ActionChip(
                      label: disabled ? 'Activate' : 'Deactivate',
                      icon: disabled
                          ? Icons.check_circle_outline
                          : Icons.block,
                      onTap: () =>
                          _toggleActive(card, activate: disabled),
                    ),
                    const Spacer(),
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
    final codeController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
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
                  initialBalance:
                      double.parse(amountController.text.trim()),
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
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
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
          content: Text(
            AppErrorMessage.from(e, fallback: 'Update failed.'),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Gift Card'),
        content: Text(
          'Delete card ${card['code']}? This cannot be undone.',
        ),
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
            content: Text(
              AppErrorMessage.from(e, fallback: 'Delete failed.'),
            ),
          ),
        );
      }
    }
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
