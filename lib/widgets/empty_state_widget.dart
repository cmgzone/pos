import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'beautiful_icon.dart';

class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onAction;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onSecondaryAction;
  final String? secondaryActionLabel;
  final bool compact;
  final bool positiveTone;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onAction,
    this.actionLabel,
    this.actionIcon,
    this.onSecondaryAction,
    this.secondaryActionLabel,
    this.compact = false,
    this.positiveTone = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = positiveTone
        ? AppColors.success.withValues(alpha: 0.55)
        : scheme.onSurfaceVariant.withValues(alpha: 0.35);
    final pad = compact ? AppSpacing.xxl : 40.0;
    final iconPad = compact ? AppSpacing.xl : AppSpacing.xxl;
    final iconSize = compact ? 36.0 : 48.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final effectivePad = compact && constraints.maxHeight < 360
            ? AppSpacing.md
            : pad;
        final minContentHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight - (effectivePad * 2)).clamp(
                0.0,
                double.infinity,
              )
            : 0.0;

        return SingleChildScrollView(
          padding: EdgeInsets.all(effectivePad),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                minHeight: minContentHeight,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(iconPad),
                    decoration: BoxDecoration(
                      color: positiveTone
                          ? AppColors.success.withValues(alpha: 0.10)
                          : scheme.surfaceContainerHighest.withValues(
                              alpha: 0.55,
                            ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: positiveTone
                            ? AppColors.success.withValues(alpha: 0.22)
                            : scheme.outline.withValues(alpha: 0.35),
                      ),
                    ),
                    child: BeautifulIcon(
                      icon,
                      size: iconSize,
                      color: iconColor,
                    ),
                  ),
                  SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xxl),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: compact ? 16 : 18,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                      letterSpacing: -0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (onAction != null && actionLabel != null) ...[
                    SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xxl),
                    FilledButton.icon(
                      onPressed: onAction,
                      icon: Icon(actionIcon ?? Icons.add_rounded, size: 18),
                      label: Text(actionLabel!),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? AppSpacing.xl : AppSpacing.xxl,
                          vertical: compact ? AppSpacing.sm : AppSpacing.md,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                    ),
                  ],
                  if (onSecondaryAction != null &&
                      secondaryActionLabel != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    TextButton(
                      onPressed: onSecondaryAction,
                      child: Text(
                        secondaryActionLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
