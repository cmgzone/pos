import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/utils/expiry_utils.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/utils/category_icon_utils.dart';
import '../../../widgets/compact_header_actions.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../training/widgets/training_anchor.dart';
import '../../purchases/presentation/purchase_management_screen.dart';
import '../data/product_provider.dart';
import '../data/product_repository.dart';
import 'catalog_orders_screen.dart';
import 'product_form_screen.dart';
import 'product_batches_screen.dart';
import 'category_management_screen.dart';
import 'product_variants_screen.dart';
import 'stock_list_screen.dart';
import '../../app/app_shell.dart';

enum _MobileProductPageAction {
  catalogOrders,
  stockList,
  purchases,
  categories,
}

enum _MobileProductMenuAction { viewStock, adjustStock, edit, delete }

class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  String _searchQuery = '';
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 800;
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        toolbarHeight: 50,
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () =>
                    AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        title: Text(
          isMobile ? 'Products' : 'Product Management',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (!isMobile)
            CompactHeaderButton(
              onPressed: _openCatalogOrders,
              icon: Icons.receipt_long_outlined,
              label: 'Catalog Orders',
              filled: false,
            ),
          if (!isMobile) const SizedBox(width: 6),
          if (!isMobile)
            CompactHeaderButton(
              onPressed: _openStockList,
              icon: Icons.fact_check_outlined,
              label: 'Stock List',
              filled: false,
            ),
          if (!isMobile) const SizedBox(width: 4),
          if (!isMobile)
            CompactHeaderIconButton(
              icon: Icons.local_shipping_outlined,
              tooltip: 'Purchases & Suppliers',
              onPressed: _openPurchases,
            ),
          if (!isMobile)
            CompactHeaderIconButton(
              icon: Icons.category_outlined,
              tooltip: 'Manage Categories',
              onPressed: _openCategories,
            ),
          TrainingAnchor(
            id: 'products.add',
            child: isMobile
                ? IconButton(
                    tooltip: 'Add Product',
                    onPressed: _addProduct,
                    icon: const Icon(Icons.add_circle_outline),
                  )
                : CompactHeaderButton(
                    onPressed: _addProduct,
                    icon: Icons.add,
                    label: 'Add Product',
                  ),
          ),
          if (isMobile)
            PopupMenuButton<_MobileProductPageAction>(
              tooltip: 'More product tools',
              onSelected: _handleMobilePageAction,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _MobileProductPageAction.catalogOrders,
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_outlined),
                    title: Text('Catalog Orders'),
                  ),
                ),
                PopupMenuItem(
                  value: _MobileProductPageAction.stockList,
                  child: ListTile(
                    leading: Icon(Icons.fact_check_outlined),
                    title: Text('Stock List'),
                  ),
                ),
                PopupMenuItem(
                  value: _MobileProductPageAction.purchases,
                  child: ListTile(
                    leading: Icon(Icons.local_shipping_outlined),
                    title: Text('Purchases & Suppliers'),
                  ),
                ),
                PopupMenuItem(
                  value: _MobileProductPageAction.categories,
                  child: ListTile(
                    leading: Icon(Icons.category_outlined),
                    title: Text('Manage Categories'),
                  ),
                ),
              ],
            ),
          SizedBox(width: isMobile ? 4 : 16),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndFilter(categoriesAsync, isMobile),
          const Divider(height: 1),

          // Product table
          Expanded(
            child: TrainingAnchor(
              id: 'products.list',
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _getFilteredProducts(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return ListView.separated(
                      padding: EdgeInsets.all(isMobile ? 12 : 24),
                      itemCount: 8,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, _) => Container(
                        height: 100,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceHighlight.withValues(
                            alpha: 0.3,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    );
                  }
                  final products = snapshot.data ?? [];
                  if (products.isEmpty) {
                    return EmptyStateWidget(
                      icon: Icons.inventory_2_outlined,
                      title: _searchQuery.isEmpty
                          ? 'No products yet'
                          : 'No results found',
                      subtitle: _searchQuery.isEmpty
                          ? 'Add your first product to start managing inventory.'
                          : 'Try searching with different keywords or clear the filter.',
                      actionLabel: _searchQuery.isEmpty
                          ? 'Add Your First Product'
                          : null,
                      onAction: _searchQuery.isEmpty
                          ? () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ProductFormScreen(),
                                ),
                              );
                              if (result == true) _refreshProducts();
                            }
                          : null,
                    );
                  }

                  return ListView.separated(
                    padding: EdgeInsets.all(isMobile ? 12 : 24),
                    itemCount: products.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      // Resolve category name for icon fallback
                      final catId = product['category_id'] as String?;
                      final catName = catId != null
                          ? categoriesAsync.valueOrNull?.firstWhere(
                                  (c) => c['id'] == catId,
                                  orElse: () => {},
                                )['name']
                                as String?
                          : null;
                      return _ProductRow(
                        product: product,
                        categoryName: catName,
                        onEdit: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductFormScreen(product: product),
                            ),
                          );
                          if (result == true) _refreshProducts();
                        },
                        onAdjustStock: () =>
                            _showStockAdjustmentDialog(product),
                        onViewBatches: () => _viewBatches(context, product),
                        onDelete: () => _confirmDelete(product),
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // Footer stats
          TrainingAnchor(
            id: 'products.stats',
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 24,
                vertical: isMobile ? 8 : 12,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _getFilteredProducts(),
                builder: (context, snapshot) {
                  final products = snapshot.data ?? [];
                  final lowStock = products.where((p) {
                    if (!UnitUtils.tracksStock(p)) {
                      return false;
                    }
                    final stock = (p['stock'] as num? ?? 0).toDouble();
                    final lowThreshold = (p['low_stock'] as num? ?? 5)
                        .toDouble();
                    return stock <= lowThreshold;
                  }).length;
                  final unitTypes = products
                      .map((p) => UnitUtils.normalize(p['unit'] as String?))
                      .toSet()
                      .length;
                  return Wrap(
                    spacing: isMobile ? 8 : 16,
                    runSpacing: isMobile ? 8 : 12,
                    children: [
                      _StatChip(
                        icon: Icons.inventory,
                        label: '${products.length} Products',
                        color: AppColors.primary,
                      ),
                      _StatChip(
                        icon: Icons.straighten,
                        label: '$unitTypes Unit Types',
                        color: AppColors.secondary,
                      ),
                      if (lowStock > 0)
                        _StatChip(
                          icon: Icons.warning_amber,
                          label: '$lowStock Low Stock',
                          color: AppColors.warning,
                        ),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: ProductRepository.getExpiryAlerts(),
                        builder: (context, expirySnapshot) {
                          final alertCount = expirySnapshot.data?.length ?? 0;
                          if (alertCount == 0) {
                            return const SizedBox.shrink();
                          }
                          return _StatChip(
                            icon: Icons.event_busy_outlined,
                            label:
                                '$alertCount Expiry Alert${alertCount == 1 ? '' : 's'}',
                            color: AppColors.error,
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter(
    AsyncValue<List<Map<String, dynamic>>> categoriesAsync,
    bool isMobile,
  ) {
    final search = TextField(
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: const InputDecoration(
        hintText: 'Search name, SKU, or barcode...',
        prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
        contentPadding: EdgeInsets.symmetric(vertical: 12),
      ),
    );
    final categories = categoriesAsync.when(
      data: (items) => Container(
        width: isMobile ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceHighlight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            isExpanded: isMobile,
            value: _selectedCategory,
            hint: const Text('All Categories', style: TextStyle(fontSize: 14)),
            dropdownColor: AppColors.surface,
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('All Categories'),
              ),
              ...items.map(
                (category) => DropdownMenuItem(
                  value: category['id'] as String,
                  child: Text(category['name'] as String),
                ),
              ),
            ],
            onChanged: (value) => setState(() => _selectedCategory = value),
          ),
        ),
      ),
      loading: () => const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );

    return TrainingAnchor(
      id: 'products.search',
      child: Container(
        color: AppColors.surface,
        padding: EdgeInsets.fromLTRB(
          isMobile ? 12 : 24,
          isMobile ? 12 : 0,
          isMobile ? 12 : 24,
          12,
        ),
        child: isMobile
            ? Column(children: [search, const SizedBox(height: 8), categories])
            : Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 16),
                  categories,
                ],
              ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getFilteredProducts() async {
    if (_searchQuery.isNotEmpty) {
      return ProductRepository.search(_searchQuery);
    }
    return ProductRepository.getAll(categoryId: _selectedCategory);
  }

  void _refreshProducts() {
    ref.invalidate(filteredProductsProvider);
    setState(() {});
  }

  Future<void> _addProduct() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProductFormScreen()),
    );
    if (result == true) _refreshProducts();
  }

  Future<void> _openStockList() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StockListScreen()),
    );
    _refreshProducts();
  }

  Future<void> _openCatalogOrders() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CatalogOrdersScreen()),
    );
  }

  Future<void> _openPurchases() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PurchaseManagementScreen()),
    );
    _refreshProducts();
  }

  Future<void> _openCategories() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CategoryManagementScreen()),
    );
    ref.invalidate(categoriesProvider);
    ref.invalidate(filteredProductsProvider);
  }

  Future<void> _handleMobilePageAction(_MobileProductPageAction action) async {
    switch (action) {
      case _MobileProductPageAction.catalogOrders:
        await _openCatalogOrders();
      case _MobileProductPageAction.stockList:
        await _openStockList();
      case _MobileProductPageAction.purchases:
        await _openPurchases();
      case _MobileProductPageAction.categories:
        await _openCategories();
    }
  }

  void _showStockAdjustmentDialog(Map<String, dynamic> product) {
    if (!UnitUtils.tracksStock(product)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${product['name']} does not track stock. Turn on stock tracking in Edit Product to receive inventory.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final hasVariants = ((product['has_variants'] as num?) ?? 0) == 1;
    if (hasVariants) {
      _openVariantManager(product);
      return;
    }

    bool isTotalCostMode = false;
    DateTime? expiryDate;
    final purchaseUnit = UnitUtils.purchaseUnitForProduct(product);
    final stockUnit = UnitUtils.stockUnitForProduct(product);
    final purchaseUnitLabel = UnitUtils.label(purchaseUnit);
    final stockUnitLabel = UnitUtils.label(stockUnit);
    final allowsDecimal = UnitUtils.allowsDecimal(purchaseUnit);
    final conversionFactor =
        UnitUtils.conversionFactor(purchaseUnit, stockUnit) ?? 1.0;
    final qtyController = TextEditingController();
    final batchNumberController = TextEditingController();
    final costController = TextEditingController(
      text: (product['cost'] as num? ?? 0).toString(),
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Receive Stock: ${product['name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                purchaseUnit == stockUnit
                    ? 'Log incoming stock in $purchaseUnitLabel so your inventory stays accurate.'
                    : 'Receive stock in $purchaseUnitLabel and it will be stored as $stockUnitLabel automatically.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qtyController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(allowsDecimal ? r'^\d*\.?\d{0,3}' : r'^\d*'),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: 'Quantity Received ($purchaseUnitLabel)',
                  prefixIcon: const Icon(Icons.add_shopping_cart),
                ),
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              if (purchaseUnit != stockUnit &&
                  qtyController.text.trim().isNotEmpty &&
                  double.tryParse(qtyController.text) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      'Stored stock: ${UnitUtils.formatQuantity((double.tryParse(qtyController.text) ?? 0) * conversionFactor)} $stockUnitLabel',
                      style: const TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: batchNumberController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Batch Number',
                  prefixIcon: Icon(Icons.numbers_outlined),
                  helperText: 'Recommended for medicine stock tracking.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              RadioGroup<bool>(
                groupValue: isTotalCostMode,
                onChanged: (val) {
                  setState(() => isTotalCostMode = val!);
                  costController.clear();
                },
                child: Row(
                  children: [
                    Expanded(
                      child: RadioListTile<bool>(
                        title: Text(
                          'Per $purchaseUnitLabel Cost',
                          style: const TextStyle(fontSize: 13),
                        ),
                        value: false,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        title: const Text(
                          'Bulk Total Invoice',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                          ),
                        ),
                        value: true,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ),
              TextField(
                controller: costController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: isTotalCostMode
                      ? 'Total Invoice Cost for this stock'
                      : 'Cost Per $purchaseUnitLabel',
                  prefixIcon: const Icon(Icons.attach_money),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (isTotalCostMode &&
                  qtyController.text.isNotEmpty &&
                  costController.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'Auto-Calculated Unit Cost: ${ShopSettings.currency}${((double.tryParse(costController.text) ?? 0) / ((double.tryParse(qtyController.text) ?? 1) == 0 ? 1 : (double.tryParse(qtyController.text) ?? 1))).toStringAsFixed(2)}/$purchaseUnitLabel',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
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
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Expiry Date'),
                  subtitle: Text(
                    expiryDate == null
                        ? 'Optional for this stock batch'
                        : '${ExpiryUtils.format(expiryDate)} - ${ExpiryUtils.statusLabel(expiryDate)}',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      if (expiryDate != null)
                        IconButton(
                          tooltip: 'Clear expiry date',
                          onPressed: () => setState(() => expiryDate = null),
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
                                expiryDate ??
                                DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => expiryDate = picked);
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final addedQty = double.tryParse(qtyController.text);
                final costInput = double.tryParse(costController.text);
                if (addedQty != null && addedQty > 0 && costInput != null) {
                  final finalUnitCost = isTotalCostMode
                      ? (costInput / addedQty)
                      : costInput;
                  await ProductRepository.addStockBatch(
                    productId: product['id'] as String,
                    quantity: addedQty,
                    unitCost: finalUnitCost,
                    product: product,
                    sourceUnit: purchaseUnit,
                    expiryDate: ExpiryUtils.toStorageString(expiryDate),
                    batchNumber: batchNumberController.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _refreshProducts();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          purchaseUnit == stockUnit
                              ? 'Received ${UnitUtils.formatWithUnit(addedQty, purchaseUnit)} of ${product['name']}!'
                              : 'Received ${UnitUtils.formatWithUnit(addedQty, purchaseUnit)} of ${product['name']} and stored it as ${UnitUtils.formatQuantity(addedQty * conversionFactor)} $stockUnitLabel.',
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Save Stock'),
            ),
          ],
        ),
      ),
    );
  }

  void _viewBatches(BuildContext context, Map<String, dynamic> product) {
    if (!UnitUtils.tracksStock(product)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product['name']} does not track stock batches.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final hasVariants = ((product['has_variants'] as num?) ?? 0) == 1;
    if (hasVariants) {
      _openVariantManager(product);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductBatchesScreen(product: product)),
    );
  }

  Future<void> _openVariantManager(Map<String, dynamic> product) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductVariantsScreen(product: product),
      ),
    );
    if (changed == true) {
      _refreshProducts();
    }
  }

  void _confirmDelete(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Product'),
        content: Text(
          'Are you sure you want to delete "${product['name']}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await ProductRepository.delete(product['id'] as String);
              if (ctx.mounted) Navigator.pop(ctx);
              _refreshProducts();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${product['name']} deleted'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final Map<String, dynamic> product;
  final String? categoryName;
  final VoidCallback onEdit;
  final VoidCallback onAdjustStock;
  final VoidCallback onViewBatches;
  final VoidCallback onDelete;

  const _ProductRow({
    required this.product,
    this.categoryName,
    required this.onEdit,
    required this.onAdjustStock,
    required this.onViewBatches,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final stock = (product['stock'] as num? ?? 0).toDouble();
    final lowStock = (product['low_stock'] as num? ?? 5).toDouble();
    final saleUnit = UnitUtils.saleUnitForProduct(product);
    final stockUnit = UnitUtils.stockUnitForProduct(product);
    final hasVariants = ((product['has_variants'] as num?) ?? 0) == 1;
    final tracksStock = UnitUtils.tracksStock(product);
    final isLow = tracksStock && stock <= lowStock && stock > 0;
    final isOut = tracksStock && stock == 0;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isMobile
          ? _buildMobileLayout(
              context,
              isOut,
              isLow,
              stock,
              saleUnit,
              stockUnit,
              hasVariants,
              tracksStock,
            )
          : Row(
              children: [
                // Image or Icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildProductImage(product['image_url'] as String?),
                ),
                const SizedBox(width: 16),

                // Name + SKU
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (product['brand'] != null &&
                          (product['brand'] as String).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            (product['brand'] as String).toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      Text(
                        product['name'] as String? ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SKU: ${product['sku'] ?? 'N/A'} · Barcode: ${product['barcode'] ?? 'N/A'}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasVariants
                            ? 'Variants enabled - Sell: ${UnitUtils.label(saleUnit)} - Stock: ${UnitUtils.label(stockUnit)}'
                            : !tracksStock
                            ? 'No stock tracking'
                            : saleUnit == stockUnit
                            ? 'Unit: ${UnitUtils.label(saleUnit)}'
                            : 'Sell: ${UnitUtils.label(saleUnit)} - Stock: ${UnitUtils.label(stockUnit)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Price
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${ShopSettings.currency}${(product['price'] as num? ?? 0).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      Text(
                        UnitUtils.priceLabel(saleUnit),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      if (product['cost'] != null)
                        Text(
                          'Cost: ${ShopSettings.currency}${(product['cost'] as num).toStringAsFixed(2)}/${UnitUtils.label(saleUnit)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),

                // Stock badge
                Container(
                  width: 120,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isOut
                        ? AppColors.error.withValues(alpha: 0.12)
                        : !tracksStock
                        ? AppColors.primary.withValues(alpha: 0.10)
                        : isLow
                        ? AppColors.warning.withValues(alpha: 0.12)
                        : AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    !tracksStock
                        ? 'No stock limit'
                        : isOut
                        ? 'Out of stock'
                        : UnitUtils.formatWithUnit(stock, stockUnit),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isOut
                          ? AppColors.error
                          : !tracksStock
                          ? AppColors.primary
                          : isLow
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Actions
                IconButton(
                  icon: const Icon(
                    Icons.history,
                    size: 20,
                    color: AppColors.primaryLight,
                  ),
                  tooltip: hasVariants ? 'Manage Variants' : 'View Batches',
                  onPressed: tracksStock ? onViewBatches : null,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.add_box_outlined,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  tooltip: hasVariants
                      ? 'Adjust Variant Stock'
                      : 'Receive Stock',
                  onPressed: tracksStock ? onAdjustStock : null,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  tooltip: 'Edit',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppColors.error,
                  ),
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
              ],
            ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    bool isOut,
    bool isLow,
    double stock,
    String saleUnit,
    String stockUnit,
    bool hasVariants,
    bool tracksStock,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildProductImage(product['image_url'] as String?),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name'] as String? ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    'SKU: ${product['sku'] ?? 'N/A'}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    hasVariants
                        ? 'Variants enabled - Sell: ${UnitUtils.label(saleUnit)} - Stock: ${UnitUtils.label(stockUnit)}'
                        : !tracksStock
                        ? 'No stock tracking'
                        : saleUnit == stockUnit
                        ? 'Unit: ${UnitUtils.label(saleUnit)}'
                        : 'Sell: ${UnitUtils.label(saleUnit)} - Stock: ${UnitUtils.label(stockUnit)}',
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
                  '${ShopSettings.currency}${(product['price'] as num? ?? 0).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.primaryLight,
                  ),
                ),
                Text(
                  UnitUtils.priceLabel(saleUnit),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                if (product['cost'] != null)
                  Text(
                    'C: ${ShopSettings.currency}${(product['cost'] as num).toStringAsFixed(2)}/${UnitUtils.label(saleUnit)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isOut
                    ? AppColors.error.withValues(alpha: 0.12)
                    : !tracksStock
                    ? AppColors.primary.withValues(alpha: 0.10)
                    : isLow
                    ? AppColors.warning.withValues(alpha: 0.12)
                    : AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                !tracksStock
                    ? 'No stock limit'
                    : isOut
                    ? 'Out'
                    : UnitUtils.formatWithUnit(stock, stockUnit),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isOut
                      ? AppColors.error
                      : !tracksStock
                      ? AppColors.primary
                      : isLow
                      ? AppColors.warning
                      : AppColors.success,
                ),
              ),
            ),
            PopupMenuButton<_MobileProductMenuAction>(
              tooltip: 'Manage product',
              onSelected: (action) {
                switch (action) {
                  case _MobileProductMenuAction.viewStock:
                    onViewBatches();
                  case _MobileProductMenuAction.adjustStock:
                    onAdjustStock();
                  case _MobileProductMenuAction.edit:
                    onEdit();
                  case _MobileProductMenuAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: tracksStock,
                  value: _MobileProductMenuAction.viewStock,
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: Text(
                      hasVariants ? 'Manage Variants' : 'View Batches',
                    ),
                  ),
                ),
                PopupMenuItem(
                  enabled: tracksStock,
                  value: _MobileProductMenuAction.adjustStock,
                  child: ListTile(
                    leading: const Icon(Icons.add_box_outlined),
                    title: Text(
                      hasVariants ? 'Adjust Variant Stock' : 'Receive Stock',
                    ),
                  ),
                ),
                const PopupMenuItem(
                  value: _MobileProductMenuAction.edit,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit Product'),
                  ),
                ),
                const PopupMenuItem(
                  value: _MobileProductMenuAction.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: AppColors.error),
                    title: Text('Delete Product'),
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Manage',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.more_horiz, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProductImage(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) {
      return Icon(
        CategoryIconUtils.iconFor(categoryName),
        color: AppColors.primaryLight,
        size: 22,
      );
    }

    // Handle web URLs (http/https)
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(
          CategoryIconUtils.iconFor(categoryName),
          color: AppColors.primaryLight,
          size: 22,
        ),
      );
    }

    // Handle file:// URIs
    String filePath = imagePath;
    if (imagePath.startsWith('file://')) {
      filePath = Uri.parse(imagePath).toFilePath();
    }

    // Handle local file paths
    if (File(filePath).existsSync()) {
      return Image.file(
        File(filePath),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
      );
    }

    return Icon(
      CategoryIconUtils.iconFor(categoryName),
      color: AppColors.primaryLight,
      size: 22,
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
