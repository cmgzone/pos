import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/services/product_image_upload_service.dart';
import '../../../../core/services/shop_settings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/unit_utils.dart';
import 'color_option_tile.dart';

class ProductColorDrawer extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic> variant;
  final List<Map<String, dynamic>> colors;
  final String? selectedColorId;
  final String? heroTag;

  const ProductColorDrawer({
    super.key,
    required this.product,
    required this.variant,
    required this.colors,
    this.selectedColorId,
    this.heroTag,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Map<String, dynamic> product,
    required Map<String, dynamic> variant,
    required List<Map<String, dynamic>> colors,
    String? selectedColorId,
    String? heroTag,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<Map<String, dynamic>>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => const SizedBox.shrink(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return _ProductColorDrawerRouteBody(
            animation: curved,
            drawer: ProductColorDrawer(
              product: product,
              variant: variant,
              colors: colors,
              selectedColorId: selectedColorId,
              heroTag: heroTag,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final drawerWidth = size.width <= 640
        ? size.width * 0.86
        : size.width * 0.7;
    final price =
        (variant['price'] as num?)?.toDouble() ??
        (product['price'] as num?)?.toDouble() ??
        0;
    final tracksStock = UnitUtils.tracksStock(product);
    final stock = _asDouble(variant['stock']);
    final stockLabel = tracksStock
        ? UnitUtils.formatWithUnit(
            stock,
            UnitUtils.stockUnitForProduct(product),
          )
        : 'No stock limit';
    final headerImagePath = _bestImageForDrawer(
      product: product,
      colors: colors,
      selectedColorId: selectedColorId,
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: SafeArea(
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(24),
          ),
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: SizedBox(
              width: drawerWidth,
              height: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DrawerHeroHeader(
                    product: product,
                    variant: variant,
                    imagePath: headerImagePath,
                    heroTag: heroTag,
                    price: price,
                    stockLabel: stockLabel,
                  ),
                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'Choose Color',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${colors.length} options',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                          sliver: SliverList.separated(
                            itemCount: colors.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final color = colors[index];
                              final enabled = _isColorAvailable(product, color);
                              return ColorOptionTile(
                                option: color,
                                enabled: enabled,
                                selected: color['id'] == selectedColorId,
                                stockLabel: _colorStockLabel(product, color),
                                onTap: () => Navigator.pop(context, color),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static bool _isColorAvailable(
    Map<String, dynamic> product,
    Map<String, dynamic> color,
  ) {
    return !UnitUtils.tracksStock(product) || _asDouble(color['stock']) > 0;
  }

  static String _colorStockLabel(
    Map<String, dynamic> product,
    Map<String, dynamic> color,
  ) {
    if (!UnitUtils.tracksStock(product)) {
      return 'No stock limit';
    }
    final stock = _asDouble(color['stock']);
    if (stock <= 0) {
      return 'Out of stock';
    }
    return '${UnitUtils.formatWithUnit(stock, UnitUtils.stockUnitForProduct(product))} available';
  }

  static String? _bestImageForDrawer({
    required Map<String, dynamic> product,
    required List<Map<String, dynamic>> colors,
    required String? selectedColorId,
  }) {
    Map<String, dynamic>? selectedColor;
    if (selectedColorId != null) {
      for (final color in colors) {
        if (color['id'] == selectedColorId) {
          selectedColor = color;
          break;
        }
      }
    }
    final selectedImage = selectedColor?['image_url']?.toString().trim();
    if (selectedImage != null && selectedImage.isNotEmpty) {
      return selectedImage;
    }
    for (final color in colors) {
      final image = color['image_url']?.toString().trim() ?? '';
      if (image.isNotEmpty) {
        return image;
      }
    }
    return product['image_url']?.toString().trim();
  }
}

class _ProductColorDrawerRouteBody extends StatelessWidget {
  final Animation<double> animation;
  final ProductColorDrawer drawer;

  const _ProductColorDrawerRouteBody({
    required this.animation,
    required this.drawer,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = animation.value;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 4 * value,
                    sigmaY: 4 * value,
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.32 * value),
                  ),
                ),
              ),
            ),
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(-1, 0),
                end: Offset.zero,
              ).animate(animation),
              child: Transform.scale(
                alignment: Alignment.centerLeft,
                scale: 0.985 + (0.015 * value),
                child: drawer,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DrawerHeroHeader extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic> variant;
  final String? imagePath;
  final String? heroTag;
  final double price;
  final String stockLabel;

  const _DrawerHeroHeader({
    required this.product,
    required this.variant,
    required this.imagePath,
    required this.heroTag,
    required this.price,
    required this.stockLabel,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton.filledTonal(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close',
            ),
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _ProductImage(imagePath: imagePath),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            product['name']?.toString() ?? 'Product',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(
                icon: Icons.memory_rounded,
                label: variant['name']?.toString() ?? 'Variant',
              ),
              _InfoPill(
                icon: Icons.sell_rounded,
                label: '${ShopSettings.currency}${price.toStringAsFixed(2)}',
              ),
              _InfoPill(icon: Icons.inventory_2_rounded, label: stockLabel),
            ],
          ),
        ],
      ),
    );

    if (heroTag == null) {
      return content;
    }
    return Hero(
      tag: heroTag!,
      transitionOnUserGestures: true,
      child: Material(color: Colors.white, child: content),
    );
  }
}

class _ProductImage extends StatelessWidget {
  final String? imagePath;

  const _ProductImage({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final path = imagePath?.trim() ?? '';
    if (path.isEmpty) {
      return const _ImagePlaceholder();
    }
    if (ProductImageUploadService.isRemoteImage(path)) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => const _ImagePlaceholder(),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => const _ImagePlaceholder(),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6F7FB), Color(0xFFE8EBF3)],
        ),
      ),
      child: Center(
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.84),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.inventory_2_outlined,
            color: AppColors.primaryLight,
            size: 34,
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EC)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primaryLight, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
