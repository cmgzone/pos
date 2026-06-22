import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  /// Two-stop: a tight lift near the card plus a soft spread further out,
  /// so panels read as mounted rather than floating.
  List<BoxShadow> get appPanelShadow => isDarkMode
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0A20242D),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
          BoxShadow(
            color: Color(0x0B20242D),
            blurRadius: 20,
            offset: Offset(0, 8),
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

  // ── Radius tokens (BuildContext surface) ─────────────────────────────────
  double get appRadiusXs => AppRadius.xs;
  double get appRadiusSm => AppRadius.sm;
  double get appRadiusMd => AppRadius.md;
  double get appRadiusLg => AppRadius.lg;
  double get appRadiusXl => AppRadius.xl;

  // ── Spacing tokens (BuildContext surface) ────────────────────────────────
  double get appSpacingXs => AppSpacing.xs;
  double get appSpacingSm => AppSpacing.sm;
  double get appSpacingMd => AppSpacing.md;
  double get appSpacingLg => AppSpacing.lg;
  double get appSpacingXl => AppSpacing.xl;
  double get appSpacingXxl => AppSpacing.xxl;
  double get appSpacingSection => AppSpacing.section;

  // ── Section header style (uppercase, tracked, small) ─────────────────────
  // Replaces the AI-default titleMedium blob with a real section label.
  TextStyle get appSectionHeaderStyle => TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.08,
        color: appTextSecondary,
        fontFamily: GoogleFonts.inter().fontFamily,
      );

  // ── Flat brand badge color (no gradient) ─────────────────────────────────
  // Used in AppBar logo badges instead of LinearGradient(primary, primaryLight).
  Color get brandBadgeColor => appPrimary;

  // ── Named metric colors for dashboard KPIs ───────────────────────────────
  // Centralizes the magic hex that used to live in dashboard_screen.dart so
  // tiles can ask for a color by semantic key instead of hardcoding it.
  Color metricColor(String key) {
    return switch (key) {
      'sales' => appPrimary,
      'month' => AppColors.metricMonth,
      'profit' => AppColors.success,
      'top' => AppColors.metricTop,
      'stock' => AppColors.warning,
      'orders' => AppColors.metricOrders,
      'staff' => AppColors.metricStaff,
      _ => appPrimary,
    };
  }
}
