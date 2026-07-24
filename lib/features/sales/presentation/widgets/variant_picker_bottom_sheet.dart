import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/product_image_upload_service.dart';
import '../../../../core/services/shop_settings.dart';
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

/// ---------------------------------------------------------------------------
/// The Counter design language for the variant picker.
///
/// Instead of a generic card grid, the picker reads like a shop counter:
/// a deep ink header band with the product and its price, variants as paper
/// ticket stubs with a perforated edge, colors as a wall of tactile swatches,
/// and a receipt-style add-to-cart bar. Built for speed at the till.
/// ---------------------------------------------------------------------------
class _Counter {
  const _Counter._();

  static const Color ink = Color(0xFF132019);
  static const Color inkDeep = Color(0xFF0C1712);
  static const Color paper = Color(0xFFF8F4E8);
  static const Color paperDeep = Color(0xFFEDE7D5);
  static const Color paperRule = Color(0xFFD3CBB2);
  static const Color paperInk = Color(0xFF1B241F);
  static const Color paperFaded = Color(0xFF6B7566);
  static const Color accent = Color(0xFFE0641A);
  static const Color accentDeep = Color(0xFFB14E0C);
  static const Color mint = Color(0xFF2FBFA4);

  static TextStyle display(
    double size, {
    Color color = paper,
    FontWeight weight = FontWeight.w700,
    double? height,
  }) =>
      GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: size * -0.02,
        height: height ?? 1.05,
      );

  static TextStyle mono(
    double size, {
    Color color = paperInk,
    FontWeight weight = FontWeight.w600,
    double? letterSpacing,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  static TextStyle body(
    double size, {
    Color color = paperFaded,
    FontWeight weight = FontWeight.w500,
    double? height,
  }) =>
      TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height ?? 1.35,
      );
}

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
      barrierColor: const Color(0xFF0A120D).withValues(alpha: 0.55),
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
    final inset = isMobile ? 12.0 : 24.0;
    final maxWidth = math.min(size.width - (inset * 2), 1080.0);
    final maxHeight = math.min(size.height - (inset * 2), 780.0);

    return Dialog(
      insetPadding: EdgeInsets.all(inset),
      backgroundColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.max(maxWidth, 320),
          maxHeight: math.max(maxHeight, isMobile ? 520 : 540),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: _Counter.paper,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 620) {
                  return _MobileLayout(state: this);
                }
                return _WideLayout(state: this);
              },
            ),
          ),
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

  Future<void> _addToCart(BuildContext context) async {
    await widget.onAddToCart(
      _selectedVariant.value,
      _selectedColor.value,
      context,
    );
  }
}

/// ── Wide (desktop / tablet) layout ─────────────────────────────────────────
class _WideLayout extends StatelessWidget {
  final _ProductVariantDialogState state;

  const _WideLayout({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CounterHeader(state: state),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 300,
                child: _VariantRail(state: state),
              ),
              Container(width: 1, color: _Counter.paperRule),
              Expanded(
                child: _ColorWall(state: state),
              ),
            ],
          ),
        ),
        _AddBar(state: state),
      ],
    );
  }
}

/// ── Mobile layout ──────────────────────────────────────────────────────────
class _MobileLayout extends StatelessWidget {
  final _ProductVariantDialogState state;

  const _MobileLayout({required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CounterHeader(state: state, compact: true),
        Expanded(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _VariantRail(state: state, horizontal: true),
              ),
              SliverToBoxAdapter(
                child: _ColorWall(state: state, inScroll: true),
              ),
            ],
          ),
        ),
        _AddBar(state: state),
      ],
    );
  }
}

/// ── Header band ────────────────────────────────────────────────────────────
class _CounterHeader extends StatelessWidget {
  final _ProductVariantDialogState state;
  final bool compact;

  const _CounterHeader({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final widget = state.widget;
    final product = widget.product;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _Counter.ink,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 22,
          compact ? 14 : 18,
          compact ? 12 : 18,
          compact ? 14 : 18,
        ),
        child: ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: state._selectedVariant,
          builder: (context, variant, _) {
            final price = _priceFor(product, variant);
            final stockSource =
                _asDouble(variant['stock']) > 0 ? variant : product;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderThumb(
                  imagePath: _bestProductImageFor(
                    product,
                    widget.variants,
                    widget.colorsByVariantId,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _Counter.paper.withValues(alpha: 0.3),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (_nonEmptyString(widget.categoryName) ?? 'GENERAL')
                                  .toUpperCase(),
                              style: _Counter.mono(
                                8.5,
                                color: _Counter.paper.withValues(alpha: 0.7),
                                weight: FontWeight.w700,
                                letterSpacing: 1.6,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${widget.variants.length} VARIANTS',
                            style: _Counter.mono(
                              9,
                              color: _Counter.paper.withValues(alpha: 0.45),
                              weight: FontWeight.w600,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _displayName(product['name'], fallback: 'Product'),
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: _Counter.display(
                          compact ? 22 : 26,
                          color: _Counter.paper,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              key: ValueKey(price),
                              _formatCurrency(price),
                              style: _Counter.mono(
                                compact ? 20 : 24,
                                color: _Counter.accent,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              _stockLabel(product, stockSource).toUpperCase(),
                              style: _Counter.mono(
                                9.5,
                                color: _Counter.mint,
                                weight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _CloseButton(compact: compact),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderThumb extends StatelessWidget {
  final String? imagePath;

  const _HeaderThumb({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final path = imagePath?.trim() ?? '';
    final fallback = Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: _Counter.paper.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Counter.paper.withValues(alpha: 0.16)),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        color: _Counter.paper.withValues(alpha: 0.5),
        size: 24,
      ),
    );

    if (path.isEmpty) return fallback;

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
      width: 58,
      height: 58,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Counter.paper.withValues(alpha: 0.2)),
      ),
      child: image,
    );
  }
}

class _CloseButton extends StatelessWidget {
  final bool compact;

  const _CloseButton({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            border: Border.all(
              color: _Counter.paper.withValues(alpha: 0.25),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.close_rounded,
            size: 18,
            color: _Counter.paper.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

/// ── Variant rail: paper ticket stubs ───────────────────────────────────────
class _VariantRail extends StatelessWidget {
  final _ProductVariantDialogState state;
  final bool horizontal;

  const _VariantRail({required this.state, this.horizontal = false});

  @override
  Widget build(BuildContext context) {
    final widget = state.widget;
    if (horizontal) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _railLabel('VARIANT'),
            const SizedBox(height: 10),
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: widget.variants.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final variant = widget.variants[index];
                  return SizedBox(
                    width: 190,
                    child: _VariantStub(
                      state: state,
                      variant: variant,
                      compact: true,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: _Counter.paperDeep.withValues(alpha: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _railLabel('VARIANT'),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              physics: const BouncingScrollPhysics(),
              itemCount: widget.variants.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final variant = widget.variants[index];
                return _VariantStub(state: state, variant: variant);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _railLabel(String text) {
    return Row(
      children: [
        Text(
          text,
          style: _Counter.mono(
            10,
            color: _Counter.paperFaded,
            weight: FontWeight.w700,
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(height: 1, color: _Counter.paperRule),
        ),
      ],
    );
  }
}

/// A single variant rendered as a ticket stub with a perforated left edge.
class _VariantStub extends StatelessWidget {
  final _ProductVariantDialogState state;
  final Map<String, dynamic> variant;
  final bool compact;

  const _VariantStub({
    required this.state,
    required this.variant,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final widget = state.widget;
    final product = widget.product;
    final colors = state._colorsFor(variant);
    final enabled = _variantIsAvailable(product, variant, colors);
    final price = _priceFor(product, variant);
    final stockLabel = colors.isEmpty
        ? _stockLabel(product, variant)
        : _variantColorSummary(product, colors);

    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: state._selectedVariant,
      builder: (context, selectedVariant, _) {
        final selected =
            selectedVariant['id']?.toString() == variant['id']?.toString();
        return _StubBody(
          variant: variant,
          selected: selected,
          enabled: enabled,
          price: price,
          stockLabel: stockLabel,
          compact: compact,
          swatch: _variantPreviewSwatch(colors),
          onTap: () => state._selectVariant(variant),
        );
      },
    );
  }
}

class _StubBody extends StatefulWidget {
  final Map<String, dynamic> variant;
  final bool selected;
  final bool enabled;
  final double price;
  final String stockLabel;
  final bool compact;
  final Color? swatch;
  final VoidCallback onTap;

  const _StubBody({
    required this.variant,
    required this.selected,
    required this.enabled,
    required this.price,
    required this.stockLabel,
    required this.compact,
    required this.swatch,
    required this.onTap,
  });

  @override
  State<_StubBody> createState() => _StubBodyState();
}

class _StubBodyState extends State<_StubBody> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final enabled = widget.enabled;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(
              selected ? 0 : (_hovered ? 2 : 0),
              0,
              0,
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: selected ? _Counter.ink : _Counter.paper,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? _Counter.ink
                    : _Counter.paperRule,
                width: selected ? 1.5 : 1,
              ),
              boxShadow: enabled && (_hovered || selected)
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: selected ? 0.24 : 0.12,
                        ),
                        blurRadius: selected ? 18 : 12,
                        offset: const Offset(0, 7),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                // Perforation notch column
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    3,
                    (_) => Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? _Counter.paper.withValues(alpha: 0.35)
                            : _Counter.paperRule,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 3,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected ? _Counter.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                if (widget.swatch != null) ...[
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: widget.swatch,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? _Counter.paper.withValues(alpha: 0.5)
                            : Colors.white,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _displayName(widget.variant['name'], fallback: 'Variant'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _Counter.display(
                          widget.compact ? 14 : 15,
                          color: selected ? _Counter.paper : _Counter.paperInk,
                          weight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            _formatCurrency(widget.price),
                            style: _Counter.mono(
                              11.5,
                              color: selected
                                  ? _Counter.accent
                                  : _Counter.paperInk,
                              weight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.stockLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _Counter.mono(
                                9.5,
                                color: selected
                                    ? _Counter.paper.withValues(alpha: 0.55)
                                    : _Counter.paperFaded,
                                weight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: selected
                      ? Container(
                          key: const ValueKey('on'),
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: _Counter.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Color(0xFF171006),
                          ),
                        )
                      : Icon(
                          key: const ValueKey('off'),
                          enabled ? Icons.add_rounded : Icons.block_rounded,
                          size: 18,
                          color: enabled
                              ? _Counter.paperFaded
                              : const Color(0xFFB63C3C),
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

/// ── Color wall: tactile swatches ───────────────────────────────────────────
class _ColorWall extends StatelessWidget {
  final _ProductVariantDialogState state;
  final bool inScroll;

  const _ColorWall({required this.state, this.inScroll = false});

  @override
  Widget build(BuildContext context) {
    final widget = state.widget;
    final product = widget.product;
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: state._selectedVariant,
      builder: (context, variant, _) {
        final colors = state._colorsFor(variant);
        final available = colors
            .where((color) => _colorIsAvailable(product, color))
            .length;

        final body = colors.isEmpty
            ? _NoColors(variant: variant)
            : ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: state._selectedColor,
                builder: (context, selectedColor, _) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 760
                          ? 5
                          : constraints.maxWidth >= 560
                          ? 4
                          : 3;
                      return GridView.builder(
                        shrinkWrap: inScroll,
                        physics: inScroll
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 14,
                              mainAxisSpacing: 18,
                              childAspectRatio: 0.86,
                            ),
                        itemCount: colors.length,
                        itemBuilder: (context, index) {
                          final color = colors[index];
                          return _Swatch(
                            colorOption: color,
                            selected: selectedColor?['id']?.toString() ==
                                color['id']?.toString(),
                            enabled: _colorIsAvailable(product, color),
                            stockLabel: _stockLabel(product, color),
                            onTap: () {
                              state._selectedColor.value = color;
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: Container(
            key: ValueKey(variant['id']?.toString() ?? 'variant'),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'COLOUR',
                      style: _Counter.mono(
                        10,
                        color: _Counter.paperFaded,
                        weight: FontWeight.w700,
                        letterSpacing: 2.2,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(height: 1, color: _Counter.paperRule),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      colors.isEmpty ? '—' : '$available/${colors.length} IN STOCK',
                      style: _Counter.mono(
                        9.5,
                        color: _Counter.paperFaded,
                        weight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (inScroll) body else Expanded(child: body),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NoColors extends StatelessWidget {
  final Map<String, dynamic> variant;

  const _NoColors({required this.variant});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: _Counter.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.flash_on_rounded,
                color: _Counter.accentDeep,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Single option',
              style: _Counter.display(17, color: _Counter.paperInk),
            ),
            const SizedBox(height: 4),
            Text(
              '${_displayName(variant['name'], fallback: 'This variant')} has no colour choices — add it directly.',
              textAlign: TextAlign.center,
              style: _Counter.body(12, color: _Counter.paperFaded),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single colour swatch on the wall.
class _Swatch extends StatefulWidget {
  final Map<String, dynamic> colorOption;
  final bool selected;
  final bool enabled;
  final String stockLabel;
  final VoidCallback onTap;

  const _Swatch({
    required this.colorOption,
    required this.selected,
    required this.enabled,
    required this.stockLabel,
    required this.onTap,
  });

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final swatch = colorOptionSwatch(widget.colorOption);
    final label = _displayName(widget.colorOption['name'], fallback: 'Colour');
    final isLight =
        ThemeData.estimateBrightnessForColor(swatch) == Brightness.light;
    final selected = widget.selected;
    final enabled = widget.enabled;

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: enabled ? widget.onTap : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                transform: Matrix4.diagonal3Values(
                  selected ? 1.06 : (_hovered ? 1.03 : 1.0),
                  selected ? 1.06 : (_hovered ? 1.03 : 1.0),
                  1.0,
                ),
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isLight ? _Counter.paperRule : Colors.white,
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: swatch.withValues(alpha: isLight ? 0.2 : 0.35),
                      blurRadius: selected ? 20 : 12,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: swatch,
                    border: selected
                        ? Border.all(color: _Counter.accent, width: 3)
                        : null,
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          color: isLight ? _Counter.paperInk : Colors.white,
                          size: 26,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _Counter.display(
                  12.5,
                  color: selected ? _Counter.accentDeep : _Counter.paperInk,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.stockLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _Counter.mono(
                  9.5,
                  color: _Counter.paperFaded,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ── Add-to-cart receipt bar ────────────────────────────────────────────────
class _AddBar extends StatelessWidget {
  final _ProductVariantDialogState state;

  const _AddBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final widget = state.widget;
    final product = widget.product;
    return Container(
      decoration: BoxDecoration(
        color: _Counter.inkDeep,
        border: Border(
          top: BorderSide(color: _Counter.paper.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          child: ValueListenableBuilder<Map<String, dynamic>>(
            valueListenable: state._selectedVariant,
            builder: (context, variant, _) {
              final colors = state._colorsFor(variant);
              return ValueListenableBuilder<Map<String, dynamic>?>(
                valueListenable: state._selectedColor,
                builder: (context, selectedColor, _) {
                  final canAdd = colors.isEmpty
                      ? _variantIsAvailable(product, variant, colors)
                      : selectedColor != null &&
                            _colorIsAvailable(product, selectedColor);
                  final price = _priceFor(product, variant);
                  final line =
                      '1 × ${_selectionLabel(variant, selectedColor)}';

                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              line,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _Counter.mono(
                                11.5,
                                color: _Counter.paper.withValues(alpha: 0.85),
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  _formatCurrency(price),
                                  style: _Counter.mono(
                                    16,
                                    color: _Counter.accent,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'INCL. STOCK',
                                  style: _Counter.mono(
                                    8.5,
                                    color: _Counter.paper.withValues(
                                      alpha: 0.4,
                                    ),
                                    weight: FontWeight.w600,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      _AddButton(
                        enabled: canAdd,
                        onTap: () => state._addToCart(context),
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

class _AddButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;

  const _AddButton({required this.enabled, required this.onTap});

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.diagonal3Values(
          enabled && _hovered ? 1.03 : 1.0,
          enabled && _hovered ? 1.03 : 1.0,
          1.0,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: _Counter.accent.withValues(
                      alpha: _hovered ? 0.5 : 0.35,
                    ),
                    blurRadius: _hovered ? 24 : 16,
                    offset: const Offset(0, 7),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: enabled ? _Counter.accent : _Counter.paper.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            onTap: enabled ? widget.onTap : null,
            borderRadius: BorderRadius.circular(13),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_shopping_cart_rounded,
                    size: 18,
                    color: enabled
                        ? const Color(0xFF171006)
                        : _Counter.paper.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'ADD TO CART',
                    style: _Counter.mono(
                      12.5,
                      color: enabled
                          ? const Color(0xFF171006)
                          : _Counter.paper.withValues(alpha: 0.4),
                      weight: FontWeight.w700,
                      letterSpacing: 1.6,
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

/// ── Logic helpers (unchanged behaviour) ────────────────────────────────────
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
