import 'package:flutter/material.dart';

import '../../../core/services/messaging_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/etims_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../app/app_shell.dart';
import '../../customers/data/customer_repository.dart';
import '../../products/data/product_repository.dart';
import '../../sales/presentation/receipt_service.dart';
import '../../services/data/service_repository.dart';
import '../data/customer_invoice_repository.dart';

class CustomerInvoicesScreen extends StatefulWidget {
  const CustomerInvoicesScreen({super.key});

  @override
  State<CustomerInvoicesScreen> createState() => _CustomerInvoicesScreenState();
}

class _CustomerInvoicesScreenState extends State<CustomerInvoicesScreen> {
  final _searchController = TextEditingController();
  String _filter = 'open';
  bool _loading = true;
  List<Map<String, dynamic>> _invoices = const [];
  Map<String, dynamic> _stats = const {};

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
    setState(() => _loading = true);
    try {
      final invoices = await CustomerInvoiceRepository.getAll(
        filter: _filter,
        query: _searchController.text,
      );
      final stats = await CustomerInvoiceRepository.getStats();
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _stats = stats;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createInvoice() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => const _InvoiceEditorDialog(),
    );
    if (id == null || !mounted) return;
    await _load();
    await _openInvoice(id);
  }

  Future<void> _openInvoice(String id) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _InvoiceDetailDialog(invoiceId: id),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () =>
                    AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        title: const Text('Invoices'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createInvoice,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Invoice'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, isMobile ? 96 : 24),
          children: [
            _InvoiceStats(stats: _stats),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search invoice, customer, phone...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final entry in const [
                    ('open', 'Open'),
                    ('overdue', 'Overdue'),
                    ('draft', 'Draft'),
                    ('sent', 'Sent'),
                    ('partial', 'Partial'),
                    ('paid', 'Paid'),
                    ('all', 'All'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(entry.$2),
                        selected: _filter == entry.$1,
                        onSelected: (_) {
                          setState(() => _filter = entry.$1);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_invoices.isEmpty)
              const _EmptyInvoices()
            else
              ..._invoices.map(
                (invoice) => _InvoiceListTile(
                  invoice: invoice,
                  onTap: () => _openInvoice(invoice['id'] as String),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceStats extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _InvoiceStats({required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final cards = [
          _StatCard(
            label: 'Open Amount',
            value:
                '${ShopSettings.currency}${((stats['open_amount'] as num?) ?? 0).toStringAsFixed(2)}',
            icon: Icons.pending_actions_rounded,
            color: AppColors.warning,
          ),
          _StatCard(
            label: 'Paid',
            value:
                '${ShopSettings.currency}${((stats['paid_amount'] as num?) ?? 0).toStringAsFixed(2)}',
            icon: Icons.check_circle_outline,
            color: AppColors.success,
          ),
          _StatCard(
            label: 'Overdue',
            value: '${(stats['overdue_count'] as num? ?? 0).toInt()}',
            icon: Icons.schedule_rounded,
            color: AppColors.error,
          ),
        ];
        if (compact) {
          return Column(
            children: cards
                .map(
                  (card) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: card,
                  ),
                )
                .toList(),
          );
        }
        return Row(
          children: cards
              .map(
                (card) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: card,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.14),
            foregroundColor: color,
            child: Icon(icon),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceListTile extends StatelessWidget {
  final Map<String, dynamic> invoice;
  final VoidCallback onTap;

  const _InvoiceListTile({required this.invoice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = (invoice['display_status'] ?? invoice['status'] ?? 'draft')
        .toString();
    final color = _statusColor(status);
    final balance = (invoice['balance_due'] as num? ?? 0).toDouble();
    final total = (invoice['total_amount'] as num? ?? 0).toDouble();
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
          child: const Icon(Icons.request_quote_outlined),
        ),
        title: Text(
          invoice['invoice_number'] as String? ?? 'Invoice',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${invoice['customer_name'] ?? 'Customer'}\n${_statusLabel(status)} - Balance ${ShopSettings.currency}${balance.toStringAsFixed(2)}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${ShopSettings.currency}${total.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              '${invoice['item_count'] ?? 0} items',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyInvoices extends StatelessWidget {
  const _EmptyInvoices();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.request_quote_outlined,
            size: 42,
            color: AppColors.primary,
          ),
          SizedBox(height: 10),
          Text(
            'No invoices yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 6),
          Text(
            'Create product or service invoices before payment, then convert them to sales once paid.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _InvoiceEditorDialog extends StatefulWidget {
  const _InvoiceEditorDialog();

  @override
  State<_InvoiceEditorDialog> createState() => _InvoiceEditorDialogState();
}

class _InvoiceEditorDialogState extends State<_InvoiceEditorDialog> {
  final _customerName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _kraPin = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _note = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _lines = <_InvoiceLineVm>[];
  String? _customerId;
  DateTime _issueDate = DateTime.now();
  DateTime? _dueDate = DateTime.now().add(const Duration(days: 7));
  String _status = CustomerInvoiceRepository.statusDraft;
  bool _saving = false;

  @override
  void dispose() {
    _customerName.dispose();
    _phone.dispose();
    _email.dispose();
    _kraPin.dispose();
    _discount.dispose();
    _note.dispose();
    super.dispose();
  }

  double get _subtotal =>
      _lines.fold<double>(0, (sum, line) => sum + line.lineTotal);
  double get _tax => _subtotal * (ShopSettings.taxRate / 100);
  double get _discountValue => double.tryParse(_discount.text) ?? 0;
  double get _total => _subtotal + _tax - _discountValue;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lines.isEmpty) {
      _showSnack('Add at least one invoice line');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await CustomerInvoiceRepository.createInvoice(
        customerId: _customerId,
        customerName: _customerName.text,
        customerPhone: _phone.text,
        customerEmail: _email.text,
        customerKraPin: _kraPin.text,
        status: _status,
        issueDate: _issueDate,
        dueDate: _dueDate,
        discount: _discountValue,
        note: _note.text,
        lines: _lines.map((line) => line.toDraft()).toList(),
      );
      if (mounted) Navigator.pop(context, id);
    } catch (error) {
      _showSnack(AppErrorMessage.from(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickCustomer() async {
    final customer = await _showCustomerPicker(context);
    if (customer == null) return;
    setState(() {
      _customerId = customer['id'] as String?;
      _customerName.text = customer['name'] as String? ?? '';
      _phone.text = customer['phone'] as String? ?? '';
      _email.text = customer['email'] as String? ?? '';
    });
  }

  Future<void> _addProduct() async {
    final product = await _showProductPicker(context);
    if (product == null) return;
    setState(() => _lines.add(_InvoiceLineVm.fromProduct(product)));
  }

  Future<void> _addService() async {
    final service = await _showServicePicker(context);
    if (service == null) return;
    setState(() => _lines.add(_InvoiceLineVm.fromService(service)));
  }

  Future<void> _addCustom() async {
    final line = await showDialog<_InvoiceLineVm>(
      context: context,
      builder: (_) => _LineEditorDialog(line: _InvoiceLineVm.custom()),
    );
    if (line != null) setState(() => _lines.add(line));
  }

  Future<void> _editLine(int index) async {
    final line = await showDialog<_InvoiceLineVm>(
      context: context,
      builder: (_) => _LineEditorDialog(line: _lines[index].copy()),
    );
    if (line != null) setState(() => _lines[index] = line);
  }

  Future<void> _pickDate({required bool due}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: due ? (_dueDate ?? DateTime.now()) : _issueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (due) {
        _dueDate = picked;
      } else {
        _issueDate = picked;
      }
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 700;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: EdgeInsets.all(isMobile ? 8 : 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 780,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.request_quote_outlined,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Create Invoice',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _customerName,
                            decoration: const InputDecoration(
                              labelText: 'Customer name',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Required'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _pickCustomer,
                          icon: const Icon(Icons.search_rounded),
                          label: const Text('Find'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _email,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _kraPin,
                            decoration: const InputDecoration(
                              labelText: 'Customer KRA PIN optional',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _status,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'draft',
                                child: Text('Draft'),
                              ),
                              DropdownMenuItem(
                                value: 'sent',
                                child: Text('Sent'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _status = value ?? 'draft'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _pickDate(due: false),
                          icon: const Icon(Icons.event_outlined),
                          label: Text('Issue: ${_shortDate(_issueDate)}'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _pickDate(due: true),
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(
                            _dueDate == null
                                ? 'Set due date'
                                : 'Due: ${_shortDate(_dueDate!)}',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _dueDate = null),
                          icon: const Icon(Icons.clear_rounded),
                          label: const Text('No due date'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Invoice Items',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'product') _addProduct();
                            if (value == 'service') _addService();
                            if (value == 'custom') _addCustom();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'product',
                              child: Text('Add product'),
                            ),
                            PopupMenuItem(
                              value: 'service',
                              child: Text('Add service'),
                            ),
                            PopupMenuItem(
                              value: 'custom',
                              child: Text('Add custom line'),
                            ),
                          ],
                          child: FilledButton.icon(
                            onPressed: null,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add Line'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_lines.isEmpty)
                      const Text(
                        'No items yet. Add a product, service, or custom charge.',
                        style: TextStyle(color: AppColors.textSecondary),
                      )
                    else
                      ..._lines.asMap().entries.map(
                        (entry) => _EditableLineTile(
                          line: entry.value,
                          onTap: () => _editLine(entry.key),
                          onDelete: () =>
                              setState(() => _lines.removeAt(entry.key)),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _discount,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Discount',
                        prefixIcon: Icon(Icons.discount_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _note,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Invoice note',
                        prefixIcon: Icon(Icons.note_alt_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _InvoiceTotals(
                      subtotal: _subtotal,
                      tax: _tax,
                      discount: _discountValue,
                      total: _total,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Save Invoice'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceDetailDialog extends StatefulWidget {
  final String invoiceId;

  const _InvoiceDetailDialog({required this.invoiceId});

  @override
  State<_InvoiceDetailDialog> createState() => _InvoiceDetailDialogState();
}

class _InvoiceDetailDialogState extends State<_InvoiceDetailDialog> {
  bool _loading = true;
  Map<String, dynamic>? _invoice;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await CustomerInvoiceRepository.getInvoiceWithItems(
      widget.invoiceId,
    );
    if (!mounted) return;
    setState(() {
      _invoice = data?['invoice'] as Map<String, dynamic>?;
      _items =
          (data?['items'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList() ??
          const [];
      _loading = false;
    });
  }

  Future<void> _previewPdf() async {
    final invoice = _invoice;
    if (invoice == null) return;
    await ReceiptService.showReceiptPreview(
      context,
      saleId: invoice['id'] as String,
      total: (invoice['total_amount'] as num? ?? 0).toDouble(),
      subtotal: (invoice['subtotal'] as num? ?? 0).toDouble(),
      tax: (invoice['tax'] as num? ?? 0).toDouble(),
      discount: (invoice['discount'] as num? ?? 0).toDouble(),
      paymentType: _statusLabel(invoice['status'] as String? ?? 'draft'),
      items: _items
          .map(
            (item) => {
              'product_name': item['description'],
              'quantity': item['quantity'],
              'unit': item['unit'],
              'unit_price': item['unit_price'],
            },
          )
          .toList(),
      customerName: invoice['customer_name'] as String?,
      balanceDue: (invoice['balance_due'] as num? ?? 0).toDouble(),
      dueDate: invoice['due_date'] as String?,
      documentDate: invoice['issue_date'] as String?,
      documentTitle: 'Customer Invoice',
      recordLabel: 'Invoice',
      previewTitle: 'Invoice Preview',
      fileNamePrefix: 'invoice',
      note: invoice['note'] as String?,
    );
  }

  Future<void> _sendInvoice() async {
    final invoice = _invoice;
    if (invoice == null) return;
    try {
      await CustomerInvoiceRepository.markSent(widget.invoiceId);
      final amount =
          '${ShopSettings.currency}${((invoice['total_amount'] as num?) ?? 0).toStringAsFixed(2)}';
      final message =
          'Hello ${invoice['customer_name']}, your invoice ${invoice['invoice_number']} for $amount is ready. Due date: ${_shortRawDate(invoice['due_date'] as String?)}.';
      final phone = (invoice['customer_phone'] as String?)?.trim() ?? '';
      final email = (invoice['customer_email'] as String?)?.trim() ?? '';
      if (phone.isNotEmpty) {
        await MessagingService.openManual(
          channel: CustomerMessageChannel.whatsapp,
          phoneNumber: phone,
          message: message,
        );
      } else if (email.isNotEmpty) {
        await MessagingService.openManual(
          channel: CustomerMessageChannel.email,
          phoneNumber: email,
          message: message,
        );
      }
      await _load();
    } catch (error) {
      _showSnack(AppErrorMessage.from(error));
    }
  }

  Future<void> _recordPayment() async {
    final result =
        await showDialog<({double amount, String method, String ref})>(
          context: context,
          builder: (_) => const _PaymentDialog(),
        );
    if (result == null) return;
    try {
      await CustomerInvoiceRepository.recordPayment(
        id: widget.invoiceId,
        amount: result.amount,
        method: result.method,
        reference: result.ref,
      );
      await _load();
    } catch (error) {
      _showSnack(AppErrorMessage.from(error));
    }
  }

  Future<void> _convertToSale() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Convert invoice to sale?'),
        content: const Text(
          'This will create a sale receipt and deduct product stock. Continue only after payment is complete.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final saleId = await CustomerInvoiceRepository.convertToSale(
        id: widget.invoiceId,
        paymentType: (_invoice?['payment_method'] as String?) ?? 'cash',
      );
      _showSnack('Created sale ${saleId.substring(0, 8)}');
      
      try {
        final etimsResult = await EtimsService.submitSaleIfEnabled(saleId);
        if (etimsResult != null) {
          if (etimsResult.status == 'submitted') {
            _showSnack('KRA eTIMS submitted: ${etimsResult.controlUnitInvoiceNumber ?? etimsResult.invoiceNumber ?? 'received'}');
          } else {
            _showSnack('KRA eTIMS: ${etimsResult.status.replaceAll('_', ' ')}');
          }
        }
      } catch (etimsError) {
        _showSnack('eTIMS Submission failed: ${etimsError.toString()}');
      }

      await _load();
    } catch (error) {
      _showSnack(AppErrorMessage.from(error));
    }
  }

  Future<void> _cancelInvoice() async {
    try {
      await CustomerInvoiceRepository.cancel(widget.invoiceId);
      await _load();
    } catch (error) {
      _showSnack(AppErrorMessage.from(error));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final invoice = _invoice;
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            : invoice == null
            ? const Padding(
                padding: EdgeInsets.all(32),
                child: Text('Invoice not found'),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.request_quote_outlined,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            invoice['invoice_number'] as String? ?? 'Invoice',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _InvoiceHeader(invoice: invoice),
                        const SizedBox(height: 16),
                        ..._items.map((item) => _InvoiceItemRow(item: item)),
                        const SizedBox(height: 16),
                        _InvoiceTotals(
                          subtotal: (invoice['subtotal'] as num? ?? 0)
                              .toDouble(),
                          tax: (invoice['tax'] as num? ?? 0).toDouble(),
                          discount: (invoice['discount'] as num? ?? 0)
                              .toDouble(),
                          total: (invoice['total_amount'] as num? ?? 0)
                              .toDouble(),
                          paid: (invoice['amount_paid'] as num? ?? 0)
                              .toDouble(),
                          balance: (invoice['balance_due'] as num? ?? 0)
                              .toDouble(),
                        ),
                        if ((invoice['note'] as String?)?.trim().isNotEmpty ==
                            true) ...[
                          const SizedBox(height: 12),
                          Text(
                            invoice['note'] as String,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _previewPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('PDF'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _sendInvoice,
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('Send'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _recordPayment,
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Payment'),
                        ),
                        FilledButton.icon(
                          onPressed: _convertToSale,
                          icon: const Icon(Icons.point_of_sale_outlined),
                          label: const Text('Convert to Sale'),
                        ),
                        TextButton.icon(
                          onPressed: _cancelInvoice,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel Invoice'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _InvoiceHeader extends StatelessWidget {
  final Map<String, dynamic> invoice;

  const _InvoiceHeader({required this.invoice});

  @override
  Widget build(BuildContext context) {
    final status = invoice['status'] as String? ?? 'draft';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invoice['customer_name'] as String? ?? 'Customer',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusPill(status: status),
            ],
          ),
          const SizedBox(height: 8),
          Text('Issue: ${_shortRawDate(invoice['issue_date'] as String?)}'),
          Text('Due: ${_shortRawDate(invoice['due_date'] as String?)}'),
          if ((invoice['customer_phone'] as String?)?.isNotEmpty == true)
            Text('Phone: ${invoice['customer_phone']}'),
          if ((invoice['customer_email'] as String?)?.isNotEmpty == true)
            Text('Email: ${invoice['customer_email']}'),
          if ((invoice['sale_id'] as String?)?.trim().isNotEmpty == true)
            Text('Sale: ${(invoice['sale_id'] as String).substring(0, 8)}'),
        ],
      ),
    );
  }
}

class _InvoiceItemRow extends StatelessWidget {
  final Map<String, dynamic> item;

  const _InvoiceItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final qty = (item['quantity'] as num? ?? 1).toDouble();
    final price = (item['unit_price'] as num? ?? 0).toDouble();
    final total = (item['line_total'] as num? ?? qty * price).toDouble();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(item['description'] as String? ?? 'Item'),
      subtitle: Text(
        '${_formatQty(qty)} ${item['unit'] ?? 'pcs'} x ${ShopSettings.currency}${price.toStringAsFixed(2)}',
      ),
      trailing: Text(
        '${ShopSettings.currency}${total.toStringAsFixed(2)}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _InvoiceTotals extends StatelessWidget {
  final double subtotal;
  final double tax;
  final double discount;
  final double total;
  final double? paid;
  final double? balance;

  const _InvoiceTotals({
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.total,
    this.paid,
    this.balance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _totalRow('Subtotal', subtotal),
          _totalRow('Tax (${ShopSettings.taxRate}%)', tax),
          if (discount > 0) _totalRow('Discount', -discount),
          const Divider(),
          _totalRow('Total', total, strong: true),
          if (paid != null) _totalRow('Paid', paid!),
          if (balance != null) _totalRow('Balance', balance!, strong: true),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontWeight: strong ? FontWeight.w800 : null),
            ),
          ),
          Text(
            '${value < 0 ? '-' : ''}${ShopSettings.currency}${value.abs().toStringAsFixed(2)}',
            style: TextStyle(fontWeight: strong ? FontWeight.w800 : null),
          ),
        ],
      ),
    );
  }
}

class _EditableLineTile extends StatelessWidget {
  final _InvoiceLineVm line;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _EditableLineTile({
    required this.line,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surfaceHighlight,
      child: ListTile(
        onTap: onTap,
        title: Text(line.description),
        subtitle: Text(
          '${_formatQty(line.quantity)} ${line.unit} x ${ShopSettings.currency}${line.unitPrice.toStringAsFixed(2)}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${ShopSettings.currency}${line.lineTotal.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineEditorDialog extends StatefulWidget {
  final _InvoiceLineVm line;

  const _LineEditorDialog({required this.line});

  @override
  State<_LineEditorDialog> createState() => _LineEditorDialogState();
}

class _LineEditorDialogState extends State<_LineEditorDialog> {
  late final TextEditingController _description;
  late final TextEditingController _quantity;
  late final TextEditingController _unit;
  late final TextEditingController _price;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _description = TextEditingController(text: widget.line.description);
    _quantity = TextEditingController(text: _formatQty(widget.line.quantity));
    _unit = TextEditingController(text: widget.line.unit);
    _price = TextEditingController(
      text: widget.line.unitPrice.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _unit.dispose();
    _price.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      widget.line.copy()
        ..description = _description.text.trim()
        ..quantity = double.tryParse(_quantity.text) ?? 1
        ..unit = _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim()
        ..unitPrice = double.tryParse(_price.text) ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invoice line'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Required' : null,
            ),
            TextFormField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            TextFormField(
              controller: _unit,
              decoration: const InputDecoration(labelText: 'Unit'),
            ),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Unit price'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog();

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  String _method = 'cash';

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record payment'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _method,
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
              DropdownMenuItem(value: 'bank', child: Text('Bank')),
            ],
            onChanged: (value) => setState(() => _method = value ?? 'cash'),
            decoration: const InputDecoration(labelText: 'Method'),
          ),
          TextField(
            controller: _reference,
            decoration: const InputDecoration(labelText: 'Reference optional'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amount.text) ?? 0;
            Navigator.pop(context, (
              amount: amount,
              method: _method,
              ref: _reference.text,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;

  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _InvoiceLineVm {
  String lineType;
  String? productId;
  String? variantId;
  String? serviceId;
  String description;
  double quantity;
  String unit;
  double unitPrice;
  double unitCost;
  double saleToStockFactor;
  String stockUnit;
  bool trackStock;

  _InvoiceLineVm({
    required this.lineType,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    this.productId,
    this.variantId,
    this.serviceId,
    this.unitCost = 0,
    this.saleToStockFactor = 1,
    this.stockUnit = 'pcs',
    this.trackStock = true,
  });

  double get lineTotal => quantity * unitPrice;

  factory _InvoiceLineVm.custom() => _InvoiceLineVm(
    lineType: 'custom',
    description: '',
    quantity: 1,
    unit: 'pcs',
    unitPrice: 0,
    trackStock: false,
  );

  factory _InvoiceLineVm.fromProduct(Map<String, dynamic> product) {
    final variantId = product['matched_variant_id'] as String?;
    final variantName = product['matched_variant_name'] as String?;
    final productName = product['name'] as String? ?? 'Product';
    return _InvoiceLineVm(
      lineType: 'product',
      productId: product['id'] as String?,
      variantId: variantId,
      description: variantId == null || variantName == null
          ? productName
          : '$productName - $variantName',
      quantity: 1,
      unit:
          product['sale_unit'] as String? ??
          product['unit'] as String? ??
          'pcs',
      unitPrice:
          (product['matched_variant_price'] as num? ??
                  product['price'] as num? ??
                  0)
              .toDouble(),
      unitCost:
          (product['matched_variant_cost'] as num? ??
                  product['cost'] as num? ??
                  0)
              .toDouble(),
      saleToStockFactor: (product['sale_to_stock_factor'] as num? ?? 1)
          .toDouble(),
      stockUnit:
          product['stock_unit'] as String? ??
          product['unit'] as String? ??
          'pcs',
      trackStock: (product['track_stock'] as num? ?? 1) != 0,
    );
  }

  factory _InvoiceLineVm.fromService(Map<String, dynamic> service) {
    return _InvoiceLineVm(
      lineType: 'service',
      serviceId: service['id'] as String?,
      description: service['name'] as String? ?? 'Service',
      quantity: 1,
      unit: 'service',
      unitPrice: (service['base_price'] as num? ?? 0).toDouble(),
      trackStock: false,
    );
  }

  _InvoiceLineVm copy() => _InvoiceLineVm(
    lineType: lineType,
    productId: productId,
    variantId: variantId,
    serviceId: serviceId,
    description: description,
    quantity: quantity,
    unit: unit,
    unitPrice: unitPrice,
    unitCost: unitCost,
    saleToStockFactor: saleToStockFactor,
    stockUnit: stockUnit,
    trackStock: trackStock,
  );

  CustomerInvoiceLineDraft toDraft() => CustomerInvoiceLineDraft(
    lineType: lineType,
    productId: productId,
    variantId: variantId,
    serviceId: serviceId,
    description: description,
    quantity: quantity,
    unit: unit,
    unitPrice: unitPrice,
    unitCost: unitCost,
    saleToStockFactor: saleToStockFactor,
    stockUnit: stockUnit,
    trackStock: trackStock,
  );
}

Future<Map<String, dynamic>?> _showCustomerPicker(BuildContext context) async {
  return _showSearchPicker(
    context,
    title: 'Find customer',
    search: CustomerRepository.search,
    label: (row) => row['name'] as String? ?? 'Customer',
    subtitle: (row) => [row['phone'], row['email']]
        .where((value) => value != null && value.toString().trim().isNotEmpty)
        .join(' - '),
  );
}

Future<Map<String, dynamic>?> _showProductPicker(BuildContext context) async {
  return _showSearchPicker(
    context,
    title: 'Add product',
    search: (query) => ProductRepository.searchForPos(query),
    label: (row) {
      final variant = row['matched_variant_name'] as String?;
      final name = row['name'] as String? ?? 'Product';
      return variant == null || variant.isEmpty ? name : '$name - $variant';
    },
    subtitle: (row) {
      final price =
          (row['matched_variant_price'] as num? ?? row['price'] as num? ?? 0)
              .toDouble();
      return '${ShopSettings.currency}${price.toStringAsFixed(2)}';
    },
  );
}

Future<Map<String, dynamic>?> _showServicePicker(BuildContext context) async {
  return _showSearchPicker(
    context,
    title: 'Add service',
    search: (query) =>
        ServiceRepository.getServices(activeOnly: true, query: query),
    label: (row) => row['name'] as String? ?? 'Service',
    subtitle: (row) =>
        '${ShopSettings.currency}${((row['base_price'] as num?) ?? 0).toStringAsFixed(2)}',
  );
}

Future<Map<String, dynamic>?> _showSearchPicker(
  BuildContext context, {
  required String title,
  required Future<List<Map<String, dynamic>>> Function(String query) search,
  required String Function(Map<String, dynamic> row) label,
  required String Function(Map<String, dynamic> row) subtitle,
}) async {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _SearchPickerDialog(
      title: title,
      search: search,
      label: label,
      subtitle: subtitle,
    ),
  );
}

class _SearchPickerDialog extends StatefulWidget {
  final String title;
  final Future<List<Map<String, dynamic>>> Function(String query) search;
  final String Function(Map<String, dynamic> row) label;
  final String Function(Map<String, dynamic> row) subtitle;

  const _SearchPickerDialog({
    required this.title,
    required this.search,
    required this.label,
    required this.subtitle,
  });

  @override
  State<_SearchPickerDialog> createState() => _SearchPickerDialogState();
}

class _SearchPickerDialogState extends State<_SearchPickerDialog> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await widget.search(_controller.text);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _rows.length,
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return ListTile(
                          title: Text(widget.label(row)),
                          subtitle: Text(widget.subtitle(row)),
                          onTap: () => Navigator.pop(context, row),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _shortRawDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Not set';
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? raw : _shortDate(parsed);
}

String _formatQty(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

Color _statusColor(String status) {
  switch (status) {
    case 'paid':
      return AppColors.success;
    case 'partial':
      return AppColors.primaryLight;
    case 'overdue':
      return AppColors.error;
    case 'cancelled':
      return AppColors.textSecondary;
    case 'sent':
      return AppColors.warning;
    default:
      return AppColors.secondary;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'paid':
      return 'Paid';
    case 'partial':
      return 'Part paid';
    case 'overdue':
      return 'Overdue';
    case 'cancelled':
      return 'Cancelled';
    case 'sent':
      return 'Sent';
    default:
      return 'Draft';
  }
}
