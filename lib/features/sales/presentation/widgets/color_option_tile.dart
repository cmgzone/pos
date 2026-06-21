import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/services/product_image_upload_service.dart';
import '../../../../core/theme/app_colors.dart';

Color colorOptionSwatch(Map<String, dynamic> option) {
  final hex = option['hex_color']?.toString().trim();
  final fromHex = _colorFromHex(hex);
  if (fromHex != null) {
    return fromHex;
  }
  return _colorFromName(option['name']?.toString() ?? '');
}

Color? _colorFromHex(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final normalized = value.startsWith('#') ? value.substring(1) : value;
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(normalized)) {
    return null;
  }
  return Color(int.parse('FF$normalized', radix: 16));
}

Color _colorFromName(String value) {
  final name = value.trim().toLowerCase();
  if (name.contains('black')) return const Color(0xFF111827);
  if (name.contains('white')) return const Color(0xFFFFFFFF);
  if (name.contains('silver')) return const Color(0xFFC0C7D2);
  if (name.contains('gold')) return const Color(0xFFD4AF37);
  if (name.contains('blue')) return const Color(0xFF2563EB);
  if (name.contains('red')) return const Color(0xFFDC2626);
  if (name.contains('green')) return const Color(0xFF16A34A);
  if (name.contains('yellow')) return const Color(0xFFEAB308);
  if (name.contains('orange')) return const Color(0xFFF97316);
  if (name.contains('purple')) return const Color(0xFF7C3AED);
  if (name.contains('pink')) return const Color(0xFFEC4899);
  if (name.contains('brown')) return const Color(0xFF92400E);
  if (name.contains('grey') || name.contains('gray')) {
    return const Color(0xFF6B7280);
  }
  return AppColors.secondary;
}

class ColorOptionTile extends StatelessWidget {
  final Map<String, dynamic> option;
  final bool selected;
  final bool enabled;
  final String stockLabel;
  final VoidCallback onTap;

  const ColorOptionTile({
    super.key,
    required this.option,
    required this.selected,
    required this.enabled,
    required this.stockLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final swatch = colorOptionSwatch(option);
    final name = option['name']?.toString().trim();
    final label = name == null || name.isEmpty ? 'Color' : name;
    final borderColor = selected
        ? AppColors.primaryLight
        : theme.colorScheme.outline.withValues(alpha: 0.55);
    final background = enabled
        ? Colors.white
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);

    return Opacity(
      opacity: enabled ? 1 : 0.48,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.primaryLight.withValues(alpha: 0.12),
          highlightColor: AppColors.primaryLight.withValues(alpha: 0.06),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor, width: selected ? 2 : 1),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: const Color(0xFF20242D).withValues(alpha: 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              children: [
                _ColorPreview(
                  color: swatch,
                  imagePath: option['image_url'] as String?,
                  enabled: enabled,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: enabled
                              ? AppColors.textPrimary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stockLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: enabled
                              ? AppColors.textSecondary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: !enabled
                      ? const Icon(
                          Icons.block_rounded,
                          key: ValueKey('blocked'),
                          color: AppColors.error,
                        )
                      : selected
                      ? const Icon(
                          Icons.check_circle_rounded,
                          key: ValueKey('selected'),
                          color: AppColors.primaryLight,
                        )
                      : Icon(
                          Icons.chevron_right_rounded,
                          key: const ValueKey('next'),
                          color: theme.colorScheme.onSurfaceVariant,
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

class _ColorPreview extends StatelessWidget {
  final Color color;
  final String? imagePath;
  final bool enabled;

  const _ColorPreview({
    required this.color,
    required this.imagePath,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final isLight =
        ThemeData.estimateBrightnessForColor(color) == Brightness.light;
    final path = imagePath?.trim() ?? '';
    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: Border.all(
        color: isLight ? const Color(0xFFD1D5DB) : Colors.white,
        width: 2,
      ),
      boxShadow: enabled
          ? [
              BoxShadow(
                color: color.withValues(alpha: isLight ? 0.14 : 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ]
          : const [],
    );
    if (path.isEmpty) {
      return Container(width: 52, height: 52, decoration: decoration);
    }

    final image = ProductImageUploadService.isRemoteImage(path)
        ? Image.network(
            path,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        : Image.file(
            File(path),
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );

    return Container(
      width: 52,
      height: 52,
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}
