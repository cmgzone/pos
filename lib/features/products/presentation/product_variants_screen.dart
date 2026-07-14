import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/product_image_upload_service.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/stitch_kit.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/unit_utils.dart';
import '../data/product_variant_color_repository.dart';
import '../data/product_variant_repository.dart';

class ProductVariantsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> product;

  const ProductVariantsScreen({super.key, required this.product});

  @override
  ConsumerState<ProductVariantsScreen> createState() =>
      _ProductVariantsScreenState();
}

class _ProductVariantsScreenState extends ConsumerState<ProductVariantsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _didChange = false;
  List<Map<String, dynamic>> _variants = const [];
  Map<String, List<Map<String, dynamic>>> _colorsByVariantId = const {};

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
    final colors = await ProductVariantColorRepository.getForProduct(
      _productId,
    );
    final groupedColors = <String, List<Map<String, dynamic>>>{};
    for (final color in colors) {
      final variantId = color['variant_id']?.toString();
      if (variantId == null || variantId.isEmpty) {
        continue;
      }
      groupedColors.putIfAbsent(variantId, () => []).add(color);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _variants = variants;
      _colorsByVariantId = groupedColors;
      _isLoading = false;
    });
  }

  Future<void> _showVariantDialog([Map<String, dynamic>? variant]) async {
    final isEditing = variant != null;
    final existingColors = isEditing
        ? _colorsByVariantId[variant['id'] as String] ??
              const <Map<String, dynamic>>[]
        : const <Map<String, dynamic>>[];
    final stockManagedByColors = existingColors.isNotEmpty;
    final nameController = TextEditingController(
      text: variant?['name'] as String? ?? '',
    );
    final priceController = TextEditingController(
      text: variant != null ? ((variant['price'] as num?) ?? 0).toString() : '',
    );
    final costController = TextEditingController(
      text: variant?['cost'] != null
          ? (variant!['cost'] as num).toString()
          : '',
    );
    final skuController = TextEditingController(
      text: variant?['sku'] as String? ?? '',
    );
    final barcodeController = TextEditingController(
      text: variant?['barcode'] as String? ?? '',
    );
    final stockController = TextEditingController(
      text: variant != null
          ? ((variant['stock'] as num?) ?? 0).toString()
          : '0',
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
          backgroundColor: Theme.of(context).colorScheme.surface,
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
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 16),
                    TextFormField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Variant Name',
                        hintText: 'e.g. Red / Large',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Variant name is required'
                          : null,
                    ),
                    SizedBox(height: 12),
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
                    SizedBox(height: 12),
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
                    SizedBox(height: 12),
                    TextFormField(
                      controller: stockController,
                      enabled: !stockManagedByColors,
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
                        helperText: stockManagedByColors
                            ? 'Stock is calculated from this variant\'s colors.'
                            : null,
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
                    SizedBox(height: 12),
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
                    SizedBox(height: 12),
                    TextFormField(
                      controller: skuController,
                      decoration: InputDecoration(labelText: 'SKU'),
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: barcodeController,
                      decoration: InputDecoration(labelText: 'Barcode'),
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: sortOrderController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(labelText: 'Sort Order'),
                    ),
                    if (stockController.text.trim().isNotEmpty &&
                        double.tryParse(stockController.text) != null &&
                        _saleToStockFactor > 0) ...[
                      SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Approx. sellable quantity: ${UnitUtils.formatWithUnit((double.tryParse(stockController.text) ?? 0) / _saleToStockFactor, _saleUnit)}',
                          style: TextStyle(
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
              child: Text('Cancel'),
            ),
            FilledButton(
              onPressed: _isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }
                      final price =
                          double.tryParse(priceController.text.trim()) ?? 0;
                      final costText = costController.text.trim();
                      final payload = <String, dynamic>{
                        'name': nameController.text.trim(),
                        'price': price,
                        'cost': costText.isEmpty
                            ? null
                            : double.tryParse(costText),
                        'sku': _normalizedText(skuController.text),
                        'barcode': _normalizedText(barcodeController.text),
                        'stock': stockManagedByColors
                            ? _sumColorStock(existingColors)
                            : double.tryParse(stockController.text.trim()) ?? 0,
                        'low_stock':
                            double.tryParse(lowStockController.text.trim()) ??
                            0,
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
                              content: Text(
                                AppErrorMessage.withContext(
                                  error,
                                  prefix: 'Could not save variant.',
                                  fallback: AppErrorMessage.saveFailed,
                                ),
                              ),
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
              isEditing
                  ? 'Variant updated.'
                  : 'Variant added to $_productName.',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _showVariantColorDialog(
    Map<String, dynamic> variant, [
    Map<String, dynamic>? color,
  ]) async {
    final isEditing = color != null;
    final variantId = variant['id'] as String;
    final variantName = variant['name'] as String? ?? 'Variant';
    final siblingColors =
        _colorsByVariantId[variantId] ?? const <Map<String, dynamic>>[];
    final nameController = TextEditingController(
      text: color?['name'] as String? ?? '',
    );
    final hexController = TextEditingController(
      text: color?['hex_color'] as String? ?? '',
    );
    final stockController = TextEditingController(
      text: color != null ? ((color['stock'] as num?) ?? 0).toString() : '0',
    );
    final sortOrderController = TextEditingController(
      text: color != null
          ? ((color['sort_order'] as num?) ?? 0).toString()
          : siblingColors.length.toString(),
    );
    final imageController = TextEditingController(
      text: color?['image_url'] as String? ?? '',
    );
    final formKey = GlobalKey<FormState>();
    var uploadingImage = false;

    void applyPickedColor(
      _VariantColorPreset preset,
      StateSetter setDialogState,
    ) {
      hexController.text = _hexFromColor(preset.color);
      if (nameController.text.trim().isEmpty) {
        nameController.text = preset.label;
      }
      setDialogState(() {});
    }

    Future<void> openCustomColorPicker(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      final picked = await showDialog<Color>(
        context: dialogContext,
        builder: (_) => _CustomVariantColorPickerDialog(
          initialColor:
              _colorFromHex(hexController.text) ??
              _variantColorSwatch({'name': nameController.text}),
        ),
      );
      if (picked == null) {
        return;
      }
      hexController.text = _hexFromColor(picked);
      setDialogState(() {});
    }

    Future<void> pickImage(
      BuildContext dialogContext,
      StateSetter setDialogState,
      ImageSource source,
    ) async {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 86,
      );
      if (picked == null) {
        return;
      }

      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/product_variant_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      final fileName =
          'variant_color_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = await File(
        picked.path,
      ).copy('${imagesDir.path}/$fileName');
      imageController.text = savedFile.path;
      setDialogState(() => uploadingImage = true);

      try {
        final hostedUrl = await ProductImageUploadService.uploadProductImage(
          imagePath: savedFile.path,
          productId: _productId,
          productName: '$_productName $variantName ${nameController.text}',
        );
        if (!dialogContext.mounted) {
          return;
        }
        setDialogState(() => imageController.text = hostedUrl);
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(
            content: Text('Color photo uploaded.'),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (error) {
        if (!dialogContext.mounted) {
          return;
        }
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content: Text(
              'Saved locally. ${AppErrorMessage.from(error, fallback: 'Could not upload this image.')}',
            ),
            backgroundColor: AppColors.warning,
          ),
        );
      } finally {
        if (dialogContext.mounted) {
          setDialogState(() => uploadingImage = false);
        }
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(isEditing ? 'Edit Color' : 'Add Color'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$variantName can have its own colors, photos, and stock.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _VariantColorImagePreview(
                          imagePath: imageController.text,
                          color: _variantColorSwatch({
                            'name': nameController.text,
                            'hex_color': hexController.text,
                          }),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            children: [
                              TextFormField(
                                controller: nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Color name',
                                  hintText: 'e.g. Black',
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                    ? 'Color name is required'
                                    : null,
                                onChanged: (_) => setDialogState(() {}),
                              ),
                              SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: hexController,
                                      decoration: const InputDecoration(
                                        labelText: 'Hex color',
                                        hintText: '#111827',
                                      ),
                                      onChanged: (_) => setDialogState(() {}),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: () => openCustomColorPicker(
                                      dialogContext,
                                      setDialogState,
                                    ),
                                    icon: const Icon(
                                      Icons.colorize_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Pick'),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),
                              _VariantColorPresetGrid(
                                selectedHex: hexController.text,
                                onSelected: (preset) =>
                                    applyPickedColor(preset, setDialogState),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
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
                        labelText: 'Stock for this color ($_stockUnitLabel)',
                        helperText:
                            'This stock contributes to $variantName availability.',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Color stock is required';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Enter a valid stock value';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: sortOrderController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Sort Order',
                      ),
                    ),
                    SizedBox(height: 12),
                    TextFormField(
                      controller: imageController,
                      decoration: const InputDecoration(
                        labelText: 'Color photo URL or local path',
                        prefixIcon: Icon(Icons.image_outlined),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: uploadingImage
                              ? null
                              : () => pickImage(
                                  dialogContext,
                                  setDialogState,
                                  ImageSource.gallery,
                                ),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Gallery'),
                        ),
                        OutlinedButton.icon(
                          onPressed: uploadingImage
                              ? null
                              : () => pickImage(
                                  dialogContext,
                                  setDialogState,
                                  ImageSource.camera,
                                ),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Camera'),
                        ),
                        if (imageController.text.trim().isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: uploadingImage
                                ? null
                                : () => setDialogState(
                                    () => imageController.clear(),
                                  ),
                            icon: const Icon(Icons.clear_rounded),
                            label: const Text('Remove photo'),
                          ),
                      ],
                    ),
                    if (uploadingImage) ...[
                      SizedBox(height: 12),
                      const LinearProgressIndicator(minHeight: 3),
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
              onPressed: _isSaving || uploadingImage
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }
                      final payload = <String, dynamic>{
                        'name': nameController.text.trim(),
                        'hex_color': _normalizedText(hexController.text),
                        'image_url': _normalizedText(imageController.text),
                        'stock':
                            double.tryParse(stockController.text.trim()) ?? 0,
                        'sort_order':
                            int.tryParse(sortOrderController.text.trim()) ?? 0,
                      };

                      setState(() => _isSaving = true);
                      try {
                        if (isEditing) {
                          await ProductVariantColorRepository.update(
                            color['id'] as String,
                            payload,
                          );
                        } else {
                          await ProductVariantColorRepository.create(
                            productId: _productId,
                            variantId: variantId,
                            name: payload['name'] as String,
                            hexColor: payload['hex_color'] as String?,
                            imageUrl: payload['image_url'] as String?,
                            stock: payload['stock'] as double,
                            sortOrder: payload['sort_order'] as int,
                          );
                        }
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppErrorMessage.withContext(
                                  error,
                                  prefix: 'Could not save color.',
                                  fallback: AppErrorMessage.saveFailed,
                                ),
                              ),
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
              child: Text(isEditing ? 'Save Color' : 'Add Color'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    hexController.dispose();
    stockController.dispose();
    sortOrderController.dispose();
    imageController.dispose();

    if (saved == true) {
      _didChange = true;
      await _loadVariants();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing ? 'Color updated.' : 'Color added.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Future<void> _deleteVariantColor(Map<String, dynamic> color) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Color'),
        content: Text('Delete "${color['name']}" from this variant?'),
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
      await ProductVariantColorRepository.delete(color['id'] as String);
      _didChange = true;
      await _loadVariants();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Color deleted.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppErrorMessage.withContext(
                error,
                prefix: 'Could not delete color.',
                fallback: 'Could not delete this color. Please try again.',
              ),
            ),
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

  Future<void> _deleteVariant(Map<String, dynamic> variant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Variant'),
        content: Text('Delete "${variant['name']}" from $_productName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text('Delete'),
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
            content: Text(
              AppErrorMessage.withContext(
                error,
                prefix: 'Could not delete variant.',
                fallback: 'Could not delete this variant. Please try again.',
              ),
            ),
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
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && next != previous && mounted) {
          _loadVariants();
        }
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, _didChange);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, _didChange),
          ),
          title: Text('Variants - $_productName'),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _isSaving ? null : _showVariantDialog,
          backgroundColor: AppColors.primary,
          icon: Icon(Icons.add),
          label: Text('Add Variant'),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _productName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Manage sellable variants for this product. Parent stock stays synced from variant stock totals.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 12),
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
                        label:
                            '${_variants.length} variant${_variants.length == 1 ? '' : 's'}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
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
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.45),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No variants yet',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Add the real choices you sell for $_productName, such as size, color, or pack type.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.85),
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
                        separatorBuilder: (_, _) => SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final variant = _variants[index];
                          final stock = (variant['stock'] as num? ?? 0)
                              .toDouble();
                          final lowStock = (variant['low_stock'] as num? ?? 0)
                              .toDouble();
                          final isLow = stock <= lowStock && stock > 0;
                          final isOut = stock <= 0;
                          final stockColor = isOut
                              ? AppColors.error
                              : isLow
                              ? AppColors.warning
                              : AppColors.success;
                          final colors =
                              _colorsByVariantId[variant['id'] as String] ??
                              const <Map<String, dynamic>>[];

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline,
                              ),
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
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                          SizedBox(height: 6),
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 8,
                                            children: [
                                              Text(
                                                '${ShopSettings.currency}${((variant['price'] as num?) ?? 0).toStringAsFixed(2)} / $_saleUnitLabel',
                                                style: TextStyle(
                                                  color: AppColors.primaryLight,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              if (variant['cost'] != null)
                                                Text(
                                                  'Cost ${ShopSettings.currency}${(variant['cost'] as num).toStringAsFixed(2)} / $_stockUnitLabel',
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
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
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
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
                                SizedBox(height: 12),
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
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    if ((variant['barcode'] as String?)
                                            ?.trim()
                                            .isNotEmpty ??
                                        false)
                                      Text(
                                        'Barcode: ${variant['barcode']}',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    Text(
                                      'Low stock: ${UnitUtils.formatWithUnit(lowStock, _stockUnit)}',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 14),
                                _VariantColorsPanel(
                                  colors: colors,
                                  stockUnit: _stockUnit,
                                  onAdd: _isSaving
                                      ? null
                                      : () => _showVariantColorDialog(variant),
                                  onEdit: _isSaving
                                      ? null
                                      : (color) => _showVariantColorDialog(
                                          variant,
                                          color,
                                        ),
                                  onDelete: _isSaving
                                      ? null
                                      : _deleteVariantColor,
                                ),
                                SizedBox(height: 14),
                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _isSaving
                                          ? null
                                          : () => _showVariantDialog(variant),
                                      icon: Icon(Icons.edit_outlined),
                                      label: Text('Edit'),
                                    ),
                                    SizedBox(width: 10),
                                    OutlinedButton.icon(
                                      onPressed: _isSaving
                                          ? null
                                          : () => _deleteVariant(variant),
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: AppColors.error,
                                      ),
                                      label: Text(
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

  double _sumColorStock(List<Map<String, dynamic>> colors) {
    return colors.fold<double>(
      0,
      (sum, color) => sum + ((color['stock'] as num?) ?? 0).toDouble(),
    );
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
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primaryLight),
          SizedBox(width: 8),
          Text(label, style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _VariantColorsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> colors;
  final String stockUnit;
  final VoidCallback? onAdd;
  final ValueChanged<Map<String, dynamic>>? onEdit;
  final ValueChanged<Map<String, dynamic>>? onDelete;

  const _VariantColorsPanel({
    required this.colors,
    required this.stockUnit,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StitchCard(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(12),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Colors for this variant',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Add color'),
              ),
            ],
          ),
          if (colors.isEmpty) ...[
            SizedBox(height: 6),
            Text(
              'No colors yet. Add Black, Silver, Blue, Gold, or any real color this variant sells in.',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ] else ...[
            SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in colors)
                  _VariantColorCard(
                    color: color,
                    stockUnit: stockUnit,
                    onEdit: onEdit == null ? null : () => onEdit!(color),
                    onDelete: onDelete == null ? null : () => onDelete!(color),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _VariantColorCard extends StatelessWidget {
  final Map<String, dynamic> color;
  final String stockUnit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _VariantColorCard({
    required this.color,
    required this.stockUnit,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stock = _asDouble(color['stock']);
    final outOfStock = stock <= 0;
    final stockColor = outOfStock ? AppColors.error : AppColors.success;
    final swatch = _variantColorSwatch(color);

    return Container(
      width: 260,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: outOfStock
              ? AppColors.error.withValues(alpha: 0.35)
              : theme.colorScheme.outline,
        ),
      ),
      child: Row(
        children: [
          _VariantColorImagePreview(
            imagePath: color['image_url'] as String?,
            color: swatch,
            size: 58,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: swatch,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.outline),
                      ),
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        color['name'] as String? ?? 'Color',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  outOfStock
                      ? 'Out of stock'
                      : '${UnitUtils.formatWithUnit(stock, stockUnit)} available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: stockColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    InkWell(
                      onTap: onEdit,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          'Edit',
                          style: TextStyle(
                            color: AppColors.primaryLight,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(999),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          'Delete',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantColorImagePreview extends StatelessWidget {
  final String? imagePath;
  final Color color;
  final double size;

  const _VariantColorImagePreview({
    required this.imagePath,
    required this.color,
    this.size = 76,
  });

  @override
  Widget build(BuildContext context) {
    final path = imagePath?.trim() ?? '';
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Container(
          width: size * 0.48,
          height: size * 0.48,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
      ),
    );

    Widget child;
    if (path.isEmpty) {
      child = fallback;
    } else if (ProductImageUploadService.isRemoteImage(path)) {
      child = Image.network(
        path,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => fallback,
      );
    } else {
      child = Image.file(
        File(path),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}

class _VariantColorPreset {
  final String label;
  final Color color;

  const _VariantColorPreset(this.label, this.color);
}

const _variantColorPresets = [
  _VariantColorPreset('Black', Color(0xFF111827)),
  _VariantColorPreset('Silver', Color(0xFFC0C7D2)),
  _VariantColorPreset('Blue', Color(0xFF2563EB)),
  _VariantColorPreset('Gold', Color(0xFFD4AF37)),
  _VariantColorPreset('Red', Color(0xFFDC2626)),
  _VariantColorPreset('White', Color(0xFFFFFFFF)),
  _VariantColorPreset('Green', Color(0xFF16A34A)),
  _VariantColorPreset('Yellow', Color(0xFFEAB308)),
  _VariantColorPreset('Orange', Color(0xFFF97316)),
  _VariantColorPreset('Purple', Color(0xFF7C3AED)),
  _VariantColorPreset('Pink', Color(0xFFEC4899)),
  _VariantColorPreset('Brown', Color(0xFF92400E)),
  _VariantColorPreset('Grey', Color(0xFF6B7280)),
];

class _VariantColorPresetGrid extends StatelessWidget {
  final String selectedHex;
  final ValueChanged<_VariantColorPreset> onSelected;

  const _VariantColorPresetGrid({
    required this.selectedHex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final selected = _normalizedHex(selectedHex);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in _variantColorPresets)
          _VariantColorPresetChip(
            preset: preset,
            selected: selected == _hexFromColor(preset.color),
            onTap: () => onSelected(preset),
          ),
      ],
    );
  }
}

class _VariantColorPresetChip extends StatelessWidget {
  final _VariantColorPreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _VariantColorPresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLight =
        ThemeData.estimateBrightnessForColor(preset.color) == Brightness.light;
    return Material(
      color: selected
          ? AppColors.primaryLight.withValues(alpha: 0.12)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? AppColors.primaryLight
                  : Theme.of(context).colorScheme.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: preset.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isLight ? const Color(0xFFD1D5DB) : Colors.white,
                  ),
                ),
              ),
              SizedBox(width: 6),
              Text(
                preset.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomVariantColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _CustomVariantColorPickerDialog({required this.initialColor});

  @override
  State<_CustomVariantColorPickerDialog> createState() =>
      _CustomVariantColorPickerDialogState();
}

class _CustomVariantColorPickerDialogState
    extends State<_CustomVariantColorPickerDialog> {
  late int _red;
  late int _green;
  late int _blue;

  Color get _color => Color.fromARGB(255, _red, _green, _blue);

  @override
  void initState() {
    super.initState();
    final value = widget.initialColor.toARGB32();
    _red = (value >> 16) & 0xFF;
    _green = (value >> 8) & 0xFF;
    _blue = value & 0xFF;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Pick Colour'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _color.withValues(alpha: 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _hexFromColor(_color),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),
            _RgbSlider(
              label: 'Red',
              value: _red,
              color: const Color(0xFFDC2626),
              onChanged: (value) => setState(() => _red = value),
            ),
            _RgbSlider(
              label: 'Green',
              value: _green,
              color: const Color(0xFF16A34A),
              onChanged: (value) => setState(() => _green = value),
            ),
            _RgbSlider(
              label: 'Blue',
              value: _blue,
              color: const Color(0xFF2563EB),
              onChanged: (value) => setState(() => _blue = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('Use Colour'),
        ),
      ],
    );
  }
}

class _RgbSlider extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  const _RgbSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: color,
            label: value.toString(),
            onChanged: (next) => onChanged(next.round()),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.toString(),
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

Color _variantColorSwatch(Map<String, dynamic> color) {
  final hex = color['hex_color']?.toString().trim();
  final fromHex = _colorFromHex(hex);
  if (fromHex != null) {
    return fromHex;
  }
  return _colorFromName(color['name']?.toString() ?? '');
}

Color? _colorFromHex(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  final raw = value.trim();
  final normalized = raw.startsWith('#') ? raw.substring(1) : raw;
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(normalized)) {
    return null;
  }
  return Color(int.parse('FF$normalized', radix: 16));
}

String _hexFromColor(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

String _normalizedHex(String? value) {
  final color = _colorFromHex(value);
  return color == null ? '' : _hexFromColor(color);
}

Color _colorFromName(String value) {
  final name = value.trim().toLowerCase();
  if (name.contains('black')) return const Color(0xFF111827);
  if (name.contains('white')) return const Color(0xFFFFFFFF);
  if (name.contains('silver')) return const Color(0xFFC0C7D2);
  if (name.contains('gold')) return const Color(0xFFD4AF37);
  if (name.contains('blue')) return const Color(0xFF2563EB);
  if (name.contains('red')) return const Color(0xFFDC2626);
  if (name.contains('green')) return const Color(0xFF16A34A);
  if (name.contains('yellow')) return const Color(0xFFEAB308);
  if (name.contains('orange')) return const Color(0xFFF97316);
  if (name.contains('purple')) return const Color(0xFF7C3AED);
  if (name.contains('pink')) return const Color(0xFFEC4899);
  if (name.contains('brown')) return const Color(0xFF92400E);
  if (name.contains('grey') || name.contains('gray')) {
    return const Color(0xFF6B7280);
  }
  return AppColors.secondary;
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
