import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/sync_controller.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/expiry_utils.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../widgets/compact_header_actions.dart';
import '../../training/widgets/training_anchor.dart';
import '../../../widgets/overlay_notice.dart';
import '../../products/data/product_repository.dart';
import '../data/purchase_repository.dart';
import 'supplier_statement_screen.dart';

class PurchaseManagementScreen extends ConsumerStatefulWidget {
  const PurchaseManagementScreen({super.key});

  @override
  ConsumerState<PurchaseManagementScreen> createState() =>
      _PurchaseManagementScreenState();
}

class _PurchaseManagementScreenState
    extends ConsumerState<PurchaseManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isLoading = true;
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _purchases = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final suppliers = await PurchaseRepository.getSuppliers();
    final purchases = await PurchaseRepository.getPurchases();
    if (!mounted) {
      return;
    }
    setState(() {
      _suppliers = suppliers;
      _purchases = purchases;
      _isLoading = false;
    });
  }

  Future<String?> _showAddSupplierDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final noteController = TextEditingController();
    bool isSaving = false;

    final createdId = await showDialog<String?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Create Supplier'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width < 800
                  ? MediaQuery.of(context).size.width - 32
                  : 520,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Supplier Name',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    autofocus: true,
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: phoneController,
                    decoration: InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: addressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Note',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        final supplierId =
                            await PurchaseRepository.createSupplier(
                              name: nameController.text,
                              phone: phoneController.text,
                              email: emailController.text,
                              address: addressController.text,
                              note: noteController.text,
                            );
                        if (context.mounted) {
                          Navigator.pop(ctx, supplierId);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          AppOverlayNotice.showSnackBar(
                            context,
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
                        setDialogState(() => isSaving = false);
                      }
                    },
              icon: isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.check, size: 18),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              label: Text('Save Supplier'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    addressController.dispose();
    noteController.dispose();

    if (createdId != null) {
      await _loadData();
      if (!mounted) {
        return createdId;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supplier created'),
          backgroundColor: AppColors.success,
        ),
      );
    }
    return createdId;
  }

  Future<void> _showCreatePurchaseDialog() async {
    final products = await ProductRepository.getAll();
    if (!mounted) {
      return;
    }

    if (_suppliers.isEmpty) {
      final supplierId = await _showAddSupplierDialog();
      if (supplierId == null || !mounted) {
        return;
      }
    }

    final invoiceController = TextEditingController();
    final noteController = TextEditingController();
    final lines = [_PurchaseLineDraft()];
    String? selectedSupplierId = _suppliers.isNotEmpty
        ? _suppliers.first['id'] as String?
        : null;
    bool isSaving = false;

    final purchaseId = await showDialog<String?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final productsById = {
            for (final product in products) product['id'] as String: product,
          };
          final isCompact = MediaQuery.of(context).size.width < 720;

          double totalAmount() {
            return lines.fold<double>(0.0, (sum, line) {
              final qty = double.tryParse(line.quantityController.text) ?? 0.0;
              final unitCost =
                  double.tryParse(line.unitCostController.text) ?? 0.0;
              return sum + (qty * unitCost);
            });
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text('New Purchase Invoice'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width < 800
                    ? MediaQuery.of(context).size.width - 32
                    : 760,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    isCompact
                        ? Column(
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: selectedSupplierId,
                                decoration: InputDecoration(
                                  labelText: 'Supplier',
                                  prefixIcon: Icon(Icons.store_mall_directory),
                                ),
                                items: _suppliers
                                    .map(
                                      (supplier) => DropdownMenuItem(
                                        value: supplier['id'] as String,
                                        child: Text(supplier['name'] as String),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  setDialogState(
                                    () => selectedSupplierId = value,
                                  );
                                },
                              ),
                              SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: isSaving
                                      ? null
                                      : () async {
                                          final createdId =
                                              await _showAddSupplierDialog();
                                          if (!mounted || createdId == null) {
                                            return;
                                          }
                                          setDialogState(
                                            () =>
                                                selectedSupplierId = createdId,
                                          );
                                        },
                                  icon: Icon(Icons.add, size: 18),
                                  label: Text('New Supplier'),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: selectedSupplierId,
                                  decoration: InputDecoration(
                                    labelText: 'Supplier',
                                    prefixIcon: Icon(
                                      Icons.store_mall_directory,
                                    ),
                                  ),
                                  items: _suppliers
                                      .map(
                                        (supplier) => DropdownMenuItem(
                                          value: supplier['id'] as String,
                                          child: Text(
                                            supplier['name'] as String,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setDialogState(
                                      () => selectedSupplierId = value,
                                    );
                                  },
                                ),
                              ),
                              SizedBox(width: 12),
                              OutlinedButton.icon(
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        final createdId =
                                            await _showAddSupplierDialog();
                                        if (!mounted || createdId == null) {
                                          return;
                                        }
                                        setDialogState(
                                          () => selectedSupplierId = createdId,
                                        );
                                      },
                                icon: Icon(Icons.add, size: 18),
                                label: Text('New Supplier'),
                              ),
                            ],
                          ),
                    SizedBox(height: 16),
                    isCompact
                        ? Column(
                            children: [
                              TextField(
                                controller: invoiceController,
                                decoration: InputDecoration(
                                  labelText: 'Invoice Number',
                                  prefixIcon: Icon(Icons.receipt_long_outlined),
                                ),
                              ),
                              SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  'Total: ${ShopSettings.currency}${totalAmount().toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: invoiceController,
                                  decoration: InputDecoration(
                                    labelText: 'Invoice Number',
                                    prefixIcon: Icon(
                                      Icons.receipt_long_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    'Total: ${ShopSettings.currency}${totalAmount().toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                    SizedBox(height: 16),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Invoice Note',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    SizedBox(height: 18),
                    Text(
                      'Products',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 10),
                    ...List.generate(lines.length, (index) {
                      final line = lines[index];
                      final selectedProduct = line.productId == null
                          ? null
                          : productsById[line.productId!];
                      final purchaseUnit = selectedProduct == null
                          ? UnitUtils.defaultUnit
                          : UnitUtils.purchaseUnitForProduct(selectedProduct);
                      final stockUnit = selectedProduct == null
                          ? UnitUtils.defaultUnit
                          : UnitUtils.stockUnitForProduct(selectedProduct);
                      final unitLabel = UnitUtils.label(purchaseUnit);
                      final qty =
                          double.tryParse(line.quantityController.text) ?? 0.0;
                      final unitCost =
                          double.tryParse(line.unitCostController.text) ?? 0.0;
                      final convertedQty = selectedProduct == null
                          ? qty
                          : (UnitUtils.convertQuantity(
                                  qty,
                                  purchaseUnit,
                                  stockUnit,
                                ) ??
                                qty);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: line.productId,
                                    decoration: InputDecoration(
                                      labelText: 'Product',
                                      prefixIcon: Icon(
                                        Icons.inventory_2_outlined,
                                      ),
                                    ),
                                    items: products
                                        .map(
                                          (product) => DropdownMenuItem(
                                            value: product['id'] as String,
                                            child: Text(
                                              product['name'] as String,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        line.productId = value;
                                        if (value != null) {
                                          final product = productsById[value]!;
                                          if (line.unitCostController.text
                                              .trim()
                                              .isEmpty) {
                                            line.unitCostController.text =
                                                ((product['cost'] as num?) ?? 0)
                                                    .toString();
                                          }
                                          line.quantityController.clear();
                                        }
                                      });
                                    },
                                  ),
                                ),
                                SizedBox(width: 10),
                                if (lines.length > 1)
                                  IconButton(
                                    onPressed: isSaving
                                        ? null
                                        : () {
                                            setDialogState(() {
                                              final removed = lines.removeAt(
                                                index,
                                              );
                                              removed.dispose();
                                            });
                                          },
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 12),
                            isCompact
                                ? Column(
                                    children: [
                                      TextField(
                                        controller: line.quantityController,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: InputDecoration(
                                          labelText: 'Quantity ($unitLabel)',
                                          prefixIcon: Icon(
                                            Icons.scale_outlined,
                                          ),
                                          helperText: purchaseUnit == stockUnit
                                              ? null
                                              : 'Stores as ${UnitUtils.formatQuantity(convertedQty)} ${UnitUtils.label(stockUnit)}',
                                        ),
                                        onChanged: (_) => setDialogState(() {}),
                                      ),
                                      SizedBox(height: 12),
                                      TextField(
                                        controller: line.unitCostController,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: InputDecoration(
                                          labelText: 'Unit Cost',
                                          prefixIcon: Icon(
                                            Icons.payments_outlined,
                                          ),
                                        ),
                                        onChanged: (_) => setDialogState(() {}),
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: line.quantityController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: 'Quantity ($unitLabel)',
                                            prefixIcon: Icon(
                                              Icons.scale_outlined,
                                            ),
                                            helperText:
                                                purchaseUnit == stockUnit
                                                ? null
                                                : 'Stores as ${UnitUtils.formatQuantity(convertedQty)} ${UnitUtils.label(stockUnit)}',
                                          ),
                                          onChanged: (_) =>
                                              setDialogState(() {}),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: line.unitCostController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: InputDecoration(
                                            labelText: 'Unit Cost',
                                            prefixIcon: Icon(
                                              Icons.payments_outlined,
                                            ),
                                          ),
                                          onChanged: (_) =>
                                              setDialogState(() {}),
                                        ),
                                      ),
                                    ],
                                  ),
                            SizedBox(height: 10),
                            TextField(
                              controller: line.batchNumberController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                labelText: 'Batch Number',
                                prefixIcon: Icon(Icons.numbers_outlined),
                                helperText:
                                    'Recommended for medicine and pharmacy stock.',
                              ),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                            SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 2,
                                ),
                                leading: Icon(Icons.event_outlined),
                                title: Text('Expiry Date'),
                                subtitle: Text(
                                  line.expiryDate == null
                                      ? 'Optional for this batch'
                                      : '${ExpiryUtils.format(line.expiryDate)} - ${ExpiryUtils.statusLabel(line.expiryDate)}',
                                ),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    if (line.expiryDate != null)
                                      IconButton(
                                        tooltip: 'Clear expiry date',
                                        onPressed: () => setDialogState(
                                          () => line.expiryDate = null,
                                        ),
                                        icon: Icon(
                                          Icons.close,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    IconButton(
                                      tooltip: 'Pick expiry date',
                                      onPressed: () async {
                                        final picked = await showDatePicker(
                                          context: ctx,
                                          initialDate:
                                              line.expiryDate ??
                                              DateTime.now().add(
                                                const Duration(days: 30),
                                              ),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime(2100),
                                        );
                                        if (picked != null) {
                                          setDialogState(
                                            () => line.expiryDate = picked,
                                          );
                                        }
                                      },
                                      icon: Icon(
                                        Icons.calendar_month_outlined,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'Line Total: ${ShopSettings.currency}${(qty * unitCost).toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: AppColors.primaryLight,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    OutlinedButton.icon(
                      onPressed: isSaving
                          ? null
                          : () {
                              setDialogState(() {
                                lines.add(_PurchaseLineDraft());
                              });
                            },
                      icon: Icon(Icons.add, size: 18),
                      label: Text('Add Product Line'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        try {
                          if (selectedSupplierId == null ||
                              selectedSupplierId!.isEmpty) {
                            throw Exception('Select a supplier');
                          }

                          final selectedSupplier = _suppliers.firstWhere(
                            (supplier) => supplier['id'] == selectedSupplierId,
                          );

                          final items = <Map<String, dynamic>>[];
                          for (final line in lines) {
                            if (line.productId == null) {
                              continue;
                            }

                            final quantity = double.tryParse(
                              line.quantityController.text.trim(),
                            );
                            final unitCost = double.tryParse(
                              line.unitCostController.text.trim(),
                            );
                            final product = productsById[line.productId!];
                            if (quantity == null ||
                                quantity <= 0 ||
                                unitCost == null) {
                              throw Exception(
                                'Each product line needs a valid quantity and unit cost',
                              );
                            }
                            items.add({
                              'product_id': line.productId,
                              'quantity': quantity,
                              'unit_cost': unitCost,
                              'unit': product == null
                                  ? UnitUtils.defaultUnit
                                  : UnitUtils.purchaseUnitForProduct(product),
                              'batch_number': line.batchNumberController.text,
                              'expiry_date': ExpiryUtils.toStorageString(
                                line.expiryDate,
                              ),
                            });
                          }

                          final createdPurchaseId =
                              await PurchaseRepository.createPurchase(
                                supplierId: selectedSupplierId,
                                supplierName:
                                    selectedSupplier['name'] as String?,
                                invoiceNumber: invoiceController.text,
                                note: noteController.text,
                                items: items,
                              );
                          if (context.mounted) {
                            Navigator.pop(ctx, createdPurchaseId);
                          }
                        } catch (e) {
                          if (context.mounted) {
                            AppOverlayNotice.showSnackBar(
                              context,
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
                          setDialogState(() => isSaving = false);
                        }
                      },
                icon: isSaving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.check_circle_outline, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                label: Text('Save Purchase'),
              ),
            ],
          );
        },
      ),
    );

    invoiceController.dispose();
    noteController.dispose();
    for (final line in lines) {
      line.dispose();
    }

    if (purchaseId != null) {
      await _loadData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchase saved and stock received'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _showPurchaseDetails(String purchaseId) async {
    final details = await PurchaseRepository.getPurchaseDetails(purchaseId);
    if (details == null || !mounted) {
      return;
    }

    final items = details['items'] as List<Map<String, dynamic>>? ?? [];
    final supplierId = details['supplier_id'] as String?;
    final supplier = supplierId == null
        ? null
        : _suppliers.cast<Map<String, dynamic>?>().firstWhere(
            (item) => item?['id'] == supplierId,
            orElse: () => null,
          );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          (details['invoice_number'] as String?)?.trim().isNotEmpty == true
              ? 'Purchase ${details['invoice_number']}'
              : 'Purchase Invoice',
        ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width < 800
                    ? MediaQuery.of(context).size.width - 32
                    : 620,
              ),
              child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow(
                  'Supplier',
                  details['supplier_name'] as String? ?? 'Unknown supplier',
                ),
                _detailRow(
                  'Date',
                  _friendlyDate(details['created_at'] as String?),
                ),
                if ((details['note'] as String?)?.trim().isNotEmpty == true)
                  _detailRow('Note', details['note'] as String),
                SizedBox(height: 14),
                Divider(),
                ...items.map((item) {
                  final quantity = (item['quantity_received'] as num? ?? 0)
                      .toDouble();
                  final unitCost = (item['unit_cost'] as num? ?? 0).toDouble();
                  final unit =
                      item['stock_unit'] as String? ??
                      item['product_unit'] as String?;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item['product_name'] as String? ?? 'Item',
                              ),
                            ),
                            Text(
                              UnitUtils.formatWithUnit(quantity, unit),
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            SizedBox(width: 20),
                            Text(
                              '${ShopSettings.currency}${(quantity * unitCost).toStringAsFixed(2)}',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        if ((item['batch_number'] as String?)
                                ?.trim()
                                .isNotEmpty ==
                            true)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Batch: ${item['batch_number']}',
                                  style: TextStyle(
                                    color: AppColors.primaryLight,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if ((item['expiry_date'] as String?)
                                ?.trim()
                                .isNotEmpty ==
                            true)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Expiry: ${ExpiryUtils.format(item['expiry_date'])}',
                                  style: TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                Divider(),
                SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total: ${ShopSettings.currency}${((details['total_amount'] as num? ?? 0).toDouble()).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (supplier != null)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showSupplierPaymentDialog(supplier);
              },
              icon: Icon(Icons.add_card_outlined),
              label: Text('Record Payment'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close')),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && next != previous && mounted) {
          _loadData();
        }
      },
    );

    final totalSpend = _purchases.fold<double>(
      0.0,
      (sum, purchase) =>
          sum + ((purchase['total_amount'] as num? ?? 0).toDouble()),
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        title: Text(
          'Purchases & Suppliers',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: TrainingAnchor(
            id: 'purchases.tabs',
            child: TabBar(
              controller: _tabController,
              labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              tabs: const [
                Tab(height: 40, text: 'Purchases'),
                Tab(height: 40, text: 'Suppliers'),
              ],
            ),
          ),
        ),
        actions: [
          CompactHeaderIconButton(
            onPressed: _isLoading ? null : _loadData,
            icon: Icons.refresh,
            tooltip: 'Refresh',
          ),
          SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          TrainingAnchor(
            id: 'purchases.stats',
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _PurchaseStatCard(
                    icon: Icons.receipt_long_outlined,
                    label: 'Invoices',
                    value: '${_purchases.length}',
                    color: AppColors.primary,
                  ),
                  _PurchaseStatCard(
                    icon: Icons.store_mall_directory_outlined,
                    label: 'Suppliers',
                    value: '${_suppliers.length}',
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  _PurchaseStatCard(
                    icon: Icons.payments_outlined,
                    label: 'Total Spend',
                    value:
                        '${ShopSettings.currency}${totalSpend.toStringAsFixed(2)}',
                    color: AppColors.success,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TrainingAnchor(
              id: 'purchases.list',
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [_buildPurchasesTab(), _buildSuppliersTab()],
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          final onPurchasesTab = _tabController.index == 0;
          return TrainingAnchor(
            id: 'purchases.new',
            child: FloatingActionButton.extended(
              onPressed: () async {
                if (onPurchasesTab) {
                  await _showCreatePurchaseDialog();
                } else {
                  await _showAddSupplierDialog();
                }
              },
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: Icon(
                onPurchasesTab ? Icons.add_business : Icons.person_add_alt,
              ),
              label: Text(onPurchasesTab ? 'New Purchase' : 'Add Supplier'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPurchasesTab() {
    if (_purchases.isEmpty) {
      return const _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No purchase invoices yet',
        subtitle: 'Record a supplier invoice to receive stock into inventory.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _purchases.length,
      separatorBuilder: (_, _) => SizedBox(height: 10),
      itemBuilder: (context, index) {
        final purchase = _purchases[index];
        final invoiceNumber = (purchase['invoice_number'] as String?)?.trim();
        final balanceDue = (purchase['balance_due'] as num? ?? 0).toDouble();
        final status = purchase['status'] as String? ?? 'unpaid';
        return InkWell(
          onTap: () => _showPurchaseDetails(purchase['id'] as String),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.primaryLight,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoiceNumber?.isNotEmpty == true
                            ? invoiceNumber!
                            : 'Purchase Invoice',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        purchase['supplier_name'] as String? ??
                            'Unknown supplier',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '${purchase['item_lines']} product lines',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${ShopSettings.currency}${((purchase['total_amount'] as num? ?? 0).toDouble()).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      _friendlyDate(purchase['created_at'] as String?),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    if (balanceDue > 0.009) ...[
                      SizedBox(height: 4),
                      Text(
                        'Due ${ShopSettings.currency}${balanceDue.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else ...[
                      SizedBox(height: 4),
                      Text(
                        status == 'paid' ? 'Paid' : status,
                        style: TextStyle(
                          color: AppColors.success,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuppliersTab() {
    if (_suppliers.isEmpty) {
      return const _EmptyState(
        icon: Icons.store_mall_directory_outlined,
        title: 'No suppliers yet',
        subtitle: 'Add your first supplier so purchases are linked to history.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: _suppliers.length,
      separatorBuilder: (_, _) => SizedBox(height: 10),
      itemBuilder: (context, index) {
        final supplier = _suppliers[index];
        final outstanding = (supplier['outstanding_balance'] as num? ?? 0)
            .toDouble();
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      supplier['name'] as String? ?? 'Supplier',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${ShopSettings.currency}${((supplier['total_spend'] as num? ?? 0).toDouble()).toStringAsFixed(2)} spent',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (outstanding > 0.009)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${ShopSettings.currency}${outstanding.toStringAsFixed(2)} payable',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 6),
              if ((supplier['phone'] as String?)?.trim().isNotEmpty == true)
                Text(
                  supplier['phone'] as String,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if ((supplier['email'] as String?)?.trim().isNotEmpty == true)
                Text(
                  supplier['email'] as String,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if ((supplier['address'] as String?)?.trim().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    supplier['address'] as String,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${supplier['purchase_count']} purchase invoices',
                      style: TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openSupplierStatement(supplier),
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    label: Text('Statement'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _openSupplierStatement(Map<String, dynamic> supplier) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupplierStatementScreen(supplier: supplier),
      ),
    );
  }

  Future<void> _showSupplierPaymentDialog(Map<String, dynamic> supplier) async {
    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    final noteController = TextEditingController();
    String method = 'cash';
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Pay ${supplier['name'] ?? 'Supplier'}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: ShopSettings.currency,
                  ),
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: InputDecoration(labelText: 'Payment method'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: saving
                      ? null
                      : (value) =>
                            setDialogState(() => method = value ?? 'cash'),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: referenceController,
                  decoration: InputDecoration(labelText: 'Reference'),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: 'Note'),
                ),
              ],
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
                        await PurchaseRepository.recordSupplierPayment(
                          supplierId: supplier['id'] as String,
                          amount:
                              double.tryParse(amountController.text.trim()) ??
                              0,
                          paymentMethod: method,
                          reference: referenceController.text,
                          note: noteController.text,
                        );
                        if (ctx.mounted) {
                          Navigator.pop(ctx, true);
                        }
                      } catch (error) {
                        if (context.mounted) {
                          AppOverlayNotice.showSnackBar(
                            context,
                            SnackBar(
                              content: Text(
                                AppErrorMessage.from(
                                  error,
                                  fallback:
                                      'Supplier payment could not be saved.',
                                ),
                              ),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                        setDialogState(() => saving = false);
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save Payment'),
            ),
          ],
        ),
      ),
    );

    amountController.dispose();
    referenceController.dispose();
    noteController.dispose();

    if (saved == true) {
      await _loadData();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Supplier payment recorded'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  String _friendlyDate(String? raw) {
    final parsed = DateTime.tryParse(raw ?? '');
    if (parsed == null) {
      return raw ?? '';
    }
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}

class _PurchaseLineDraft {
  String? productId;
  DateTime? expiryDate;
  final TextEditingController batchNumberController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController unitCostController = TextEditingController();

  void dispose() {
    batchNumberController.dispose();
    quantityController.dispose();
    unitCostController.dispose();
  }
}

class _PurchaseStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _PurchaseStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
