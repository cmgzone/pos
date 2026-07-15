import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/utils/expiry_utils.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../widgets/overlay_notice.dart';
import '../data/serial_number_repository.dart';

class ProductBatchesScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> product;
  const ProductBatchesScreen({super.key, required this.product});

  @override
  ConsumerState<ProductBatchesScreen> createState() =>
      _ProductBatchesScreenState();
}

class _ProductBatchesScreenState extends ConsumerState<ProductBatchesScreen> {
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
        p.supplier_name,
        COALESCE((
          SELECT COUNT(*)
          FROM product_serials ps
          WHERE ps.stock_batch_id = sb.id
            AND ps.deleted_at IS NULL
        ), 0) AS serial_count,
        COALESCE((
          SELECT COUNT(*)
          FROM product_serials ps
          WHERE ps.stock_batch_id = sb.id
            AND ps.status = 'available'
            AND ps.deleted_at IS NULL
        ), 0) AS available_serial_count
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
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && next != previous && mounted) {
          _loadBatches();
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.product['name']} - Stock Batches'),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_batches.isEmpty) {
      return Center(child: Text('No stock batches found.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _batches.length,
      separatorBuilder: (_, _) => SizedBox(height: 12),
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
          ExpiryStatus.unknown => Theme.of(
            context,
          ).colorScheme.onSurfaceVariant,
        };
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? AppColors.primary : ctx.appBorder,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.success.withValues(alpha: 0.1)
                      : Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inventory_2,
                  color: isActive
                      ? AppColors.success
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(width: 16),
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
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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
                    SizedBox(height: 4),
                    if ((b['batch_number'] as String?)?.trim().isNotEmpty ==
                        true)
                      Text(
                        'Batch No: ${b['batch_number']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      'Received: ${_formatDate(b['received_at'])}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if ((b['invoice_number'] as String?)?.trim().isNotEmpty ==
                        true)
                      Text(
                        'Invoice: ${b['invoice_number']}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (!isActive && b['finished_at'] != null)
                      Text(
                        'Finished: ${_formatDate(b['finished_at'])}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Cost: ${ShopSettings.currency}${unitCost.toStringAsFixed(2)}/${UnitUtils.label(unit)}',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _showAddSerialsDialog(b),
                    icon: Icon(Icons.qr_code_2_outlined, size: 18),
                    label: Text(
                      '${(b['available_serial_count'] as num? ?? 0).toInt()}/${(b['serial_count'] as num? ?? 0).toInt()} serials',
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

  Future<void> _showAddSerialsDialog(Map<String, dynamic> batch) async {
    final serialsController = TextEditingController();
    final noteController = TextEditingController();
    DateTime? warrantyDate;
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Add Serials'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.sizeOf(context).height * 0.68,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Paste or scan one serial number per line for ${_batchTitle(batch, true)}.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: serialsController,
                    minLines: 5,
                    maxLines: 9,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Serial numbers',
                      hintText: 'IMEI001\nIMEI002\nIMEI003',
                      prefixIcon: Icon(Icons.qr_code_scanner_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.verified_outlined),
                    title: Text('Warranty expiry'),
                    subtitle: Text(
                      warrantyDate == null
                          ? 'Optional'
                          : _formatDate(warrantyDate!.toIso8601String()),
                    ),
                    trailing: Wrap(
                      children: [
                        if (warrantyDate != null)
                          IconButton(
                            tooltip: 'Clear warranty date',
                            onPressed: () =>
                                setDialogState(() => warrantyDate = null),
                            icon: Icon(Icons.close),
                          ),
                        IconButton(
                          tooltip: 'Pick warranty date',
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  warrantyDate ??
                                  DateTime.now().add(const Duration(days: 365)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() => warrantyDate = picked);
                            }
                          },
                          icon: Icon(Icons.calendar_month_outlined),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: InputDecoration(
                      labelText: 'Note',
                      prefixIcon: Icon(Icons.notes_outlined),
                      border: OutlineInputBorder(),
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
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        final values = serialsController.text
                            .split(RegExp(r'[\n,;]+'))
                            .map((value) => value.trim())
                            .where((value) => value.isNotEmpty)
                            .toList();
                        final count = await SerialNumberRepository.createMany(
                          productId: widget.product['id'] as String,
                          stockBatchId: batch['id'] as String?,
                          purchaseId: batch['purchase_id'] as String?,
                          serialNumbers: values,
                          warrantyExpiresAt: warrantyDate?.toIso8601String(),
                          note: noteController.text,
                        );
                        if (context.mounted) {
                          AppOverlayNotice.showSnackBar(
                            context,
                            SnackBar(
                              content: Text('$count serial number(s) added'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                          Navigator.pop(ctx, true);
                        }
                      } catch (error) {
                        if (context.mounted) {
                          AppOverlayNotice.showSnackBar(
                            context,
                            SnackBar(
                              content: Text(error.toString()),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              child: saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Save Serials'),
            ),
          ],
        ),
      ),
    );

    serialsController.dispose();
    noteController.dispose();

    if (saved == true) {
      await _loadBatches();
    }
  }
}
