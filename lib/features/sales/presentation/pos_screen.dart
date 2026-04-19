import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/session_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/shop_settings.dart';
import '../../../core/services/sync_controller.dart';
import '../../../core/services/license_service.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/utils/category_icon_utils.dart';
import '../../products/data/product_provider.dart';
import '../../products/data/product_repository.dart';

import '../data/cart_provider.dart';
import '../data/sale_repository.dart';
import '../../app/app_shell.dart';
import 'barcode_scanner.dart';
import 'customer_checkout_dialog.dart';
import 'receipt_service.dart';

class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.of(context).size.width <= 800;
    final cartCount = ref.watch(cartProvider).length;
    final cashierName = SessionService.currentUserName;
    final cashierRole = RolePermissions.label(SessionService.currentUserRole);
    final syncState = ref.watch(syncControllerProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () =>
                    AppShell.scaffoldKey.currentState?.openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.point_of_sale_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(ShopSettings.shopName),
          ],
        ),
        actions: [
          _LicenseIndicatorChip(state: syncState),
          const SizedBox(width: 8),
          _SyncIndicatorChip(state: syncState),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              cashierName.isEmpty
                  ? '?'
                  : cashierName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cashierName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                cashierRole,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive: side-by-side on wide screens, stacked on narrow
          if (constraints.maxWidth > 800) {
            return Row(
              children: [
                Expanded(flex: 7, child: _ProductSide()),
                Container(width: 1, color: AppColors.border),
                SizedBox(width: 380, child: _CartSide()),
              ],
            );
          } else {
            return _ProductSide(); // Mobile: full screen products + FAB for cart
          }
        },
      ),
      floatingActionButton: isMobile
          ? FloatingActionButton.extended(
              onPressed: () => _showMobileCartSheet(context),
              backgroundColor: cartCount > 0
                  ? AppColors.success
                  : AppColors.surfaceHighlight,
              foregroundColor: Colors.white,
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.shopping_cart_checkout_rounded),
                  if (cartCount > 0)
                    Positioned(
                      right: -8,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$cartCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              label: Text(cartCount > 0 ? 'Checkout' : 'Cart'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _showMobileCartSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          height: MediaQuery.of(ctx).size.height * 0.88,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 5,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Expanded(child: _CartSide()),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncIndicatorChip extends StatelessWidget {
  final SyncState state;

  const _SyncIndicatorChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final config = _resolveIndicatorStyle(state);

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(config.icon, size: 16, color: config.color),
          const SizedBox(width: 6),
          Text(
            config.label,
            style: TextStyle(color: config.color, fontSize: 12),
          ),
        ],
      ),
    );
  }

  _SyncIndicatorStyle _resolveIndicatorStyle(SyncState state) {
    switch (state.indicator) {
      case SyncIndicatorState.localOnly:
        return const _SyncIndicatorStyle(
          icon: Icons.cloud_off,
          color: AppColors.textSecondary,
          label: 'Local Only',
        );
      case SyncIndicatorState.offline:
        return const _SyncIndicatorStyle(
          icon: Icons.cloud_off_outlined,
          color: AppColors.warning,
          label: 'Offline',
        );
      case SyncIndicatorState.syncing:
        return const _SyncIndicatorStyle(
          icon: Icons.sync,
          color: AppColors.primaryLight,
          label: 'Syncing',
        );
      case SyncIndicatorState.error:
        return const _SyncIndicatorStyle(
          icon: Icons.sync_problem,
          color: AppColors.error,
          label: 'Sync Error',
        );
      case SyncIndicatorState.issues:
        return const _SyncIndicatorStyle(
          icon: Icons.warning_amber_rounded,
          color: AppColors.warning,
          label: 'Needs Review',
        );
      case SyncIndicatorState.pending:
        return const _SyncIndicatorStyle(
          icon: Icons.cloud_upload_outlined,
          color: AppColors.warning,
          label: 'Pending Sync',
        );
      case SyncIndicatorState.updatesAvailable:
        return const _SyncIndicatorStyle(
          icon: Icons.cloud_download_outlined,
          color: AppColors.primaryLight,
          label: 'Updates Ready',
        );
      case SyncIndicatorState.synced:
        return const _SyncIndicatorStyle(
          icon: Icons.cloud_done,
          color: AppColors.success,
          label: 'Synced',
        );
    }
  }
}

class _LicenseIndicatorChip extends StatelessWidget {
  final SyncState state;

  const _LicenseIndicatorChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final license = state.licenseSnapshot;
    final color = switch (license.accessStatus) {
      LicenseAccessStatus.active => AppColors.success,
      LicenseAccessStatus.grace => AppColors.warning,
      LicenseAccessStatus.expired ||
      LicenseAccessStatus.invalid => AppColors.error,
      LicenseAccessStatus.localOnly => AppColors.textSecondary,
    };
    final icon = switch (license.accessStatus) {
      LicenseAccessStatus.active => Icons.verified_outlined,
      LicenseAccessStatus.grace => Icons.schedule_outlined,
      LicenseAccessStatus.expired => Icons.lock_clock_outlined,
      LicenseAccessStatus.invalid => Icons.gpp_bad_outlined,
      LicenseAccessStatus.localOnly => Icons.offline_bolt_outlined,
    };

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(switch (license.accessStatus) {
            LicenseAccessStatus.active => 'Active',
            LicenseAccessStatus.grace => 'Grace',
            LicenseAccessStatus.expired => 'Expired',
            LicenseAccessStatus.invalid => 'License Error',
            LicenseAccessStatus.localOnly => 'Local Only',
          }, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SyncIndicatorStyle {
  final IconData icon;
  final Color color;
  final String label;

  const _SyncIndicatorStyle({
    required this.icon,
    required this.color,
    required this.label,
  });
}

// ──────────────── LEFT SIDE: Products ────────────────

class _ProductSide extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ProductSide> createState() => _ProductSideState();
}

class _ProductSideState extends ConsumerState<_ProductSide> {
  Future<void> _handleBarcodeScan(String barcode, WidgetRef ref) async {
    final product = await ProductRepository.getByBarcode(barcode);
    if (product != null) {
      final success = ref.read(cartProvider.notifier).addProduct(product);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.warning_amber,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    success
                        ? '${product['name']} added to cart'
                        : 'Not enough stock for ${product['name']}!',
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
            backgroundColor: success ? AppColors.success : AppColors.error,
            width: 360,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('No product found with barcode: $barcode'),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.warning,
            width: 360,
          ),
        );
      }
    }
  }

  Future<void> _openCameraScanner() async {
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (barcode != null && barcode.isNotEmpty) {
      await _handleBarcodeScan(barcode, ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(filteredProductsProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final searchQuery = ref.watch(productSearchProvider);
    final isMobileDevice = Platform.isAndroid || Platform.isIOS;

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar with scan button
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) =>
                      ref.read(productSearchProvider.notifier).state = v,
                  onSubmitted: (v) {
                    final code = v.trim();
                    final lower = code.toLowerCase();
                    // Only attempt barcode lookup if it looks like a barcode
                    // (not a URL or plain text search entry)
                    if (code.length >= 4 &&
                        !lower.startsWith('http') &&
                        !lower.startsWith('www.') &&
                        !lower.contains('://') &&
                        RegExp(r'^[A-Za-z0-9\-\.]+$').hasMatch(code)) {
                      _handleBarcodeScan(code, ref);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Search products or scan barcode...',
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.textSecondary,
                    ),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () =>
                                ref.read(productSearchProvider.notifier).state =
                                    '',
                          )
                        : null,
                  ),
                ),
              ),
              if (isMobileDevice) ...[
                const SizedBox(width: 12),
                Material(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: _openCameraScanner,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),

          // Category chips
          categoriesAsync.when(
            data: (categories) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CategoryChip(
                    title: 'All',
                    isSelected: selectedCategory == null,
                    onTap: () =>
                        ref.read(selectedCategoryProvider.notifier).state =
                            null,
                  ),
                  ...categories.map(
                    (cat) => _CategoryChip(
                      title: cat['name'] as String,
                      color: cat['color'] as String?,
                      categoryName: cat['name'] as String?,
                      isSelected: selectedCategory == cat['id'],
                      onTap: () =>
                          ref.read(selectedCategoryProvider.notifier).state =
                              cat['id'] as String,
                    ),
                  ),
                ],
              ),
            ),
            loading: () => const SizedBox(
              height: 40,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Text('Error: $e'),
          ),
          const SizedBox(height: 20),

          // Product grid
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final categories = categoriesAsync.valueOrNull ?? [];
                if (products.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No products found',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 0.82,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    // Resolve category name for icon fallback
                    final catId = product['category_id'] as String?;
                    final catName = catId != null
                        ? (categories.firstWhere(
                                (c) => c['id'] == catId,
                                orElse: () => {},
                              )['name']
                              as String?)
                        : null;
                    return _ProductCard(
                      product: product,
                      categoryName: catName,
                      onTap: () {
                        final success = ref
                            .read(cartProvider.notifier)
                            .addProduct(product);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                Icon(
                                  success
                                      ? Icons.check_circle
                                      : Icons.warning_amber,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  success
                                      ? '${product['name']} added to cart'
                                      : 'Not enough stock!',
                                ),
                              ],
                            ),
                            duration: const Duration(milliseconds: 1200),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: success
                                ? AppColors.success
                                : AppColors.error,
                            width: 320,
                          ),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Error loading products: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────── RIGHT SIDE: Cart ────────────────

class _CartSide extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final subtotal = ref.watch(cartSubtotalProvider);
    final tax = ref.watch(cartTaxProvider);
    final discount = ref.watch(discountProvider);
    final total = ref.watch(cartTotalProvider);
    final profit = ref.watch(cartProfitProvider);

    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current Sale',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (cart.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => ref.read(cartProvider.notifier).clear(),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppColors.error,
                    ),
                    label: const Text(
                      'Clear',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Cart items
          Expanded(
            child: cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 56,
                          color: AppColors.textSecondary.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Cart is empty',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap a product to add it',
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: cart.length,
                    separatorBuilder: (_, _) => const Divider(height: 24),
                    itemBuilder: (context, index) {
                      final item = cart[index];
                      return _CartItemRow(item: item);
                    },
                  ),
          ),

          // Totals & Pay
          if (cart.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.surfaceHighlight,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  _SummaryRow(
                    title: 'Subtotal',
                    value:
                        '${ShopSettings.currency}${subtotal.toStringAsFixed(2)}',
                  ),
                  const SizedBox(height: 8),
                  _SummaryRow(
                    title: 'Tax (${ShopSettings.taxRate}%)',
                    value: '${ShopSettings.currency}${tax.toStringAsFixed(2)}',
                  ),
                  if (discount > 0) ...[
                    const SizedBox(height: 8),
                    _SummaryRow(
                      title: 'Discount',
                      value:
                          '-${ShopSettings.currency}${discount.toStringAsFixed(2)}',
                      isDiscount: true,
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Profit',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      Text(
                        '${ShopSettings.currency}${profit.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _processCashPayment(context, ref),
                          icon: const Icon(Icons.payment),
                          label: const Text(
                            'Pay',
                            style: TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            backgroundColor: AppColors.success,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _processKopeshaPayment(context, ref),
                          icon: const Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                          label: const Text(
                            'Kopesha [Credit]',
                            style: TextStyle(fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            backgroundColor: AppColors.warning,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Kopesha saves the sale to a customer balance for later payment.',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _processCashPayment(BuildContext context, WidgetRef ref) async {
    final total = ref.read(cartTotalProvider);
    final cashCheckout = await _showCashCheckoutDialog(context, total);

    if (!context.mounted || cashCheckout == null) return;

    await _completeSale(
      context,
      ref,
      paymentType: 'cash',
      amountTendered: cashCheckout.amountTendered,
      changeGiven: cashCheckout.changeGiven,
    );
  }

  Future<void> _processKopeshaPayment(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final total = ref.read(cartTotalProvider);
    final kopeshaSelection = await CustomerCheckoutDialog.show(
      context,
      total: total,
    );

    if (!context.mounted || kopeshaSelection == null) return;

    final customer = kopeshaSelection['customer'] as Map<String, dynamic>?;
    final dueDate = kopeshaSelection['dueDate'] as String?;
    if (customer == null || dueDate == null) return;

    await _completeSale(
      context,
      ref,
      paymentType: 'kopesha',
      customerId: customer['id'] as String,
      customerName: customer['name'] as String,
      dueDate: dueDate,
    );
  }

  Future<void> _completeSale(
    BuildContext context,
    WidgetRef ref, {
    required String paymentType,
    double? amountTendered,
    double? changeGiven,
    String? customerId,
    String? customerName,
    String? dueDate,
  }) async {
    final cart = ref.read(cartProvider);
    final subtotal = ref.read(cartSubtotalProvider);
    final tax = ref.read(cartTaxProvider);
    final discount = ref.read(discountProvider);
    final total = ref.read(cartTotalProvider);
    final isKopesha = paymentType == 'kopesha';

    // Save items before clearing cart
    final saleItems = cart
        .map(
          (item) => {
            'product_id': item.productId,
            'product_name': item.productName,
            'quantity': item.quantity,
            'unit_price': item.unitPrice,
            'unit': item.unit,
          },
        )
        .toList();

    try {
      final saleId = await SaleRepository.createSale(
        totalAmount: total,
        tax: tax,
        discount: discount,
        paymentType: paymentType,
        userId: SessionService.currentUserId.isNotEmpty
            ? SessionService.currentUserId
            : 'admin',
        items: cart.map((item) => item.toSaleItem()).toList(),
        amountTendered: amountTendered,
        changeGiven: changeGiven,
        customerId: customerId,
        customerName: customerName,
        dueDate: dueDate,
      );

      ref.read(cartProvider.notifier).clear();
      ref.read(discountProvider.notifier).state = 0;
      ref.invalidate(filteredProductsProvider);

      if (context.mounted) {
        _showSaleSuccessDialog(
          context,
          saleId: saleId,
          total: total,
          subtotal: subtotal,
          tax: tax,
          discount: discount,
          saleItems: saleItems,
          paymentType: paymentType,
          customerName: customerName,
          amountTendered: amountTendered ?? 0,
          changeGiven: changeGiven ?? 0,
          balanceDue: isKopesha ? total : 0,
          dueDate: dueDate,
          cashierName: SessionService.currentUserName,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showSaleSuccessDialog(
    BuildContext context, {
    required String saleId,
    required double total,
    required double subtotal,
    required double tax,
    required double discount,
    required List<Map<String, dynamic>> saleItems,
    required String paymentType,
    String? customerName,
    double amountTendered = 0,
    double changeGiven = 0,
    double balanceDue = 0,
    String? dueDate,
    required String cashierName,
  }) {
    final isKopesha = paymentType == 'kopesha';
    final isCash = paymentType == 'cash';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              isKopesha
                  ? Icons.account_balance_wallet_outlined
                  : Icons.check_circle,
              color: isKopesha ? AppColors.warning : AppColors.success,
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(isKopesha ? 'Kopesha Saved' : 'Sale Complete'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total: ${ShopSettings.currency}${total.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isKopesha ? AppColors.warning : AppColors.success,
              ),
            ),
            if (isCash) ...[
              const SizedBox(height: 12),
              Text(
                'Cash Received: ${ShopSettings.currency}${amountTendered.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Change Returned: ${ShopSettings.currency}${changeGiven.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: changeGiven > 0
                      ? AppColors.primaryLight
                      : AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Sale ID: ${saleId.substring(0, 8)}...',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            if (customerName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Customer: $customerName',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (balanceDue > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Outstanding Kopesha: ${ShopSettings.currency}${balanceDue.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (dueDate != null) ...[
              const SizedBox(height: 8),
              Text(
                'Due date: $dueDate',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ReceiptService.showReceiptPreview(
                context,
                saleId: saleId,
                total: total,
                subtotal: subtotal,
                tax: tax,
                discount: discount,
                paymentType: paymentType,
                items: saleItems,
                customerName: customerName,
                amountTendered: amountTendered,
                changeGiven: changeGiven,
                balanceDue: balanceDue,
                dueDate: dueDate,
                cashierName: cashierName,
                documentDate: DateTime.now().toIso8601String(),
                showTenderedBreakdown: isCash,
              );
            },
            icon: const Icon(Icons.receipt_long, size: 18),
            label: const Text('Print Receipt'),
          ),
        ],
      ),
    );
  }

  Future<_CashCheckoutResult?> _showCashCheckoutDialog(
    BuildContext context,
    double total,
  ) async {
    final controller = TextEditingController(text: total.toStringAsFixed(2));
    var tenderedAmount = total;
    String? errorText;

    final result = await showDialog<_CashCheckoutResult>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hasEnoughCash = tenderedAmount + 0.001 >= total;
          final changeGiven = hasEnoughCash ? tenderedAmount - total : 0.0;

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: const [
                Icon(Icons.payments_outlined, color: AppColors.success),
                SizedBox(width: 12),
                Text('Cash Checkout'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Due',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${ShopSettings.currency}${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Cash Received',
                      prefixText: ShopSettings.currency,
                      errorText: errorText,
                      helperText: hasEnoughCash
                          ? 'Change to return: ${ShopSettings.currency}${changeGiven.toStringAsFixed(2)}'
                          : 'Enter at least ${ShopSettings.currency}${total.toStringAsFixed(2)}',
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        tenderedAmount = double.tryParse(value.trim()) ?? 0.0;
                        errorText = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        controller.text = total.toStringAsFixed(2);
                        setDialogState(() {
                          tenderedAmount = total;
                          errorText = null;
                        });
                      },
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Use Exact Amount'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: hasEnoughCash
                          ? AppColors.primaryLight.withValues(alpha: 0.08)
                          : AppColors.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasEnoughCash
                              ? Icons.reply_outlined
                              : Icons.warning_amber_rounded,
                          color: hasEnoughCash
                              ? AppColors.primaryLight
                              : AppColors.warning,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                hasEnoughCash
                                    ? 'Change Returned'
                                    : 'More Cash Needed',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: hasEnoughCash
                                      ? AppColors.primaryLight
                                      : AppColors.warning,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${ShopSettings.currency}${(hasEnoughCash ? changeGiven : total - tenderedAmount).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final parsed = double.tryParse(controller.text.trim());
                  if (parsed == null) {
                    setDialogState(() {
                      errorText = 'Enter a valid cash amount';
                    });
                    return;
                  }
                  if (parsed + 0.001 < total) {
                    setDialogState(() {
                      errorText = 'Cash received must cover the sale total';
                    });
                    return;
                  }
                  Navigator.pop(
                    ctx,
                    _CashCheckoutResult(
                      amountTendered: parsed,
                      changeGiven: parsed - total,
                    ),
                  );
                },
                icon: const Icon(Icons.check_circle_outline),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                ),
                label: const Text('Complete Sale'),
              ),
            ],
          );
        },
      ),
    );

    controller.dispose();
    return result;
  }
}

class _CashCheckoutResult {
  final double amountTendered;
  final double changeGiven;

  const _CashCheckoutResult({
    required this.amountTendered,
    required this.changeGiven,
  });
}

// ──────────────── Reusable Widgets ────────────────

class _CartItemRow extends ConsumerWidget {
  final CartItem item;
  const _CartItemRow({required this.item});

  Future<void> _editQuantity(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: UnitUtils.formatQuantity(item.quantity),
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Set Quantity (${UnitUtils.label(item.unit)})'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity',
            helperText: item.usesConversion
                ? 'Available: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)} (${UnitUtils.formatWithUnit(item.stockOnHand, item.stockUnit)})'
                : 'Available: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value == null ||
                  !ref
                      .read(cartProvider.notifier)
                      .setQuantity(item.productId, value)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      item.usesConversion
                          ? 'Enter a quantity up to ${UnitUtils.formatWithUnit(item.maxStock, item.unit)} (${UnitUtils.formatWithUnit(item.stockOnHand, item.stockUnit)} available).'
                          : 'Enter a quantity up to ${UnitUtils.formatWithUnit(item.maxStock, item.unit)}.',
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.inventory_2_outlined,
            color: AppColors.primaryLight,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${ShopSettings.currency}${item.unitPrice.toStringAsFixed(2)} ${UnitUtils.priceLabel(item.unit)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.usesConversion
                    ? 'In stock: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)} (${UnitUtils.formatWithUnit(item.stockOnHand, item.stockUnit)})'
                    : 'In stock: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Profit: ${ShopSettings.currency}${item.profit.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => ref
                    .read(cartProvider.notifier)
                    .decrementQuantity(item.productId),
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.remove,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _editQuantity(context, ref),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    UnitUtils.formatWithUnit(item.quantity, item.unit),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  final success = ref
                      .read(cartProvider.notifier)
                      .incrementQuantity(item.productId);
                  if (!success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.usesConversion
                                    ? 'Maximum stock reached: ${UnitUtils.formatWithUnit(item.maxStock, item.unit)}.'
                                    : 'Maximum stock reached!',
                              ),
                            ),
                          ],
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: AppColors.error,
                        width: 250,
                      ),
                    );
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    Icons.add,
                    size: 16,
                    color: AppColors.primaryLight,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          child: Text(
            '${ShopSettings.currency}${item.total.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.primaryLight,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String title;
  final String? color;
  final String? categoryName;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.title,
    this.color,
    this.categoryName,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Resolve category color
    Color? accentColor;
    if (color != null) {
      try {
        accentColor = Color(int.parse(color!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    final chipColor = accentColor ?? AppColors.primary;
    final icon = CategoryIconUtils.iconFor(categoryName ?? title);

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: isSelected ? chipColor : AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: isSelected ? chipColor : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected
                      ? Colors.white
                      : (accentColor ?? AppColors.textSecondary),
                ),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final String? categoryName;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    this.categoryName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stock = (product['stock'] as num? ?? 0).toDouble();
    final lowStock = (product['low_stock'] as num? ?? 5).toDouble();
    final saleUnit = UnitUtils.saleUnitForProduct(product);
    final stockUnit = UnitUtils.stockUnitForProduct(product);
    final saleToStockFactor = UnitUtils.saleToStockFactor(product);
    final saleStock = saleToStockFactor > 0
        ? (stock / saleToStockFactor)
        : stock;
    final usesConversion = saleUnit != stockUnit;
    final isLowStock = stock <= lowStock;

    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      elevation: 0,
      child: InkWell(
        onTap: stock > 0 ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child:
                      product['image_url'] != null &&
                          product['image_url'].toString().isNotEmpty &&
                          File(product['image_url'] as String).existsSync()
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(product['image_url'] as String),
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Center(
                          child: Icon(
                            CategoryIconUtils.iconFor(categoryName),
                            size: 36,
                            color: stock > 0
                                ? AppColors.primaryLight.withValues(alpha: 0.6)
                                : AppColors.textSecondary.withValues(
                                    alpha: 0.3,
                                  ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                product['name'] as String? ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                UnitUtils.priceLabel(saleUnit),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${ShopSettings.currency}${(product['price'] as num? ?? 0).toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: stock == 0
                          ? AppColors.error.withValues(alpha: 0.15)
                          : isLowStock
                          ? AppColors.warning.withValues(alpha: 0.15)
                          : AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      stock == 0
                          ? 'Out'
                          : UnitUtils.formatWithUnit(saleStock, saleUnit),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: stock == 0
                            ? AppColors.error
                            : isLowStock
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
              if (usesConversion) ...[
                const SizedBox(height: 4),
                Text(
                  'Stocked as ${UnitUtils.formatWithUnit(stock, stockUnit)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String title;
  final String value;
  final bool isDiscount;

  const _SummaryRow({
    required this.title,
    required this.value,
    this.isDiscount = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: AppColors.textSecondary)),
        Text(
          value,
          style: TextStyle(
            color: isDiscount ? AppColors.warning : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
