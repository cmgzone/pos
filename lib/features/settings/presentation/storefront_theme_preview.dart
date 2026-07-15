import 'package:flutter/material.dart';

import '../../../core/services/storefront_theme_service.dart';

class StorefrontThemePreview extends StatelessWidget {
  final StorefrontTheme theme;
  final bool isUpdating;

  const StorefrontThemePreview({
    super.key,
    required this.theme,
    this.isUpdating = false,
  });

  @override
  Widget build(BuildContext context) {
    final design = theme.design;
    final background = _color(design.backgroundColor, const Color(0xff100f0d));
    final foreground = _color(design.textColor, Colors.white);
    final muted = _color(design.mutedColor, foreground.withValues(alpha: 0.7));
    final surface = _color(design.surfaceColor, const Color(0xff181614));
    final elevated = _color(design.surfaceElevatedColor, surface);
    final border = _color(
      design.borderColor,
      foreground.withValues(alpha: 0.2),
    );
    final accent = _color(
      design.accentColor,
      Theme.of(context).colorScheme.primary,
    );
    final radius = switch (design.cornerStyle) {
      'sharp' => 2.0,
      'soft' => 10.0,
      'pill' => 28.0,
      _ => 18.0,
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Row(
              children: [
                const Icon(Icons.preview_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live theme preview',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Updates as soon as Piki saves the draft.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(theme.isPublished ? 'Published' : 'Draft'),
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: Container(
              key: ValueKey(
                '${theme.id}-${theme.updatedAt?.millisecondsSinceEpoch}-${design.toJson()}',
              ),
              color: background,
              padding: const EdgeInsets.all(18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 620;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(radius),
                            ),
                            child: Icon(
                              Icons.storefront_rounded,
                              size: 17,
                              color: _readableOn(accent),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              theme.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: foreground,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Icon(Icons.search_rounded, size: 18, color: muted),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: 18,
                            color: muted,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: EdgeInsets.all(compact ? 16 : 22),
                        decoration: BoxDecoration(
                          color: elevated,
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(color: border),
                        ),
                        child: Flex(
                          direction: compact ? Axis.vertical : Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: compact
                                  ? double.infinity
                                  : constraints.maxWidth * 0.52,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _eyebrow(theme.storefrontType),
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _headline(theme.storefrontType),
                                    style: TextStyle(
                                      color: foreground,
                                      fontSize: compact ? 22 : 27,
                                      height: 1.05,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'A preview of the colours, cards, spacing, imagery, and checkout action.',
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent,
                                      borderRadius: BorderRadius.circular(
                                        design.cornerStyle == 'pill'
                                            ? 999
                                            : radius,
                                      ),
                                    ),
                                    child: Text(
                                      theme.checkout.checkoutButtonLabel,
                                      style: TextStyle(
                                        color: _readableOn(accent),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!compact) const SizedBox(width: 20),
                            if (compact) const SizedBox(height: 18),
                            SizedBox(
                              width: compact
                                  ? double.infinity
                                  : constraints.maxWidth * 0.28,
                              child: AspectRatio(
                                aspectRatio: _imageAspect(design.imageRatio),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: surface,
                                    borderRadius: BorderRadius.circular(radius),
                                    border: Border.all(color: border),
                                  ),
                                  child: Icon(
                                    _heroIcon(theme.storefrontType),
                                    color: accent,
                                    size: 42,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: List.generate(3, (index) {
                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: index == 0 ? 0 : 8,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(radius),
                                  border: Border.all(color: border),
                                  boxShadow: design.cardStyle == 'elevated'
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.16,
                                            ),
                                            blurRadius: 12,
                                            offset: const Offset(0, 5),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AspectRatio(
                                      aspectRatio: _imageAspect(
                                        design.imageRatio,
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: elevated,
                                          borderRadius: BorderRadius.circular(
                                            radius * 0.7,
                                          ),
                                        ),
                                        child: Icon(
                                          _itemIcon(
                                            theme.storefrontType,
                                            index,
                                          ),
                                          size: 25,
                                          color: accent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      height: 7,
                                      width: 58 + (index * 9),
                                      decoration: BoxDecoration(
                                        color: foreground.withValues(
                                          alpha: 0.86,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      height: 6,
                                      width: 38,
                                      decoration: BoxDecoration(
                                        color: accent,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                      if (isUpdating) ...[
                        const SizedBox(height: 14),
                        LinearProgressIndicator(
                          color: accent,
                          backgroundColor: surface,
                          minHeight: 3,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          'Piki is preparing a new draft…',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
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

  static Color _color(String value, Color fallback) {
    final hex = value.replaceFirst('#', '');
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null || hex.length != 6
        ? fallback
        : Color(0xff000000 | parsed);
  }

  static Color _readableOn(Color color) {
    return color.computeLuminance() > 0.52 ? Colors.black : Colors.white;
  }

  static double _imageAspect(String ratio) => switch (ratio) {
    'square' => 1,
    'landscape' => 1.45,
    _ => 0.82,
  };

  static String _eyebrow(String type) => switch (type) {
    'restaurant' => 'TODAY’S MENU',
    'services' => 'BOOK WITH US',
    _ => 'NEW COLLECTION',
  };

  static String _headline(String type) => switch (type) {
    'restaurant' => 'Fresh favourites, ready to order.',
    'services' => 'Good work, beautifully delivered.',
    _ => 'Find something worth taking home.',
  };

  static IconData _heroIcon(String type) => switch (type) {
    'restaurant' => Icons.restaurant_rounded,
    'services' => Icons.design_services_rounded,
    _ => Icons.shopping_bag_rounded,
  };

  static IconData _itemIcon(String type, int index) {
    if (type == 'restaurant') {
      return [Icons.lunch_dining, Icons.local_cafe, Icons.bakery_dining][index];
    }
    if (type == 'services') {
      return [Icons.content_cut, Icons.spa, Icons.auto_awesome][index];
    }
    return [Icons.checkroom, Icons.inventory_2, Icons.local_mall][index];
  }
}
