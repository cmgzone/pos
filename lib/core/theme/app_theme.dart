import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
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

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        surfaceContainerHighest: AppColors.surfaceHighlight,
        error: AppColors.error,
      ),
      canvasColor: AppColors.background,
      iconTheme: const IconThemeData(
        color: AppColors.secondary, // Cyber mint fallback
        size: 24,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
          .copyWith(
            displayLarge: GoogleFonts.outfit(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
            displayMedium: GoogleFonts.outfit(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
            titleLarge: GoogleFonts.outfit(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: GoogleFonts.inter(color: AppColors.textPrimary),
            bodyMedium: GoogleFonts.inter(color: AppColors.textSecondary),
            labelLarge: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.premiumPanel,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actionsIconTheme: const IconThemeData(color: AppColors.textSecondary),
        titleTextStyle: GoogleFonts.outfit(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.premiumStroke),
        ),
        margin: EdgeInsets.zero,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: AppColors.premiumPanel,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.premiumPanel,
        surfaceTintColor: Colors.transparent,
        shape: _rounded(24),
        titleTextStyle: GoogleFonts.outfit(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: AppColors.textSecondary,
          height: 1.42,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.premiumPanel,
        modalBackgroundColor: AppColors.premiumPanel,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.textSecondary.withValues(alpha: 0.38),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.secondary,
        selectionColor: AppColors.primary.withValues(alpha: 0.24),
        selectionHandleColor: AppColors.secondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHighlight.withValues(alpha: 0.74),
        hoverColor: AppColors.surfaceHighlight.withValues(alpha: 0.92),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: _inputBorder(AppColors.border),
        enabledBorder: _inputBorder(AppColors.border.withValues(alpha: 0.95)),
        focusedBorder: _inputBorder(AppColors.secondary, width: 1.6),
        errorBorder: _inputBorder(AppColors.error.withValues(alpha: 0.72)),
        focusedErrorBorder: _inputBorder(AppColors.error, width: 1.6),
        disabledBorder: _inputBorder(AppColors.border.withValues(alpha: 0.38)),
        labelStyle: GoogleFonts.inter(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          letterSpacing: 0.1,
        ),
        floatingLabelStyle: GoogleFonts.inter(
          color: AppColors.secondary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        hintStyle: GoogleFonts.inter(
          color: AppColors.textSecondary.withValues(alpha: 0.62),
          fontWeight: FontWeight.w500,
        ),
        helperStyle: GoogleFonts.inter(
          color: AppColors.textSecondary.withValues(alpha: 0.78),
          fontSize: 12,
          height: 1.25,
        ),
        errorStyle: GoogleFonts.inter(
          color: AppColors.error,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          height: 1.25,
        ),
        prefixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.error)) return AppColors.error;
          if (states.contains(WidgetState.focused)) return AppColors.secondary;
          if (states.contains(WidgetState.disabled)) {
            return AppColors.textSecondary.withValues(alpha: 0.38);
          }
          return AppColors.textSecondary.withValues(alpha: 0.82);
        }),
        suffixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.error)) return AppColors.error;
          if (states.contains(WidgetState.focused)) return AppColors.secondary;
          if (states.contains(WidgetState.disabled)) {
            return AppColors.textSecondary.withValues(alpha: 0.38);
          }
          return AppColors.textSecondary.withValues(alpha: 0.82);
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: AppColors.primary.withValues(alpha: 0.35),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: _rounded(16),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceHighlight.withValues(
            alpha: 0.55,
          ),
          disabledForegroundColor: AppColors.textSecondary.withValues(
            alpha: 0.55,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: _rounded(16),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.premiumStroke),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: _rounded(16),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.secondary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: _rounded(14),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w800),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          hoverColor: AppColors.surfaceHighlight,
          highlightColor: AppColors.primary.withValues(alpha: 0.14),
          shape: _rounded(14),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.16),
        selectedIconTheme: const IconThemeData(color: AppColors.primary),
        unselectedIconTheme: const IconThemeData(
          color: AppColors.textSecondary,
        ),
        selectedLabelTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: GoogleFonts.inter(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.premiumPanel,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.primary.withValues(alpha: 0.16),
        elevation: 0,
        iconTheme: _state(
          normal: const IconThemeData(color: AppColors.textSecondary),
          selected: const IconThemeData(color: AppColors.primary),
        ),
        labelTextStyle: _state(
          normal: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          selected: GoogleFonts.inter(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: AppColors.border,
        indicatorColor: AppColors.primary,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w800),
        unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHighlight,
        selectedColor: AppColors.primary.withValues(alpha: 0.20),
        disabledColor: AppColors.surfaceHighlight.withValues(alpha: 0.45),
        side: const BorderSide(color: AppColors.premiumStroke),
        shape: _rounded(999),
        labelStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: GoogleFonts.inter(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
        shape: _rounded(16),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.premiumPanel,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: _rounded(18),
        textStyle: GoogleFonts.inter(color: AppColors.textPrimary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: _state(
          normal: AppColors.textSecondary,
          selected: AppColors.secondary,
          disabled: AppColors.textSecondary.withValues(alpha: 0.36),
        ),
        trackColor: _state(
          normal: AppColors.surfaceHighlight,
          selected: AppColors.primary.withValues(alpha: 0.45),
          disabled: AppColors.surfaceHighlight.withValues(alpha: 0.45),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: _state(
          normal: AppColors.surfaceHighlight,
          selected: AppColors.primary,
          disabled: AppColors.surfaceHighlight.withValues(alpha: 0.45),
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: AppColors.premiumStroke),
        shape: _rounded(6),
      ),
      radioTheme: RadioThemeData(
        fillColor: _state(
          normal: AppColors.textSecondary,
          selected: AppColors.primary,
          disabled: AppColors.textSecondary.withValues(alpha: 0.38),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceHighlight,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHighlight,
        contentTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: _rounded(16),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.premiumPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.premiumStroke),
        ),
        textStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
    );
  }
}
