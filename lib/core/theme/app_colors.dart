import 'package:flutter/material.dart';

/// Piki's visual language is deliberately warm and tactile: paper-like
/// backgrounds, ink surfaces, coral for momentum, and teal for confirmation.
/// The palette avoids the purple/blue gradients common to generic SaaS apps.
class AppColors {
  static const Color background = Color(0xFFF6F4F0);
  static const Color surface = Color(0xFFFFFEFC);
  static const Color surfaceHighlight = Color(0xFFEFECE6);
  static const Color premiumPanel = Color(0xFFFFFEFC);
  static const Color premiumPanelSoft = Color(0xFFFAF8F4);
  static const Color premiumStroke = Color(0xFFE2DED6);

  /// Accessible action coral. [brandCoral] is reserved for larger decorative
  /// moments where white text contrast is not required.
  static const Color primary = Color(0xFFC74343);
  static const Color primaryLight = Color(0xFFF26A5E);
  static const Color brandCoral = Color(0xFFFF5C52);
  static const Color apricot = Color(0xFFFFB86B);
  static const Color fuchsia = Color(0xFF9B4F62);
  static const Color secondary = Color(0xFF087D73);
  static const Color signal = Color(0xFF18A999);

  static const Color ink = Color(0xFF0B1020);
  static const Color textPrimary = Color(0xFF171A22);
  static const Color textSecondary = Color(0xFF6B6F78);

  static const Color error = Color(0xFFB63C3C);
  static const Color success = Color(0xFF27745A);
  static const Color warning = Color(0xFF9A641F);
  static const Color border = Color(0xFFE2DED6);

  // Dark mode uses ink rather than pure black so long shifts remain calm.
  static const Color darkBackground = Color(0xFF090E19);
  static const Color darkSurface = Color(0xFF111827);
  static const Color darkSurfaceHighlight = Color(0xFF1A2333);
  static const Color darkBorder = Color(0xFF2A3446);
  static const Color darkTextPrimary = Color(0xFFF8F5EF);
  static const Color darkTextSecondary = Color(0xFFA9B2C1);
  static const Color darkTextMuted = Color(0xFF768196);
  static const Color darkAccent = Color(0xFFFF766E);
  static const Color darkAccentSoft = Color(0xFFFF9A8F);

  static LinearGradient get premiumGradient => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [premiumPanel, premiumPanelSoft],
  );

  static LinearGradient get brandGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandCoral, apricot],
  );

  static List<BoxShadow> premiumShadow([double alpha = 0.08]) => [
    BoxShadow(
      color: ink.withValues(alpha: alpha),
      blurRadius: 28,
      offset: const Offset(0, 12),
    ),
  ];

  static const Color metricMonth = Color(0xFF4C659A);
  static const Color metricTop = Color(0xFF8C5968);
  static const Color metricOrders = secondary;
  static const Color metricStaff = Color(0xFFB76134);
}

/// A compact 4pt-based spacing rhythm shared by phone and desktop layouts.
class AppSpacing {
  const AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double section = 32;
}

/// Small controls stay crisp while larger panels receive a softer silhouette.
class AppRadius {
  const AppRadius._();
  static const double xs = 7;
  static const double sm = 11;
  static const double md = 15;
  static const double lg = 20;
  static const double xl = 26;
}
