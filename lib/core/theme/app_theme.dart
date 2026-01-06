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
      
      // تعريف الألوان الأساسية
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accentYellow,
        onPrimary: AppColors.backgroundPrimary,
        secondary: AppColors.accentOrange,
        surface: AppColors.backgroundSecondary,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
      ),

      // النصوص (مطابقة لخطوط Roboto/Google Sans)
      textTheme: TextTheme(
        displayLarge: GoogleFonts.roboto(
          color: AppColors.textPrimary, 
          fontWeight: FontWeight.w900, // Black
          letterSpacing: -1.0,
        ),
        headlineLarge: GoogleFonts.roboto(
          color: AppColors.textPrimary, 
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.roboto(
          color: AppColors.textPrimary, 
          fontWeight: FontWeight.bold,
        ),
        bodyLarge: GoogleFonts.roboto(
          color: AppColors.textPrimary,
          fontSize: 16,
        ),
        bodyMedium: GoogleFonts.roboto(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        labelLarge: GoogleFonts.roboto( // للأزرار
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),

      // إعدادات الكروت (Cards) - rounded-m3-xl
      cardTheme: CardTheme(
        color: AppColors.backgroundSecondary,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20), // m3-xl approx
          side: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
        ),
        shadowColor: Colors.black.withOpacity(0.3),
      ),

      // إعدادات الأزرار (Elevated Button)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentYellow,
          foregroundColor: AppColors.backgroundPrimary,
          elevation: 4,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), // m3-lg
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0),
        ),
      ),

      // حقول الإدخال (Inputs)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.backgroundSecondary,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), // m3-lg
          borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accentYellow, width: 1), // focus:border-accent-yellow/50
        ),
        hintStyle: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
