import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/expiry_utils.dart';
import '../../../core/utils/unit_utils.dart';
import '../../sales/presentation/barcode_scanner.dart';
import '../../training/widgets/training_anchor.dart';
import '../data/product_provider.dart';
import '../data/product_repository.dart';
import 'product_variants_screen.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? product;

  const ProductFormScreen({super.key, this.product});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  static const Map<String, String> _conversionPresets = <String, String>{
    'kg:g': '1 kg = 1000 g',
    'litre:ml': '1 litre = 1000 ml',
    'm:cm': '1 m = 100 cm',
  };

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _costController;
  late final TextEditingController _brandController;
  late final TextEditingController _skuController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _stockController;
  late final TextEditingController _lowStockController;

  String? _selectedCategoryId;
  String _selectedUnit = UnitUtils.defaultUnit;
  late String _selectedStockUnit;
  late String _selectedPurchaseUnit;
  String? _imagePath;
  DateTime? _initialExpiryDate;
  bool _useUnitConversion = false;
  bool _isLoading = false;
  bool _isTotalCostMode = false;
  bool _trackStock = true;
  bool _hasVariants = false;

  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?['name'] as String? ?? '');
    _priceController = TextEditingController(
      text: p != null ? (p['price'] as num).toString() : '',
    );
    _costController = TextEditingController(
      text: p != null && p['cost'] != null ? (p['cost'] as num).toString() : '',
    );
    _skuController = TextEditingController(text: p?['sku'] as String? ?? '');
    _brandController = TextEditingController(
      text: p?['brand'] as String? ?? '',
    );
    _barcodeController = TextEditingController(
      text: p?['barcode'] as String? ?? '',
    );
    _stockController = TextEditingController(
      text: p != null
          ? UnitUtils.formatQuantity((p['stock'] as num?)?.toDouble() ?? 0)
          : '0',
    );
    _lowStockController = TextEditingController(
      text: p != null
          ? UnitUtils.formatQuantity((p['low_stock'] as num?)?.toDouble() ?? 5)
          : '5',
    );
    _selectedCategoryId = p?['category_id'] as String?;
    _selectedUnit = UnitUtils.saleUnitForProduct(p ?? const {});
    _selectedStockUnit = UnitUtils.stockUnitForProduct(p ?? const {});
    _selectedPurchaseUnit = UnitUtils.purchaseUnitForProduct(p ?? const {});
    _useUnitConversion = p != null ? UnitUtils.usesConversion(p) : false;
    _trackStock = p != null ? UnitUtils.tracksStock(p) : true;
    _hasVariants = ((p?['has_variants'] as num?) ?? 0) == 1;
    _imagePath = p?['image_url'] as String?;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _brandController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    _lowStockController.dispose();
    super.dispose();
  }

  String get _effectiveSaleUnit => _selectedUnit;
  String get _effectiveStockUnit =>
      _useUnitConversion ? _selectedStockUnit : _selectedUnit;
  String get _effectivePurchaseUnit =>
      _useUnitConversion ? _selectedPurchaseUnit : _selectedUnit;

  String get _saleUnitLabel => UnitUtils.label(_effectiveSaleUnit);
  String get _stockUnitLabel => UnitUtils.label(_effectiveStockUnit);
  String get _purchaseUnitLabel => UnitUtils.label(_effectivePurchaseUnit);
  bool get _stockAllowsDecimal => UnitUtils.allowsDecimal(_effectiveStockUnit);
  List<String> get _saleUnitOptions => _useUnitConversion
      ? UnitUtils.relatedUnits(_effectiveStockUnit)
      : UnitUtils.supportedUnits;
  List<String> get _purchaseUnitOptions => _useUnitConversion
      ? UnitUtils.relatedUnits(_effectiveStockUnit)
      : UnitUtils.supportedUnits;
  double? get _stockValue => double.tryParse(_stockController.text);
  double? get _lowStockValue => double.tryParse(_lowStockController.text);
  double get _saleToStockFactor =>
      UnitUtils.conversionFactor(_effectiveSaleUnit, _effectiveStockUnit) ??
      1.0;
  double get _purchaseToStockFactor =>
      UnitUtils.conversionFactor(_effectivePurchaseUnit, _effectiveStockUnit) ??
      1.0;

  TextInputFormatter get _quantityFormatter =>
      FilteringTextInputFormatter.allow(
        RegExp(_stockAllowsDecimal ? r'^\d*\.?\d{0,3}' : r'^\d*'),
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final stock = double.tryParse(_stockController.text) ?? 0;
      final lowStock = double.tryParse(_lowStockController.text) ?? 0;
      final saleUnit = _effectiveSaleUnit;
      final stockUnit = _effectiveStockUnit;
      final purchaseUnit = _effectivePurchaseUnit;
      final saleToStockFactor =
          UnitUtils.conversionFactor(saleUnit, stockUnit) ?? 1.0;
      final purchaseToStockFactor =
          UnitUtils.conversionFactor(purchaseUnit, stockUnit) ?? 1.0;

      double? finalCost;
      if (_costController.text.isNotEmpty) {
        final rawCost = double.parse(_costController.text);
        finalCost = _isTotalCostMode && stock > 0 ? (rawCost / stock) : rawCost;
      }

      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'price': double.parse(_priceController.text),
        'cost': finalCost,
        'sku': _skuController.text.isNotEmpty
            ? _skuController.text.trim()
            : null,
        'barcode': _barcodeController.text.isNotEmpty
            ? _barcodeController.text.trim()
            : null,
        'stock': stock,
        'low_stock': lowStock,
        'unit': saleUnit,
        'stock_unit': stockUnit,
        'sale_unit': saleUnit,
        'sale_to_stock_factor': saleToStockFactor,
        'purchase_unit': purchaseUnit,
        'purchase_to_stock_factor': purchaseToStockFactor,
        'category_id': _selectedCategoryId,
        'image_url': _imagePath,
        'brand': _brandController.text.trim().isNotEmpty
            ? _brandController.text.trim()
            : null,
        'track_stock': _trackStock ? 1 : 0,
        'has_variants': _hasVariants ? 1 : 0,
      };

      if (_isEditing) {
        await ProductRepository.update(
          widget.product!['id'] as String,
          payload,
        );
      } else {
        await ProductRepository.create(
          name: payload['name'] as String,
          price: payload['price'] as double,
          cost: payload['cost'] as double?,
          sku: payload['sku'] as String?,
          barcode: payload['barcode'] as String?,
          stock: payload['stock'] as double,
          lowStock: payload['low_stock'] as double,
          unit: saleUnit,
          stockUnit: stockUnit,
          saleUnit: saleUnit,
          saleToStockFactor: saleToStockFactor,
          purchaseUnit: purchaseUnit,
          purchaseToStockFactor: purchaseToStockFactor,
          categoryId: _selectedCategoryId,
          imageUrl: _imagePath,
          brand: payload['brand'] as String?,
          initialExpiryDate: ExpiryUtils.toStorageString(_initialExpiryDate),
          trackStock: _trackStock,
          hasVariants: _hasVariants,
        );
      }

      ref.invalidate(filteredProductsProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${appDir.path}/product_images');
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);

    final fileName = 'product_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final savedFile = await File(
      picked.path,
    ).copy('${imagesDir.path}/$fileName');
    setState(() => _imagePath = savedFile.path);
  }

  void _toggleConversion(bool enabled) {
    setState(() {
      _useUnitConversion = enabled;
      if (!enabled) {
        _selectedStockUnit = _selectedUnit;
        _selectedPurchaseUnit = _selectedUnit;
        return;
      }

      final familyUnits = UnitUtils.relatedUnits(_selectedUnit);
      _selectedStockUnit = familyUnits.contains(_selectedStockUnit)
          ? _selectedStockUnit
          : familyUnits.first;
      _selectedUnit = familyUnits.contains(_selectedUnit)
          ? _selectedUnit
          : familyUnits.last;
      _selectedPurchaseUnit = familyUnits.contains(_selectedPurchaseUnit)
          ? _selectedPurchaseUnit
          : _selectedUnit;
    });
  }

  void _applyConversionPreset(String saleUnit, String stockUnit) {
    final familyUnits = UnitUtils.relatedUnits(stockUnit);
    setState(() {
      _useUnitConversion = true;
      _selectedUnit = saleUnit;
      _selectedStockUnit = stockUnit;
      _selectedPurchaseUnit = familyUnits.contains(_selectedPurchaseUnit)
          ? _selectedPurchaseUnit
          : saleUnit;
    });
  }

  Future<void> _openVariantManager() async {
    if (!_isEditing || !_hasVariants) {
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductVariantsScreen(product: widget.product!),
      ),
    );
    if (changed == true) {
      ref.invalidate(filteredProductsProvider);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  Widget _buildImagePicker() {
    final isCompactLayout = MediaQuery.sizeOf(context).width < 600;

    return Column(
      children: [
        if (_imagePath != null &&
            _imagePath!.isNotEmpty &&
            File(_imagePath!).existsSync()) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                Image.file(
                  File(_imagePath!),
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                      tooltip: 'Remove image',
                      onPressed: () => setState(() => _imagePath = null),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (isCompactLayout)
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildUnitSelector({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return _LabeledField(
      label: label,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        dropdownColor: AppColors.surface,
        decoration: const InputDecoration(),
        items: options
            .map(
              (unit) => DropdownMenuItem<String>(
                value: unit,
                child: Text(UnitUtils.label(unit)),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildUnitConfigurationCard() {
    final isCompactLayout = MediaQuery.sizeOf(context).width < 600;

    return _FormCard(
      children: [
        Text(
          'Keep simple products in one unit, or turn on conversion when the selling unit differs from how you store stock.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.looks_one_outlined),
                label: Text('Simple Unit'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.swap_horiz_rounded),
                label: Text('Unit Conversion'),
              ),
            ],
            selected: {_useUnitConversion},
            onSelectionChanged: (selection) =>
                _toggleConversion(selection.first),
            showSelectedIcon: false,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _conversionPresets.entries.map((entry) {
            final parts = entry.key.split(':');
            return OutlinedButton(
              onPressed: () => _applyConversionPreset(parts[0], parts[1]),
              child: Text(entry.value),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        if (_useUnitConversion) ...[
          if (isCompactLayout)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUnitSelector(
                  label: 'Stock Unit',
                  value: _selectedStockUnit,
                  options: UnitUtils.relatedUnits(_selectedStockUnit),
                  onChanged: (value) {
                    if (value == null) return;
                    final familyUnits = UnitUtils.relatedUnits(value);
                    setState(() {
                      _selectedStockUnit = value;
                      if (!familyUnits.contains(_selectedUnit)) {
                        _selectedUnit = value;
                      }
                      if (!familyUnits.contains(_selectedPurchaseUnit)) {
                        _selectedPurchaseUnit = value;
                      }
                    });
                  },
                ),
                const SizedBox(height: 20),
                _buildUnitSelector(
                  label: 'Selling Unit',
                  value: _selectedUnit,
                  options: _saleUnitOptions,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedUnit = value);
                  },
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildUnitSelector(
                    label: 'Stock Unit',
                    value: _selectedStockUnit,
                    options: UnitUtils.relatedUnits(_selectedStockUnit),
                    onChanged: (value) {
                      if (value == null) return;
                      final familyUnits = UnitUtils.relatedUnits(value);
                      setState(() {
                        _selectedStockUnit = value;
                        if (!familyUnits.contains(_selectedUnit)) {
                          _selectedUnit = value;
                        }
                        if (!familyUnits.contains(_selectedPurchaseUnit)) {
                          _selectedPurchaseUnit = value;
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildUnitSelector(
                    label: 'Selling Unit',
                    value: _selectedUnit,
                    options: _saleUnitOptions,
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedUnit = value);
                    },
                  ),
                ),
              ],
            ),
          const SizedBox(height: 20),
          _buildUnitSelector(
            label: 'Purchase Unit',
            value: _selectedPurchaseUnit,
            options: _purchaseUnitOptions,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedPurchaseUnit = value);
            },
          ),
        ] else
          _buildUnitSelector(
            label: 'Unit',
            value: _selectedUnit,
            options: UnitUtils.supportedUnits,
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selectedUnit = value;
                _selectedStockUnit = value;
                _selectedPurchaseUnit = value;
              });
            },
          ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Storage Preview',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                !_trackStock
                    ? 'This product sells in $_saleUnitLabel without stock limits.'
                    : _useUnitConversion
                    ? 'Stock is stored in $_stockUnitLabel. Price is entered per $_saleUnitLabel. Purchases are received in $_purchaseUnitLabel.'
                    : 'This product uses $_saleUnitLabel for selling, stocking, and purchases.',
              ),
              if (_trackStock && _useUnitConversion) ...[
                const SizedBox(height: 8),
                Text(
                  '1 $_saleUnitLabel = ${UnitUtils.formatQuantity(_saleToStockFactor)} $_stockUnitLabel',
                ),
                Text(
                  '1 $_purchaseUnitLabel = ${UnitUtils.formatQuantity(_purchaseToStockFactor)} $_stockUnitLabel',
                ),
              ],
              if (_trackStock && _stockValue != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Current stock will be saved as ${UnitUtils.formatWithUnit(_stockValue, _effectiveStockUnit)}.',
                ),
              ],
              if (_trackStock && _lowStockValue != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Low-stock alert will trigger at ${UnitUtils.formatWithUnit(_lowStockValue, _effectiveStockUnit)}.',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final isCompactLayout = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(_isEditing ? 'Edit Product' : 'New Product'),
        actions: [
          TrainingAnchor(
            id: 'productForm.save',
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _save,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(_isEditing ? Icons.save : Icons.add, size: 18),
              label: Text(_isEditing ? 'Save Changes' : 'Create Product'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 680),
            margin: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(
                    title: 'Basic Information',
                    icon: Icons.info_outline,
                  ),
                  const SizedBox(height: 16),
                  TrainingAnchor(
                    id: 'productForm.identity',
                    child: _FormCard(
                      children: [
                        _LabeledField(
                          label: 'Product Name *',
                          child: TextFormField(
                            controller: _nameController,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Name is required'
                                : null,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Wireless Mouse',
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _LabeledField(
                          label: 'Brand',
                          child: TextFormField(
                            controller: _brandController,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Logitech, Samsung',
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (isCompactLayout)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _LabeledField(
                                label: 'SKU',
                                child: TextFormField(
                                  controller: _skuController,
                                  decoration: const InputDecoration(
                                    hintText: 'e.g. ELC-001',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _LabeledField(
                                label: 'Barcode',
                                child: TextFormField(
                                  controller: _barcodeController,
                                  decoration: InputDecoration(
                                    hintText: 'e.g. 1000000001',
                                    suffixIcon:
                                        (Platform.isAndroid || Platform.isIOS)
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.qr_code_scanner,
                                              color: AppColors.primary,
                                            ),
                                            tooltip: 'Scan barcode',
                                            onPressed: () async {
                                              final barcode =
                                                  await Navigator.of(
                                                    context,
                                                  ).push<String>(
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          const BarcodeScannerScreen(),
                                                    ),
                                                  );
                                              if (barcode != null &&
                                                  barcode.isNotEmpty) {
                                                _barcodeController.text =
                                                    barcode;
                                              }
                                            },
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: _LabeledField(
                                  label: 'SKU',
                                  child: TextFormField(
                                    controller: _skuController,
                                    decoration: const InputDecoration(
                                      hintText: 'e.g. ELC-001',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: _LabeledField(
                                  label: 'Barcode',
                                  child: TextFormField(
                                    controller: _barcodeController,
                                    decoration: InputDecoration(
                                      hintText: 'e.g. 1000000001',
                                      suffixIcon:
                                          (Platform.isAndroid || Platform.isIOS)
                                          ? IconButton(
                                              icon: const Icon(
                                                Icons.qr_code_scanner,
                                                color: AppColors.primary,
                                              ),
                                              tooltip: 'Scan barcode',
                                              onPressed: () async {
                                                final barcode =
                                                    await Navigator.of(
                                                      context,
                                                    ).push<String>(
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            const BarcodeScannerScreen(),
                                                      ),
                                                    );
                                                if (barcode != null &&
                                                    barcode.isNotEmpty) {
                                                  _barcodeController.text =
                                                      barcode;
                                                }
                                              },
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 20),
                        if (isCompactLayout)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _LabeledField(
                                label: 'Category',
                                child: categoriesAsync.when(
                                  data: (categories) =>
                                      DropdownButtonFormField<String?>(
                                        initialValue: _selectedCategoryId,
                                        dropdownColor: AppColors.surface,
                                        decoration: const InputDecoration(),
                                        items: [
                                          const DropdownMenuItem(
                                            value: null,
                                            child: Text('No category'),
                                          ),
                                          ...categories.map(
                                            (cat) => DropdownMenuItem(
                                              value: cat['id'] as String,
                                              child: Text(
                                                cat['name'] as String,
                                              ),
                                            ),
                                          ),
                                        ],
                                        onChanged: (v) => setState(
                                          () => _selectedCategoryId = v,
                                        ),
                                      ),
                                  loading: () =>
                                      const LinearProgressIndicator(),
                                  error: (_, _) =>
                                      const Text('Error loading categories'),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _useUnitConversion
                                    ? 'Selling in $_saleUnitLabel, stocking in $_stockUnitLabel'
                                    : 'Using $_saleUnitLabel',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _LabeledField(
                                  label: 'Category',
                                  child: categoriesAsync.when(
                                    data: (categories) =>
                                        DropdownButtonFormField<String?>(
                                          initialValue: _selectedCategoryId,
                                          dropdownColor: AppColors.surface,
                                          decoration: const InputDecoration(),
                                          items: [
                                            const DropdownMenuItem(
                                              value: null,
                                              child: Text('No category'),
                                            ),
                                            ...categories.map(
                                              (cat) => DropdownMenuItem(
                                                value: cat['id'] as String,
                                                child: Text(
                                                  cat['name'] as String,
                                                ),
                                              ),
                                            ),
                                          ],
                                          onChanged: (v) => setState(
                                            () => _selectedCategoryId = v,
                                          ),
                                        ),
                                    loading: () =>
                                        const LinearProgressIndicator(),
                                    error: (_, _) =>
                                        const Text('Error loading categories'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 28),
                                  child: Text(
                                    _useUnitConversion
                                        ? 'Selling in $_saleUnitLabel, stocking in $_stockUnitLabel'
                                        : 'Using $_saleUnitLabel',
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (!_isEditing) ...[
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHighlight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),
                              leading: const Icon(
                                Icons.event_available_outlined,
                              ),
                              title: const Text('Initial Batch Expiry Date'),
                              subtitle: Text(
                                _initialExpiryDate == null
                                    ? 'Optional. Applied only to the opening stock batch.'
                                    : '${ExpiryUtils.format(_initialExpiryDate)} - ${ExpiryUtils.statusLabel(_initialExpiryDate)}',
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  if (_initialExpiryDate != null)
                                    IconButton(
                                      tooltip: 'Clear expiry date',
                                      onPressed: () => setState(
                                        () => _initialExpiryDate = null,
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
                                        context: context,
                                        initialDate:
                                            _initialExpiryDate ??
                                            DateTime.now().add(
                                              const Duration(days: 30),
                                            ),
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        setState(
                                          () => _initialExpiryDate = picked,
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
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: 'Units',
                    icon: Icons.straighten_outlined,
                  ),
                  const SizedBox(height: 16),
                  TrainingAnchor(
                    id: 'productForm.units',
                    child: _buildUnitConfigurationCard(),
                  ),
                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: 'Product Image',
                    icon: Icons.image_outlined,
                  ),
                  const SizedBox(height: 16),
                  _FormCard(children: [_buildImagePicker()]),
                  const SizedBox(height: 32),
                  _SectionHeader(title: 'Pricing', icon: Icons.attach_money),
                  const SizedBox(height: 16),
                  TrainingAnchor(
                    id: 'productForm.pricing',
                    child: _FormCard(
                      children: [
                        if (isCompactLayout)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _LabeledField(
                                label: 'Selling Price per $_saleUnitLabel *',
                                child: TextFormField(
                                  controller: _priceController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,2}'),
                                    ),
                                  ],
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Price is required';
                                    }
                                    if (double.tryParse(v) == null) {
                                      return 'Invalid price';
                                    }
                                    return null;
                                  },
                                  decoration: InputDecoration(
                                    hintText: '0.00',
                                    prefixText: '${ShopSettings.currency} ',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cost Type ($_saleUnitLabel):',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SegmentedButton<bool>(
                                      segments: const [
                                        ButtonSegment(
                                          value: false,
                                          label: Text(
                                            'Per Unit',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        ButtonSegment(
                                          value: true,
                                          label: Text(
                                            'Bulk Invoice',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ],
                                      selected: {_isTotalCostMode},
                                      onSelectionChanged: (val) {
                                        setState(
                                          () => _isTotalCostMode = val.first,
                                        );
                                      },
                                      style: SegmentedButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                      ),
                                      showSelectedIcon: false,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _LabeledField(
                                    label: _isTotalCostMode
                                        ? 'Bulk Total Invoice Cost (optional)'
                                        : 'Cost per $_saleUnitLabel (optional)',
                                    child: TextFormField(
                                      controller: _costController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d{0,2}'),
                                        ),
                                      ],
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return null;
                                        }
                                        if (double.tryParse(v) == null) {
                                          return 'Invalid cost';
                                        }
                                        return null;
                                      },
                                      decoration: InputDecoration(
                                        hintText: '0.00',
                                        prefixText: '${ShopSettings.currency} ',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: _LabeledField(
                                  label: 'Selling Price per $_saleUnitLabel *',
                                  child: TextFormField(
                                    controller: _priceController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*\.?\d{0,2}'),
                                      ),
                                    ],
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return 'Price is required';
                                      }
                                      if (double.tryParse(v) == null) {
                                        return 'Invalid price';
                                      }
                                      return null;
                                    },
                                    decoration: InputDecoration(
                                      hintText: '0.00',
                                      prefixText: '${ShopSettings.currency} ',
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Cost Type ($_saleUnitLabel):',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: SegmentedButton<bool>(
                                          segments: const [
                                            ButtonSegment(
                                              value: false,
                                              label: Text(
                                                'Per Unit',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                            ButtonSegment(
                                              value: true,
                                              label: Text(
                                                'Bulk Invoice',
                                                style: TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          ],
                                          selected: {_isTotalCostMode},
                                          onSelectionChanged: (val) {
                                            setState(
                                              () =>
                                                  _isTotalCostMode = val.first,
                                            );
                                          },
                                          style: SegmentedButton.styleFrom(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                          ),
                                          showSelectedIcon: false,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _LabeledField(
                                      label: _isTotalCostMode
                                          ? 'Bulk Total Invoice Cost (optional)'
                                          : 'Cost per $_saleUnitLabel (optional)',
                                      child: TextFormField(
                                        controller: _costController,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d*\.?\d{0,2}'),
                                          ),
                                        ],
                                        validator: (v) {
                                          if (v == null || v.trim().isEmpty) {
                                            return null;
                                          }
                                          if (double.tryParse(v) == null) {
                                            return 'Invalid cost';
                                          }
                                          return null;
                                        },
                                        decoration: InputDecoration(
                                          hintText: '0.00',
                                          prefixText:
                                              '${ShopSettings.currency} ',
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        if (_priceController.text.isNotEmpty &&
                            _costController.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Builder(
                              builder: (context) {
                                final price =
                                    double.tryParse(_priceController.text) ?? 0;
                                final rawCost =
                                    double.tryParse(_costController.text) ?? 0;
                                final stock =
                                    double.tryParse(_stockController.text) ?? 1;
                                final cost = _isTotalCostMode
                                    ? (stock > 0 ? (rawCost / stock) : rawCost)
                                    : rawCost;
                                final margin = price > 0
                                    ? ((price - cost) / price * 100)
                                    : 0;
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Wrap(
                                    spacing: 16,
                                    runSpacing: 8,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.trending_up,
                                        size: 16,
                                        color: AppColors.success,
                                      ),
                                      Text(
                                        'Margin: ${margin.toStringAsFixed(1)}%',
                                        style: const TextStyle(
                                          color: AppColors.success,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'Profit: ${ShopSettings.currency}${(price - cost).toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  _SectionHeader(
                    title: 'Inventory',
                    icon: Icons.warehouse_outlined,
                  ),
                  const SizedBox(height: 16),
                  TrainingAnchor(
                    id: 'productForm.inventory',
                    child: _FormCard(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _trackStock,
                          title: const Text('Track stock for this product'),
                          subtitle: Text(
                            _trackStock
                                ? 'Use stock limits for packaged inventory and items you count.'
                                : 'Sell without stock limits. Good for cooked food, services, and custom charges.',
                          ),
                          onChanged: _isLoading
                              ? null
                              : (value) => setState(() => _trackStock = value),
                        ),
                        const SizedBox(height: 16),
                        if (_hasVariants) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                            ),
                            child: Text(
                              !_trackStock
                                  ? 'Variants can still be used for choices, but stock will not block sales while tracking is off.'
                                  : _isEditing
                                  ? 'Parent stock stays synced from the variants you manage below. Use this screen for product defaults, then add real stock on each variant.'
                                  : 'Save the product first, then add real stock on each variant from the variant manager.',
                              style: const TextStyle(
                                color: AppColors.primaryLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        if (!_trackStock)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHighlight,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Text(
                              'Stock fields are ignored for this product. It will stay sellable even when stock is zero.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else if (isCompactLayout)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _LabeledField(
                                label: 'Current Stock ($_stockUnitLabel)',
                                child: TextFormField(
                                  controller: _stockController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [_quantityFormatter],
                                  decoration: InputDecoration(
                                    hintText: _stockAllowsDecimal
                                        ? '0.000'
                                        : '0',
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return null;
                                    }
                                    if (double.tryParse(v) == null) {
                                      return 'Invalid stock';
                                    }
                                    return null;
                                  },
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(height: 20),
                              _LabeledField(
                                label: 'Low Stock Alert ($_stockUnitLabel)',
                                child: TextFormField(
                                  controller: _lowStockController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [_quantityFormatter],
                                  decoration: InputDecoration(
                                    hintText: _stockAllowsDecimal
                                        ? '5.000'
                                        : '5',
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return 'Alert level is required';
                                    }
                                    if (double.tryParse(v) == null) {
                                      return 'Invalid alert level';
                                    }
                                    return null;
                                  },
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: _LabeledField(
                                  label: 'Current Stock ($_stockUnitLabel)',
                                  child: TextFormField(
                                    controller: _stockController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: [_quantityFormatter],
                                    decoration: InputDecoration(
                                      hintText: _stockAllowsDecimal
                                          ? '0.000'
                                          : '0',
                                    ),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return null;
                                      }
                                      if (double.tryParse(v) == null) {
                                        return 'Invalid stock';
                                      }
                                      return null;
                                    },
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: _LabeledField(
                                  label: 'Low Stock Alert ($_stockUnitLabel)',
                                  child: TextFormField(
                                    controller: _lowStockController,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    inputFormatters: [_quantityFormatter],
                                    decoration: InputDecoration(
                                      hintText: _stockAllowsDecimal
                                          ? '5.000'
                                          : '5',
                                    ),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) {
                                        return 'Alert level is required';
                                      }
                                      if (double.tryParse(v) == null) {
                                        return 'Invalid alert level';
                                      }
                                      return null;
                                    },
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  _SectionHeader(title: 'Variants', icon: Icons.tune_outlined),
                  const SizedBox(height: 16),
                  _FormCard(
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _hasVariants,
                        title: const Text('This product has variants'),
                        subtitle: Text(
                          _hasVariants
                              ? 'Sell this item by real choices like size, color, or pack type.'
                              : 'Keep this as one direct sellable product.',
                        ),
                        onChanged: _isLoading
                            ? null
                            : (value) => setState(() => _hasVariants = value),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _hasVariants
                            ? _isEditing
                                  ? 'Save your product changes, then open the variant manager to add, edit, delete, and stock each variant.'
                                  : 'Create the product first, then reopen it to add and stock its variants.'
                            : 'Simple products keep price and stock directly on the main product record.',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      if (_hasVariants) ...[
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isEditing ? _openVariantManager : null,
                          icon: const Icon(Icons.tune_outlined, size: 18),
                          label: Text(
                            _isEditing
                                ? 'Manage Variants'
                                : 'Save Product First',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primaryLight),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  final List<Widget> children;

  const _FormCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
