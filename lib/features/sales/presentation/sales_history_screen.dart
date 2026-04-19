import 'package:flutter/material.dart';
import '../../../core/services/session_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/utils/unit_utils.dart';
import '../data/sale_repository.dart';
import 'receipt_service.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List<Map<String, dynamic>> _sales = [];
  bool _isLoading = true;
  String _selectedFilter = 'today';

  bool get _isCashierView =>
      RolePermissions.normalizeRole(SessionService.currentUserRole) ==
      RolePermissions.cashier;

  String? get _cashierFilterId {
    final userId = SessionService.currentUserId.trim();
    if (!_isCashierView) {
      return null;
    }
    return userId.isEmpty ? '__missing_cashier__' : userId;
  }

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => _isLoading = true);

    String? startDate;
    String? endDate;
    final now = DateTime.now();

    switch (_selectedFilter) {
      case 'today':
        startDate = DateTime(now.year, now.month, now.day).toIso8601String();
        endDate = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
        ).toIso8601String();
        break;
      case 'week':
        startDate = now.subtract(const Duration(days: 7)).toIso8601String();
        endDate = now.toIso8601String();
        break;
      case 'month':
        startDate = DateTime(now.year, now.month, 1).toIso8601String();
        endDate = now.toIso8601String();
        break;
      case 'all':
        break;
    }

    _sales = await SaleRepository.getAll(
      startDate: startDate,
      endDate: endDate,
      cashierId: _cashierFilterId,
    );
    setState(() => _isLoading = false);
  }

  bool _canRefund(Map<String, dynamic> sale) {
    final paymentType = (sale['payment_type'] as String? ?? 'cash')
        .toLowerCase();
    final total = (sale['total_amount'] as num? ?? 0).toDouble().abs();
    final refunded = (sale['refunded_amount'] as num? ?? 0).toDouble();
    return RolePermissions.canRefundSales(SessionService.currentUserRole) &&
        !paymentType.startsWith('refund') &&
        refunded + 0.009 < total;
  }

  @override
  Widget build(BuildContext context) {
    final totalRevenue = _sales.fold<double>(
      0.0,
      (sum, s) => sum + (s['total_amount'] as num? ?? 0).toDouble(),
    );
    final totalTax = _sales.fold<double>(
      0.0,
      (sum, s) => sum + (s['tax'] as num? ?? 0).toDouble(),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(_isCashierView ? 'My Sales History' : 'Sales History'),
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatCard(
                  icon: Icons.receipt_long,
                  label: 'Total Sales',
                  value: '${_sales.length}',
                  color: AppColors.primary,
                ),
                _StatCard(
                  icon: Icons.attach_money,
                  label: 'Revenue',
                  value:
                      '${ShopSettings.currency}${totalRevenue.toStringAsFixed(2)}',
                  color: AppColors.success,
                ),
                _StatCard(
                  icon: Icons.account_balance,
                  label: 'Tax Collected',
                  value:
                      '${ShopSettings.currency}${totalTax.toStringAsFixed(2)}',
                  color: AppColors.warning,
                ),

                // Filter chips
                Container(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    children: [
                      _FilterChip(
                        label: 'Today',
                        isSelected: _selectedFilter == 'today',
                        onTap: () {
                          _selectedFilter = 'today';
                          _loadSales();
                        },
                      ),
                      _FilterChip(
                        label: 'Week',
                        isSelected: _selectedFilter == 'week',
                        onTap: () {
                          _selectedFilter = 'week';
                          _loadSales();
                        },
                      ),
                      _FilterChip(
                        label: 'Month',
                        isSelected: _selectedFilter == 'month',
                        onTap: () {
                          _selectedFilter = 'month';
                          _loadSales();
                        },
                      ),
                      _FilterChip(
                        label: 'All',
                        isSelected: _selectedFilter == 'all',
                        onTap: () {
                          _selectedFilter = 'all';
                          _loadSales();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_isCashierView)
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Showing only your own sales activity.',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),

          // Sales list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _sales.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 64,
                          color: AppColors.textSecondary.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No sales found',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isCashierView
                              ? 'Your completed sales will appear here.'
                              : 'Complete a sale from the POS screen',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(24),
                    itemCount: _sales.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final sale = _sales[index];
                      return _SaleRow(
                        sale: sale,
                        onTap: () => _showSaleDetails(sale),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showSaleDetails(Map<String, dynamic> sale) async {
    final details = await SaleRepository.getSaleWithItems(sale['id'] as String);
    if (details == null || !mounted) {
      return;
    }

    final items = details['items'] as List<Map<String, dynamic>>? ?? [];
    final paymentType = (sale['payment_type'] as String? ?? 'cash')
        .toLowerCase();
    final isCash = paymentType == 'cash';
    final amountTendered = (sale['amount_tendered'] as num?)?.toDouble() ?? 0;
    final changeGiven = (sale['change_given'] as num?)?.toDouble() ?? 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.receipt, color: AppColors.primaryLight),
            const SizedBox(width: 12),
            const Text('Sale Details'),
            const Spacer(),
            Text(
              '#${(sale['id'] as String).substring(0, 8)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date & payment
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Date: ${_formatDate(sale['created_at'] as String? ?? '')}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _paymentTypeColor(sale).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _paymentTypeLabel(sale),
                      style: TextStyle(
                        color: _paymentTypeColor(sale),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if ((sale['customer_name'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                _DetailRow(
                  label: 'Customer',
                  value: sale['customer_name'] as String,
                ),
              ],
              if ((sale['cashier_name'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'Cashier',
                  value: sale['cashier_name'] as String,
                ),
              ],
              if ((sale['due_date'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'Due Date',
                  value: sale['due_date'] as String,
                  valueColor: (sale['balance_due'] as num? ?? 0) > 0
                      ? AppColors.warning
                      : null,
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              // Items
              ...items.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['product_name'] as String? ?? 'Unknown',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(
                        UnitUtils.formatWithUnit(
                          item['quantity'] as num?,
                          item['unit'] as String?,
                        ),
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 24),
                      Text(
                        '${ShopSettings.currency}${((item['unit_price'] as num) * (item['quantity'] as num)).toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              const SizedBox(height: 8),
              _DetailRow(
                label: 'Subtotal',
                value:
                    '${ShopSettings.currency}${((sale['total_amount'] as num) - (sale['tax'] as num) + (sale['discount'] as num)).toStringAsFixed(2)}',
              ),
              _DetailRow(
                label: 'Tax',
                value:
                    '${ShopSettings.currency}${(sale['tax'] as num).toStringAsFixed(2)}',
              ),
              if ((sale['discount'] as num? ?? 0) > 0)
                _DetailRow(
                  label: 'Discount',
                  value:
                      '-${ShopSettings.currency}${(sale['discount'] as num).toStringAsFixed(2)}',
                ),
              if ((sale['refunded_amount'] as num? ?? 0) > 0)
                _DetailRow(
                  label: 'Refunded',
                  value:
                      '${ShopSettings.currency}${(sale['refunded_amount'] as num).toStringAsFixed(2)}',
                  valueColor: AppColors.error,
                ),
              if ((sale['balance_due'] as num? ?? 0) > 0)
                _DetailRow(
                  label: 'Kopesha Balance',
                  value:
                      '${ShopSettings.currency}${(sale['balance_due'] as num).toStringAsFixed(2)}',
                  valueColor: AppColors.warning,
                ),
              if (isCash && amountTendered > 0) ...[
                _DetailRow(
                  label: 'Cash Received',
                  value:
                      '${ShopSettings.currency}${amountTendered.toStringAsFixed(2)}',
                ),
                _DetailRow(
                  label: 'Change Returned',
                  value:
                      '${ShopSettings.currency}${changeGiven.toStringAsFixed(2)}',
                ),
              ],
              const SizedBox(height: 8),
              _DetailRow(
                label: 'Profit',
                value:
                    '${ShopSettings.currency}${(sale['profit'] as num? ?? 0).toStringAsFixed(2)}',
                valueColor: (sale['profit'] as num? ?? 0) >= 0
                    ? AppColors.success
                    : AppColors.error,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${ShopSettings.currency}${(sale['total_amount'] as num).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          if (_canRefund(sale))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showRefundDialog(sale);
              },
              child: const Text(
                'Return',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final totalAmount = (sale['total_amount'] as num).toDouble();
              final saleTax = (sale['tax'] as num).toDouble();
              final saleDiscount = (sale['discount'] as num).toDouble();
              ReceiptService.showReceiptPreview(
                context,
                saleId: sale['id'] as String,
                total: totalAmount,
                subtotal: totalAmount - saleTax + saleDiscount,
                tax: saleTax,
                discount: saleDiscount,
                paymentType: sale['payment_type'] as String? ?? 'cash',
                items: items,
                customerName: sale['customer_name'] as String?,
                amountTendered:
                    (sale['amount_tendered'] as num?)?.toDouble() ?? 0,
                changeGiven: (sale['change_given'] as num?)?.toDouble() ?? 0,
                balanceDue: (sale['balance_due'] as num?)?.toDouble() ?? 0,
                dueDate: sale['due_date'] as String?,
                cashierName: sale['cashier_name'] as String?,
                documentDate: sale['created_at'] as String?,
                showTenderedBreakdown: isCash,
              );
            },
            child: const Text('Print'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRefundDialog(Map<String, dynamic> sale) async {
    final refundableItems = await SaleRepository.getRefundableItems(
      sale['id'] as String,
    );
    if (!mounted) {
      return;
    }
    if (refundableItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This sale has no returnable items left'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final noteController = TextEditingController();
    final quantityControllers = <String, TextEditingController>{
      for (final item in refundableItems)
        item['product_id'] as String: TextEditingController(),
    };
    bool isSaving = false;

    final refundId = await showDialog<String?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Return Items'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose the item quantities to return for sale #${(sale['id'] as String).substring(0, 8)}.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Returned stock will be restored automatically.',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: refundableItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = refundableItems[index];
                      final controller =
                          quantityControllers[item['product_id']]!;
                      final refundableQuantity =
                          (item['refundable_quantity'] as num? ?? 0).toDouble();
                      final unit = item['unit'] as String?;
                      final isCompact = MediaQuery.of(context).size.width < 560;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighlight,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: isCompact
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['product_name'] as String? ?? 'Item',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Returnable: ${UnitUtils.formatWithUnit(refundableQuantity, unit)}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Price: ${ShopSettings.currency}${(item['unit_price'] as num? ?? 0).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: controller,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Return Qty',
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['product_name'] as String? ??
                                              'Item',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Returnable: ${UnitUtils.formatWithUnit(refundableQuantity, unit)}',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          'Price: ${ShopSettings.currency}${(item['unit_price'] as num? ?? 0).toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 130,
                                    child: TextField(
                                      controller: controller,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Return Qty',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Reason / note',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        final selectedItems = <Map<String, dynamic>>[];
                        for (final item in refundableItems) {
                          final controller =
                              quantityControllers[item['product_id']]!;
                          final quantity = double.tryParse(
                            controller.text.trim(),
                          );
                          if (quantity == null || quantity <= 0) {
                            continue;
                          }
                          selectedItems.add({
                            'product_id': item['product_id'],
                            'quantity': quantity,
                          });
                        }

                        if (selectedItems.isEmpty) {
                          throw Exception(
                            'Choose at least one product to return',
                          );
                        }

                        final refundId = await SaleRepository.refundSale(
                          saleId: sale['id'] as String,
                          userId: SessionService.currentUserId.isNotEmpty
                              ? SessionService.currentUserId
                              : 'admin',
                          note: noteController.text,
                          items: selectedItems,
                        );
                        if (context.mounted) {
                          Navigator.pop(ctx, refundId);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('$e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => isSaving = false);
                      }
                    },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Refund'),
            ),
          ],
        ),
      ),
    );

    noteController.dispose();
    for (final controller in quantityControllers.values) {
      controller.dispose();
    }

    if (refundId != null && mounted) {
      await _loadSales();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sale refunded and stock restored'),
          backgroundColor: AppColors.success,
        ),
      );
      await _showRefundReceipt(refundId, sale);
    }
  }

  Future<void> _showRefundReceipt(
    String refundId,
    Map<String, dynamic> originalSale,
  ) async {
    final refundDetails = await SaleRepository.getSaleWithItems(refundId);
    if (refundDetails == null || !mounted) {
      return;
    }

    final refundTotal = (refundDetails['total_amount'] as num? ?? 0)
        .toDouble()
        .abs();
    final refundTax = (refundDetails['tax'] as num? ?? 0).toDouble().abs();
    final refundDiscount = (refundDetails['discount'] as num? ?? 0)
        .toDouble()
        .abs();

    await ReceiptService.showReceiptPreview(
      context,
      saleId: refundId,
      total: refundTotal,
      subtotal: refundTotal - refundTax + refundDiscount,
      tax: refundTax,
      discount: refundDiscount,
      paymentType: refundDetails['payment_type'] as String? ?? 'refund_cash',
      items:
          refundDetails['items'] as List<Map<String, dynamic>>? ??
          <Map<String, dynamic>>[],
      customerName: refundDetails['customer_name'] as String?,
      previewTitle: 'Refund Receipt Preview',
      documentTitle: 'Refund Receipt',
      fileNamePrefix: 'refund_receipt',
      recordLabel: 'Refund',
      referenceSaleId: originalSale['id'] as String,
      note: refundDetails['refund_note'] as String?,
      useAbsoluteAmounts: true,
      cashierName: refundDetails['cashier_name'] as String?,
      documentDate: refundDetails['created_at'] as String?,
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) {
      return iso;
    }
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _paymentTypeLabel(Map<String, dynamic> sale) {
    final type = (sale['payment_type'] as String? ?? 'cash').toLowerCase();
    if (type == 'kopesha') {
      return 'KOPESHA [CREDIT]';
    }
    if (type == 'refund_cash') {
      return 'REFUND [CASH]';
    }
    if (type == 'refund_kopesha') {
      return 'REFUND [KOPESHA]';
    }
    return type.toUpperCase();
  }

  Color _paymentTypeColor(Map<String, dynamic> sale) {
    final type = (sale['payment_type'] as String? ?? 'cash').toLowerCase();
    if (type == 'kopesha') {
      return AppColors.warning;
    }
    if (type.startsWith('refund')) {
      return AppColors.error;
    }
    return AppColors.primaryLight;
  }
}

class _SaleRow extends StatelessWidget {
  final Map<String, dynamic> sale;
  final VoidCallback onTap;
  const _SaleRow({required this.sale, required this.onTap});

  Color _badgeColor(String paymentType) {
    if (paymentType == 'kopesha') {
      return AppColors.warning;
    }
    if (paymentType.startsWith('refund')) {
      return AppColors.error;
    }
    return AppColors.primaryLight;
  }

  String _badgeLabel(String paymentType) {
    if (paymentType == 'kopesha') {
      return 'KOPESHA';
    }
    if (paymentType == 'refund_cash') {
      return 'REFUND';
    }
    if (paymentType == 'refund_kopesha') {
      return 'REFUND';
    }
    return paymentType.toUpperCase();
  }

  String _refundStateLabel(Map<String, dynamic> sale) {
    final total = (sale['total_amount'] as num? ?? 0).toDouble().abs();
    final refunded = (sale['refunded_amount'] as num? ?? 0).toDouble();
    if (refunded <= 0.009) {
      return '';
    }
    if (refunded + 0.009 >= total) {
      return 'Refunded';
    }
    return 'Partial Refund';
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = sale['created_at'] as String? ?? '';
    final dt = DateTime.tryParse(createdAt);
    final paymentType = (sale['payment_type'] as String? ?? 'cash')
        .toLowerCase();
    final isRefund = paymentType.startsWith('refund');
    final hasRefund = (sale['refund_sale_id'] as String?)?.isNotEmpty == true;
    final refundState = _refundStateLabel(sale);
    final dateStr = dt != null
        ? '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (isRefund ? AppColors.error : AppColors.success)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isRefund ? Icons.assignment_return : Icons.receipt_long,
                  color: isRefund ? AppColors.error : AppColors.success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sale #${(sale['id'] as String).substring(0, 8)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if ((sale['customer_name'] as String?)?.isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 4),
                      Text(
                        sale['customer_name'] as String,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (hasRefund) ...[
                      const SizedBox(height: 4),
                      Text(
                        refundState.isEmpty ? 'Refunded' : refundState,
                        style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _badgeColor(paymentType).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _badgeLabel(paymentType),
                  style: TextStyle(
                    color: _badgeColor(paymentType),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${ShopSettings.currency}${(sale['total_amount'] as num? ?? 0).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isRefund ? AppColors.error : AppColors.success,
                    ),
                  ),
                  Text(
                    'Profit: ${ShopSettings.currency}${(sale['profit'] as num? ?? 0).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: (sale['profit'] as num? ?? 0) >= 0
                          ? AppColors.success.withValues(alpha: 0.8)
                          : AppColors.error,
                    ),
                  ),
                  if ((sale['balance_due'] as num? ?? 0) > 0)
                    Text(
                      'Due: ${ShopSettings.currency}${(sale['balance_due'] as num).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: isSelected ? AppColors.primary : AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w500, color: valueColor),
          ),
        ],
      ),
    );
  }
}
