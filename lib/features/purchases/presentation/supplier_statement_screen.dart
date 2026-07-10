import 'package:flutter/material.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../data/purchase_repository.dart';

class SupplierStatementScreen extends StatefulWidget {
  final Map<String, dynamic> supplier;

  const SupplierStatementScreen({super.key, required this.supplier});

  @override
  State<SupplierStatementScreen> createState() =>
      _SupplierStatementScreenState();
}

class _SupplierStatementScreenState extends State<SupplierStatementScreen> {
  late Future<Map<String, dynamic>> _statementFuture;

  @override
  void initState() {
    super.initState();
    _statementFuture = PurchaseRepository.getSupplierStatement(
      widget.supplier['id'] as String? ?? '',
    );
  }

  Future<void> _reload() async {
    setState(() {
      _statementFuture = PurchaseRepository.getSupplierStatement(
        widget.supplier['id'] as String? ?? '',
      );
    });
    await _statementFuture;
  }

  @override
  Widget build(BuildContext context) {
    final supplierName =
        widget.supplier['name'] as String? ?? 'Supplier Statement';
    return Scaffold(
      appBar: AppBar(
        title: Text(supplierName),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _statementFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Statement could not be loaded: ${snapshot.error}'),
              ),
            );
          }
          final statement = snapshot.data ?? const <String, dynamic>{};
          final supplier =
              statement['supplier'] as Map<String, dynamic>? ?? widget.supplier;
          final aging =
              statement['aging'] as Map<String, dynamic>? ??
              const <String, dynamic>{};
          final openInvoices =
              (statement['open_invoices'] as List<dynamic>? ?? const [])
                  .cast<Map<String, dynamic>>();
          final ledger = (statement['ledger'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();
          return RefreshIndicator(
            onRefresh: _reload,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HeaderCard(supplier: supplier, aging: aging),
                      const SizedBox(height: 16),
                      _AgingBuckets(aging: aging),
                      const SizedBox(height: 16),
                      _OpenInvoices(invoices: openInvoices),
                      const SizedBox(height: 16),
                      _LedgerTable(entries: ledger),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> supplier;
  final Map<String, dynamic> aging;

  const _HeaderCard({required this.supplier, required this.aging});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final outstanding = _amount(aging['total_outstanding']);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 640;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                supplier['name'] as String? ?? 'Supplier',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if ((supplier['phone'] as String?)?.trim().isNotEmpty == true)
                    _InfoChip(
                      Icons.phone_outlined,
                      supplier['phone'] as String,
                    ),
                  if ((supplier['email'] as String?)?.trim().isNotEmpty == true)
                    _InfoChip(
                      Icons.email_outlined,
                      supplier['email'] as String,
                    ),
                  _InfoChip(
                    Icons.receipt_long_outlined,
                    '${(aging['open_invoice_count'] as num? ?? 0).toInt()} open invoices',
                  ),
                ],
              ),
            ],
          );
          final balance = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Outstanding',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _money(outstanding),
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          );
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: title),
                const SizedBox(width: 16),
                SizedBox(width: 230, child: balance),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [title, const SizedBox(height: 14), balance],
          );
        },
      ),
    );
  }
}

class _AgingBuckets extends StatelessWidget {
  final Map<String, dynamic> aging;

  const _AgingBuckets({required this.aging});

  @override
  Widget build(BuildContext context) {
    final buckets = [
      ('Current', aging['current_amount'], AppColors.success),
      ('1-30', aging['d1_30_amount'], AppColors.warning),
      ('31-60', aging['d31_60_amount'], Colors.deepOrange),
      ('61-90', aging['d61_90_amount'], Colors.redAccent),
      ('90+', aging['over90_amount'], AppColors.error),
    ];
    return _Section(
      title: 'Aging Buckets',
      icon: Icons.timelapse_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 860
              ? 5
              : constraints.maxWidth >= 560
              ? 3
              : 2;
          final gap = 10.0;
          final width =
              (constraints.maxWidth - (gap * (columns - 1))) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: buckets.map((bucket) {
              return SizedBox(
                width: width,
                child: _MetricTile(
                  label: bucket.$1,
                  value: _money(_amount(bucket.$2)),
                  color: bucket.$3,
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _OpenInvoices extends StatelessWidget {
  final List<Map<String, dynamic>> invoices;

  const _OpenInvoices({required this.invoices});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Open Invoices',
      icon: Icons.pending_actions_outlined,
      child: invoices.isEmpty
          ? const Text('No open supplier invoices.')
          : Column(
              children: invoices.map((invoice) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(
                    (invoice['invoice_number'] as String?)?.trim().isNotEmpty ==
                            true
                        ? invoice['invoice_number'] as String
                        : 'Purchase invoice',
                  ),
                  subtitle: Text(
                    'Due: ${_shortDate(invoice['due_date'] as String?)} - ${invoice['status'] ?? 'open'}',
                  ),
                  trailing: Text(
                    _money(_amount(invoice['balance_due'])),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: AppColors.warning,
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _LedgerTable extends StatelessWidget {
  final List<Map<String, dynamic>> entries;

  const _LedgerTable({required this.entries});

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Running Ledger',
      icon: Icons.account_balance_wallet_outlined,
      child: entries.isEmpty
          ? const Text('No supplier activity yet.')
          : Column(
              children: entries.reversed.map((entry) {
                final type = entry['entry_type'] as String? ?? '';
                final isPayment = type == 'payment';
                final debit = _amount(entry['debit']);
                final credit = _amount(entry['credit']);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isPayment
                        ? Icons.payments_outlined
                        : Icons.receipt_long_outlined,
                    color: isPayment ? AppColors.success : AppColors.primary,
                  ),
                  title: Text(isPayment ? 'Payment' : 'Purchase'),
                  subtitle: Text(
                    [
                          entry['reference']?.toString(),
                          _shortDate(entry['entry_at'] as String?),
                          entry['note']?.toString(),
                        ]
                        .where((item) => item?.trim().isNotEmpty == true)
                        .join(' - '),
                  ),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isPayment ? '-${_money(credit)}' : _money(debit),
                        style: TextStyle(
                          color: isPayment
                              ? AppColors.success
                              : AppColors.warning,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Bal ${_money(_amount(entry['running_balance']))}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

double _amount(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _money(double value) =>
    '${ShopSettings.currency}${value.toStringAsFixed(2)}';

String _shortDate(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) {
    return 'N/A';
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }
  return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
}
