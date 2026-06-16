import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFF7F8FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceHighlight = Color(0xFFF1F3F6);
  static const Color premiumPanel = Color(0xFFFFFFFF);
  static const Color premiumPanelSoft = Color(0xFFFAFAFC);
  static const Color premiumStroke = Color(0xFFE5E7EC);

  static const Color primary = Color(0xFFD72668);
  static const Color primaryLight = Color(0xFFFF5A8A);
  static const Color fuchsia = Color(0xFF8B4FD6);
  static const Color secondary = Color(0xFF566174);

  static const Color textPrimary = Color(0xFF20242D);
  static const Color textSecondary = Color(0xFF6E7582);

  static const Color error = Color(0xFFB85450);
  static const Color success = Color(0xFF447A61);
  static const Color warning = Color(0xFFA66A24);

  static const Color border = Color(0xFFE5E7EC);

  // ── Dark mode POS palette (premium glassmorphism) ───────────────────────
  static const Color darkBackground = Color(0xFF0B1220);
  static const Color darkSurface = Color(0xFF161B22);
  static const Color darkSurfaceHighlight = Color(0xFF1F2937);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);
  static const Color darkAccent = Color(0xFFEC4899);
  static const Color darkAccentSoft = Color(0xFFF472B6);

  static LinearGradient get premiumGradient => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [premiumPanel, premiumPanelSoft],
  );

  static LinearGradient get brandGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
  );

  static List<BoxShadow> premiumShadow([double alpha = 0.08]) => [
    BoxShadow(
      color: const Color(0xFF20242D).withValues(alpha: alpha),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}
