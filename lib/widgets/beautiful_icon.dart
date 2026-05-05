import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class BeautifulIcon extends StatelessWidget {
  final IconData? icon;
  final double? size;
  final Color? color;
  final bool withBackground;

  const BeautifulIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.withBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    if (icon == null) return const SizedBox.shrink();
    
    final iconWidget = ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          color ?? AppColors.secondary,
          (color ?? AppColors.primary).withValues(alpha: 0.7),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Icon(
        icon,
        size: size ?? 24.0,
        color: Colors.white,
      ),
    );

    if (withBackground) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (color ?? AppColors.primary).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: (color ?? AppColors.primary).withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: iconWidget,
      );
    }
    
    return iconWidget;
  }
}
