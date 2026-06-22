import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/product_image_upload_service.dart';
import '../../../../core/services/shop_settings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/unit_utils.dart';
import 'color_option_tile.dart';

typedef ProductVariantAddCallback =
    FutureOr<void> Function(
      Map<String, dynamic> variant,
      Map<String, dynamic>? variantColor,
      BuildContext dialogContext,
    );

typedef ProductVariantRememberedColor =
    String? Function(Map<String, dynamic> variant);

class ProductVariantDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> variants;
  final Map<String, List<Map<String, dynamic>>> colorsByVariantId;
  final String? categoryName;
  final ProductVariantRememberedColor? rememberedColorIdForVariant;
  final ProductVariantAddCallback onAddToCart;

  const ProductVariantDialog({
    super.key,
    required this.product,
    required this.variants,
    required this.colorsByVariantId,
    required this.onAddToCart,
    this.categoryName,
    this.rememberedColorIdForVariant,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> product,
    required List<Map<String, dynamic>> variants,
    required Map<String, List<Map<String, dynamic>>> colorsByVariantId,
    required ProductVariantAddCallback onAddToCart,
    String? categoryName,
    ProductVariantRememberedColor? rememberedColorIdForVariant,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (dialogContext) => ProductVariantDialog(
        product: product,
        variants: variants,
        colorsByVariantId: colorsByVariantId,
        categoryName: categoryName,
        rememberedColorIdForVariant: rememberedColorIdForVariant,
        onAddToCart: onAddToCart,
      ),
    );
  }

  static String heroTagFor(
    Map<String, dynamic> product,
    Map<String, dynamic> variant,
  ) {
    return 'variant-color-${product['id']}-${variant['id']}';
  }

  @override
  State<ProductVariantDialog> createState() => _ProductVariantDialogState();
}

class _ProductVariantDialogState extends State<ProductVariantDialog> {
  late final ValueNotifier<Map<String, dynamic>> _selectedVariant;
  late final ValueNotifier<Map<String, dynamic>?> _selectedColor;

  @override
  void initState() {
    super.initState();
    final initialVariant = _initialVariant();
    _selectedVariant = ValueNotifier<Map<String, dynamic>>(initialVariant);
    _selectedColor = ValueNotifier<Map<String, dynamic>?>(
      _preferredColorForVariant(initialVariant),
    );
  }

  @override
  void dispose() {
    _selectedVariant.dispose();
    _selectedColor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 600;
    final inset = isMobile ? AppSpacing.sm : AppSpacing.lg;
    final maxWidth = math.min(size.width - (inset * 2), 1180.0);
    final maxHeight = math.min(size.height - (inset * 2), 820.0);

    return Dialog(
      insetPadding: EdgeInsets.all(inset),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.max(maxWidth, 320),
          maxHeight: math.max(maxHeight, isMobile ? 520 : 540),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) {
              return _MobileVariantLayout(
                product: widget.product,
                categoryName: widget.categoryName,
                variants: widget.variants,
                colorsByVariantId: widget.colorsByVariantId,
                selectedVariantListenable: _selectedVariant,
                selectedColorListenable: _selectedColor,
                onVariantSelected: _selectVariant,
                onColorSelected: (color) {
                  _selectedColor.value = color;
                },
                onAddToCart: () async {
                  await widget.onAddToCart(
                    _selectedVariant.value,
                    _selectedColor.value,
                    context,
                  );
                },
              );
            }

            final isTwoColumn = constraints.maxWidth >= 820;
            final content = isTwoColumn
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 35,
                        child: _LeftPanel(
                          product: widget.product,
                          categoryName: widget.categoryName,
                          variants: widget.variants,
                          colorsByVariantId: widget.colorsByVariantId,
                          selectedVariantListenable: _selectedVariant,
                          onVariantSelected: _selectVariant,
                        ),
                      ),
                      Container(
                        width: 1,
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.64),
                      ),
                      Expanded(
                        flex: 65,
                        child: _RightPanel(
                          product: widget.product,
                          colorsByVariantId: widget.colorsByVariantId,
                          selectedVariantListenable: _selectedVariant,
                          selectedColorListenable: _selectedColor,
                          onColorSelected: (color) {
                            _selectedColor.value = color;
                          },
                          onAddToCart: () async {
                            await widget.onAddToCart(
                              _selectedVariant.value,
                              _selectedColor.value,
                              context,
                            );
                          },
                        ),
                      ),
                    ],
                  )
                : _StackedLayout(
                    product: widget.product,
                    categoryName: widget.categoryName,
                    variants: widget.variants,
                    colorsByVariantId: widget.colorsByVariantId,
                    selectedVariantListenable: _selectedVariant,
                    selectedColorListenable: _selectedColor,
                    onVariantSelected: _selectVariant,
                    onColorSelected: (color) {
                      _selectedColor.value = color;
                    },
                    onAddToCart: () async {
                      await widget.onAddToCart(
                        _selectedVariant.value,
                        _selectedColor.value,
                        context,
                      );
                    },
                  );

            return AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: content,
            );
          },
        ),
      ),
    );
  }

  Map<String, dynamic> _initialVariant() {
    for (final variant in widget.variants) {
      if (_variantIsAvailable(widget.product, variant, _colorsFor(variant))) {
        return variant;
      }
    }
    return widget.variants.first;
  }

  void _selectVariant(Map<String, dynamic> variant) {
    if (variant['id'] == _selectedVariant.value['id']) {
      return;
    }
    _selectedVariant.value = variant;
    _selectedColor.value = _preferredColorForVariant(variant);
  }

  List<Map<String, dynamic>> _colorsFor(Map<String, dynamic> variant) {
    return widget.colorsByVariantId[variant['id']?.toString()] ??
        const <Map<String, dynamic>>[];
  }

  Map<String, dynamic>? _preferredColorForVariant(
    Map<String, dynamic> variant,
  ) {
    final colors = _colorsFor(variant);
    if (colors.isEmpty) {
      return null;
    }

    final rememberedId = widget.rememberedColorIdForVariant?.call(variant);
    if (rememberedId != null && rememberedId.trim().isNotEmpty) {
      for (final color in colors) {
        if (color['id']?.toString() == rememberedId &&
            _colorIsAvailable(widget.product, color)) {
          return color;
        }
      }
    }

    for (final color in colors) {
      if (_colorIsAvailable(widget.product, color)) {
        return color;
      }
    }
    return colors.first;
  }
}

class _LeftPanel extends StatelessWidget {
  final Map<String, dynamic> product;
  final String? categoryName;
  final List<Map<String, dynamic>> variants;
  final Map<String, List<Map<String, dynamic>>> colorsByVariantId;
  final ValueListenable<Map<String, dynamic>> selectedVariantListenable;
  final ValueChanged<Map<String, dynamic>> onVariantSelected;
  final bool compact;

  const _LeftPanel({
    required this.product,
    required this.categoryName,
    required this.variants,
    required this.colorsByVariantId,
    required this.selectedVariantListenable,
    required this.onVariantSelected,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Image is useful, not dominant — capped at 120px on desktop, 72px compact.
            final imageHeight = compact
                ? (constraints.maxHeight * 0.18).clamp(56.0, 84.0)
                : (constraints.maxHeight * 0.22).clamp(110.0, 160.0);
            final gap = compact ? AppSpacing.sm : AppSpacing.md;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: imageHeight,
                  width: double.infinity,
                  child: _ProductHeroImage(imagePath: _bestProductImage()),
                ),
                SizedBox(height: gap),
                ValueListenableBuilder<Map<String, dynamic>>(
                  valueListenable: selectedVariantListenable,
                  builder: (context, selectedVariant, _) {
                    return _ProductInfoBlock(
                      product: product,
                      variant: selectedVariant,
                      categoryName: categoryName,
                      compact: compact,
                    );
                  },
                ),
                SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Product Variants',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${variants.length}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: variants.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final variant = variants[index];
                      final colors =
                          colorsByVariantId[variant['id']?.toString()] ??
                          const <Map<String, dynamic>>[];
                      return ValueListenableBuilder<Map<String, dynamic>>(
                        valueListenable: selectedVariantListenable,
                        builder: (context, selectedVariant, _) {
                          final selected =
                              selectedVariant['id']?.toString() ==
                              variant['id']?.toString();
                          return _VariantCard(
                            product: product,
                            variant: variant,
                            colors: colors,
                            selected: selected,
                            enabled: _variantIsAvailable(
                              product,
                              variant,
                              colors,
                            ),
                            onTap: () => onVariantSelected(variant),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String? _bestProductImage() {
    final productImage = product['image_url']?.toString().trim() ?? '';
    if (productImage.isNotEmpty) {
      return productImage;
    }
    for (final variant in variants) {
      final colors =
          colorsByVariantId[variant['id']?.toString()] ??
          const <Map<String, dynamic>>[];
      for (final color in colors) {
        final image = color['image_url']?.toString().trim() ?? '';
        if (image.isNotEmpty) {
          return image;
        }
      }
    }
    return null;
  }
}

class _RightPanel extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, List<Map<String, dynamic>>> colorsByVariantId;
  final ValueListenable<Map<String, dynamic>> selectedVariantListenable;
  final ValueListenable<Map<String, dynamic>?> selectedColorListenable;
  final ValueChanged<Map<String, dynamic>> onColorSelected;
  final FutureOr<void> Function() onAddToCart;

  const _RightPanel({
    required this.product,
    required this.colorsByVariantId,
    required this.selectedVariantListenable,
    required this.selectedColorListenable,
    required this.onColorSelected,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surface),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.xl, AppSpacing.lg, AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose Color',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ValueListenableBuilder<Map<String, dynamic>>(
                        valueListenable: selectedVariantListenable,
                        builder: (context, variant, _) {
                          final colors =
                              colorsByVariantId[variant['id']?.toString()] ??
                              const <Map<String, dynamic>>[];
                          final available = colors
                              .where(
                                (color) => _colorIsAvailable(product, color),
                              )
                              .length;
                          return Text(
                            colors.isEmpty
                                ? 'Fast add for ${_displayName(variant['name'], fallback: 'Variant')}'
                                : '$available of ${colors.length} available',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Cancel',
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<Map<String, dynamic>>(
              valueListenable: selectedVariantListenable,
              builder: (context, variant, _) {
                final colors =
                    colorsByVariantId[variant['id']?.toString()] ??
                    const <Map<String, dynamic>>[];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 230),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.035, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _ColorPanelBody(
                    key: ValueKey(variant['id']?.toString() ?? 'variant'),
                    product: product,
                    variant: variant,
                    colors: colors,
                    selectedColorListenable: selectedColorListenable,
                    onColorSelected: onColorSelected,
                  ),
                );
              },
            ),
          ),
          _StickySummary(
            product: product,
            colorsByVariantId: colorsByVariantId,
            selectedVariantListenable: selectedVariantListenable,
            selectedColorListenable: selectedColorListenable,
            onAddToCart: onAddToCart,
          ),
        ],
      ),
    );
  }
}

class _StackedLayout extends StatelessWidget {
  final Map<String, dynamic> product;
  final String? categoryName;
  final List<Map<String, dynamic>> variants;
  final Map<String, List<Map<String, dynamic>>> colorsByVariantId;
  final ValueListenable<Map<String, dynamic>> selectedVariantListenable;
  final ValueListenable<Map<String, dynamic>?> selectedColorListenable;
  final ValueChanged<Map<String, dynamic>> onVariantSelected;
  final ValueChanged<Map<String, dynamic>> onColorSelected;
  final FutureOr<void> Function() onAddToCart;

  const _StackedLayout({
    required this.product,
    required this.categoryName,
    required this.variants,
    required this.colorsByVariantId,
    required this.selectedVariantListenable,
    required this.selectedColorListenable,
    required this.onVariantSelected,
    required this.onColorSelected,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 44,
          child: _LeftPanel(
            product: product,
            categoryName: categoryName,
            variants: variants,
            colorsByVariantId: colorsByVariantId,
            selectedVariantListenable: selectedVariantListenable,
            onVariantSelected: onVariantSelected,
            compact: true,
          ),
        ),
        Container(
          height: 1,
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.64),
        ),
        Expanded(
          flex: 56,
          child: _RightPanel(
            product: product,
            colorsByVariantId: colorsByVariantId,
            selectedVariantListenable: selectedVariantListenable,
            selectedColorListenable: selectedColorListenable,
            onColorSelected: onColorSelected,
            onAddToCart: onAddToCart,
          ),
        ),
      ],
    );
  }
}

class _MobileVariantLayout extends StatelessWidget {
  final Map<String, dynamic> product;
  final String? categoryName;
  final List<Map<String, dynamic>> variants;
  final Map<String, List<Map<String, dynamic>>> colorsByVariantId;
  final ValueListenable<Map<String, dynamic>> selectedVariantListenable;
  final ValueListenable<Map<String, dynamic>?> selectedColorListenable;
  final ValueChanged<Map<String, dynamic>> onVariantSelected;
  final ValueChanged<Map<String, dynamic>> onColorSelected;
  final FutureOr<void> Function() onAddToCart;

  const _MobileVariantLayout({
    required this.product,
    required this.categoryName,
    required this.variants,
    required this.colorsByVariantId,
    required this.selectedVariantListenable,
    required this.selectedColorListenable,
    required this.onVariantSelected,
    required this.onColorSelected,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surface),
      child: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _MobileProductHeader(
                    product: product,
                    categoryName: categoryName,
                    selectedVariantListenable: selectedVariantListenable,
                    imagePath: _bestProductImageFor(
                      product,
                      variants,
                      colorsByVariantId,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Product Variants',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '${variants.length}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _MobileVariantSelector(
                    product: product,
                    variants: variants,
                    colorsByVariantId: colorsByVariantId,
                    selectedVariantListenable: selectedVariantListenable,
                    onVariantSelected: onVariantSelected,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _MobileColorSection(
                    product: product,
                    colorsByVariantId: colorsByVariantId,
                    selectedVariantListenable: selectedVariantListenable,
                    selectedColorListenable: selectedColorListenable,
                    onColorSelected: onColorSelected,
                  ),
                ),
              ],
            ),
          ),
          _MobileStickySummary(
            product: product,
            colorsByVariantId: colorsByVariantId,
            selectedVariantListenable: selectedVariantListenable,
            selectedColorListenable: selectedColorListenable,
            onAddToCart: onAddToCart,
          ),
        ],
      ),
    );
  }
}

class _MobileProductHeader extends StatelessWidget {
  final Map<String, dynamic> product;
  final String? categoryName;
  final ValueListenable<Map<String, dynamic>> selectedVariantListenable;
  final String? imagePath;

  const _MobileProductHeader({
    required this.product,
    required this.categoryName,
    required this.selectedVariantListenable,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              SizedBox(
                height: 72,
                width: double.infinity,
                child: _ProductHeroImage(imagePath: imagePath),
              ),
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Cancel',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _displayName(product['name'], fallback: 'Product'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: selectedVariantListenable,
            builder: (context, variant, _) {
              final barcode =
                  _nonEmptyString(variant['barcode']) ??
                  _nonEmptyString(product['barcode']);
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _InfoPill(
                    icon: Icons.category_outlined,
                    label: _nonEmptyString(categoryName) ?? 'General',
                  ),
                  _InfoPill(
                    icon: Icons.inventory_2_outlined,
                    label: _stockLabel(product, variant),
                  ),
                  if (barcode != null)
                    _InfoPill(icon: Icons.qr_code_2_rounded, label: barcode),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MobileVariantSelector extends StatelessWidget {
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> variants;
  final Map<String, List<Map<String, dynamic>>> colorsByVariantId;
  final ValueListenable<Map<String, dynamic>> selectedVariantListenable;
  final ValueChanged<Map<String, dynamic>> onVariantSelected;

  const _MobileVariantSelector({
    required this.product,
    required this.variants,
    required this.colorsByVariantId,
    required this.selectedVariantListenable,
    required this.onVariantSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth * 0.52).clamp(172.0, 232.0);
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: variants.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final variant = variants[index];
              final colors =
                  colorsByVariantId[variant['id']?.toString()] ??
                  const <Map<String, dynamic>>[];
              return SizedBox(
                width: itemWidth,
                child: ValueListenableBuilder<Map<String, dynamic>>(
                  valueListenable: selectedVariantListenable,
                  builder: (context, selectedVariant, _) {
                    return _MobileVariantChip(
                      product: product,
                      variant: variant,
                      colors: colors,
                      selected:
                          selectedVariant['id']?.toString() ==
                          variant['id']?.toString(),
                      enabled: _variantIsAvailable(product, variant, colors),
                      onTap: () => onVariantSelected(variant),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MobileVariantChip extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic> variant;
  final List<Map<String, dynamic>> colors;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _MobileVariantChip({
    required this.product,
    required this.variant,
    required this.colors,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stockLabel = colors.isEmpty
        ? _stockLabel(product, variant)
        : _variantColorSummary(product, colors);
    final previewImage = _variantPreviewImage(variant, colors);
    final previewSwatch = _variantPreviewSwatch(colors);
    final showPreview = previewImage != null || previewSwatch != null;

    return Opacity(
      opacity: enabled ? 1 : 0.52,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          splashColor: scheme.primary.withValues(alpha: 0.12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 210),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.13)
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : scheme.outline.withValues(alpha: 0.58),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 210),
                  width: 4,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (showPreview) ...[
                  _MobileVariantPreview(
                    imagePath: previewImage,
                    swatch: previewSwatch,
                    enabled: enabled,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName(variant['name'], fallback: 'Variant'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${_formatCurrency(_priceFor(product, variant))} - $stockLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : enabled
                      ? Icons.chevron_right_rounded
                      : Icons.block_rounded,
                  color: selected
                      ? scheme.primary
                      : enabled
                      ? scheme.onSurfaceVariant
                      : scheme.error,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileVariantPreview extends StatelessWidget {
  final String? imagePath;
  final Color? swatch;
  final bool enabled;

  const _MobileVariantPreview({
    required this.imagePath,
    required this.swatch,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = imagePath?.trim() ?? '';
    final fallback = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color:
            swatch ??
            scheme.primaryContainer.withValues(alpha: enabled ? 0.68 : 0.34),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: scheme.outline.withValues(alpha: enabled ? 0.55 : 0.32),
        ),
      ),
      child: swatch == null
          ? Icon(
              Icons.inventory_2_outlined,
              color: scheme.onSurfaceVariant,
              size: 18,
            )
          : null,
    );

    if (path.isEmpty) {
      return fallback;
    }

    final image = ProductImageUploadService.isRemoteImage(path)
        ? Image.network(
            path,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.file(
            File(path),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => fallback,
          );

    return Container(
      width: 38,
      height: 38,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.55)),
      ),
      child: image,
    );
  }
}

class _MobileColorSection extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, List<Map<String, dynamic>>> colorsByVariantId;
  final ValueListenable<Map<String, dynamic>> selectedVariantListenable;
  final ValueListenable<Map<String, dynamic>?> selectedColorListenable;
  final ValueChanged<Map<String, dynamic>> onColorSelected;

  const _MobileColorSection({
    required this.product,
    required this.colorsByVariantId,
    required this.selectedVariantListenable,
    required this.selectedColorListenable,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: selectedVariantListenable,
      builder: (context, variant, _) {
        final colors =
            colorsByVariantId[variant['id']?.toString()] ??
            const <Map<String, dynamic>>[];
        final available = colors
            .where((color) => _colorIsAvailable(product, color))
            .length;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 230),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Padding(
            key: ValueKey(variant['id']?.toString() ?? 'variant'),
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose Color',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  colors.isEmpty
                      ? 'Fast add for ${_displayName(variant['name'], fallback: 'Variant')}'
                      : '$available of ${colors.length} available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (colors.isEmpty)
                  _MobileNoColorState(product: product, variant: variant)
                else
                  ValueListenableBuilder<Map<String, dynamic>?>(
                    valueListenable: selectedColorListenable,
                    builder: (context, selectedColor, _) {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 440 ? 3 : 2;
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.zero,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: AppSpacing.sm,
                                  mainAxisSpacing: AppSpacing.sm,
                                  mainAxisExtent: 144,
                                ),
                            itemCount: colors.length,
                            itemBuilder: (context, index) {
                              final color = colors[index];
                              return _ColorCard(
                                colorOption: color,
                                selected:
                                    selectedColor?['id']?.toString() ==
                                    color['id']?.toString(),
                                enabled: _colorIsAvailable(product, color),
                                stockLabel: _stockLabel(product, color),
                                onTap: () => onColorSelected(color),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MobileNoColorState extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic> variant;

  const _MobileNoColorState({required this.product, required this.variant});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = _variantIsAvailable(
      product,
      variant,
      const <Map<String, dynamic>>[],
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: enabled
              ? scheme.outline.withValues(alpha: 0.58)
              : scheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (enabled ? scheme.primary : scheme.error).withValues(
                alpha: 0.12,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              enabled ? Icons.flash_on_rounded : Icons.block_rounded,
              color: enabled ? scheme.primary : scheme.error,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enabled ? 'Ready to add' : 'Out of stock',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? scheme.onSurface : scheme.error,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  enabled
                      ? '${_displayName(variant['name'], fallback: 'Variant')} has no color choices.'
                      : '${_displayName(variant['name'], fallback: 'Variant')} is unavailable.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileStickySummary extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, List<Map<String, dynamic>>> colorsByVariantId;
  final ValueListenable<Map<String, dynamic>> selectedVariantListenable;
  final ValueListenable<Map<String, dynamic>?> selectedColorListenable;
  final FutureOr<void> Function() onAddToCart;

  const _MobileStickySummary({
    required this.product,
    required this.colorsByVariantId,
    required this.selectedVariantListenable,
    required this.selectedColorListenable,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outline.withValues(alpha: 0.7)),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF20242D).withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
          child: ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: selectedVariantListenable,
            builder: (context, variant, _) {
              final colors =
                  colorsByVariantId[variant['id']?.toString()] ??
                  const <Map<String, dynamic>>[];
              return ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: selectedColorListenable,
                builder: (context, selectedColor, _) {
                  final canAdd = colors.isEmpty
                      ? _variantIsAvailable(product, variant, colors)
                      : selectedColor != null &&
                            _colorIsAvailable(product, selectedColor);
                  final stockSource = selectedColor ?? variant;
                  final summary =
                      '${_selectionLabel(variant, selectedColor)} - '
                      '${_formatCurrency(_priceFor(product, variant))} - '
                      '${_stockLabel(product, stockSource)}';

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.42,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: scheme.outline.withValues(alpha: 0.55),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              color: scheme.primary,
                              size: 18,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                summary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          SizedBox(
                            width: 102,
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.lg,
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: canAdd ? () => onAddToCart() : null,
                              icon: const Icon(
                                Icons.add_shopping_cart_rounded,
                                size: 20,
                              ),
                              label: const Text('Add to Cart'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.lg,
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProductHeroImage extends StatelessWidget {
  final String? imagePath;

  const _ProductHeroImage({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = imagePath?.trim() ?? '';
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.52),
            scheme.surface.withValues(alpha: 0.94),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.88),
            shape: BoxShape.circle,
            boxShadow: AppColors.premiumShadow(0.08),
          ),
          child: Icon(
            Icons.inventory_2_outlined,
            color: scheme.primary,
            size: 38,
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

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppColors.premiumShadow(0.08),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(AppRadius.lg), child: child),
    );
  }
}

class _ProductInfoBlock extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic> variant;
  final String? categoryName;
  final bool compact;

  const _ProductInfoBlock({
    required this.product,
    required this.variant,
    required this.categoryName,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final price = _priceFor(product, variant);
    final stockSource = _asDouble(variant['stock']) > 0 ? variant : product;
    final barcode =
        _nonEmptyString(variant['barcode']) ??
        _nonEmptyString(product['barcode']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _displayName(product['name'], fallback: 'Product'),
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: compact ? 18 : 23,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
        SizedBox(height: compact ? AppSpacing.xs : AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _InfoPill(
              icon: Icons.category_outlined,
              label: _nonEmptyString(categoryName) ?? 'General',
            ),
            _InfoPill(
              icon: Icons.sell_rounded,
              label: _formatCurrency(price),
              emphasized: true,
            ),
            _InfoPill(
              icon: Icons.inventory_2_outlined,
              label: _stockLabel(product, stockSource),
            ),
            if (barcode != null)
              _InfoPill(icon: Icons.qr_code_2_rounded, label: barcode),
          ],
        ),
      ],
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool emphasized;

  const _InfoPill({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: emphasized
            ? scheme.primary.withValues(alpha: 0.1)
            : scheme.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: emphasized
              ? scheme.primary.withValues(alpha: 0.24)
              : scheme.outline.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: emphasized ? scheme.primary : scheme.onSurfaceVariant,
            size: 15,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: emphasized ? scheme.primary : scheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VariantCard extends StatefulWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic> variant;
  final List<Map<String, dynamic>> colors;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _VariantCard({
    required this.product,
    required this.variant,
    required this.colors,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_VariantCard> createState() => _VariantCardState();
}

class _VariantCardState extends State<_VariantCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final price = _priceFor(widget.product, widget.variant);
    final stockLabel = widget.colors.isEmpty
        ? _stockLabel(widget.product, widget.variant)
        : _variantColorSummary(widget.product, widget.colors);
    final selected = widget.selected;
    final enabled = widget.enabled;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        scale: enabled && _hovered ? 1.012 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? widget.onTap : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
            splashColor: scheme.primary.withValues(alpha: 0.09),
            highlightColor: scheme.primary.withValues(alpha: 0.045),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 210),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: !enabled
                    ? scheme.surface.withValues(alpha: 0.48)
                    : selected
                    ? scheme.primary.withValues(alpha: 0.11)
                    : scheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: selected
                      ? scheme.primary
                      : scheme.outline.withValues(
                          alpha: _hovered ? 0.95 : 0.62,
                        ),
                  width: selected ? 1.6 : 1,
                ),
                boxShadow: enabled && (_hovered || selected)
                    ? [
                        BoxShadow(
                          color: const Color(
                            0xFF20242D,
                          ).withValues(alpha: _hovered ? 0.10 : 0.07),
                          blurRadius: _hovered ? 22 : 16,
                          offset: Offset(0, _hovered ? 10 : 7),
                        ),
                      ]
                    : const [],
              ),
              child: Opacity(
                opacity: enabled ? 1 : 0.52,
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 210),
                      width: 4,
                      height: 48,
                      decoration: BoxDecoration(
                        color: selected ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName(
                              widget.variant['name'],
                              fallback: 'Variant',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            children: [
                              _TinyMetric(
                                icon: Icons.sell_outlined,
                                label: _formatCurrency(price),
                                accent: selected,
                              ),
                              _TinyMetric(
                                icon: Icons.inventory_2_outlined,
                                label: stockLabel,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: selected
                          ? Icon(
                              Icons.check_circle_rounded,
                              key: const ValueKey('selected'),
                              color: scheme.primary,
                            )
                          : Icon(
                              enabled
                                  ? Icons.chevron_right_rounded
                                  : Icons.block_rounded,
                              key: ValueKey(enabled ? 'arrow' : 'blocked'),
                              color: enabled
                                  ? scheme.onSurfaceVariant
                                  : scheme.error,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TinyMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;

  const _TinyMetric({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 13,
          color: accent ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent ? scheme.primary : scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorPanelBody extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic> variant;
  final List<Map<String, dynamic>> colors;
  final ValueListenable<Map<String, dynamic>?> selectedColorListenable;
  final ValueChanged<Map<String, dynamic>> onColorSelected;

  const _ColorPanelBody({
    super.key,
    required this.product,
    required this.variant,
    required this.colors,
    required this.selectedColorListenable,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) {
      return _NoColorState(product: product, variant: variant);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.sm, AppSpacing.xxl, AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 860
              ? 4
              : constraints.maxWidth >= 570
              ? 3
              : 2;
          return ValueListenableBuilder<Map<String, dynamic>?>(
            valueListenable: selectedColorListenable,
            builder: (context, selectedColor, _) {
              return GridView.builder(
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  mainAxisExtent: 154,
                ),
                itemCount: colors.length,
                itemBuilder: (context, index) {
                  final color = colors[index];
                  final enabled = _colorIsAvailable(product, color);
                  final selected =
                      selectedColor?['id']?.toString() ==
                      color['id']?.toString();
                  return _ColorCard(
                    colorOption: color,
                    selected: selected,
                    enabled: enabled,
                    stockLabel: _stockLabel(product, color),
                    onTap: () => onColorSelected(color),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _NoColorState extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic> variant;

  const _NoColorState({required this.product, required this.variant});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = _variantIsAvailable(
      product,
      variant,
      const <Map<String, dynamic>>[],
    );
    return Center(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.xxl),
        padding: const EdgeInsets.all(AppSpacing.xl),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: enabled
                ? scheme.outline.withValues(alpha: 0.7)
                : scheme.error.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: (enabled ? scheme.primary : scheme.error).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                enabled
                    ? Icons.flash_on_rounded
                    : Icons.remove_shopping_cart_outlined,
                color: enabled ? scheme.primary : scheme.error,
                size: 30,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              enabled ? 'Ready to add' : 'Out of stock',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: enabled ? scheme.onSurface : scheme.error,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              enabled
                  ? '${_displayName(variant['name'], fallback: 'Variant')} has no color choices.'
                  : '${_displayName(variant['name'], fallback: 'Variant')} is currently unavailable.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorCard extends StatefulWidget {
  final Map<String, dynamic> colorOption;
  final bool selected;
  final bool enabled;
  final String stockLabel;
  final VoidCallback onTap;

  const _ColorCard({
    required this.colorOption,
    required this.selected,
    required this.enabled,
    required this.stockLabel,
    required this.onTap,
  });

  @override
  State<_ColorCard> createState() => _ColorCardState();
}

class _ColorCardState extends State<_ColorCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final swatch = colorOptionSwatch(widget.colorOption);
    final label = _displayName(widget.colorOption['name'], fallback: 'Color');
    final isLight =
        ThemeData.estimateBrightnessForColor(swatch) == Brightness.light;
    final selected = widget.selected;
    final enabled = widget.enabled;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        scale: enabled && selected
            ? 1.018
            : enabled && _hovered
            ? 1.012
            : 1,
        child: Material(
          color: enabled
              ? scheme.surface
              : scheme.surfaceContainerHighest.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            onTap: enabled ? widget.onTap : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
            splashColor: scheme.primary.withValues(alpha: 0.13),
            highlightColor: scheme.primary.withValues(alpha: 0.065),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 210),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: selected
                      ? scheme.primary
                      : scheme.outline.withValues(alpha: _hovered ? 0.9 : 0.58),
                  width: selected ? 1.7 : 1,
                ),
                boxShadow: enabled
                    ? [
                        BoxShadow(
                          color: const Color(0xFF20242D).withValues(
                            alpha: _hovered || selected ? 0.12 : 0.055,
                          ),
                          blurRadius: _hovered || selected ? 24 : 16,
                          offset: Offset(0, _hovered || selected ? 11 : 7),
                        ),
                      ]
                    : const [],
              ),
              child: Stack(
                children: [
                  Opacity(
                    opacity: enabled ? 1 : 0.52,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: swatch,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isLight
                                  ? const Color(0xFFD1D5DB)
                                  : Colors.white,
                              width: 2.2,
                            ),
                            boxShadow: enabled
                                ? [
                                    BoxShadow(
                                      color: swatch.withValues(
                                        alpha: isLight ? 0.15 : 0.3,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ]
                                : const [],
                          ),
                          child: selected
                              ? Icon(
                                  Icons.check_rounded,
                                  color: isLight
                                      ? AppColors.textPrimary
                                      : Colors.white,
                                  size: 30,
                                )
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          widget.stockLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 170),
                      child: !enabled
                          ? _StatusBadge(
                              key: const ValueKey('out'),
                              label: 'Out',
                              color: scheme.error,
                            )
                          : selected
                          ? Icon(
                              Icons.check_circle_rounded,
                              key: const ValueKey('selected'),
                              color: scheme.primary,
                              size: 22,
                            )
                          : const SizedBox(
                              key: ValueKey('empty'),
                              width: 22,
                              height: 22,
                            ),
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
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StickySummary extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, List<Map<String, dynamic>>> colorsByVariantId;
  final ValueListenable<Map<String, dynamic>> selectedVariantListenable;
  final ValueListenable<Map<String, dynamic>?> selectedColorListenable;
  final FutureOr<void> Function() onAddToCart;

  const _StickySummary({
    required this.product,
    required this.colorsByVariantId,
    required this.selectedVariantListenable,
    required this.selectedColorListenable,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outline.withValues(alpha: 0.7)),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF20242D).withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.md, AppSpacing.xxl, AppSpacing.lg),
          child: ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: selectedVariantListenable,
            builder: (context, variant, _) {
              final colors =
                  colorsByVariantId[variant['id']?.toString()] ??
                  const <Map<String, dynamic>>[];
              return ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: selectedColorListenable,
                builder: (context, selectedColor, _) {
                  final selectedLabel = _selectionLabel(variant, selectedColor);
                  final price = _priceFor(product, variant);
                  final stockSource = selectedColor ?? variant;
                  final canAdd = colors.isEmpty
                      ? _variantIsAvailable(product, variant, colors)
                      : selectedColor != null &&
                            _colorIsAvailable(product, selectedColor);

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 620;
                      final metrics = [
                        _SummaryMetric(label: 'Selected', value: selectedLabel),
                        _SummaryMetric(
                          label: 'Price',
                          value: _formatCurrency(price),
                        ),
                        _SummaryMetric(
                          label: 'Stock',
                          value: _stockLabel(product, stockSource),
                        ),
                      ];
                      final cancelButton = OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      );
                      final addButton = FilledButton.icon(
                        onPressed: canAdd ? () => onAddToCart() : null,
                        icon: const Icon(
                          Icons.add_shopping_cart_rounded,
                          size: 20,
                        ),
                        label: const Text('Add to Cart'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxl,
                            vertical: AppSpacing.xl,
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      );
                      final buttons = compact
                          ? Row(
                              children: [
                                Expanded(child: cancelButton),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(flex: 2, child: addButton),
                              ],
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 112, child: cancelButton),
                                const SizedBox(width: AppSpacing.sm),
                                SizedBox(width: 178, child: addButton),
                              ],
                            );

                      if (compact) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: metrics,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            buttons,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: metrics,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          buttons,
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.58)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

bool _variantIsAvailable(
  Map<String, dynamic> product,
  Map<String, dynamic> variant,
  List<Map<String, dynamic>> colors,
) {
  if (!UnitUtils.tracksStock(product)) {
    return true;
  }
  if (colors.isNotEmpty) {
    return colors.any((color) => _asDouble(color['stock']) > 0);
  }
  return _asDouble(variant['stock']) > 0;
}

bool _colorIsAvailable(
  Map<String, dynamic> product,
  Map<String, dynamic> color,
) {
  return !UnitUtils.tracksStock(product) || _asDouble(color['stock']) > 0;
}

double _priceFor(Map<String, dynamic> product, Map<String, dynamic> variant) {
  return _asDouble(variant['price'], fallback: _asDouble(product['price']));
}

String _variantColorSummary(
  Map<String, dynamic> product,
  List<Map<String, dynamic>> colors,
) {
  if (!UnitUtils.tracksStock(product)) {
    return '${colors.length} colors';
  }
  final available = colors
      .where((color) => _asDouble(color['stock']) > 0)
      .length;
  if (available == 0) {
    return 'Out of stock';
  }
  return '$available/${colors.length} colors';
}

String _stockLabel(
  Map<String, dynamic> product,
  Map<String, dynamic> stockSource,
) {
  if (!UnitUtils.tracksStock(product)) {
    return 'No stock limit';
  }
  final stock = _asDouble(stockSource['stock']);
  if (stock <= 0) {
    return 'Out of stock';
  }
  return UnitUtils.formatWithUnit(
    stock,
    UnitUtils.stockUnitForProduct(product),
  );
}

String _selectionLabel(
  Map<String, dynamic> variant,
  Map<String, dynamic>? color,
) {
  final variantName = _displayName(variant['name'], fallback: 'Variant');
  final colorName = _nonEmptyString(color?['name']);
  if (colorName == null) {
    return variantName;
  }
  return '$variantName - $colorName';
}

String _formatCurrency(double value) {
  final amount = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return '${ShopSettings.currency}$amount';
}

String? _bestProductImageFor(
  Map<String, dynamic> product,
  List<Map<String, dynamic>> variants,
  Map<String, List<Map<String, dynamic>>> colorsByVariantId,
) {
  final productImage = product['image_url']?.toString().trim() ?? '';
  if (productImage.isNotEmpty) {
    return productImage;
  }
  for (final variant in variants) {
    final colors =
        colorsByVariantId[variant['id']?.toString()] ??
        const <Map<String, dynamic>>[];
    for (final color in colors) {
      final image = color['image_url']?.toString().trim() ?? '';
      if (image.isNotEmpty) {
        return image;
      }
    }
  }
  return null;
}

String? _variantPreviewImage(
  Map<String, dynamic> variant,
  List<Map<String, dynamic>> colors,
) {
  final variantImage = _nonEmptyString(variant['image_url']);
  if (variantImage != null) {
    return variantImage;
  }
  for (final color in colors) {
    final image = _nonEmptyString(color['image_url']);
    if (image != null && _asDouble(color['stock']) > 0) {
      return image;
    }
  }
  for (final color in colors) {
    final image = _nonEmptyString(color['image_url']);
    if (image != null) {
      return image;
    }
  }
  return null;
}

Color? _variantPreviewSwatch(List<Map<String, dynamic>> colors) {
  if (colors.isEmpty) {
    return null;
  }
  for (final color in colors) {
    if (_asDouble(color['stock']) > 0) {
      return colorOptionSwatch(color);
    }
  }
  return colorOptionSwatch(colors.first);
}

String _displayName(Object? value, {required String fallback}) {
  return _nonEmptyString(value) ?? fallback;
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
