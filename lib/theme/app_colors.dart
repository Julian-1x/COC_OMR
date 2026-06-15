import 'package:flutter/material.dart';
import 'package:omr_app/services/theme_service.dart';

/// Single source of brand colors — mirrors [ThemeService].
abstract final class AppColors {
  static const Color brandGreen = ThemeService.brandGreen;
  static const Color brandGreenDark = ThemeService.brandGreenDark;
  static const Color brandSurface = ThemeService.brandSurface;
  static const Color brandBorder = ThemeService.brandBorder;
  static const Color brandText = ThemeService.brandText;
  static const Color brandMuted = ThemeService.brandMuted;
  static const Color appCanvas = ThemeService.appCanvas;

  static const Color error = Color(0xFFDC2626);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color warningBorder = Color(0xFFFDE68A);
  static const Color warningText = Color(0xFF92400E);
  static const Color borderLight = Color(0xFFE2E8F0);
  static const Color borderSubtle = Color(0xFFE5E7EB);
  static const Color inputFill = Color(0xFFF8FAFC);
  static const Color warningAccent = Color(0xFFD97706);
  static const Color cautionAccent = Color(0xFFF59E0B);

  static const LinearGradient authHeaderGradient = LinearGradient(
    colors: [Color(0xFF064E3B), brandGreenDark, brandGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
