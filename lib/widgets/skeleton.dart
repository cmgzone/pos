import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Lightweight pulse placeholder for loading states.
/// Prefer this over a bare [CircularProgressIndicator] so layout stays stable.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = AppRadius.sm,
    this.margin,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.38, end: 0.82).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? AppColors.darkSurfaceHighlight
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.width,
        height: widget.height,
        margin: widget.margin,
        decoration: BoxDecoration(
          color: base.withValues(alpha: isDark ? 0.85 : 0.75),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}

/// Vertical list of skeleton rows matching common product/stock cards.
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsetsGeometry padding;
  final double spacing;

  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.itemHeight = 100,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.spacing = AppSpacing.md,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      itemCount: itemCount,
      separatorBuilder: (_, _) => SizedBox(height: spacing),
      itemBuilder: (_, _) => SkeletonBox(
        height: itemHeight,
        borderRadius: AppRadius.lg,
        width: double.infinity,
      ),
    );
  }
}

/// Grid of skeleton product cards for POS loading.
class SkeletonProductGrid extends StatelessWidget {
  final int crossAxisCount;
  final int itemCount;
  final double mainAxisExtent;
  final EdgeInsetsGeometry padding;

  const SkeletonProductGrid({
    super.key,
    required this.crossAxisCount,
    this.itemCount = 8,
    this.mainAxisExtent = 144,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisExtent: mainAxisExtent,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: itemCount,
      itemBuilder: (_, _) => const SkeletonBox(
        height: double.infinity,
        borderRadius: AppRadius.md,
        width: double.infinity,
      ),
    );
  }
}

/// Dashboard KPI tile placeholders.
class SkeletonKpiGrid extends StatelessWidget {
  final int itemCount;

  const SkeletonKpiGrid({super.key, this.itemCount = 7});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(width: 160, height: 14, borderRadius: AppRadius.xs),
        const SizedBox(height: AppSpacing.sm),
        const SkeletonBox(width: 220, height: 12, borderRadius: AppRadius.xs),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 820
                ? 4
                : constraints.maxWidth >= 560
                    ? 3
                    : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                mainAxisExtent: 132,
              ),
              itemCount: itemCount,
              itemBuilder: (_, _) => const SkeletonBox(
                height: double.infinity,
                borderRadius: AppRadius.lg,
                width: double.infinity,
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Compact status banner for offline / sync issues on work screens.
class StatusBanner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StatusBanner({
    super.key,
    required this.icon,
    required this.message,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  factory StatusBanner.offline({VoidCallback? onRetry}) {
    return StatusBanner(
      icon: Icons.cloud_off_outlined,
      message: 'Selling offline — sales will sync when you are back online.',
      color: AppColors.warning,
      actionLabel: onRetry != null ? 'Retry' : null,
      onAction: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: color.withValues(alpha: isDark ? 0.16 : 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
            if (onAction != null && actionLabel != null)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: color,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
