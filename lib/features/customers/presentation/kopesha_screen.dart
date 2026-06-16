import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/features/app/app_shell.dart';

import '../../../core/services/messaging_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/session_service.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/error_messages.dart';
import '../../training/widgets/training_anchor.dart';
import '../data/customer_repository.dart';
import 'customer_account_screen.dart';
import 'customer_kopesha_detail_screen.dart';
import 'customer_message_dialog.dart';
import '../../sales/presentation/receipt_service.dart';

class KopeshaScreen extends ConsumerStatefulWidget {
  const KopeshaScreen({super.key});

  @override
  ConsumerState<KopeshaScreen> createState() => _KopeshaScreenState();
}

class _KopeshaScreenState extends ConsumerState<KopeshaScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final rows = await CustomerRepository.getKopeshaCustomers(
      query: _searchController.text,
      filter: _filter,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _customers = rows;
      _isLoading = false;
    });
  }

  double _money(dynamic v) => (v as num?)?.toDouble() ?? 0;
  int _count(dynamic v) => (v as num?)?.toInt() ?? 0;

  DateTime? _date(String? raw) =>
      raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);

  bool _isPastDue(String? raw) {
    final d = _date(raw);
    if (d == null) {
      return false;
    }
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    return d.isBefore(today);
  }

  String _shortDate(String? raw) {
    final d = _date(raw);
    if (d == null) {
      return 'No due date';
    }
    return '${d.month}/${d.day}/${d.year}';
  }

  String _risk(Map<String, dynamic> c) {
    final overdueCount = _count(c['overdue_count']);
    final overdueAmount = _money(c['overdue_amount']);
    final outstanding = _money(c['outstanding_balance']);
    final oldest = _date(c['oldest_overdue_date'] as String?);
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
        _count(c['due_today_count']) > 0 ||
        outstanding >= 250) {
      return 'Watch';
    }
    return 'Healthy';
  }

  Color _riskColor(Map<String, dynamic> c) {
    final label = _risk(c);
    if (label == 'High Risk') {
      return AppColors.error;
    }
    if (label == 'Watch') {
      return AppColors.warning;
    }
    return AppColors.success;
  }

  Future<void> _recordPayment(Map<String, dynamic> customer) async {
    final outstanding = _money(
      customer['outstanding_balance'] ?? customer['balance'],
    );
    final amountController = TextEditingController(
      text: outstanding.toStringAsFixed(2),
    );
    final noteController = TextEditingController();
    bool saving = false;
    String? paymentGroupId;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Record Payment: ${customer['name']}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Outstanding: ${ShopSettings.currency}${outstanding.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ChipButton(
                      label: '25%',
                      onTap: () => amountController.text = (outstanding * 0.25)
                          .toStringAsFixed(2),
                    ),
                    _ChipButton(
                      label: '50%',
                      onTap: () => amountController.text = (outstanding * 0.50)
                          .toStringAsFixed(2),
                    ),
                    _ChipButton(
                      label: 'Full',
                      onTap: () => amountController.text = outstanding
                          .toStringAsFixed(2),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount received',
                    prefixText: '${ShopSettings.currency} ',
                    prefixStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: 'Note (optional)',
                    prefixIcon: Icon(Icons.notes_outlined),
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
            ElevatedButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final amount = double.tryParse(
                        amountController.text.trim(),
                      );
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter a valid payment amount'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        paymentGroupId = await CustomerRepository.recordPayment(
                          customerId: customer['id'] as String,
                          amount: amount,
                          userId: SessionService.currentUserId.isNotEmpty
                              ? SessionService.currentUserId
                              : 'admin',
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
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.check_circle_outline, size: 18),
              label: Text('Save Payment'),
            ),
          ],
        ),
      ),
    );

    amountController.dispose();
    noteController.dispose();

    if (saved == true && mounted) {
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kopesha payment recorded'),
          backgroundColor: AppColors.success,
        ),
      );
      if (paymentGroupId != null) {
        await _showRepaymentReceipt(paymentGroupId!);
      }
    }
  }

  Future<void> _showRepaymentReceipt(String paymentGroupId) async {
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

  Future<void> _openCreateAccountScreen() async {
    final created = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const CustomerAccountScreen()),
    );

    if (created == null || !mounted) {
      return;
    }

    _searchController.clear();
    _filter = 'all';
    await _load();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${created['name']} account created'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _openStatement(Map<String, dynamic> customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            CustomerKopeshaDetailScreen(customerId: customer['id'] as String),
      ),
    );

    if (!mounted) {
      return;
    }
    await _load();
  }

  Future<void> _messageCustomer(Map<String, dynamic> customer) async {
    final name = customer['name'] as String? ?? 'Customer';
    final phone = customer['phone'] as String? ?? '';
    final balance =
        '${ShopSettings.currency}${_money(customer['outstanding_balance']).toStringAsFixed(2)}';
    final message = MessagingService.balanceReminder(
      customerName: name,
      balance: balance,
      dueDate: customer['next_due_date'] as String?,
    );
    await CustomerMessageDialog.show(
      context,
      customerName: name,
      phoneNumber: phone,
      initialMessage: message,
      metadata: {'source': 'kopesha_list', 'customerId': customer['id']},
    );
  }

  String _contactLine(Map<String, dynamic> customer) {
    final parts = [
      customer['phone'] as String?,
      customer['email'] as String?,
    ].where((value) => value != null && value.isNotEmpty).cast<String>();

    final contact = parts.join(' | ');
    return contact.ifEmpty('No contact details');
  }

  Widget _stat(String label, String value, Color color) {
    return Container(
      constraints: const BoxConstraints(minWidth: 138),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11),
          ),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(bool isMobile) {
    final filters = [
      _filterButton('All Open', 'all'),
      _filterButton('Due Today', 'due_today'),
      _filterButton('Overdue', 'overdue'),
      _filterButton('Risky', 'risky'),
    ];

    if (!isMobile) {
      return Wrap(spacing: 10, runSpacing: 10, children: filters);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < filters.length; i++) ...[
            if (i > 0) SizedBox(width: 8),
            filters[i],
          ],
        ],
      ),
    );
  }

  Widget _statsSummary({
    required bool isMobile,
    required double outstanding,
    required int dueToday,
    required int overdue,
    required int risky,
  }) {
    if (!isMobile) {
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          _stat(
            'Outstanding',
            '${ShopSettings.currency}${outstanding.toStringAsFixed(2)}',
            AppColors.warning,
          ),
          _stat('Due Today', '$dueToday customers', AppColors.primary),
          _stat('Overdue', '$overdue customers', AppColors.error),
          _stat('High Risk', '$risky customers', AppColors.error),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Outstanding',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${ShopSettings.currency}${outstanding.toStringAsFixed(2)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.warning,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.warning,
                  size: 22,
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _CompactStat(
                  label: 'Due Today',
                  value: '$dueToday',
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _CompactStat(
                  label: 'Overdue',
                  value: '$overdue',
                  color: AppColors.error,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _CompactStat(
                  label: 'Risky',
                  value: '$risky',
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterButton(String label, String value) {
    final selected = _filter == value;
    return InkWell(
      onTap: () {
        _filter = value;
        _load();
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.16)
              : context.appSurfaceHighlight,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primaryLight : context.appBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primaryLight : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _customerCard(Map<String, dynamic> c, bool isMobile) {
    final risk = _risk(c);
    final riskColor = _riskColor(c);
    final overdueCount = _count(c['overdue_count']);
    final dueTodayCount = _count(c['due_today_count']);

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(isMobile ? 16 : 18),
        border: Border.all(
          color: overdueCount > 0
              ? AppColors.error.withValues(alpha: 0.45)
              : context.appBorder,
        ),
      ),
      child: isMobile
          ? _mobileCustomerCard(c, risk, riskColor, overdueCount, dueTodayCount)
          : _desktopCustomerCard(
              c,
              risk,
              riskColor,
              overdueCount,
              dueTodayCount,
            ),
    );
  }

  Widget _mobileCustomerCard(
    Map<String, dynamic> c,
    String risk,
    Color riskColor,
    int overdueCount,
    int dueTodayCount,
  ) {
    final nextDue = c['next_due_date'] as String?;
    final pastDue = _isPastDue(nextDue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                overdueCount > 0
                    ? Icons.warning_amber_rounded
                    : Icons.person_outline_rounded,
                color: riskColor,
                size: 22,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c['name'] as String? ?? 'Customer',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _contactLine(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            _RiskBadge(label: risk, color: riskColor),
          ],
        ),
        SizedBox(height: 14),
        Text(
          'Outstanding',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 3),
        Text(
          '${ShopSettings.currency}${_money(c['outstanding_balance']).toStringAsFixed(2)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            color: AppColors.warning,
          ),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Icon(
              pastDue ? Icons.event_busy_outlined : Icons.event_available,
              size: 16,
              color: pastDue ? AppColors.error : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Next due: ${_shortDate(nextDue)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: pastDue ? AppColors.error : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: pastDue ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (dueTodayCount > 0 || overdueCount > 0) ...[
          SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (dueTodayCount > 0)
                const _RiskBadge(label: 'Due Today', color: AppColors.primary),
              if (overdueCount > 0)
                _RiskBadge(
                  label: '$overdueCount Overdue',
                  color: AppColors.error,
                ),
            ],
          ),
        ],
        SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: _MetricPill(
                    icon: Icons.receipt_long_outlined,
                    label: 'Open',
                    value: '${_count(c['open_credit_count'])}',
                    color: AppColors.primaryLight,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _MetricPill(
                    icon: Icons.report_problem_outlined,
                    label: 'Overdue',
                    value:
                        '${ShopSettings.currency}${_money(c['overdue_amount']).toStringAsFixed(2)}',
                    color: AppColors.error,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _MetricPill(
                    icon: Icons.today_outlined,
                    label: 'Today',
                    value:
                        '${ShopSettings.currency}${_money(c['due_today_amount']).toStringAsFixed(2)}',
                    color: AppColors.warning,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _MetricPill(
                    icon: Icons.trending_up_outlined,
                    label: 'Risk',
                    value: risk,
                    color: riskColor,
                  ),
                ),
              ],
            );
          },
        ),
        SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _recordPayment(c),
            icon: Icon(Icons.payments_rounded, size: 18),
            label: Text('Record Payment'),
          ),
        ),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openStatement(c),
                icon: Icon(Icons.visibility_outlined, size: 18),
                label: Text('Statement'),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _messageCustomer(c),
                icon: Icon(Icons.message_outlined, size: 18),
                label: Text('Message'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _desktopCustomerCard(
    Map<String, dynamic> c,
    String risk,
    Color riskColor,
    int overdueCount,
    int dueTodayCount,
  ) {
    final nextDue = c['next_due_date'] as String?;
    final pastDue = _isPastDue(nextDue);

    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                overdueCount > 0
                    ? Icons.warning_amber_rounded
                    : Icons.person_outline_rounded,
                color: riskColor,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c['name'] as String? ?? 'Customer',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    _contactLine(c),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _RiskBadge(label: risk, color: riskColor),
                      if (dueTodayCount > 0)
                        const _RiskBadge(
                          label: 'Due Today',
                          color: AppColors.primary,
                        ),
                      if (overdueCount > 0)
                        _RiskBadge(
                          label: '$overdueCount Overdue',
                          color: AppColors.error,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${ShopSettings.currency}${_money(c['outstanding_balance']).toStringAsFixed(2)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.warning,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Next due: ${_shortDate(nextDue)}',
                  style: TextStyle(
                    color: pastDue ? AppColors.error : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: pastDue ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _Info(
                label: 'Open Sales',
                value: '${_count(c['open_credit_count'])}',
              ),
            ),
            Expanded(
              child: _Info(
                label: 'Overdue Amount',
                value:
                    '${ShopSettings.currency}${_money(c['overdue_amount']).toStringAsFixed(2)}',
              ),
            ),
            Expanded(
              child: _Info(
                label: 'Due Today',
                value:
                    '${ShopSettings.currency}${_money(c['due_today_amount']).toStringAsFixed(2)}',
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openStatement(c),
                icon: Icon(Icons.visibility_outlined, size: 18),
                label: Text('View Statement'),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _messageCustomer(c),
                icon: Icon(Icons.message_outlined, size: 18),
                label: Text('Message'),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _recordPayment(c),
                icon: Icon(Icons.payments_rounded, size: 18),
                label: Text('Record Payment'),
              ),
            ),
          ],
        ),
      ],
    );
  }

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

    final outstanding = _customers.fold<double>(
      0.0,
      (sum, c) => sum + _money(c['outstanding_balance']),
    );
    final dueToday = _customers
        .where((c) => _count(c['due_today_count']) > 0)
        .length;
    final overdue = _customers
        .where((c) => _count(c['overdue_count']) > 0)
        .length;
    final risky = _customers.where((c) => _risk(c) == 'High Risk').length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth <= 640;
        final horizontalPadding = isMobile ? 14.0 : 24.0;

        return Scaffold(
          appBar: AppBar(
            leading: !Navigator.of(context).canPop() &&
                    MediaQuery.of(context).size.width <= 800
                ? IconButton(
                    icon: Icon(Icons.menu),
                    onPressed: () => AppShell.scaffoldKey.currentState?.openDrawer(),
                  )
                : null,
            title: Text('Kopesha'),
            actions: [
              if (!isMobile) ...[
                TrainingAnchor(
                  id: 'kopesha.createAccount',
                  child: FilledButton.icon(
                    onPressed: _openCreateAccountScreen,
                    icon: Icon(Icons.person_add_alt_1, size: 18),
                    label: Text('Create Account'),
                  ),
                ),
                SizedBox(width: 8),
              ],
              IconButton(
                onPressed: _load,
                icon: Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
              SizedBox(width: isMobile ? 4 : 12),
            ],
          ),
          floatingActionButton: isMobile
              ? TrainingAnchor(
                  id: 'kopesha.createAccount',
                  child: FloatingActionButton.extended(
                    onPressed: _openCreateAccountScreen,
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    icon: Icon(Icons.person_add_alt_1),
                    label: Text('New Account'),
                  ),
                )
              : null,
          body: Column(
            children: [
              TrainingAnchor(
                id: 'kopesha.search',
                child: Container(
                  color: Theme.of(context).colorScheme.surface,
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    isMobile ? 14 : 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => _load(),
                        decoration: InputDecoration(
                          hintText: isMobile
                              ? 'Search customers...'
                              : 'Search customer name, phone, or email...',
                          prefixIcon: Icon(
                            Icons.search,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    _load();
                                  },
                                  icon: Icon(Icons.clear, size: 18),
                                ),
                        ),
                      ),
                      SizedBox(height: isMobile ? 12 : 14),
                      _filterBar(isMobile),
                      SizedBox(height: isMobile ? 14 : 16),
                      TrainingAnchor(
                        id: 'kopesha.stats',
                        child: _statsSummary(
                          isMobile: isMobile,
                          outstanding: outstanding,
                          dueToday: dueToday,
                          overdue: overdue,
                          risky: risky,
                        ),
                      ),
                      if (!isMobile) ...[
                        SizedBox(height: 10),
                        Text(
                          'Risk flag: 2+ overdue sales, overdue amount above ${ShopSettings.currency}250, overdue for 7+ days, or balance above ${ShopSettings.currency}750.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.9,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Divider(height: 1),
              Expanded(
                child: TrainingAnchor(
                  id: 'kopesha.list',
                  child: _isLoading
                      ? Center(child: CircularProgressIndicator())
                      : _customers.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No customers match this Kopesha filter right now.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.9,
                                ),
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            isMobile ? 12 : 24,
                            horizontalPadding,
                            isMobile ? 92 : 24,
                          ),
                          itemCount: _customers.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(height: isMobile ? 10 : 12),
                          itemBuilder: (context, index) =>
                              _customerCard(_customers[index], isMobile),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Info extends StatelessWidget {
  final String label;
  final String value;
  const _Info({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
        ),
        SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _CompactStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _CompactStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color.withValues(alpha: 0.78),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.78),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RiskBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _RiskBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
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

class _ChipButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ChipButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
