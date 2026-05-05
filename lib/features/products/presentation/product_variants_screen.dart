import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/unit_utils.dart';
import '../data/product_variant_repository.dart';

class ProductVariantsScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductVariantsScreen({super.key, required this.product});

  @override
  State<ProductVariantsScreen> createState() => _ProductVariantsScreenState();
}

class _ProductVariantsScreenState extends State<ProductVariantsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _didChange = false;
  List<Map<String, dynamic>> _variants = const [];

  String get _productId => widget.product['id'] as String;
  String get _productName => widget.product['name'] as String? ?? 'Product';
  String get _saleUnit => UnitUtils.saleUnitForProduct(widget.product);
  String get _stockUnit => UnitUtils.stockUnitForProduct(widget.product);
  String get _saleUnitLabel => UnitUtils.label(_saleUnit);
  String get _stockUnitLabel => UnitUtils.label(_stockUnit);
  double get _saleToStockFactor => UnitUtils.saleToStockFactor(widget.product);

  @override
  void initState() {
    super.initState();
    _loadVariants();
  }

  Future<void> _loadVariants() async {
    setState(() => _isLoading = true);
    final variants = await ProductVariantRepository.getForProduct(_productId);
    if (!mounted) {
      return;
    }
    setState(() {
      _variants = variants;
      _isLoading = false;
    });
  }

  Future<void> _showVariantDialog([Map<String, dynamic>? variant]) async {
    final isEditing = variant != null;
    final nameController = TextEditingController(
      text: variant?['name'] as String? ?? '',
    );
    final priceController = TextEditingController(
      text: variant != null ? ((variant['price'] as num?) ?? 0).toString() : '',
    );
    final costController = TextEditingController(
      text: variant?['cost'] != null ? (variant!['cost'] as num).toString() : '',
    );
    final skuController = TextEditingController(
      text: variant?['sku'] as String? ?? '',
    );
    final barcodeController = TextEditingController(
      text: variant?['barcode'] as String? ?? '',
    );
    final stockController = TextEditingController(
      text: variant != null ? ((variant['stock'] as num?) ?? 0).toString() : '0',
    );
    final lowStockController = TextEditingController(
      text: variant != null
          ? ((variant['low_stock'] as num?) ?? 0).toString()
          : '0',
    );
    final sortOrderController = TextEditingController(
      text: variant != null
          ? ((variant['sort_order'] as num?) ?? 0).toString()
          : _variants.length.toString(),
    );
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(isEditing ? 'Edit Variant' : 'Add Variant'),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This variant sells in $_saleUnitLabel and stores stock in $_stockUnitLabel.',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Variant Name',
                        hintText: 'e.g. Red / Large',
                      ),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Variant name is required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Selling Price per $_saleUnitLabel',
                        prefixText: '${ShopSettings.currency} ',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Price is required';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Enter a valid price';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: costController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Cost per $_stockUnitLabel',
                        prefixText: '${ShopSettings.currency} ',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return null;
                        }
                        if (double.tryParse(value) == null) {
                          return 'Enter a valid cost';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: stockController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(
                            UnitUtils.allowsDecimal(_stockUnit)
                                ? r'^\d*\.?\d{0,3}'
                                : r'^\d*',
                          ),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Current Stock ($_stockUnitLabel)',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Stock is required';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Enter a valid stock value';
                        }
                        return null;
                      },
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: lowStockController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(
                            UnitUtils.allowsDecimal(_stockUnit)
                                ? r'^\d*\.?\d{0,3}'
                                : r'^\d*',
                          ),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Low Stock Alert ($_stockUnitLabel)',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Low stock alert is required';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Enter a valid alert value';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: skuController,
                      decoration: const InputDecoration(
                        labelText: 'SKU',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: barcodeController,
                      decoration: const InputDecoration(
                        labelText: 'Barcode',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: sortOrderController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Sort Order',
                      ),
                    ),
                    if (stockController.text.trim().isNotEmpty &&
                        double.tryParse(stockController.text) != null &&
                        _saleToStockFactor > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Approx. sellable quantity: ${UnitUtils.formatWithUnit((double.tryParse(stockController.text) ?? 0) / _saleToStockFactor, _saleUnit)}',
                          style: const TextStyle(
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }
                      final price = double.parse(priceController.text.trim());
                      final costText = costController.text.trim();
                      final payload = <String, dynamic>{
                        'name': nameController.text.trim(),
                        'price': price,
                        'cost': costText.isEmpty
                            ? null
                            : double.parse(costText),
                        'sku': _normalizedText(skuController.text),
                        'barcode': _normalizedText(barcodeController.text),
                        'stock': double.parse(stockController.text.trim()),
                        'low_stock': double.parse(lowStockController.text.trim()),
                        'sort_order':
                            int.tryParse(sortOrderController.text.trim()) ?? 0,
                      };

                      setState(() => _isSaving = true);
                      try {
                        await ProductVariantRepository.setProductHasVariants(
                          _productId,
                          true,
                        );
                        if (isEditing) {
                          await ProductVariantRepository.update(
                            variant['id'] as String,
                            payload,
                          );
                        } else {
                          await ProductVariantRepository.create(
                            productId: _productId,
                            name: payload['name'] as String,
                            price: payload['price'] as double,
                            cost: payload['cost'] as double?,
                            sku: payload['sku'] as String?,
                            barcode: payload['barcode'] as String?,
                            stock: payload['stock'] as double,
                            lowStock: payload['low_stock'] as double,
                            sortOrder: payload['sort_order'] as int,
                          );
                        }
                        await ProductVariantRepository.syncAggregateStock(
                          _productId,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text('Could not save variant: $error'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isSaving = false);
                        }
                      }
                    },
              child: Text(isEditing ? 'Save Variant' : 'Add Variant'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    priceController.dispose();
    costController.dispose();
    skuController.dispose();
    barcodeController.dispose();
    stockController.dispose();
    lowStockController.dispose();
    sortOrderController.dispose();

    if (saved == true) {
      _didChange = true;
      await _loadVariants();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEditing ? 'Variant updated.' : 'Variant added to $_productName.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _deleteVariant(Map<String, dynamic> variant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Variant'),
        content: Text(
          'Delete "${variant['name']}" from $_productName?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ProductVariantRepository.delete(variant['id'] as String);
      await ProductVariantRepository.syncAggregateStock(_productId);
      _didChange = true;
      await _loadVariants();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Variant deleted.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not delete variant: $error'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, _didChange);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _didChange),
          ),
          title: Text('Variants - $_productName'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isSaving ? null : _showVariantDialog,
          backgroundColor: AppColors.primary,
          icon: const Icon(Icons.add),
          label: const Text('Add Variant'),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _productName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Manage sellable variants for this product. Parent stock stays synced from variant stock totals.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.point_of_sale_outlined,
                        label: 'Sell in $_saleUnitLabel',
                      ),
                      _InfoChip(
                        icon: Icons.warehouse_outlined,
                        label: 'Stock in $_stockUnitLabel',
                      ),
                      _InfoChip(
                        icon: Icons.layers_outlined,
                        label: '${_variants.length} variant${_variants.length == 1 ? '' : 's'}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _variants.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.tune_outlined,
                              size: 56,
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.45,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No variants yet',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add the real choices you sell for $_productName, such as size, color, or pack type.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadVariants,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 120),
                        itemCount: _variants.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final variant = _variants[index];
                          final stock =
                              (variant['stock'] as num? ?? 0).toDouble();
                          final lowStock =
                              (variant['low_stock'] as num? ?? 0).toDouble();
                          final isLow = stock <= lowStock && stock > 0;
                          final isOut = stock <= 0;
                          final stockColor = isOut
                              ? AppColors.error
                              : isLow
                              ? AppColors.warning
                              : AppColors.success;

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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            variant['name'] as String? ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 8,
                                            children: [
                                              Text(
                                                '${ShopSettings.currency}${((variant['price'] as num?) ?? 0).toStringAsFixed(2)} / $_saleUnitLabel',
                                                style: const TextStyle(
                                                  color:
                                                      AppColors.primaryLight,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (variant['cost'] != null)
                                                Text(
                                                  'Cost ${ShopSettings.currency}${(variant['cost'] as num).toStringAsFixed(2)} / $_stockUnitLabel',
                                                  style: const TextStyle(
                                                    color: AppColors
                                                        .textSecondary,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: stockColor.withValues(
                                          alpha: 0.12,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        isOut
                                            ? 'Out of stock'
                                            : UnitUtils.formatWithUnit(
                                                stock,
                                                _stockUnit,
                                              ),
                                        style: TextStyle(
                                          color: stockColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    if ((variant['sku'] as String?)
                                            ?.trim()
                                            .isNotEmpty ??
                                        false)
                                      Text(
                                        'SKU: ${variant['sku']}',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    if ((variant['barcode'] as String?)
                                            ?.trim()
                                            .isNotEmpty ??
                                        false)
                                      Text(
                                        'Barcode: ${variant['barcode']}',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    Text(
                                      'Low stock: ${UnitUtils.formatWithUnit(lowStock, _stockUnit)}',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _isSaving
                                          ? null
                                          : () => _showVariantDialog(variant),
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Edit'),
                                    ),
                                    const SizedBox(width: 10),
                                    OutlinedButton.icon(
                                      onPressed: _isSaving
                                          ? null
                                          : () => _deleteVariant(variant),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: AppColors.error,
                                      ),
                                      label: const Text(
                                        'Delete',
                                        style: TextStyle(
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String? _normalizedText(String value) {
    final clean = value.trim();
    return clean.isEmpty ? null : clean;
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primaryLight),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
