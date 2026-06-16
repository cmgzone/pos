import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Theme-aware semantic colors. Prefer these over static [AppColors] for
/// surfaces, text, and borders so light and dark mode stay consistent.
extension AppThemeColors on BuildContext {
  ThemeData get appTheme => Theme.of(this);

  ColorScheme get colors => appTheme.colorScheme;

  bool get isDarkMode => appTheme.brightness == Brightness.dark;

  Color get appBackground => appTheme.scaffoldBackgroundColor;

  Color get appSurface => colors.surface;

  Color get appSurfaceHighlight => colors.surfaceContainerHighest;

  Color get appTextPrimary => colors.onSurface;

  Color get appTextSecondary => colors.onSurfaceVariant;

  Color get appBorder => colors.outline;

  Color get appPrimary => colors.primary;

  Color get appOnPrimary => colors.onPrimary;

  Color get appPrimaryContainer => colors.primaryContainer;

  Color get appOnPrimaryContainer => colors.onPrimaryContainer;

  /// Subtle card/panel shadow — omitted in dark mode.
  List<BoxShadow> get appPanelShadow => isDarkMode
      ? const []
      : [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ];

  /// Soft tinted panel background (e.g. warning cards).
  Color warningPanelBackground([double alpha = 1]) {
    final base = isDarkMode
        ? const Color(0xFF2A2318)
        : const Color(0xFFFFFAF0);
    return alpha == 1 ? base : base.withValues(alpha: alpha);
  }

  // ── POS dark mode premium palette helpers ───────────────────────────────
  Color get posCardBackground =>
      isDarkMode ? AppColors.darkSurface : appSurface;

  Color get posImageBackground =>
      isDarkMode ? AppColors.darkSurfaceHighlight : appSurfaceHighlight;

  Color get posCardBorder =>
      isDarkMode ? AppColors.darkBorder : appBorder;

  Color get posTextPrimary =>
      isDarkMode ? AppColors.darkTextPrimary : appTextPrimary;

  Color get posTextSecondary =>
      isDarkMode ? AppColors.darkTextSecondary : appTextSecondary;

  Color get posTextMuted =>
      isDarkMode ? AppColors.darkTextMuted : appTextSecondary;

  Color get posAccent => isDarkMode ? AppColors.darkAccent : appPrimary;

  Color get posAccentSoft =>
      isDarkMode ? AppColors.darkAccentSoft : appPrimary;

  Color get posPrice => isDarkMode ? AppColors.darkAccentSoft : appPrimary;

  Color get posBackground =>
      isDarkMode ? AppColors.darkBackground : appBackground;
}
