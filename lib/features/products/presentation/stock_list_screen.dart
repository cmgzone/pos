import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_app/features/app/app_shell.dart';

import '../../../core/services/sync_controller.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/expiry_utils.dart';
import '../../../core/utils/unit_utils.dart';
import '../../training/widgets/training_anchor.dart';
import '../data/product_repository.dart';

class StockListScreen extends ConsumerStatefulWidget {
  const StockListScreen({super.key});

  @override
  ConsumerState<StockListScreen> createState() => _StockListScreenState();
}

class _StockListScreenState extends ConsumerState<StockListScreen> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _stockFuture;

  @override
  void initState() {
    super.initState();
    _stockFuture = _loadStock();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadStock() {
    return ProductRepository.getStockList(search: _searchController.text);
  }

  void _refresh() {
    setState(() => _stockFuture = _loadStock());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && next != previous && mounted) {
          _refresh();
        }
      },
    );

    final isMobile = MediaQuery.sizeOf(context).width <= 700;

    return Scaffold(
      appBar: AppBar(
        leading: !Navigator.of(context).canPop() &&
                MediaQuery.of(context).size.width <= 800
            ? IconButton(
                icon: Icon(Icons.menu),
                onPressed: () => AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        title: Text('Stock List'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: Icon(Icons.refresh),
          ),
          SizedBox(width: 8),
        ],
      ),
      body: TrainingAnchor(
        id: 'stockList.workspace',
        child: Column(
          children: [
            Container(
              color: Theme.of(context).colorScheme.surface,
              padding: EdgeInsets.fromLTRB(
                isMobile ? 16 : 24,
                0,
                isMobile ? 16 : 24,
                16,
              ),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _refresh(),
                onChanged: (_) => _refresh(),
                decoration: InputDecoration(
                  hintText: 'Search product, SKU, barcode, or batch...',
                  prefixIcon: Icon(Icons.search),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _refresh();
                          },
                        ),
                ),
              ),
            ),
            Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _stockFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }

                  final rows = snapshot.data ?? [];
                  if (rows.isEmpty) {
                    return Center(
                      child: Text(
                        'No tracked stock found.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: EdgeInsets.all(isMobile ? 12 : 20),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _StockListCard(row: rows[index], isMobile: isMobile),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockListCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool isMobile;

  const _StockListCard({required this.row, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final stockUnit = UnitUtils.normalize(row['stock_unit'] as String?);
    final productStock = (row['product_stock'] as num? ?? 0).toDouble();
    final lowStock = (row['low_stock'] as num? ?? 0).toDouble();
    final remaining = (row['quantity_remaining'] as num?)?.toDouble();
    final unitCost =
        (row['unit_cost'] as num? ?? row['product_cost'] as num? ?? 0)
            .toDouble();
    final hasBatch = row['batch_id'] != null;
    final expiryStatus = ExpiryUtils.statusFor(row['expiry_date']);
    final status = _stockStatus(productStock, lowStock, expiryStatus);
    final statusColor = _statusColor(status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _titleRow(context, status, statusColor),
                SizedBox(height: 10),
                _infoWrap(
                  context,
                  stockUnit,
                  productStock,
                  remaining,
                  unitCost,
                  hasBatch,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(flex: 3, child: _titleBlock(context, status, statusColor)),
                SizedBox(width: 18),
                Expanded(
                  flex: 5,
                  child: _infoWrap(
                    context,
                    stockUnit,
                    productStock,
                    remaining,
                    unitCost,
                    hasBatch,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _titleRow(BuildContext context, String status, Color statusColor) {
    return Row(
      children: [
        Expanded(child: _titleBlock(context, status, statusColor)),
        _StatusPill(label: status, color: statusColor),
      ],
    );
  }

  Widget _titleBlock(BuildContext context, String status, Color statusColor) {
    final sku = (row['sku'] as String?)?.trim();
    final barcode = (row['barcode'] as String?)?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                row['product_name'] as String? ?? 'Product',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (!isMobile) _StatusPill(label: status, color: statusColor),
          ],
        ),
        SizedBox(height: 4),
        Text(
          [
            if (sku != null && sku.isNotEmpty) 'SKU: $sku',
            if (barcode != null && barcode.isNotEmpty) 'Barcode: $barcode',
          ].join('  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
        ),
      ],
    );
  }

  Widget _infoWrap(
    BuildContext context,
    String stockUnit,
    double productStock,
    double? remaining,
    double unitCost,
    bool hasBatch,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StockInfoChip(
          icon: Icons.inventory_2_outlined,
          label: 'Stock',
          value: UnitUtils.formatWithUnit(productStock, stockUnit),
          color: AppColors.primaryLight,
        ),
        if (hasBatch)
          _StockInfoChip(
            icon: Icons.numbers_outlined,
            label: 'Batch',
            value: ((row['batch_number'] as String?)?.trim().isNotEmpty == true)
                ? row['batch_number'] as String
                : 'No batch',
            color: Theme.of(context).colorScheme.secondary,
          ),
        if (hasBatch)
          _StockInfoChip(
            icon: Icons.layers_outlined,
            label: 'Batch Qty',
            value: UnitUtils.formatWithUnit(remaining ?? 0, stockUnit),
            color: AppColors.success,
          ),
        _StockInfoChip(
          icon: Icons.event_outlined,
          label: 'Expiry',
          value: ExpiryUtils.format(row['expiry_date']),
          color: _expiryColor(context, row['expiry_date']),
        ),
        _StockInfoChip(
          icon: Icons.local_shipping_outlined,
          label: 'Supplier',
          value: (row['supplier_name'] as String?)?.trim().isNotEmpty == true
              ? row['supplier_name'] as String
              : 'Unknown',
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        _StockInfoChip(
          icon: Icons.payments_outlined,
          label: 'Cost',
          value:
              '${ShopSettings.currency}${unitCost.toStringAsFixed(2)}/${UnitUtils.label(stockUnit)}',
          color: AppColors.warning,
        ),
      ],
    );
  }

  String _stockStatus(
    double productStock,
    double lowStock,
    ExpiryStatus expiryStatus,
  ) {
    if (productStock <= 0) {
      return 'Out';
    }
    if (expiryStatus == ExpiryStatus.expired) {
      return 'Expired';
    }
    if (expiryStatus == ExpiryStatus.expiringSoon) {
      return 'Expiring';
    }
    if (productStock <= lowStock) {
      return 'Low';
    }
    return 'OK';
  }

  Color _statusColor(String status) {
    return switch (status) {
      'Out' || 'Expired' => AppColors.error,
      'Expiring' || 'Low' => AppColors.warning,
      _ => AppColors.success,
    };
  }

  Color _expiryColor(BuildContext context, Object? value) {
    return switch (ExpiryUtils.statusFor(value)) {
      ExpiryStatus.expired => AppColors.error,
      ExpiryStatus.expiringSoon => AppColors.warning,
      ExpiryStatus.ok => AppColors.success,
      ExpiryStatus.unknown => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }
}

class _StockInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StockInfoChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              '$label: $value',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
