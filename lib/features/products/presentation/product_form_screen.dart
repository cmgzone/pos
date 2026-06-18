import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/openrouter_service.dart';
import '../../../core/services/product_image_upload_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/utils/error_messages.dart';
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

  static const _wizardSteps = [
    'Basic Info',
    'Pricing & Units',
    'Inventory',
    'Review',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _costController;
  late final TextEditingController _brandController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _skuController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _stockController;
  late final TextEditingController _lowStockController;
  late final TextEditingController _imageUrlController;

  String? _selectedCategoryId;
  String _selectedUnit = UnitUtils.defaultUnit;
  late String _selectedStockUnit;
  late String _selectedPurchaseUnit;
  String? _imagePath;
  List<String> _imageUrls = [];
  DateTime? _initialExpiryDate;
  bool _useUnitConversion = false;
  bool _isLoading = false;
  bool _isEnhancingImage = false;
  bool _isUploadingImage = false;
  bool _isTotalCostMode = false;
  bool _trackStock = true;
  bool _hasVariants = false;
  bool _showOnline = true;
  bool _isFeatured = false;
  int _currentStep = 0;

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
    _descriptionController = TextEditingController(
      text: p?['description'] as String? ?? '',
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
    _imageUrls = _readProductImageUrls(p?['image_urls_json'], _imagePath);
    if (_imageUrls.isNotEmpty) {
      _imagePath = _imageUrls.first;
    }
    _imageUrlController = TextEditingController();
    _showOnline = _readBoolish(p?['show_online'], fallback: true);
    _isFeatured = _readBoolish(p?['is_featured'], fallback: false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _brandController.dispose();
    _descriptionController.dispose();
    _skuController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    _lowStockController.dispose();
    _imageUrlController.dispose();
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

  static bool _readBoolish(dynamic value, {required bool fallback}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final clean = value.toString().trim().toLowerCase();
    if (clean.isEmpty) return fallback;
    return !['0', 'false', 'no', 'off'].contains(clean);
  }

  static List<String> _readProductImageUrls(dynamic raw, String? fallback) {
    final values = <String>[];
    if (raw is List) {
      values.addAll(raw.map((value) => value.toString()));
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          values.addAll(decoded.map((value) => value.toString()));
        } else {
          values.add(raw);
        }
      } catch (_) {
        values.add(raw);
      }
    }
    if (values.isEmpty && fallback?.trim().isNotEmpty == true) {
      values.add(fallback!.trim());
    }
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(value))
        .take(8)
        .toList();
  }

  TextInputFormatter get _quantityFormatter =>
      FilteringTextInputFormatter.allow(
        RegExp(_stockAllowsDecimal ? r'^\d*\.?\d{0,3}' : r'^\d*'),
      );

  bool get _canProceed {
    switch (_currentStep) {
      case 0:
        return _nameController.text.trim().isNotEmpty;
      case 1:
        if (!_hasVariants) {
          if (_priceController.text.isEmpty) return false;
          if (double.tryParse(_priceController.text) == null) return false;
        }
        return true;
      case 2:
        if (_trackStock) {
          if (_lowStockController.text.isEmpty) return false;
          if (double.tryParse(_lowStockController.text) == null) return false;
        }
        return true;
      case 3:
        return true;
      default:
        return false;
    }
  }

  Future<void> _save({bool openVariants = false}) async {
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
        final rawCost = double.tryParse(_costController.text) ?? 0;
        finalCost = _isTotalCostMode && stock > 0 ? (rawCost / stock) : rawCost;
      }
      final productImageUrls = _normalizedProductImageUrls();

      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'price': double.tryParse(_priceController.text) ?? 0.0,
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
        'image_url': productImageUrls.isNotEmpty
            ? productImageUrls.first
            : null,
        'brand': _brandController.text.trim().isNotEmpty
            ? _brandController.text.trim()
            : null,
        'description': _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        'image_urls_json': productImageUrls.isNotEmpty
            ? jsonEncode(productImageUrls)
            : null,
        'show_online': _showOnline ? 1 : 0,
        'is_featured': _isFeatured ? 1 : 0,
        'track_stock': _trackStock ? 1 : 0,
        'has_variants': _hasVariants ? 1 : 0,
      };

      Map<String, dynamic>? updatedProduct;
      if (_isEditing) {
        await ProductRepository.update(
          widget.product!['id'] as String,
          payload,
        );
        updatedProduct = await ProductRepository.getById(
          widget.product!['id'] as String,
        );
      } else {
        final id = await ProductRepository.create(
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
          imageUrl: productImageUrls.isNotEmpty ? productImageUrls.first : null,
          brand: payload['brand'] as String?,
          description: payload['description'] as String?,
          imageUrlsJson: payload['image_urls_json'] as String?,
          showOnline: _showOnline,
          isFeatured: _isFeatured,
          initialExpiryDate: ExpiryUtils.toStorageString(_initialExpiryDate),
          trackStock: _trackStock,
          hasVariants: _hasVariants,
        );
        updatedProduct = await ProductRepository.getById(id);
      }

      ref.invalidate(filteredProductsProvider);

      if (!mounted) return;

      if (openVariants && updatedProduct != null) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => ProductVariantsScreen(product: updatedProduct!),
          ),
        );
        if (mounted) Navigator.pop(context, true);
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(e, fallback: AppErrorMessage.saveFailed),
          ),
          backgroundColor: AppColors.error,
        ),
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
    final wasFirstImage = _normalizedProductImageUrls().isEmpty;
    setState(() {
      _addProductImageUrl(savedFile.path, makeMain: wasFirstImage);
      _isUploadingImage = true;
    });

    try {
      final hostedUrl = await ProductImageUploadService.uploadProductImage(
        imagePath: savedFile.path,
        productId: widget.product?['id'] as String?,
        productName: _nameController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _replaceProductImageUrl(savedFile.path, hostedUrl));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo added to the online product gallery.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved locally. ${AppErrorMessage.from(e, fallback: 'Could not upload this image to Bunny.')}',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _enhanceImage() async {
    final imagePath = _imagePath;
    if (imagePath == null || imagePath.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose or capture a product image first.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isEnhancingImage = true);
    try {
      final enhancedPath = await OpenRouterService.enhanceProductImage(
        imageSource: imagePath,
        productName: _nameController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _replaceProductImageUrl(imagePath, enhancedPath));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Image enhanced using ${OpenRouterService.imageModelName}.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppErrorMessage.from(
              e,
              fallback: 'Could not enhance this product image.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isEnhancingImage = false);
    }
  }

  File _imageFileForPath(String path) {
    return path.startsWith('file:')
        ? File.fromUri(Uri.parse(path))
        : File(path);
  }

  bool _hasDisplayableProductImage() {
    final images = _normalizedProductImageUrls();
    final imagePath = images.isNotEmpty ? images.first : '';
    if (imagePath.isEmpty) return false;
    if (ProductImageUploadService.isRemoteImage(imagePath)) return true;
    try {
      return _imageFileForPath(imagePath).existsSync();
    } catch (_) {
      return false;
    }
  }

  Widget _buildProductImagePreview(String imagePath) {
    if (ProductImageUploadService.isRemoteImage(imagePath)) {
      return Image.network(
        imagePath,
        width: double.infinity,
        height: 220,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildImageFallback(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildImageFallback(isLoading: true);
        },
      );
    }

    return Image.file(
      _imageFileForPath(imagePath),
      width: double.infinity,
      height: 220,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildImageFallback(),
    );
  }

  Widget _buildImageFallback({bool isLoading = false}) {
    return Container(
      width: double.infinity,
      height: 220,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              Icons.image_not_supported_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 34,
            ),
          SizedBox(height: 8),
          Text(
            isLoading ? 'Loading image...' : 'Image preview unavailable',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageHostingStatus() {
    final images = _normalizedProductImageUrls();
    final isHosted = images.any(ProductImageUploadService.isRemoteImage);
    if (!_isUploadingImage && !isHosted) {
      return const SizedBox.shrink();
    }

    final color = _isUploadingImage ? AppColors.primary : AppColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          if (_isUploadingImage)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(Icons.cloud_done_outlined, size: 18, color: color),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              _isUploadingImage
                  ? 'Uploading to Bunny...'
                  : 'Hosted image ready for your web catalog.',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<String> _normalizedProductImageUrls() {
    final seen = <String>{};
    final values = <String>[
      if (_imagePath?.trim().isNotEmpty == true) _imagePath!.trim(),
      ..._imageUrls,
    ];
    return values
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty && seen.add(url))
        .take(8)
        .toList();
  }

  bool _isUsableProductImageUrl(String value) {
    final clean = value.trim();
    if (ProductImageUploadService.isRemoteImage(clean)) return true;
    if (clean.startsWith('file:')) return true;
    return !clean.contains('://');
  }

  void _addProductImageUrl(String value, {bool makeMain = false}) {
    final clean = value.trim();
    if (clean.isEmpty || !_isUsableProductImageUrl(clean)) return;
    final urls = _normalizedProductImageUrls()
        .where((url) => url != clean)
        .toList();
    if (makeMain || urls.isEmpty) {
      urls.insert(0, clean);
    } else {
      urls.add(clean);
    }
    _imageUrls = urls.take(8).toList();
    _imagePath = _imageUrls.isNotEmpty ? _imageUrls.first : null;
  }

  void _replaceProductImageUrl(String oldUrl, String newUrl) {
    final cleanNew = newUrl.trim();
    final urls = _normalizedProductImageUrls();
    final index = urls.indexOf(oldUrl);
    if (index >= 0) {
      urls[index] = cleanNew;
    } else {
      urls.insert(0, cleanNew);
    }
    final seen = <String>{};
    _imageUrls = urls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty && seen.add(url))
        .take(8)
        .toList();
    _imagePath = _imageUrls.isNotEmpty ? _imageUrls.first : null;
  }

  void _removeProductImageUrl(String url) {
    setState(() {
      _imageUrls = _normalizedProductImageUrls()
          .where((item) => item != url)
          .toList();
      _imagePath = _imageUrls.isNotEmpty ? _imageUrls.first : null;
    });
  }

  void _makeMainProductImage(String url) {
    setState(() => _addProductImageUrl(url, makeMain: true));
  }

  void _addProductImageFromInput() {
    final value = _imageUrlController.text.trim();
    if (value.isEmpty) return;
    if (!ProductImageUploadService.isRemoteImage(value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use a valid http or https image URL.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    setState(() {
      _addProductImageUrl(value);
      _imageUrlController.clear();
    });
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
        dropdownColor: context.appSurface,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Keep simple products in one unit, or turn on conversion when the selling unit differs from how you store stock.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        SizedBox(height: 16),
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
        SizedBox(height: 16),
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
        SizedBox(height: 20),
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
                SizedBox(height: 20),
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
                SizedBox(width: 20),
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
          SizedBox(height: 20),
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
        SizedBox(height: 20),
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
              Text(
                'Storage Preview',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                !_trackStock
                    ? 'This product sells in $_saleUnitLabel without stock limits.'
                    : _useUnitConversion
                    ? 'Stock is stored in $_stockUnitLabel. Price is entered per $_saleUnitLabel. Purchases are received in $_purchaseUnitLabel.'
                    : 'This product uses $_saleUnitLabel for selling, stocking, and purchases.',
              ),
              if (_trackStock && _useUnitConversion) ...[
                SizedBox(height: 8),
                Text(
                  '1 $_saleUnitLabel = ${UnitUtils.formatQuantity(_saleToStockFactor)} $_stockUnitLabel',
                ),
                Text(
                  '1 $_purchaseUnitLabel = ${UnitUtils.formatQuantity(_purchaseToStockFactor)} $_stockUnitLabel',
                ),
              ],
              if (_trackStock && _stockValue != null) ...[
                SizedBox(height: 8),
                Text(
                  'Current stock will be saved as ${UnitUtils.formatWithUnit(_stockValue, _effectiveStockUnit)}.',
                ),
              ],
              if (_trackStock && _lowStockValue != null) ...[
                SizedBox(height: 4),
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

  void _continueWizard() {
    if (_currentStep >= _wizardSteps.length - 1) {
      _save();
      return;
    }

    if (_canProceed) {
      setState(() => _currentStep++);
    }
  }

  void _previousWizardStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Widget _buildWizardProgress() {
    return SizedBox(
      height: 60,
      child: Row(
        children: List.generate(_wizardSteps.length, (index) {
          final isCurrent = index == _currentStep;
          final isComplete = index < _currentStep;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isComplete
                              ? AppColors.success
                              : isCurrent
                              ? AppColors.primary
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          border: Border.all(
                            color: isComplete
                                ? AppColors.success
                                : isCurrent
                                ? AppColors.primary
                                : Theme.of(context).colorScheme.outline,
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: isComplete
                            ? Icon(Icons.check, size: 16, color: Colors.white)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isCurrent
                                      ? Colors.white
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                      if (index < _wizardSteps.length - 1) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Container(
                            height: 2,
                            color: index < _currentStep
                                ? AppColors.success
                                : Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildImagePicker() {
    final isCompactLayout = MediaQuery.sizeOf(context).width < 600;
    final imageUrls = _normalizedProductImageUrls();
    final hasImage = _hasDisplayableProductImage();
    final imagePath = imageUrls.isNotEmpty ? imageUrls.first : '';

    return Column(
      children: [
        if (hasImage) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                _buildProductImagePreview(imagePath),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    child: IconButton(
                      icon: Icon(Icons.close, color: Colors.white, size: 20),
                      tooltip: 'Remove image',
                      onPressed: _isUploadingImage
                          ? null
                          : () => _removeProductImageUrl(imagePath),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          _buildImageHostingStatus(),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isEnhancingImage || _isUploadingImage || _isLoading
                  ? null
                  : _enhanceImage,
              icon: _isEnhancingImage
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.auto_fix_high_rounded, size: 18),
              label: Text(
                _isEnhancingImage
                    ? 'Enhancing image...'
                    : 'Enhance with Piki AI',
              ),
            ),
          ),
          SizedBox(height: 16),
        ],
        if (isCompactLayout)
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isUploadingImage
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                  icon: Icon(Icons.photo_library_outlined, size: 18),
                  label: Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isUploadingImage
                      ? null
                      : () => _pickImage(ImageSource.camera),
                  icon: Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                    ),
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
                  onPressed: _isUploadingImage
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                  icon: Icon(Icons.photo_library_outlined, size: 18),
                  label: Text('Gallery'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isUploadingImage
                      ? null
                      : () => _pickImage(ImageSource.camera),
                  icon: Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _imageUrlController,
                decoration: const InputDecoration(
                  labelText: 'Add product photo URL',
                  hintText: 'https://...',
                  prefixIcon: Icon(Icons.link_outlined),
                ),
                onSubmitted: (_) => _addProductImageFromInput(),
              ),
            ),
            SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _addProductImageFromInput,
              icon: Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text('Add'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
        if (imageUrls.isNotEmpty) ...[
          SizedBox(height: 16),
          _buildProductImageGallery(imageUrls),
        ],
      ],
    );
  }

  // ──────────────────── Wizard Step 1: Basic Information ────────────────────
  Widget _buildProductImageGallery(List<String> imageUrls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${imageUrls.length} online photo${imageUrls.length == 1 ? '' : 's'}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < imageUrls.length; index++)
                Padding(
                  padding: EdgeInsets.only(
                    right: index == imageUrls.length - 1 ? 0 : 10,
                  ),
                  child: _buildProductImageThumb(imageUrls[index], index),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductImageThumb(String url, int index) {
    final isRemote = ProductImageUploadService.isRemoteImage(url);
    return Container(
      width: 128,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: isRemote
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildImageThumbFallback(),
                  )
                : Image.file(
                    _imageFileForPath(url),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildImageThumbFallback(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  index == 0 ? 'Main photo' : 'Photo ${index + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: index == 0
                        ? AppColors.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Make main',
                      onPressed: index == 0
                          ? null
                          : () => _makeMainProductImage(url),
                      icon: Icon(Icons.star_outline, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => _removeProductImageUrl(url),
                      icon: Icon(Icons.delete_outline, size: 18),
                      visualDensity: VisualDensity.compact,
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

  Widget _buildImageThumbFallback() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildStep1BasicInfo() {
    final categoriesAsync = ref.watch(categoriesProvider);
    final isCompactLayout = MediaQuery.sizeOf(context).width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Basic Information', icon: Icons.info_outline),
        SizedBox(height: 16),
        TrainingAnchor(
          id: 'productForm.identity',
          child: _FormCard(
            children: [
              _LabeledField(
                label: 'Product Name *',
                child: TextFormField(
                  controller: _nameController,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Name is required' : null,
                  decoration: InputDecoration(hintText: 'e.g. Wireless Mouse'),
                ),
              ),
              SizedBox(height: 20),
              _LabeledField(
                label: 'Brand',
                child: TextFormField(
                  controller: _brandController,
                  decoration: InputDecoration(
                    hintText: 'e.g. Logitech, Samsung',
                  ),
                ),
              ),
              SizedBox(height: 20),
              _LabeledField(
                label: 'Online Product Description',
                child: TextFormField(
                  controller: _descriptionController,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 420,
                  decoration: InputDecoration(
                    hintText:
                        'Describe size, material, ingredients, care notes, or what makes this product special.',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              SizedBox(height: 20),
              if (isCompactLayout)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LabeledField(
                      label: 'SKU',
                      child: TextFormField(
                        controller: _skuController,
                        decoration: InputDecoration(hintText: 'e.g. ELC-001'),
                      ),
                    ),
                    SizedBox(height: 20),
                    _LabeledField(
                      label: 'Barcode',
                      child: TextFormField(
                        controller: _barcodeController,
                        decoration: InputDecoration(
                          hintText: 'e.g. 1000000001',
                          suffixIcon: (Platform.isAndroid || Platform.isIOS)
                              ? IconButton(
                                  icon: Icon(
                                    Icons.qr_code_scanner,
                                    color: AppColors.primary,
                                  ),
                                  tooltip: 'Scan barcode',
                                  onPressed: () async {
                                    final barcode = await Navigator.of(context)
                                        .push<String>(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const BarcodeScannerScreen(),
                                          ),
                                        );
                                    if (barcode != null && barcode.isNotEmpty) {
                                      _barcodeController.text = barcode;
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
                          decoration: InputDecoration(hintText: 'e.g. ELC-001'),
                        ),
                      ),
                    ),
                    SizedBox(width: 20),
                    Expanded(
                      child: _LabeledField(
                        label: 'Barcode',
                        child: TextFormField(
                          controller: _barcodeController,
                          decoration: InputDecoration(
                            hintText: 'e.g. 1000000001',
                            suffixIcon: (Platform.isAndroid || Platform.isIOS)
                                ? IconButton(
                                    icon: Icon(
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
                                        _barcodeController.text = barcode;
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
              SizedBox(height: 20),
              _LabeledField(
                label: 'Category',
                child: categoriesAsync.when(
                  data: (categories) => DropdownButtonFormField<String?>(
                    initialValue: _selectedCategoryId,
                    dropdownColor: context.appSurface,
                    decoration: const InputDecoration(),
                    items: [
                      DropdownMenuItem(value: null, child: Text('No category')),
                      ...categories.map(
                        (cat) => DropdownMenuItem(
                          value: cat['id'] as String,
                          child: Text(cat['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => Text('Error loading categories'),
                ),
              ),
              SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      value: _showOnline,
                      title: Text('Show this product online'),
                      subtitle: Text(
                        _showOnline
                            ? 'Customers can find and order this product from the store link.'
                            : 'Hidden from the online store, but still available inside POS.',
                      ),
                      onChanged: _isLoading
                          ? null
                          : (value) => setState(() => _showOnline = value),
                    ),
                    Divider(height: 1),
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      value: _isFeatured,
                      title: Text('Feature on storefront'),
                      subtitle: Text(
                        'Pin this product into the featured area above the full catalog.',
                      ),
                      onChanged: _isLoading
                          ? null
                          : (value) => setState(() => _isFeatured = value),
                    ),
                  ],
                ),
              ),
              if (!_isEditing) ...[
                SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    leading: Icon(Icons.event_available_outlined),
                    title: Text('Initial Batch Expiry Date'),
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
                            onPressed: () =>
                                setState(() => _initialExpiryDate = null),
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
                              context: context,
                              initialDate:
                                  _initialExpiryDate ??
                                  DateTime.now().add(const Duration(days: 30)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => _initialExpiryDate = picked);
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
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ──────────────────── Wizard Step 2: Pricing & Units ────────────────────
  Widget _buildStep2PricingUnits() {
    final isCompactLayout = MediaQuery.sizeOf(context).width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Pricing', icon: Icons.attach_money),
        SizedBox(height: 16),
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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return _hasVariants ? null : 'Price is required';
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
                    SizedBox(height: 20),
                    _buildCostField(),
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
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return _hasVariants ? null : 'Price is required';
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
                    SizedBox(width: 20),
                    Expanded(child: _buildCostField()),
                  ],
                ),
              if (_priceController.text.isNotEmpty &&
                  _costController.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Builder(
                    builder: (context) {
                      final price = double.tryParse(_priceController.text) ?? 0;
                      final rawCost =
                          double.tryParse(_costController.text) ?? 0;
                      final stock = double.tryParse(_stockController.text) ?? 1;
                      final cost = _isTotalCostMode
                          ? (stock > 0 ? (rawCost / stock) : rawCost)
                          : rawCost;
                      final margin = price > 0
                          ? ((price - cost) / price * 100)
                          : 0;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Icon(
                              Icons.trending_up,
                              size: 16,
                              color: AppColors.success,
                            ),
                            Text(
                              'Margin: ${margin.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Profit: ${ShopSettings.currency}${(price - cost).toStringAsFixed(2)}',
                              style: TextStyle(color: AppColors.success),
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
        SizedBox(height: 28),
        _SectionHeader(title: 'Units', icon: Icons.straighten_outlined),
        SizedBox(height: 16),
        TrainingAnchor(
          id: 'productForm.units',
          child: _FormCard(children: [_buildUnitConfigurationCard()]),
        ),
      ],
    );
  }

  Widget _buildCostField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cost Type ($_saleUnitLabel):',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Per Unit', style: TextStyle(fontSize: 12)),
              ),
              ButtonSegment(
                value: true,
                label: Text('Bulk Invoice', style: TextStyle(fontSize: 12)),
              ),
            ],
            selected: {_isTotalCostMode},
            onSelectionChanged: (val) =>
                setState(() => _isTotalCostMode = val.first),
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            showSelectedIcon: false,
          ),
        ),
        SizedBox(height: 12),
        _LabeledField(
          label: _isTotalCostMode
              ? 'Bulk Total Invoice Cost (optional)'
              : 'Cost per $_saleUnitLabel (optional)',
          child: TextFormField(
            controller: _costController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              if (double.tryParse(v) == null) return 'Invalid cost';
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
    );
  }

  // ──────────────────── Wizard Step 3: Inventory & Image ────────────────────
  Widget _buildStep3InventoryImage() {
    final isCompactLayout = MediaQuery.sizeOf(context).width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Inventory', icon: Icons.warehouse_outlined),
        SizedBox(height: 16),
        TrainingAnchor(
          id: 'productForm.inventory',
          child: _FormCard(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _trackStock,
                title: Text('Track stock for this product'),
                subtitle: Text(
                  _trackStock
                      ? 'Use stock limits for packaged inventory and items you count.'
                      : 'Sell without stock limits. Good for cooked food, services, and custom charges.',
                ),
                onChanged: _isLoading
                    ? null
                    : (value) => setState(() => _trackStock = value),
              ),
              SizedBox(height: 16),
              if (_hasVariants) ...[
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
                  child: Text(
                    !_trackStock
                        ? 'Variants can still be used for choices, but stock will not block sales while tracking is off.'
                        : _isEditing
                        ? 'Parent stock stays synced from the variants you manage below. Use this screen for product defaults, then add real stock on each variant.'
                        : 'Save the product first, then add real stock on each variant from the variant manager.',
                    style: TextStyle(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(height: 20),
              ],
              if (!_trackStock)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  child: Text(
                    'Stock fields are ignored for this product. It will stay sellable even when stock is zero.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [_quantityFormatter],
                        decoration: InputDecoration(
                          hintText: _stockAllowsDecimal ? '0.000' : '0',
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
                    SizedBox(height: 20),
                    _LabeledField(
                      label: 'Low Stock Alert ($_stockUnitLabel)',
                      child: TextFormField(
                        controller: _lowStockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [_quantityFormatter],
                        decoration: InputDecoration(
                          hintText: _stockAllowsDecimal ? '5.000' : '5',
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
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [_quantityFormatter],
                          decoration: InputDecoration(
                            hintText: _stockAllowsDecimal ? '0.000' : '0',
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
                    SizedBox(width: 20),
                    Expanded(
                      child: _LabeledField(
                        label: 'Low Stock Alert ($_stockUnitLabel)',
                        child: TextFormField(
                          controller: _lowStockController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [_quantityFormatter],
                          decoration: InputDecoration(
                            hintText: _stockAllowsDecimal ? '5.000' : '5',
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
        SizedBox(height: 28),
        _SectionHeader(title: 'Product Image', icon: Icons.image_outlined),
        SizedBox(height: 16),
        _FormCard(children: [_buildImagePicker()]),
      ],
    );
  }

  // ──────────────────── Wizard Step 4: Review ────────────────────
  Widget _buildStep4Review() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Review your product before saving:',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
        ),
        _FormCard(
          children: [
            _buildReviewRow(
              'Name',
              _nameController.text.isNotEmpty ? _nameController.text : '-',
            ),
            _buildReviewRow(
              'Brand',
              _brandController.text.isNotEmpty ? _brandController.text : '-',
            ),
            _buildReviewRow(
              'Online Description',
              _descriptionController.text.trim().isNotEmpty
                  ? _descriptionController.text.trim()
                  : '-',
            ),
            _buildReviewRow(
              'Category',
              _selectedCategoryId != null ? 'Set' : 'None',
            ),
            _buildReviewRow('Show Online', _showOnline ? 'Yes' : 'No'),
            _buildReviewRow('Featured', _isFeatured ? 'Yes' : 'No'),
            _buildReviewRow(
              'SKU',
              _skuController.text.isNotEmpty ? _skuController.text : '-',
            ),
            _buildReviewRow(
              'Barcode',
              _barcodeController.text.isNotEmpty
                  ? _barcodeController.text
                  : '-',
            ),
            Divider(height: 24),
            _buildReviewRow(
              'Selling Price',
              _priceController.text.isNotEmpty
                  ? '${ShopSettings.currency} ${_priceController.text} / $_saleUnitLabel'
                  : '-',
            ),
            _buildReviewRow(
              'Cost',
              _costController.text.isNotEmpty
                  ? (_isTotalCostMode
                        ? '${ShopSettings.currency} ${_costController.text} (bulk invoice)'
                        : '${ShopSettings.currency} ${_costController.text} / $_saleUnitLabel')
                  : '-',
            ),
            _buildReviewRow(
              'Unit',
              _useUnitConversion
                  ? 'Sell: $_saleUnitLabel, Stock: $_stockUnitLabel, Buy: $_purchaseUnitLabel'
                  : _saleUnitLabel,
            ),
            Divider(height: 24),
            _buildReviewRow('Track Stock', _trackStock ? 'Yes' : 'No'),
            if (_trackStock) ...[
              _buildReviewRow(
                'Current Stock',
                '$_stockLabelOfCurrent $_stockUnitLabel',
              ),
              _buildReviewRow(
                'Low Stock Alert',
                '$_lowStockLabelOfCurrent $_stockUnitLabel',
              ),
            ],
            _buildReviewRow(
              'Images',
              _normalizedProductImageUrls().isEmpty
                  ? 'None'
                  : '${_normalizedProductImageUrls().length} photo${_normalizedProductImageUrls().length == 1 ? '' : 's'}',
            ),
            if (_initialExpiryDate != null)
              _buildReviewRow(
                'Expiry Date',
                ExpiryUtils.format(_initialExpiryDate!),
              ),
          ],
        ),
        SizedBox(height: 20),
        _SectionHeader(title: 'Variants', icon: Icons.tune_outlined),
        SizedBox(height: 16),
        _FormCard(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _hasVariants,
              title: Text('This product has variants'),
              subtitle: Text(
                _hasVariants
                    ? 'Sell this item by real choices like size, color, or pack type.'
                    : 'Keep this as one direct sellable product.',
              ),
              onChanged: _isLoading
                  ? null
                  : (value) => setState(() => _hasVariants = value),
            ),
            SizedBox(height: 12),
            Text(
              _hasVariants
                  ? 'Save your product, then manage variants to add choices, edit stock, and set specific pricing.'
                  : 'Simple products keep price and stock directly on the main product record.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            if (_hasVariants) ...[
              SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isLoading || _isEnhancingImage || _isUploadingImage
                    ? null
                    : () => _save(openVariants: true),
                icon: Icon(Icons.tune_outlined, size: 18),
                label: Text('Save & Manage Variants'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  String get _stockLabelOfCurrent => _trackStock
      ? (_stockController.text.isNotEmpty ? _stockController.text : '0')
      : '-';
  String get _lowStockLabelOfCurrent => _trackStock
      ? (_lowStockController.text.isNotEmpty ? _lowStockController.text : '5')
      : '-';

  Widget _buildReviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────── Main Build ────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(_isEditing ? 'Edit Product' : 'New Product'),
        actions: [
          if (_currentStep == _wizardSteps.length - 1)
            TrainingAnchor(
              id: 'productForm.save',
              child: FilledButton.icon(
                onPressed: _isLoading || _isEnhancingImage || _isUploadingImage
                    ? null
                    : _save,
                icon: _isLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_isEditing ? Icons.save : Icons.add, size: 18),
                label: Text(_isEditing ? 'Save Changes' : 'Create Product'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ),
          SizedBox(width: 16),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 680),
            margin: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWizardProgress(),
                  SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _buildStepContent(),
                  ),
                  SizedBox(height: 28),
                  _buildWizardActions(),
                  SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return SizedBox(key: ValueKey('step_0'), child: _buildStep1BasicInfo());
      case 1:
        return SizedBox(
          key: ValueKey('step_1'),
          child: _buildStep2PricingUnits(),
        );
      case 2:
        return SizedBox(
          key: ValueKey('step_2'),
          child: _buildStep3InventoryImage(),
        );
      case 3:
        return SizedBox(key: ValueKey('step_3'), child: _buildStep4Review());
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWizardActions() {
    final isFirst = _currentStep == 0;
    final isLast = _currentStep == _wizardSteps.length - 1;

    return Row(
      children: [
        if (!isFirst)
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _previousWizardStep,
            icon: Icon(Icons.arrow_back, size: 18),
            label: Text('Back'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        const Spacer(),
        Text(
          'Step ${_currentStep + 1} of ${_wizardSteps.length}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: _isLoading || _isEnhancingImage || _isUploadingImage
              ? null
              : _continueWizard,
          icon: _isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(isLast ? Icons.check : Icons.arrow_forward, size: 18),
          label: Text(
            isLast
                ? (_isEditing ? 'Save Changes' : 'Create Product')
                : 'Continue',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
      ],
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
        SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
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
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 8),
        child,
      ],
    );
  }
}
