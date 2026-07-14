import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static RoundedRectangleBorder _rounded(double radius) {
    return RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
  }

  static WidgetStateProperty<T> _state<T>({
    required T normal,
    T? selected,
    T? disabled,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (disabled != null && states.contains(WidgetState.disabled)) {
        return disabled;
      }
      if (selected != null &&
          (states.contains(WidgetState.selected) ||
              states.contains(WidgetState.pressed))) {
        return selected;
      }
      return normal;
    });
  }

  static ThemeData get lightTheme {
    const scheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFBE6E2),
      onPrimaryContainer: Color(0xFF5B1E1C),
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFDDF1ED),
      onSecondaryContainer: Color(0xFF0B433D),
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceHighlight,
      onSurfaceVariant: AppColors.textSecondary,
      error: AppColors.error,
      outline: AppColors.border,
    );
    return _buildTheme(
      brightness: Brightness.light,
      scheme: scheme,
      background: AppColors.background,
      surface: AppColors.surface,
      elevatedSurface: AppColors.surfaceHighlight,
      border: AppColors.border,
      text: AppColors.textPrimary,
      muted: AppColors.textSecondary,
    );
  }

  static ThemeData get darkTheme {
    const scheme = ColorScheme.dark(
      primary: AppColors.darkAccent,
      onPrimary: Color(0xFF321110),
      primaryContainer: Color(0xFF4A211F),
      onPrimaryContainer: Color(0xFFFFD9D3),
      secondary: Color(0xFF62D8C9),
      onSecondary: Color(0xFF062E2A),
      secondaryContainer: Color(0xFF123D39),
      onSecondaryContainer: Color(0xFFC6F7F0),
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      surfaceContainerHighest: AppColors.darkSurfaceHighlight,
      onSurfaceVariant: AppColors.darkTextSecondary,
      error: Color(0xFFFFA39D),
      outline: AppColors.darkBorder,
    );
    return _buildTheme(
      brightness: Brightness.dark,
      scheme: scheme,
      background: AppColors.darkBackground,
      surface: AppColors.darkSurface,
      elevatedSurface: AppColors.darkSurfaceHighlight,
      border: AppColors.darkBorder,
      text: AppColors.darkTextPrimary,
      muted: AppColors.darkTextSecondary,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color background,
    required Color surface,
    required Color elevatedSurface,
    required Color border,
    required Color text,
    required Color muted,
  }) {
    final textTheme = GoogleFonts.hankenGroteskTextTheme(
      brightness == Brightness.light
          ? ThemeData.light(useMaterial3: true).textTheme
          : ThemeData.dark(useMaterial3: true).textTheme,
    ).apply(bodyColor: text, displayColor: text);

    // Tabular figures on money-bearing display styles so KPI values stop
    // jittering when totals change. Kept off body text for readability.
    const tabularFigures = <FontFeature>[FontFeature.tabularFigures()];

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      primaryColor: scheme.primary,
      iconTheme: IconThemeData(color: muted, size: 23),
      visualDensity: VisualDensity.standard,
      textTheme: textTheme.copyWith(
        displayLarge: textTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
          fontFeatures: tabularFigures,
        ),
        displayMedium: textTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1,
          fontFeatures: tabularFigures,
        ),
        displaySmall: textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.7,
          fontFeatures: tabularFigures,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.65,
          fontFeatures: tabularFigures,
        ),
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.45,
          fontFeatures: tabularFigures,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.45),
        bodyMedium: textTheme.bodyMedium?.copyWith(color: muted, height: 1.45),
        bodySmall: textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        labelSmall: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.08,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: text),
        actionsIconTheme: IconThemeData(color: muted),
        titleTextStyle: GoogleFonts.hankenGrotesk(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: const Color(0x140B1020),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: border.withValues(alpha: 0.86)),
        ),
        margin: EdgeInsets.zero,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: _rounded(AppRadius.xl),
        titleTextStyle: GoogleFonts.hankenGrotesk(
          color: text,
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: GoogleFonts.hankenGrotesk(color: muted, height: 1.45),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.18),
        selectionHandleColor: scheme.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light ? surface : elevatedSurface,
        hoverColor: elevatedSurface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: _inputBorder(border),
        enabledBorder: _inputBorder(border),
        focusedBorder: _inputBorder(scheme.primary, width: 1.4),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.4),
        disabledBorder: _inputBorder(border.withValues(alpha: 0.55)),
        labelStyle: GoogleFonts.hankenGrotesk(
          color: muted,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: GoogleFonts.hankenGrotesk(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: GoogleFonts.hankenGrotesk(color: muted, fontWeight: FontWeight.w400),
        helperStyle: GoogleFonts.hankenGrotesk(color: muted, fontSize: 12),
        errorStyle: GoogleFonts.hankenGrotesk(
          color: scheme.error,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        prefixIconColor: muted,
        suffixIconColor: muted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: _rounded(AppRadius.md),
          textStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: elevatedSurface,
          disabledForegroundColor: muted,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: _rounded(AppRadius.md),
          textStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: _rounded(AppRadius.md),
          textStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          shape: _rounded(AppRadius.xs),
          textStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: muted,
          hoverColor: elevatedSurface,
          highlightColor: scheme.primary.withValues(alpha: 0.09),
          shape: _rounded(AppRadius.md),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle: GoogleFonts.hankenGrotesk(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: GoogleFonts.hankenGrotesk(
          color: muted,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        iconTheme: _state(
          normal: IconThemeData(color: muted),
          selected: IconThemeData(color: scheme.primary),
        ),
        labelTextStyle: _state(
          normal: GoogleFonts.hankenGrotesk(
            color: muted,
            fontWeight: FontWeight.w500,
            fontSize: 11,
          ),
          selected: GoogleFonts.hankenGrotesk(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: border,
        indicatorColor: scheme.primary,
        labelColor: scheme.primary,
        unselectedLabelColor: muted,
        labelStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w500),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevatedSurface,
        selectedColor: scheme.primaryContainer,
        disabledColor: elevatedSurface,
        side: BorderSide(color: border),
        shape: _rounded(AppRadius.sm),
        labelStyle: GoogleFonts.hankenGrotesk(color: text, fontWeight: FontWeight.w600),
        secondaryLabelStyle: GoogleFonts.hankenGrotesk(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: text,
        titleTextStyle: GoogleFonts.hankenGrotesk(
          color: text,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: GoogleFonts.hankenGrotesk(color: muted, fontSize: 13),
        shape: _rounded(AppRadius.md),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: _rounded(AppRadius.lg),
        textStyle: GoogleFonts.hankenGrotesk(color: text),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: _state(
          normal: muted,
          selected: scheme.onPrimary,
          disabled: muted.withValues(alpha: 0.35),
        ),
        trackColor: _state(
          normal: elevatedSurface,
          selected: scheme.primary,
          disabled: elevatedSurface,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: _state(
          normal: Colors.transparent,
          selected: scheme.primary,
          disabled: elevatedSurface,
        ),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(color: border),
        shape: _rounded(AppRadius.xs),
      ),
      radioTheme: RadioThemeData(
        fillColor: _state(
          normal: muted,
          selected: scheme.primary,
          disabled: muted.withValues(alpha: 0.35),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: elevatedSurface,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.light
            ? AppColors.textPrimary
            : const Color(0xFFF1F2F5),
        contentTextStyle: GoogleFonts.hankenGrotesk(
          color: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF181B22),
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: _rounded(AppRadius.sm),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: brightness == Brightness.light
              ? AppColors.textPrimary
              : const Color(0xFFF1F2F5),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        textStyle: GoogleFonts.hankenGrotesk(
          color: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF181B22),
          fontSize: 12,
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
    );
  }
}
