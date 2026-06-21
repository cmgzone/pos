import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/shop_settings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/unit_utils.dart';
import 'color_option_tile.dart';

typedef VariantSelectedCallback =
    FutureOr<void> Function(
      Map<String, dynamic> variant,
      BuildContext bottomSheetContext,
    );

class VariantPickerBottomSheet extends StatefulWidget {
  final Map<String, dynamic> product;
  final List<Map<String, dynamic>> variants;
  final Map<String, List<Map<String, dynamic>>> colorsByVariantId;
  final VariantSelectedCallback onVariantSelected;

  const VariantPickerBottomSheet({
    super.key,
    required this.product,
    required this.variants,
    required this.colorsByVariantId,
    required this.onVariantSelected,
  });

  static String heroTagFor(
    Map<String, dynamic> product,
    Map<String, dynamic> variant,
  ) {
    return 'variant-color-${product['id']}-${variant['id']}';
  }

  @override
  State<VariantPickerBottomSheet> createState() =>
      _VariantPickerBottomSheetState();
}

class _VariantPickerBottomSheetState extends State<VariantPickerBottomSheet> {
  String? _busyVariantId;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxHeight = media.size.height * 0.76;
    final bottomPadding = media.viewInsets.bottom + media.padding.bottom;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: EdgeInsets.fromLTRB(18, 10, 18, 16 + bottomPadding),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: AppColors.premiumShadow(0.16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choose Variant',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.product['name']?.toString() ?? 'Product',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.variants.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final variant = widget.variants[index];
                  final id = variant['id']?.toString() ?? '';
                  final colors =
                      widget.colorsByVariantId[id] ??
                      const <Map<String, dynamic>>[];
                  final busy = _busyVariantId == id;
                  final enabled = _variantIsAvailable(variant, colors);
                  return Hero(
                    tag: VariantPickerBottomSheet.heroTagFor(
                      widget.product,
                      variant,
                    ),
                    transitionOnUserGestures: true,
                    child: _VariantOptionTile(
                      product: widget.product,
                      variant: variant,
                      colors: colors,
                      enabled: enabled && _busyVariantId == null,
                      busy: busy,
                      onTap: () async {
                        if (!enabled || _busyVariantId != null) {
                          return;
                        }
                        setState(() => _busyVariantId = id);
                        await widget.onVariantSelected(variant, context);
                        if (mounted) {
                          setState(() => _busyVariantId = null);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _variantIsAvailable(
    Map<String, dynamic> variant,
    List<Map<String, dynamic>> colors,
  ) {
    if (!UnitUtils.tracksStock(widget.product)) {
      return true;
    }
    if (colors.isNotEmpty) {
      return colors.any((color) => _asDouble(color['stock']) > 0);
    }
    return _asDouble(variant['stock']) > 0;
  }
}

class _VariantOptionTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final Map<String, dynamic> variant;
  final List<Map<String, dynamic>> colors;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _VariantOptionTile({
    required this.product,
    required this.variant,
    required this.colors,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price =
        (variant['price'] as num?)?.toDouble() ??
        (product['price'] as num?)?.toDouble() ??
        0;
    final hasColors = colors.isNotEmpty;
    final subtitle = hasColors
        ? _colorSummary(product, colors)
        : _stockSummary(product, variant);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: enabled
                ? theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.72,
                  )
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.38,
                  ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: enabled
                  ? AppColors.primaryLight.withValues(alpha: 0.18)
                  : theme.colorScheme.outline.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            children: [
              _VariantBadge(enabled: enabled, hasColors: hasColors),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variant['name']?.toString() ?? 'Variant',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ShopSettings.currency}${price.toStringAsFixed(2)} - $subtitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    if (hasColors) ...[
                      const SizedBox(height: 9),
                      _ColorDots(colors: colors),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: busy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : enabled
                    ? const Icon(
                        Icons.chevron_right_rounded,
                        key: ValueKey('next'),
                      )
                    : const Icon(
                        Icons.block_rounded,
                        key: ValueKey('blocked'),
                        color: AppColors.error,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _stockSummary(
    Map<String, dynamic> product,
    Map<String, dynamic> variant,
  ) {
    if (!UnitUtils.tracksStock(product)) {
      return 'No stock limit';
    }
    final stock = _asDouble(variant['stock']);
    if (stock <= 0) {
      return 'Out of stock';
    }
    return '${UnitUtils.formatWithUnit(stock, UnitUtils.stockUnitForProduct(product))} available';
  }

  static String _colorSummary(
    Map<String, dynamic> product,
    List<Map<String, dynamic>> colors,
  ) {
    if (!UnitUtils.tracksStock(product)) {
      return '${colors.length} color${colors.length == 1 ? '' : 's'}';
    }
    final available = colors
        .where((color) => _asDouble(color['stock']) > 0)
        .length;
    if (available == 0) {
      return 'All colors out of stock';
    }
    return '$available of ${colors.length} color${colors.length == 1 ? '' : 's'} available';
  }
}

class _VariantBadge extends StatelessWidget {
  final bool enabled;
  final bool hasColors;

  const _VariantBadge({required this.enabled, required this.hasColors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: enabled
            ? AppColors.primaryLight.withValues(alpha: 0.14)
            : Theme.of(context).colorScheme.outline.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        hasColors ? Icons.palette_outlined : Icons.inventory_2_outlined,
        color: enabled
            ? AppColors.primaryLight
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ColorDots extends StatelessWidget {
  final List<Map<String, dynamic>> colors;

  const _ColorDots({required this.colors});

  @override
  Widget build(BuildContext context) {
    final visible = colors.take(6).toList(growable: false);
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: [
        for (final color in visible)
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: colorOptionSwatch(color),
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    ThemeData.estimateBrightnessForColor(
                          colorOptionSwatch(color),
                        ) ==
                        Brightness.light
                    ? const Color(0xFFD1D5DB)
                    : Colors.white,
              ),
            ),
          ),
        if (colors.length > visible.length)
          Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
            ),
            child: Text(
              '+${colors.length - visible.length}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
          ),
      ],
    );
  }
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
