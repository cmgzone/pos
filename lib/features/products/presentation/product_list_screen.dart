import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/data/spreadsheet_import_reader.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_extensions.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/piki_ai_job_service.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/expiry_utils.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/utils/category_icon_utils.dart';
import '../../../widgets/compact_header_actions.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../widgets/piki_activity_panel.dart';
import '../../../widgets/skeleton.dart';
import '../../../widgets/stitch_kit.dart';
import '../../../widgets/smart_import_preview_dialog.dart';
import '../../training/widgets/training_anchor.dart';
import '../../purchases/presentation/purchase_management_screen.dart';
import '../data/product_import_service.dart';
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
  importProducts,
  catalogOrders,
  stockList,
  purchases,
  categories,
}

enum _MobileProductMenuAction { viewStock, adjustStock, edit, delete }

class ProductListScreen extends ConsumerStatefulWidget {
  final VoidCallback? onOpenCatalogOrders;

  const ProductListScreen({super.key, this.onOpenCatalogOrders});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;
  bool _isImporting = false;
  List<PikiAiJob> _activePikiJobs = const [];
  late Future<List<Map<String, dynamic>>> _productsFuture;
  late Future<List<Map<String, dynamic>>> _expiryAlertsFuture;

  @override
  void initState() {
    super.initState();
    _reloadProductFutures();
    _loadActivePikiJobs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(
      syncControllerProvider.select((state) => state.dataVersion),
      (previous, next) {
        if (previous != null && previous != next && mounted) {
          _refreshProducts();
        }
      },
    );
    final isMobile = MediaQuery.of(context).size.width <= 800;
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        toolbarHeight: 50,
        leading: isMobile
            ? IconButton(
                icon: Icon(Icons.menu),
                onPressed: () =>
                    AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        title: Text(
          isMobile ? 'Products' : 'Product Management',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        actions: [
          if (!isMobile)
            CompactHeaderButton(
              onPressed: _openCatalogOrders,
              icon: Icons.receipt_long_outlined,
              label: 'Catalog Orders',
              filled: false,
            ),
          if (!isMobile) SizedBox(width: 6),
          if (!isMobile)
            CompactHeaderButton(
              onPressed: _openStockList,
              icon: Icons.fact_check_outlined,
              label: 'Stock List',
              filled: false,
            ),
          if (!isMobile) SizedBox(width: 4),
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
          if (!isMobile) SizedBox(width: 4),
          if (!isMobile)
            CompactHeaderButton(
              onPressed: _isImporting ? null : _importProductsFromFile,
              icon: Icons.upload_file_outlined,
              label: _isImporting ? 'Importing...' : 'Import with Piki AI',
              filled: false,
            ),
          TrainingAnchor(
            id: 'products.add',
            child: isMobile
                ? IconButton(
                    tooltip: 'Add Product',
                    onPressed: _addProduct,
                    icon: Icon(Icons.add_circle_outline),
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
                  value: _MobileProductPageAction.importProducts,
                  child: ListTile(
                    leading: Icon(Icons.upload_file_outlined),
                    title: Text('Import with Piki AI'),
                  ),
                ),
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
          if (_activePikiJobs.isNotEmpty) _buildPikiJobBanner(isMobile),
          Divider(height: 1),

          // Product table
          Expanded(
            child: TrainingAnchor(
              id: 'products.list',
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _productsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SkeletonList(
                      itemCount: 8,
                      itemHeight: 100,
                      padding: EdgeInsets.all(isMobile ? 12 : 24),
                      spacing: 12,
                    );
                  }
                  final products = snapshot.data ?? [];
                  if (products.isEmpty) {
                    return EmptyStateWidget(
                      icon: _searchQuery.isEmpty
                          ? Icons.inventory_2_outlined
                          : Icons.search_off_rounded,
                      title: _searchQuery.isEmpty
                          ? 'No products yet'
                          : 'No results found',
                      subtitle: _searchQuery.isEmpty
                          ? 'Add your first product or import a spreadsheet to start selling.'
                          : 'Try different keywords or clear the filter.',
                      actionLabel: _searchQuery.isEmpty
                          ? 'Add product'
                          : 'Clear search',
                      actionIcon: _searchQuery.isEmpty
                          ? Icons.add_rounded
                          : Icons.clear_rounded,
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
                          : () {
                              _searchController.clear();
                              _setSelectedCategory(null);
                              _setSearchQuery('');
                            },
                      secondaryActionLabel:
                          _searchQuery.isEmpty && !_isImporting
                          ? 'Import with Piki AI'
                          : null,
                      onSecondaryAction: _searchQuery.isEmpty && !_isImporting
                          ? _importProductsFromFile
                          : null,
                    );
                  }

                  return ListView.separated(
                    padding: EdgeInsets.all(isMobile ? 12 : 24),
                    itemCount: products.length,
                    separatorBuilder: (_, _) => SizedBox(height: 8),
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
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(color: Theme.of(context).colorScheme.outline),
                ),
              ),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _productsFuture,
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
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      if (lowStock > 0)
                        _StatChip(
                          icon: Icons.warning_amber,
                          label: '$lowStock Low Stock',
                          color: AppColors.warning,
                        ),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _expiryAlertsFuture,
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
      controller: _searchController,
      onChanged: _setSearchQuery,
      decoration: InputDecoration(
        hintText: 'Search name, SKU, or barcode...',
        prefixIcon: Icon(
          Icons.search,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: () {
                  _searchController.clear();
                  _setSearchQuery('');
                },
              ),
        contentPadding: EdgeInsets.symmetric(vertical: 12),
      ),
    );
    final categories = categoriesAsync.when(
      data: (items) => SizedBox(
        width: isMobile ? double.infinity : 230,
        child: DropdownButtonFormField<String?>(
          initialValue: _selectedCategory,
          isExpanded: true,
          dropdownColor: context.appSurface,
          decoration: InputDecoration(
            labelText: 'Category',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: [
            DropdownMenuItem(value: null, child: Text('All Categories')),
            ...items.map(
              (category) => DropdownMenuItem(
                value: category['id'] as String,
                child: Text(category['name'] as String),
              ),
            ),
          ],
          onChanged: _setSelectedCategory,
        ),
      ),
      loading: () => SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );

    return TrainingAnchor(
      id: 'products.search',
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        padding: EdgeInsets.fromLTRB(
          isMobile ? 12 : 24,
          isMobile ? 12 : 0,
          isMobile ? 12 : 24,
          12,
        ),
        child: isMobile
            ? Column(children: [search, SizedBox(height: 8), categories])
            : Row(
                children: [
                  Expanded(child: search),
                  SizedBox(width: 16),
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

  void _reloadProductFutures() {
    _productsFuture = _getFilteredProducts();
    _expiryAlertsFuture = ProductRepository.getExpiryAlerts();
  }

  void _setSearchQuery(String value) {
    if (_searchQuery == value) {
      return;
    }
    setState(() {
      _searchQuery = value;
      _reloadProductFutures();
    });
  }

  void _setSelectedCategory(String? value) {
    if (_selectedCategory == value) {
      return;
    }
    setState(() {
      _selectedCategory = value;
      _reloadProductFutures();
    });
  }

  void _refreshProducts() {
    ref.invalidate(filteredProductsProvider);
    ref.invalidate(posCategoriesProvider);
    setState(_reloadProductFutures);
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
    final onOpenCatalogOrders = widget.onOpenCatalogOrders;
    if (onOpenCatalogOrders != null) {
      onOpenCatalogOrders();
      return;
    }
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
    ref.invalidate(posCategoriesProvider);
    ref.invalidate(filteredProductsProvider);
    _refreshProducts();
  }

  Future<void> _handleMobilePageAction(_MobileProductPageAction action) async {
    switch (action) {
      case _MobileProductPageAction.importProducts:
        await _importProductsFromFile();
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

  Future<void> _loadActivePikiJobs() async {
    try {
      final jobs = await PikiAiJobService.listActiveJobs();
      if (!mounted) return;
      setState(() {
        _activePikiJobs = jobs
            .where((job) => job.jobType == 'product_import')
            .toList(growable: false);
      });
    } catch (_) {
      // Active job hints are helpful, but they should not block product browsing.
    }
  }

  Widget _buildPikiJobBanner(bool isMobile) {
    final theme = Theme.of(context);
    final job = _activePikiJobs.first;
    final count = _activePikiJobs.length;
    final actionLabel = job.isWaitingForReview ? 'Review' : 'Open';
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        isMobile ? 12 : 24,
        10,
        isMobile ? 12 : 24,
        0,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Piki has $count active product import task${count == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton.icon(
            onPressed: _isImporting ? null : () => _resumePikiJob(job),
            icon: Icon(
              job.isWaitingForReview
                  ? Icons.fact_check_outlined
                  : Icons.bolt_outlined,
            ),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _importProductsFromFile() async {
    if (_isImporting) {
      return;
    }
    setState(() => _isImporting = true);

    ProductImportResult? result;
    Object? importError;
    try {
      final file = await SpreadsheetImportReader.pickRows(
        dialogTitle: 'Import Products with Piki AI',
        allowedExtensions: SpreadsheetImportReader.productImportExtensions,
      );
      if (file == null) {
        return;
      }
      final job = await PikiAiJobService.createProductImportJob(
        file,
        branchId: DatabaseService.currentBranchId,
      );
      final completedJob = await _showPikiJobActivity(job);
      if (completedJob == null) {
        await _loadActivePikiJobs();
        return;
      }
      result = await _reviewAndImportPikiJob(completedJob);
    } catch (error) {
      importError = error;
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }

    await _loadActivePikiJobs();
    if (!mounted) return;
    if (importError != null) {
      _showProductImportError(importError);
      return;
    }
    if (result != null) {
      await _handleProductImportComplete(result);
    }
  }

  Future<void> _resumePikiJob(PikiAiJob job) async {
    if (_isImporting) {
      return;
    }
    setState(() => _isImporting = true);
    ProductImportResult? result;
    Object? importError;
    try {
      result = await _reviewAndImportPikiJob(job);
    } catch (error) {
      importError = error;
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }

    await _loadActivePikiJobs();
    if (!mounted) return;
    if (importError != null) {
      _showProductImportError(importError);
      return;
    }
    if (result != null) {
      await _handleProductImportComplete(result);
    }
  }

  Future<PikiAiJob?> _showPikiJobActivity(PikiAiJob job) {
    return showDialog<PikiAiJob>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _PikiJobActivityDialog(initialJob: job),
    );
  }

  Future<ProductImportResult?> _reviewAndImportPikiJob(
    PikiAiJob initialJob,
  ) async {
    var job = await PikiAiJobService.getJob(initialJob.id);
    if (job.isRunning) {
      final watchedJob = await _showPikiJobActivity(job);
      if (watchedJob == null) {
        return null;
      }
      job = await PikiAiJobService.getJob(watchedJob.id);
    }
    if (job.isFailed) {
      throw Exception(job.errorMessage ?? 'Piki import failed.');
    }
    if (job.status == 'completed') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This Piki import was already completed.'),
          ),
        );
      }
      return null;
    }
    if (!job.isWaitingForReview) {
      throw Exception('Piki import is ${job.status.replaceAll('_', ' ')}.');
    }

    await PikiAiJobService.getDraftItems(job.id);
    final cloud = job.result;
    if (cloud == null) {
      throw Exception('Piki did not save import rows for this job.');
    }
    final plan = ProductImportService.buildPlanFromCloudResult(
      cloud,
      fileName: job.sourceFileName,
    );
    if (!mounted) return null;
    final confirmed = await showSmartImportPreviewDialog(
      context,
      plan: plan,
      title: 'Piki AI Product Import Check',
      actionLabel: 'Import Products',
      minimumRequirements: const [
        'New products only need a name column.',
        'Existing products can be updated with sku, barcode, or product_id.',
        'Variants can use parent_product_name plus variant_name.',
      ],
      optionalColumns: const [
        'variant_name',
        'parent_product_name',
        'price',
        'cost',
        'category',
        'stock',
        'low_stock',
        'unit',
        'brand',
        'image_url',
        'description',
        'image_urls',
        'show_online',
        'is_featured',
      ],
      defaultsNote:
          'Piki prepared this draft in the cloud. Blank optional fields are allowed. Missing price and stock import as 0; low stock defaults to 5 and unit defaults to pcs. Piki will attach clear sizes, colors, flavors, and packs as variants instead of duplicate products.',
    );
    if (!confirmed) {
      return null;
    }
    final result = await ProductImportService.importPlan(plan);
    try {
      await PikiAiJobService.markImportCompleted(
        job.id,
        created: result.created,
        updated: result.updated,
        stockBatches: result.stockBatches,
        skipped: result.skipped,
      );
    } catch (_) {
      // The local import already succeeded. A later refresh can still show the job.
    }
    return result;
  }

  void _showProductImportError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppErrorMessage.withContext(
            error,
            prefix: 'Could not import products.',
            fallback:
                'Use an Excel, CSV, PDF, DOCX, TXT, or JSON file with product names. Existing products can be updated with sku, barcode, or product_id. Variants can use parent_product_name plus variant_name.',
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<void> _handleProductImportComplete(
    ProductImportResult importResult,
  ) async {
    _refreshProducts();
    ref.invalidate(categoriesProvider);
    ref.invalidate(posCategoriesProvider);
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Product Import Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${importResult.created} product${importResult.created == 1 ? '' : 's'} created'
              '${importResult.fileName == null ? '' : ' from ${importResult.fileName}'}.',
            ),
            if (importResult.updated > 0) ...[
              SizedBox(height: 8),
              Text(
                '${importResult.updated} existing product${importResult.updated == 1 ? '' : 's'} updated.',
              ),
            ],
            if (importResult.stockBatches > 0) ...[
              SizedBox(height: 8),
              Text(
                '${importResult.stockBatches} stock batch${importResult.stockBatches == 1 ? '' : 'es'} received for existing products.',
                style: TextStyle(color: AppColors.success),
              ),
            ],
            if (importResult.skipped > 0) ...[
              SizedBox(height: 8),
              Text(
                '${importResult.skipped} row${importResult.skipped == 1 ? '' : 's'} skipped.',
                style: TextStyle(color: AppColors.warning),
              ),
            ],
            if (importResult.errors.isNotEmpty) ...[
              SizedBox(height: 12),
              Text(
                'Check these rows:',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              ...importResult.errors.map(
                (error) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Done'),
          ),
        ],
      ),
    );
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
          backgroundColor: Theme.of(context).colorScheme.surface,
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              SizedBox(height: 16),
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
                  prefixIcon: Icon(Icons.add_shopping_cart),
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
                      style: TextStyle(
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              SizedBox(height: 16),
              TextField(
                controller: batchNumberController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Batch Number',
                  prefixIcon: Icon(Icons.numbers_outlined),
                  helperText: 'Recommended for medicine stock tracking.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: 16),
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
                          style: TextStyle(fontSize: 13),
                        ),
                        value: false,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<bool>(
                        title: Text(
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
                  prefixIcon: Icon(Icons.attach_money),
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
                      style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                  leading: Icon(Icons.event_outlined),
                  title: Text('Expiry Date'),
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
                                expiryDate ??
                                DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => expiryDate = picked);
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel'),
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
              child: Text('Save Stock'),
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
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Product'),
        content: Text(
          'Are you sure you want to delete "${product['name']}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
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
            child: Text('Delete'),
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

    return StitchCard(
      padding: const EdgeInsets.all(16),
      radius: 18,
      borderColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
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
                SizedBox(width: 16),

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
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      Text(
                        product['name'] as String? ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'SKU: ${product['sku'] ?? 'N/A'} · Barcode: ${product['barcode'] ?? 'N/A'}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        hasVariants
                            ? 'Variants enabled - Sell: ${UnitUtils.label(saleUnit)} - Stock: ${UnitUtils.label(stockUnit)}'
                            : !tracksStock
                            ? 'No stock tracking'
                            : saleUnit == stockUnit
                            ? 'Unit: ${UnitUtils.label(saleUnit)}'
                            : 'Sell: ${UnitUtils.label(saleUnit)} - Stock: ${UnitUtils.label(stockUnit)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.primaryLight,
                        ),
                      ),
                      Text(
                        UnitUtils.priceLabel(saleUnit),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      if (product['cost'] != null)
                        Text(
                          'Cost: ${ShopSettings.currency}${(product['cost'] as num).toStringAsFixed(2)}/${UnitUtils.label(saleUnit)}',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: 24),

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
                SizedBox(width: 16),

                // Actions
                IconButton(
                  icon: Icon(
                    Icons.history,
                    size: 20,
                    color: AppColors.primaryLight,
                  ),
                  tooltip: hasVariants ? 'Manage Variants' : 'View Batches',
                  onPressed: tracksStock ? onViewBatches : null,
                ),
                IconButton(
                  icon: Icon(
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
                  icon: Icon(
                    Icons.edit_outlined,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  tooltip: 'Edit',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: Icon(
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
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  Text(
                    'SKU: ${product['sku'] ?? 'N/A'}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  '${ShopSettings.currency}${(product['price'] as num? ?? 0).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.primaryLight,
                  ),
                ),
                Text(
                  UnitUtils.priceLabel(saleUnit),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                if (product['cost'] != null)
                  Text(
                    'C: ${ShopSettings.currency}${(product['cost'] as num).toStringAsFixed(2)}/${UnitUtils.label(saleUnit)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],
        ),
        SizedBox(height: 16),
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
                    leading: Icon(Icons.history),
                    title: Text(
                      hasVariants ? 'Manage Variants' : 'View Batches',
                    ),
                  ),
                ),
                PopupMenuItem(
                  enabled: tracksStock,
                  value: _MobileProductMenuAction.adjustStock,
                  child: ListTile(
                    leading: Icon(Icons.add_box_outlined),
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
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
          SizedBox(width: 8),
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

class _PikiJobActivityDialog extends StatefulWidget {
  final PikiAiJob initialJob;

  const _PikiJobActivityDialog({required this.initialJob});

  @override
  State<_PikiJobActivityDialog> createState() => _PikiJobActivityDialogState();
}

class _PikiJobActivityDialogState extends State<_PikiJobActivityDialog> {
  late PikiAiJob _job;
  List<PikiAiJobEvent> _events = const [];
  StreamSubscription<PikiAiJobUpdate>? _subscription;
  Timer? _pollTimer;
  Object? _streamError;
  bool _returned = false;
  Timer? _retryTimer;
  int _retrySeconds = 0;
  int _retryAttempts = 0;
  bool _retryBusy = false;
  bool _cancelBusy = false;

  @override
  void initState() {
    super.initState();
    _job = widget.initialJob;
    _loadSavedEvents();
    _connectStream();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _pollTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedEvents() async {
    try {
      final events = await PikiAiJobService.getEvents(_job.id);
      if (!mounted) return;
      setState(() => _events = _mergeEvents(_events, events));
    } catch (_) {}
  }

  void _connectStream() {
    _subscription?.cancel();
    _subscription = PikiAiJobService.streamJob(_job.id).listen(
      (update) {
        if (!mounted) return;
        final nextJob = update.job;
        final event = update.event;
        setState(() {
          _streamError = null;
          if (nextJob != null) _job = nextJob;
          if (event != null) _events = _mergeEvents(_events, [event]);
        });
        _handleJobUpdate();
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _streamError = error);
        _startPollingFallback();
      },
      cancelOnError: true,
    );
  }

  void _startPollingFallback() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final job = await PikiAiJobService.getJob(_job.id);
        final events = await PikiAiJobService.getEvents(_job.id);
        if (!mounted) return;
        setState(() {
          _job = job;
          _events = _mergeEvents(_events, events);
        });
        _handleJobUpdate();
      } catch (_) {}
    });
  }

  void _returnWhenReady() {
    if (_returned || !_job.isWaitingForReview) {
      return;
    }
    _cancelRetryTimer();
    _returned = true;
    Future.delayed(const Duration(milliseconds: 850), () {
      if (mounted) Navigator.pop(context, _job);
    });
  }

  void _handleJobUpdate() {
    _returnWhenReady();
    _maybeScheduleAutoRetry();
  }

  void _maybeScheduleAutoRetry() {
    if (!_job.isFailed ||
        _retryBusy ||
        _cancelBusy ||
        _retryTimer != null ||
        _retryAttempts >= 2 ||
        !_isRecoverableFailure(_job.errorMessage)) {
      return;
    }
    setState(() => _retrySeconds = 12);
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_retrySeconds <= 1) {
        _cancelRetryTimer();
        unawaited(_retryNow());
        return;
      }
      setState(() => _retrySeconds -= 1);
    });
  }

  bool _isRecoverableFailure(String? message) {
    final lower = (message ?? '').toLowerCase();
    if (lower.contains('validation') || lower.contains('unsupported')) {
      return false;
    }
    return lower.contains('timeout') ||
        lower.contains('network') ||
        lower.contains('rate limit') ||
        lower.contains('openrouter') ||
        lower.contains('temporarily') ||
        lower.contains('failed') ||
        lower.contains('could not finish');
  }

  void _cancelRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (mounted && _retrySeconds != 0) {
      setState(() => _retrySeconds = 0);
    } else {
      _retrySeconds = 0;
    }
  }

  Future<void> _retryNow() async {
    if (_retryBusy || _cancelBusy) return;
    _cancelRetryTimer();
    setState(() => _retryBusy = true);
    try {
      final retried = await PikiAiJobService.retryImportJob(_job.id);
      if (!mounted) return;
      _pollTimer?.cancel();
      _pollTimer = null;
      setState(() {
        _job = retried;
        _streamError = null;
        _returned = false;
        _retryAttempts += 1;
      });
      _connectStream();
    } catch (error) {
      if (mounted) setState(() => _streamError = error);
    } finally {
      if (mounted) setState(() => _retryBusy = false);
    }
  }

  Future<void> _cancelJob() async {
    if (_cancelBusy || !_job.isRunning) return;
    _cancelRetryTimer();
    setState(() => _cancelBusy = true);
    try {
      final cancelled = await PikiAiJobService.cancelJob(_job.id);
      if (!mounted) return;
      setState(() => _job = cancelled);
    } catch (error) {
      if (mounted) setState(() => _streamError = error);
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
    }
  }

  List<PikiAiJobEvent> _mergeEvents(
    List<PikiAiJobEvent> current,
    List<PikiAiJobEvent> incoming,
  ) {
    final byId = <String, PikiAiJobEvent>{
      for (final event in current) event.id: event,
    };
    for (final event in incoming) {
      byId[event.id] = event;
    }
    final merged = byId.values.toList()
      ..sort(
        (a, b) => (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 720;
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('Piki import activity'),
      content: SizedBox(
        width: isWide ? 640 : double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PikiActivityPanel(job: _job, events: _events),
            if (_streamError != null && _job.isRunning) ...[
              const SizedBox(height: 10),
              Text(
                'Live updates disconnected. Piki is still working in the backend.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
            if (_job.isFailed || _retrySeconds > 0) ...[
              const SizedBox(height: 10),
              Text(
                _retrySeconds > 0
                    ? 'Retrying this same import in $_retrySeconds seconds.'
                    : (_job.errorMessage ??
                          'Piki could not finish that request.'),
                style: TextStyle(
                  color: _job.isFailed
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_retrySeconds > 0)
          TextButton(
            onPressed: _cancelRetryTimer,
            child: const Text('Cancel retry'),
          ),
        if (_job.isFailed)
          OutlinedButton.icon(
            onPressed: _retryBusy ? null : () => unawaited(_retryNow()),
            icon: _retryBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        if (_job.isRunning)
          TextButton(
            onPressed: _cancelBusy ? null : () => unawaited(_cancelJob()),
            child: Text(_cancelBusy ? 'Cancelling...' : 'Cancel job'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, _job.isRunning ? null : _job),
          child: Text(_job.isRunning ? 'Hide panel' : 'Close'),
        ),
      ],
    );
  }
}
