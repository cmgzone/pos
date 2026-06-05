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

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
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
          ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
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
          elevation: 4,
          shadowColor: AppColors.primary.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
    );
  }
}
