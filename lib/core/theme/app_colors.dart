import 'package:flutter/material.dart';

/// Piki's palette is sampled from the active app mark: deep navy foundations,
/// orange-led actions and highlights, and teal confirmation states.
class AppColors {
  static const Color background = Color(0xFFF6F4F0);
  static const Color surface = Color(0xFFFFFEFC);
  static const Color surfaceHighlight = Color(0xFFEFECE6);
  static const Color premiumPanel = Color(0xFFFFFEFC);
  static const Color premiumPanelSoft = Color(0xFFFAF8F4);
  static const Color premiumStroke = Color(0xFFE2DED6);

  /// The accessible orange action shade. The brighter [brandOrange] is used
  /// where it does not carry white text.
  static const Color primary = Color(0xFFC45A00);
  static const Color primaryLight = Color(0xFFF18424);
  static const Color brandOrange = Color(0xFFFF7A1A);
  static const Color apricot = Color(0xFFFFB45C);
  static const Color orangeDeep = Color(0xFF9A4600);
  static const Color secondary = Color(0xFF087D73);
  static const Color signal = Color(0xFF18A999);

  static const Color ink = Color(0xFF0B1020);
  static const Color textPrimary = Color(0xFF171A22);
  static const Color textSecondary = Color(0xFF6B6F78);

  static const Color error = Color(0xFFB63C3C);
  static const Color success = Color(0xFF27745A);
  static const Color warning = Color(0xFF9A641F);
  static const Color border = Color(0xFFE2DED6);

  static const Color darkBackground = Color(0xFF090E19);
  static const Color darkSurface = Color(0xFF111827);
  static const Color darkSurfaceHighlight = Color(0xFF1A2333);
  static const Color darkBorder = Color(0xFF2A3446);
  static const Color darkTextPrimary = Color(0xFFF8F5EF);
  static const Color darkTextSecondary = Color(0xFFA9B2C1);
  static const Color darkTextMuted = Color(0xFF768196);
  static const Color darkAccent = Color(0xFFFF9D3D);
  static const Color darkAccentSoft = Color(0xFFFFC27A);

  static LinearGradient get premiumGradient => const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [premiumPanel, premiumPanelSoft],
  );

  static LinearGradient get brandGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandOrange, apricot],
  );

  static List<BoxShadow> premiumShadow([double alpha = 0.08]) => [
    BoxShadow(
      color: ink.withValues(alpha: alpha),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static const Color metricMonth = primary;
  static const Color metricTop = Color(0xFFB76134);
  static const Color metricOrders = secondary;
  static const Color metricStaff = Color(0xFF59657A);
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
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
}
