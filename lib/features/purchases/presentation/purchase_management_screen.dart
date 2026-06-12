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
import '../../products/data/product_repository.dart';
import '../data/purchase_repository.dart';

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
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Create Supplier'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Supplier Name',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: addressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    maxLines: 2,
                    decoration: const InputDecoration(
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
              child: const Text('Cancel'),
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
                        setDialogState(() => isSaving = false);
                      }
                    },
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              label: const Text('Save Supplier'),
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
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('New Purchase Invoice'),
            content: SizedBox(
              width: 760,
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
                                decoration: const InputDecoration(
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
                              const SizedBox(height: 12),
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
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('New Supplier'),
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: selectedSupplierId,
                                  decoration: const InputDecoration(
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
                              const SizedBox(width: 12),
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
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('New Supplier'),
                              ),
                            ],
                          ),
                    const SizedBox(height: 16),
                    isCompact
                        ? Column(
                            children: [
                              TextField(
                                controller: invoiceController,
                                decoration: const InputDecoration(
                                  labelText: 'Invoice Number',
                                  prefixIcon: Icon(Icons.receipt_long_outlined),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceHighlight,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  'Total: ${ShopSettings.currency}${totalAmount().toStringAsFixed(2)}',
                                  style: const TextStyle(
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
                                  decoration: const InputDecoration(
                                    labelText: 'Invoice Number',
                                    prefixIcon: Icon(
                                      Icons.receipt_long_outlined,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceHighlight,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    'Total: ${ShopSettings.currency}${totalAmount().toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Invoice Note',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Products',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
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
                          color: AppColors.surfaceHighlight,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: line.productId,
                                    decoration: const InputDecoration(
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
                                const SizedBox(width: 10),
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
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
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
                                          prefixIcon: const Icon(
                                            Icons.scale_outlined,
                                          ),
                                          helperText: purchaseUnit == stockUnit
                                              ? null
                                              : 'Stores as ${UnitUtils.formatQuantity(convertedQty)} ${UnitUtils.label(stockUnit)}',
                                        ),
                                        onChanged: (_) => setDialogState(() {}),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: line.unitCostController,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: const InputDecoration(
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
                                            prefixIcon: const Icon(
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
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: line.unitCostController,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          decoration: const InputDecoration(
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
                            const SizedBox(height: 10),
                            TextField(
                              controller: line.batchNumberController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Batch Number',
                                prefixIcon: Icon(Icons.numbers_outlined),
                                helperText:
                                    'Recommended for medicine and pharmacy stock.',
                              ),
                              onChanged: (_) => setDialogState(() {}),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 2,
                                ),
                                leading: const Icon(Icons.event_outlined),
                                title: const Text('Expiry Date'),
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
                                        icon: const Icon(
                                          Icons.close,
                                          color: AppColors.textSecondary,
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
                                      icon: const Icon(
                                        Icons.calendar_month_outlined,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'Line Total: ${ShopSettings.currency}${(qty * unitCost).toStringAsFixed(2)}',
                                style: const TextStyle(
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
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Product Line'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
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
                          setDialogState(() => isSaving = false);
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline, size: 18),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                label: const Text('Save Purchase'),
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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          (details['invoice_number'] as String?)?.trim().isNotEmpty == true
              ? 'Purchase ${details['invoice_number']}'
              : 'Purchase Invoice',
        ),
        content: SizedBox(
          width: 620,
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
                const SizedBox(height: 14),
                const Divider(),
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
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Text(
                              '${ShopSettings.currency}${(quantity * unitCost).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
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
                                  style: const TextStyle(
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
                                  style: const TextStyle(
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
                const Divider(),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total: ${ShopSettings.currency}${((details['total_amount'] as num? ?? 0).toDouble()).toStringAsFixed(2)}',
                    style: const TextStyle(
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
              icon: const Icon(Icons.add_card_outlined),
              label: const Text('Record Payment'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
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
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
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
        backgroundColor: AppColors.surface,
        toolbarHeight: 50,
        title: const Text(
          'Purchases & Suppliers',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: TrainingAnchor(
            id: 'purchases.tabs',
            child: TabBar(
              controller: _tabController,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
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
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          TrainingAnchor(
            id: 'purchases.stats',
            child: Container(
              color: AppColors.surface,
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
                    color: AppColors.secondary,
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
                  ? const Center(child: CircularProgressIndicator())
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
      separatorBuilder: (_, _) => const SizedBox(height: 10),
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.primaryLight,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoiceNumber?.isNotEmpty == true
                            ? invoiceNumber!
                            : 'Purchase Invoice',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        purchase['supplier_name'] as String? ??
                            'Unknown supplier',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${purchase['item_lines']} product lines',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
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
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _friendlyDate(purchase['created_at'] as String?),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (balanceDue > 0.009) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Due ${ShopSettings.currency}${balanceDue.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Text(
                        status == 'paid' ? 'Paid' : status,
                        style: const TextStyle(
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
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final supplier = _suppliers[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      supplier['name'] as String? ?? 'Supplier',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
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
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if ((supplier['phone'] as String?)?.trim().isNotEmpty == true)
                Text(
                  supplier['phone'] as String,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              if ((supplier['email'] as String?)?.trim().isNotEmpty == true)
                Text(
                  supplier['email'] as String,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              if ((supplier['address'] as String?)?.trim().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    supplier['address'] as String,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${supplier['purchase_count']} purchase invoices',
                      style: const TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showSupplierLedger(supplier),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('Ledger'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSupplierLedger(Map<String, dynamic> supplier) async {
    final supplierId = supplier['id'] as String? ?? '';
    final entries = await PurchaseRepository.getSupplierLedger(supplierId);
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('${supplier['name'] ?? 'Supplier'} Ledger'),
        content: SizedBox(
          width: 560,
          child: entries.isEmpty
              ? const Text('No ledger entries yet.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final type = entry['entry_type'] as String? ?? '';
                    final debit = (entry['debit'] as num? ?? 0).toDouble();
                    final credit = (entry['credit'] as num? ?? 0).toDouble();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        type == 'payment'
                            ? Icons.payments_outlined
                            : Icons.receipt_long_outlined,
                        color: type == 'payment'
                            ? AppColors.success
                            : AppColors.primaryLight,
                      ),
                      title: Text(
                        type == 'payment' ? 'Supplier payment' : 'Purchase',
                      ),
                      subtitle: Text(
                        [
                              entry['reference']?.toString(),
                              _friendlyDate(entry['entry_at'] as String?),
                              entry['status']?.toString(),
                            ]
                            .where((item) => item?.trim().isNotEmpty == true)
                            .join(' - '),
                      ),
                      trailing: Text(
                        type == 'payment'
                            ? '-${ShopSettings.currency}${credit.toStringAsFixed(2)}'
                            : '${ShopSettings.currency}${debit.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: type == 'payment'
                              ? AppColors.success
                              : AppColors.warning,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
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
          backgroundColor: AppColors.surface,
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
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: method,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
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
                const SizedBox(height: 12),
                TextField(
                  controller: referenceController,
                  decoration: const InputDecoration(labelText: 'Reference'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
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
                          ScaffoldMessenger.of(context).showSnackBar(
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
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
              color: AppColors.textSecondary.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
