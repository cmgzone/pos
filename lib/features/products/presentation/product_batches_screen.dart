import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/utils/expiry_utils.dart';
import '../../../core/utils/unit_utils.dart';

class ProductBatchesScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductBatchesScreen({super.key, required this.product});

  @override
  State<ProductBatchesScreen> createState() => _ProductBatchesScreenState();
}

class _ProductBatchesScreenState extends State<ProductBatchesScreen> {
  List<Map<String, dynamic>> _batches = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    setState(() => _isLoading = true);
    final results = await DatabaseService.rawQuery(
      '''
      SELECT
        sb.*,
        p.invoice_number,
        p.supplier_name
      FROM stock_batches sb
      LEFT JOIN purchase_invoices p ON p.id = sb.purchase_id
      WHERE sb.product_id = ?
      ORDER BY
        CASE WHEN sb.quantity_remaining > 0 THEN 0 ELSE 1 END,
        CASE
          WHEN sb.expiry_date IS NULL OR TRIM(sb.expiry_date) = '' THEN 1
          ELSE 0
        END,
        date(sb.expiry_date) ASC,
        sb.received_at DESC
      ''',
      [widget.product['id']],
    );
    if (mounted) {
      setState(() {
        _batches = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.product['name']} - Stock Batches'),
        backgroundColor: AppColors.surface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_batches.isEmpty) {
      return const Center(child: Text('No stock batches found.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _batches.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (ctx, i) {
        final b = _batches[i];
        final unit = UnitUtils.stockUnitForProduct(widget.product);
        final isActive = (b['quantity_remaining'] as num? ?? 0).toDouble() > 0;
        final unitCost = (b['unit_cost'] as num).toDouble();
        final expiryStatus = ExpiryUtils.statusFor(b['expiry_date']);
        final expiryColor = switch (expiryStatus) {
          ExpiryStatus.expired => AppColors.error,
          ExpiryStatus.expiringSoon => AppColors.warning,
          ExpiryStatus.ok => AppColors.success,
          ExpiryStatus.unknown => AppColors.textSecondary,
        };
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.textSecondary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inventory_2,
                  color: isActive ? AppColors.success : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _batchTitle(b, isActive),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isActive
                                ? AppColors.primaryLight
                                : AppColors.textSecondary,
                          ),
                        ),
                        if ((b['expiry_date'] as String?)?.trim().isNotEmpty ==
                            true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: expiryColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              ExpiryUtils.statusLabel(b['expiry_date']),
                              style: TextStyle(
                                color: expiryColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if ((b['batch_number'] as String?)?.trim().isNotEmpty ==
                        true)
                      Text(
                        'Batch No: ${b['batch_number']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      'Received: ${_formatDate(b['received_at'])}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if ((b['expiry_date'] as String?)?.trim().isNotEmpty ==
                        true)
                      Text(
                        'Expiry: ${ExpiryUtils.format(b['expiry_date'])}',
                        style: TextStyle(
                          fontSize: 12,
                          color: expiryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if ((b['supplier_name'] as String?)?.trim().isNotEmpty ==
                        true)
                      Text(
                        'Supplier: ${b['supplier_name']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if ((b['invoice_number'] as String?)?.trim().isNotEmpty ==
                        true)
                      Text(
                        'Invoice: ${b['invoice_number']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if (!isActive && b['finished_at'] != null)
                      Text(
                        'Finished: ${_formatDate(b['finished_at'])}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${UnitUtils.formatQuantity(b['quantity_remaining'] as num?)} / ${UnitUtils.formatQuantity(b['quantity_received'] as num?)} ${UnitUtils.label(unit)} remaining',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cost: ${ShopSettings.currency}${unitCost.toStringAsFixed(2)}/${UnitUtils.label(unit)}',
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      return value?.toString() ?? '';
    }
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  String _batchTitle(Map<String, dynamic> batch, bool isActive) {
    final batchNumber = (batch['batch_number'] as String?)?.trim();
    if (batchNumber != null && batchNumber.isNotEmpty) {
      return isActive ? 'Batch $batchNumber' : 'Finished batch $batchNumber';
    }
    return isActive ? 'Active Batch' : 'Finished Batch';
  }
}
