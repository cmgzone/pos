import 'package:flutter/material.dart';
import '../../../core/services/messaging_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/stitch_kit.dart';
import '../data/customer_repository.dart';
import '../../sales/presentation/receipt_service.dart';
import 'customer_message_dialog.dart';

class CustomerKopeshaDetailScreen extends StatefulWidget {
  final String customerId;

  const CustomerKopeshaDetailScreen({super.key, required this.customerId});

  @override
  State<CustomerKopeshaDetailScreen> createState() =>
      _CustomerKopeshaDetailScreenState();
}

class _CustomerKopeshaDetailScreenState
    extends State<CustomerKopeshaDetailScreen> {
  Map<String, dynamic>? _statement;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final statement = await CustomerRepository.getKopeshaStatement(
      widget.customerId,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _statement = statement;
      _isLoading = false;
    });
  }

  double _money(dynamic value) => (value as num?)?.toDouble() ?? 0.0;
  int _count(dynamic value) => (value as num?)?.toInt() ?? 0;

  DateTime? _date(String? raw) =>
      raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);

  String _dateLabel(String? raw) {
    final date = _date(raw);
    if (date == null) {
      return 'No due date';
    }
    return '${date.month}/${date.day}/${date.year}';
  }

  bool _isOverdue(String? raw) {
    final date = _date(raw);
    if (date == null) {
      return false;
    }
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    return date.isBefore(today);
  }

  String _dateTimeLabel(String? raw) {
    final date = _date(raw);
    if (date == null) {
      return '-';
    }
    return '${date.month}/${date.day}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showPaymentReceipt(String paymentGroupId) async {
    final receipt = await CustomerRepository.getPaymentGroupReceipt(
      paymentGroupId,
    );
    if (receipt == null || !mounted) {
      return;
    }

    final total = (receipt['total_amount'] as num? ?? 0).toDouble();
    await ReceiptService.showReceiptPreview(
      context,
      saleId: paymentGroupId,
      total: total,
      subtotal: total,
      tax: 0,
      discount: 0,
      paymentType: 'repayment',
      items:
          receipt['items'] as List<Map<String, dynamic>>? ??
          <Map<String, dynamic>>[],
      customerName: receipt['customer_name'] as String?,
      amountTendered: total,
      changeGiven: 0,
      previewTitle: 'Repayment Receipt Preview',
      documentTitle: 'Repayment Receipt',
      fileNamePrefix: 'repayment_receipt',
      recordLabel: 'Payment',
      note: receipt['note'] as String?,
      cashierName: receipt['cashier_name'] as String?,
      documentDate: receipt['received_at'] as String?,
      showTenderedBreakdown: true,
    );
  }

  Future<void> _messageCustomer() async {
    final statement = _statement;
    if (statement == null) return;
    final customer = statement['customer'] as Map<String, dynamic>? ?? {};
    final summary =
        statement['summary'] as Map<String, dynamic>? ??
        <String, dynamic>{'outstanding_balance': customer['balance'] ?? 0.0};
    final name = customer['name'] as String? ?? 'Customer';
    final phone = customer['phone'] as String? ?? '';
    final balance =
        '${ShopSettings.currency}${_money(summary['outstanding_balance']).toStringAsFixed(2)}';
    final message = MessagingService.balanceReminder(
      customerName: name,
      balance: balance,
      dueDate: summary['next_due_date'] as String?,
    );
    await CustomerMessageDialog.show(
      context,
      customerName: name,
      phoneNumber: phone,
      initialMessage: message,
      metadata: {
        'source': 'kopesha_statement',
        'customerId': widget.customerId,
      },
    );
  }

  String _contactLine(Map<String, dynamic> customer) {
    final parts = [customer['phone'] as String?, customer['email'] as String?]
        .where((value) => value != null && value.isNotEmpty)
        .cast<String>()
        .toList();

    return parts.isEmpty ? 'No contact details' : parts.join(' | ');
  }

  String _risk(Map<String, dynamic> summary) {
    final overdueCount = _count(summary['overdue_count']);
    final overdueAmount = _money(summary['overdue_amount']);
    final outstanding = _money(summary['outstanding_balance']);
    final oldest = _date(summary['oldest_overdue_date'] as String?);
    final overdueDays = oldest == null
        ? 0
        : DateTime.now().difference(oldest).inDays;

    if (overdueCount >= 2 ||
        overdueAmount >= 250 ||
        overdueDays >= 7 ||
        outstanding >= 750) {
      return 'High Risk';
    }
    if (overdueCount >= 1 ||
        _count(summary['due_today_count']) > 0 ||
        outstanding >= 250) {
      return 'Watch';
    }
    return 'Healthy';
  }

  Color _riskColor(String risk) {
    switch (risk) {
      case 'High Risk':
        return AppColors.error;
      case 'Watch':
        return AppColors.warning;
      default:
        return AppColors.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final statement = _statement;
    if (statement == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: Theme.of(context).colorScheme.surface),
        body: Center(child: Text('Customer statement not found.')),
      );
    }

    final customer = statement['customer'] as Map<String, dynamic>? ?? {};
    final summary =
        statement['summary'] as Map<String, dynamic>? ??
        <String, dynamic>{'outstanding_balance': customer['balance'] ?? 0.0};
    final openCredits =
        statement['openCredits'] as List<Map<String, dynamic>>? ?? [];
    final paymentHistory =
        statement['paymentHistory'] as List<Map<String, dynamic>>? ?? [];
    final risk = _risk(summary);
    final riskColor = _riskColor(risk);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(
          customer['name'] as String? ?? 'Customer Statement',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _messageCustomer,
            icon: Icon(Icons.message_outlined),
            tooltip: 'Message customer',
          ),
          IconButton(
            onPressed: _load,
            icon: Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: Theme.of(context).colorScheme.outline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: riskColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            child: Icon(
                              Icons.person_outline_rounded,
                              color: riskColor,
                            ),
                          ),
                          SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  customer['name'] as String? ?? 'Customer',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  _contactLine(customer),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _Tag(label: risk, color: riskColor),
                        ],
                      ),
                      SizedBox(height: AppSpacing.xl),
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          _SummaryTile(
                            label: 'Outstanding',
                            value:
                                '${ShopSettings.currency}${_money(summary['outstanding_balance']).toStringAsFixed(2)}',
                            color: AppColors.warning,
                          ),
                          _SummaryTile(
                            label: 'Open Sales',
                            value: '${_count(summary['open_credit_count'])}',
                            color: AppColors.primary,
                          ),
                          _SummaryTile(
                            label: 'Due Today',
                            value:
                                '${ShopSettings.currency}${_money(summary['due_today_amount']).toStringAsFixed(2)}',
                            color: AppColors.primary,
                          ),
                          _SummaryTile(
                            label: 'Overdue',
                            value:
                                '${ShopSettings.currency}${_money(summary['overdue_amount']).toStringAsFixed(2)}',
                            color: AppColors.error,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppSpacing.xxl),
                _SectionCard(
                  title: 'Open Kopesha Sales',
                  subtitle:
                      '${openCredits.length} open sale${openCredits.length == 1 ? '' : 's'}',
                  child: openCredits.isEmpty
                      ? const _EmptyText(
                          'This customer has no open Kopesha sales right now.',
                        )
                      : Column(
                          children: openCredits
                              .map(
                                (sale) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _StatementSaleRow(
                                    saleId: sale['id'] as String? ?? '',
                                    createdAt: sale['created_at'] as String?,
                                    dueDate: sale['due_date'] as String?,
                                    totalAmount: _money(sale['total_amount']),
                                    amountPaid: _money(sale['amount_paid']),
                                    balanceDue: _money(sale['balance_due']),
                                    isOverdue: _isOverdue(
                                      sale['due_date'] as String?,
                                    ),
                                    dateLabel: _dateLabel,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
                SizedBox(height: AppSpacing.xxl),
                _SectionCard(
                  title: 'Payment History',
                  subtitle:
                      '${paymentHistory.length} payment record${paymentHistory.length == 1 ? '' : 's'}',
                  child: paymentHistory.isEmpty
                      ? const _EmptyText('No repayments recorded yet.')
                      : Column(
                          children: paymentHistory
                              .map(
                                (payment) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _PaymentHistoryRow(
                                    amount: _money(payment['amount']),
                                    receivedAt:
                                        payment['received_at'] as String?,
                                    paymentGroupId:
                                        payment['payment_group_id'] as String?,
                                    note: payment['note'] as String?,
                                    saleId: payment['sale_id'] as String?,
                                    saleDueDate:
                                        payment['sale_due_date'] as String?,
                                    cashierName:
                                        payment['cashier_name'] as String?,
                                    dateTimeLabel: _dateTimeLabel,
                                    dateLabel: _dateLabel,
                                    onPrint: () => _showPaymentReceipt(
                                      payment['payment_group_id'] as String,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return StitchCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      radius: AppRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
          ),
          SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

class _StatementSaleRow extends StatelessWidget {
  final String saleId;
  final String? createdAt;
  final String? dueDate;
  final double totalAmount;
  final double amountPaid;
  final double balanceDue;
  final bool isOverdue;
  final String Function(String?) dateLabel;

  const _StatementSaleRow({
    required this.saleId,
    required this.createdAt,
    required this.dueDate,
    required this.totalAmount,
    required this.amountPaid,
    required this.balanceDue,
    required this.isOverdue,
    required this.dateLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sale #${saleId.isEmpty ? '-' : saleId.substring(0, 8)}',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              _Tag(
                label: isOverdue ? 'Overdue' : 'Open',
                color: isOverdue ? AppColors.error : AppColors.warning,
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _MiniMeta(label: 'Created', value: dateLabel(createdAt)),
              _MiniMeta(label: 'Due', value: dateLabel(dueDate)),
              _MiniMeta(
                label: 'Total',
                value:
                    '${ShopSettings.currency}${totalAmount.toStringAsFixed(2)}',
              ),
              _MiniMeta(
                label: 'Paid',
                value:
                    '${ShopSettings.currency}${amountPaid.toStringAsFixed(2)}',
              ),
              _MiniMeta(
                label: 'Balance',
                value:
                    '${ShopSettings.currency}${balanceDue.toStringAsFixed(2)}',
                valueColor: AppColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentHistoryRow extends StatelessWidget {
  final double amount;
  final String? receivedAt;
  final String? paymentGroupId;
  final String? note;
  final String? saleId;
  final String? saleDueDate;
  final String? cashierName;
  final String Function(String?) dateTimeLabel;
  final String Function(String?) dateLabel;
  final VoidCallback onPrint;

  const _PaymentHistoryRow({
    required this.amount,
    required this.receivedAt,
    required this.paymentGroupId,
    required this.note,
    required this.saleId,
    required this.saleDueDate,
    required this.cashierName,
    required this.dateTimeLabel,
    required this.dateLabel,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${ShopSettings.currency}${amount.toStringAsFixed(2)} received',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.success,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                dateTimeLabel(receivedAt),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              IconButton(
                onPressed: paymentGroupId == null || paymentGroupId!.isEmpty
                    ? null
                    : onPrint,
                icon: Icon(Icons.receipt_long_outlined, size: 18),
                tooltip: 'Print repayment receipt',
              ),
            ],
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _MiniMeta(
                label: 'Applied Sale',
                value: saleId == null || saleId!.isEmpty
                    ? '-'
                    : '#${saleId!.substring(0, 8)}',
              ),
              _MiniMeta(label: 'Sale Due Date', value: dateLabel(saleDueDate)),
              _MiniMeta(
                label: 'Cashier',
                value: cashierName == null || cashierName!.trim().isEmpty
                    ? 'Unknown Cashier'
                    : cashierName!.trim(),
              ),
            ],
          ),
          if (note != null && note!.trim().isNotEmpty) ...[
            SizedBox(height: 10),
            Text(
              note!.trim(),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniMeta extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MiniMeta({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
        ),
        SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: valueColor ?? Theme.of(context).colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;

  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  final String message;

  const _EmptyText(this.message);

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}
