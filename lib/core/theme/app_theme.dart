import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
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
      primaryContainer: Color(0xFFFFE5EE),
      onPrimaryContainer: Color(0xFF50142B),
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFEDF0F4),
      onSecondaryContainer: Color(0xFF303846),
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
      primary: Color(0xFFEC4899),
      onPrimary: Color(0xFF351022),
      primaryContainer: Color(0xFF3A1728),
      onPrimaryContainer: Color(0xFFFFD9E6),
      secondary: Color(0xFFF472B6),
      onSecondary: Color(0xFF252C37),
      secondaryContainer: Color(0xFF1F2937),
      onSecondaryContainer: Color(0xFFE4E8EF),
      surface: Color(0xFF161B22),
      onSurface: Color(0xFFF8FAFC),
      surfaceContainerHighest: Color(0xFF1F2937),
      onSurfaceVariant: Color(0xFF94A3B8),
      error: Color(0xFFE49A96),
      outline: Color(0xFF334155),
    );
    return _buildTheme(
      brightness: Brightness.dark,
      scheme: scheme,
      background: const Color(0xFF0B1220),
      surface: const Color(0xFF161B22),
      elevatedSurface: const Color(0xFF1F2937),
      border: const Color(0xFF334155),
      text: const Color(0xFFF8FAFC),
      muted: const Color(0xFF94A3B8),
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
    final textTheme = GoogleFonts.interTextTheme(
      brightness == Brightness.light
          ? ThemeData.light(useMaterial3: true).textTheme
          : ThemeData.dark(useMaterial3: true).textTheme,
    ).apply(bodyColor: text, displayColor: text);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      primaryColor: scheme.primary,
      iconTheme: IconThemeData(color: muted, size: 23),
      textTheme: textTheme.copyWith(
        displayLarge: textTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -1.2,
        ),
        displayMedium: textTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(color: muted),
        bodySmall: textTheme.bodySmall?.copyWith(color: muted),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
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
        titleTextStyle: GoogleFonts.inter(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(22)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: _rounded(20),
        titleTextStyle: GoogleFonts.inter(
          color: text,
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: GoogleFonts.inter(color: muted, height: 1.45),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.18),
        selectionHandleColor: scheme.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hoverColor: elevatedSurface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: _inputBorder(border),
        enabledBorder: _inputBorder(border),
        focusedBorder: _inputBorder(scheme.primary, width: 1.4),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.4),
        disabledBorder: _inputBorder(border.withValues(alpha: 0.55)),
        labelStyle: GoogleFonts.inter(
          color: muted,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: GoogleFonts.inter(color: muted, fontWeight: FontWeight.w400),
        helperStyle: GoogleFonts.inter(color: muted, fontSize: 12),
        errorStyle: GoogleFonts.inter(
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
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: _rounded(12),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: elevatedSurface,
          disabledForegroundColor: muted,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: _rounded(12),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: _rounded(12),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          shape: _rounded(10),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: muted,
          hoverColor: elevatedSurface,
          highlightColor: scheme.primary.withValues(alpha: 0.09),
          shape: _rounded(12),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle: GoogleFonts.inter(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: GoogleFonts.inter(
          color: muted,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        iconTheme: _state(
          normal: IconThemeData(color: muted),
          selected: IconThemeData(color: scheme.primary),
        ),
        labelTextStyle: _state(
          normal: GoogleFonts.inter(
            color: muted,
            fontWeight: FontWeight.w500,
            fontSize: 11,
          ),
          selected: GoogleFonts.inter(
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
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: elevatedSurface,
        selectedColor: scheme.primaryContainer,
        disabledColor: elevatedSurface,
        side: BorderSide(color: border),
        shape: _rounded(999),
        labelStyle: GoogleFonts.inter(color: text, fontWeight: FontWeight.w600),
        secondaryLabelStyle: GoogleFonts.inter(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: text,
        titleTextStyle: GoogleFonts.inter(
          color: text,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: GoogleFonts.inter(color: muted, fontSize: 13),
        shape: _rounded(12),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: _rounded(14),
        textStyle: GoogleFonts.inter(color: text),
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
        shape: _rounded(5),
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
        contentTextStyle: GoogleFonts.inter(
          color: brightness == Brightness.light
              ? Colors.white
              : const Color(0xFF181B22),
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: _rounded(12),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: brightness == Brightness.light
              ? AppColors.textPrimary
              : const Color(0xFFF1F2F5),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: GoogleFonts.inter(
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
