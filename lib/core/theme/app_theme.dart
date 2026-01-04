import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      scaffoldBackgroundColor: AppColors.backgroundPrimary,
      primaryColor: AppColors.accentYellow,

      colorScheme: const ColorScheme.dark(
        primary: AppColors.accentYellow,
        onPrimary: AppColors.backgroundPrimary,
        secondary: AppColors.accentOrange,
        surface: AppColors.backgroundSecondary,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),

      textTheme: TextTheme(
        displayLarge: GoogleFonts.roboto(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        bodyLarge: GoogleFonts.roboto(color: AppColors.textPrimary),
        bodyMedium: GoogleFonts.roboto(color: AppColors.textSecondary),
      ),

      // ✅ التصحيح: إزالة النوع الصريح CardTheme لتجنب مشاكل الإصدارات
      cardTheme: CardTheme(
        color: AppColors.backgroundSecondary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.white10, width: 1),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentYellow,
          foregroundColor: AppColors.backgroundPrimary,
          elevation: 4,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.backgroundSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accentYellow),
        ),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
