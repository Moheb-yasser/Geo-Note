import 'package:flutter/material.dart';

class AppColors {
  // Screen & Card background colors
  static const Color background = Color(0xFF121212);
  static const Color cardBackground = Color(0xFF222222);
  static const Color chipBackground = Color(0xFF333333);

  // Accent & Action colors (FAB & Active state)
  static const Color primaryAccent = Color(0xFFF5B000);

  // Typography colors
  static const Color primaryText = Color(0xFFEEEEEE);
  static const Color secondaryText = Color(0xFF9E9E9E);
  static const Color dateText = Color(0xFF6E6E6E);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.cardBackground,
        primary: AppColors.primaryAccent,
        onSurface: AppColors.primaryText,
      ),
    );
  }
}