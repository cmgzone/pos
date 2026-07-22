import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../app/app_shell.dart';
import '../data/cart_provider.dart';
import '../data/quotation_form_provider.dart';
import '../data/quotation_repository.dart';
import '../presentation/receipt_service.dart';

final _quotationStatusFilterProvider = StateProvider<String?>((ref) => null);

class QuotationsScreen extends ConsumerWidget {
  const QuotationsScreen({super.key});

  Future<void> _createQuotation(BuildContext context, WidgetRef ref) async {
    final existingCart = ref.read(cartProvider);
    if (existingCart.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Create a new quotation?'),
          content: Text(
            'This will clear ${existingCart.length} item${existingCart.length == 1 ? '' : 's'} '
            'currently in the POS cart.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    ref.read(cartProvider.notifier).clear();
    ref.read(discountProvider.notifier).state = 0;
    ref.read(quotationCustomerProvider.notifier).state = null;
    ref.read(quotationExpiryProvider.notifier).state = null;
    ref.read(quotationNotesProvider.notifier).state = '';
    ref.read(lastSavedQuotationProvider.notifier).state = null;
    ref.read(activeQuotationIdProvider.notifier).state = null;
    ref.read(posModeProvider.notifier).state = PosMode.quotation;
    AppShell.selectIndex(0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotationsAsync = ref.watch(quotationsListProvider);
    final selectedStatus = ref.watch(_quotationStatusFilterProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCompact = MediaQuery.sizeOf(context).width < 560;

    if (!ShopSettings.quotationsEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quotations')),
        body: const Center(child: Text('Quotations are disabled in Settings.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quotations'),
        actions: [
          IconButton(
            tooltip: 'Refresh quotations',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(quotationsListProvider),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              key: const ValueKey('create-quotation-action'),
              onPressed: () => _createQuotation(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(isCompact ? 'Create' : 'Create quotation'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: isDark
                ? AppColors.darkSurface
                : Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _StatusChip(
                    label: 'All',
                    selected: selectedStatus == null,
                    onTap: () =>
                        ref
                                .read(_quotationStatusFilterProvider.notifier)
                                .state =
                            null,
                  ),
                  for (final status in const [
                    'draft',
                    'sent',
                    'accepted',
                    'converted',
                    'expired',
                    'cancelled',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _StatusChip(
                        label: status.capitalize(),
                        selected: selectedStatus == status,
                        onTap: () =>
                            ref
                                    .read(
                                      _quotationStatusFilterProvider.notifier,
                                    )
                                    .state =
                                status,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: quotationsAsync.when(
              data: (all) {
                final filtered = selectedStatus == null
                    ? all
                    : all
                          .where(
                            (q) =>
                                (q['status'] as String?)?.toLowerCase() ==
                                selectedStatus,
                          )
                          .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.request_quote_outlined,
                            size: 48,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            selectedStatus == null
                                ? 'No quotations yet'
                                : 'No $selectedStatus quotations',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Create a quotation to share prices with a customer.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            key: const ValueKey(
                              'create-first-quotation-action',
                            ),
                            onPressed: () => _createQuotation(context, ref),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Create quotation'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final quotation = filtered[index];
                    return _QuotationCard(
                      quotation: quotation,
                      onRefresh: () => ref.invalidate(quotationsListProvider),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    AppErrorMessage.from(
                      e,
                      fallback: AppErrorMessage.loadFailed,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _QuotationCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> quotation;
  final VoidCallback onRefresh;

  const _QuotationCard({required this.quotation, required this.onRefresh});

  @override
  ConsumerState<_QuotationCard> createState() => _QuotationCardState();
}

class _QuotationCardState extends ConsumerState<_QuotationCard> {
  bool _busy = false;

  String get id => widget.quotation['id'] as String;
  String get quotationNo =>
      (widget.quotation['quotation_no'] as String?) ?? id.substring(0, 8);
  String get status =>
      (widget.quotation['status'] as String?)?.toLowerCase() ?? 'draft';
  String? get customerName => widget.quotation['customer_name'] as String?;
  double get total => (widget.quotation['total'] as num?)?.toDouble() ?? 0;
  String? get expiryDate => widget.quotation['expiry_date'] as String?;

  Color _statusColor() {
    switch (status) {
      case 'converted':
        return AppColors.success;
      case 'sent':
        return AppColors.primaryLight;
      case 'accepted':
        return AppColors.success;
      case 'expired':
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  Future<void> _viewDetail() async {
    final full = await QuotationRepository.getWithItems(id);
    if (full == null) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _QuotationDetailDialog(
        quotation: full,
        onPrint: _print,
        onConvert: _convertToSale,
        onStatusChange: _setStatus,
        onDelete: _cancel,
      ),
    );
    widget.onRefresh();
  }

  Future<void> _print() async {
    if (!mounted) return;
    final full = await QuotationRepository.getWithItems(id);
    if (full == null || !mounted) return;
    final items = (full['items'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    await ReceiptService.showReceiptPreview(
      context,
      saleId: full['id'] as String,
      total: (full['total'] as num?)?.toDouble() ?? 0,
      subtotal: (full['subtotal'] as num?)?.toDouble() ?? 0,
      tax: (full['tax_total'] as num?)?.toDouble() ?? 0,
      discount: (full['discount_total'] as num?)?.toDouble() ?? 0,
      paymentType: 'N/A',
      items: items,
      customerName: full['customer_name'] as String?,
      dueDate: full['expiry_date'] as String?,
      note: full['notes'] as String?,
      documentTitle: 'Quotation',
      recordLabel: 'Quote',
      previewTitle: 'Quotation Preview',
      fileNamePrefix: 'quotation',
      isQuotation: true,
      quotationNo: full['quotation_no'] as String?,
      quotationStatus: full['status'] as String?,
    );
  }

  Future<void> _convertToSale() async {
    setState(() => _busy = true);
    try {
      final loaded = await QuotationRepository.loadForConvert(id);
      if (!mounted) return;
      if (loaded.items.isEmpty) {
        _snack(
          loaded.adjustments.isEmpty
              ? 'No items available to convert.'
              : loaded.adjustments.first,
          AppColors.warning,
        );
        return;
      }
      final proceed = loaded.adjustments.isEmpty
          ? true
          : await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Stock changed since quoting'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Some items were adjusted to match current stock:',
                        ),
                        const SizedBox(height: 10),
                        ...loaded.adjustments.map(
                          (a) => Text(
                            '• $a',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Continue converting to a sale?',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Convert'),
                      ),
                    ],
                  ),
                ) ??
                false;
      if (!proceed) return;

      ref.read(cartProvider.notifier).restoreQuotationItems(loaded.items);
      ref.read(discountProvider.notifier).state =
          (widget.quotation['discount_total'] as num?)?.toDouble() ?? 0;
      ref.read(activeQuotationIdProvider.notifier).state = id;
      ref.read(posModeProvider.notifier).state = PosMode.sale;
      AppShell.selectIndex(0);
    } catch (e) {
      _snack(
        AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
        AppColors.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String newStatus) async {
    try {
      await QuotationRepository.updateStatus(id, newStatus);
      widget.onRefresh();
    } catch (e) {
      _snack(
        AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
        AppColors.error,
      );
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel quotation?'),
        content: const Text(
          'This will remove the quotation from the active list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Quotation'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await QuotationRepository.delete(id);
      widget.onRefresh();
    } catch (e) {
      _snack(
        AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
        AppColors.error,
      );
    }
  }

  void _snack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _busy ? null : _viewDetail,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      quotationNo,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor().withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status.capitalize(),
                      style: TextStyle(
                        color: _statusColor(),
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      customerName ?? 'No customer',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              if (expiryDate != null && expiryDate!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Valid until: ${_formatDate(expiryDate!)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuotationDetailDialog extends StatelessWidget {
  final Map<String, dynamic> quotation;
  final VoidCallback onPrint;
  final VoidCallback onConvert;
  final ValueChanged<String> onStatusChange;
  final VoidCallback onDelete;

  const _QuotationDetailDialog({
    required this.quotation,
    required this.onPrint,
    required this.onConvert,
    required this.onStatusChange,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final items = (quotation['items'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final status = (quotation['status'] as String?)?.toLowerCase() ?? 'draft';
    final isConverted = status == 'converted';
    final isCancelled = status == 'cancelled';

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.request_quote_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              quotation['quotation_no'] as String? ?? 'Quotation',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width < 800
              ? MediaQuery.of(context).size.width - 32
              : 500,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(
                label: 'Customer',
                value: quotation['customer_name'] ?? '-',
              ),
              _DetailRow(label: 'Status', value: status.capitalize()),
              if (quotation['expiry_date'] != null)
                _DetailRow(
                  label: 'Valid until',
                  value: _formatDate(quotation['expiry_date'] as String),
                ),
              if ((quotation['notes'] as String?)?.isNotEmpty == true)
                _DetailRow(label: 'Notes', value: quotation['notes'] as String),
              const Divider(height: 24),
              const Text(
                'Items',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['product_name'] as String? ?? 'Product',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Text(
                        '${(item['quantity'] as num?)?.toStringAsFixed(0) ?? '0'} x ',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${ShopSettings.currency}${(item['unit_price'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${ShopSettings.currency}${(quotation['total'] as num?)?.toDouble().toStringAsFixed(2) ?? '0.00'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (!isConverted && !isCancelled) ...[
          TextButton.icon(
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Print'),
          ),
          if (status == 'draft')
            TextButton(
              onPressed: () {
                onStatusChange('sent');
                Navigator.pop(context);
              },
              child: const Text('Mark Sent'),
            ),
          if (status == 'sent')
            TextButton(
              onPressed: () {
                onStatusChange('accepted');
                Navigator.pop(context);
              },
              child: const Text('Mark Accepted'),
            ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onConvert();
            },
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Convert to Sale'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.success),
          ),
        ] else if (isConverted) ...[
          TextButton.icon(
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Print'),
          ),
        ],
        if (!isConverted && !isCancelled)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel'),
          ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

extension _StringCapitalize on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
