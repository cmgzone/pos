import 'package:flutter/material.dart';

class AppColors {
  // Velvet Night Premium Dark Theme
  static const Color background = Color(0xFF09090E); // Deep space Night
  static const Color surface = Color(0xFF14141E); // Elevated dark surface
  static const Color surfaceHighlight = Color(0xFF1F1F2E);
  static const Color premiumPanel = Color(0xFF0F101A);
  static const Color premiumPanelSoft = Color(0xFF191426);
  static const Color premiumStroke = Color(0xFF302A3E);

  static const Color primary = Color(0xFFFF2A5F); // Vibrant Neon Pink
  static const Color primaryLight = Color(0xFFFF7E67); // Coral Orange
  static const Color fuchsia = Color(0xFFC72DFF);
  static const Color secondary = Color(0xFF00FFC2); // Cyber Mint

  static const Color textPrimary = Color(0xFFF9F9FB);
  static const Color textSecondary = Color(0xFFA0A0B0);

  static const Color error = Color(0xFFFF3B30);
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9F0A);

  static const Color border = Color(0xFF282838);

  static LinearGradient get premiumGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [premiumPanel, premiumPanelSoft, surface],
  );

  static LinearGradient get brandGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, fuchsia],
  );

  static List<BoxShadow> premiumShadow([double alpha = 0.32]) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: alpha),
      blurRadius: 28,
      offset: const Offset(0, 16),
    ),
    BoxShadow(
      color: primary.withValues(alpha: 0.08),
      blurRadius: 42,
      offset: const Offset(0, 18),
    ),
  ];
}
