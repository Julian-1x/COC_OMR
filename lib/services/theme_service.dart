import 'package:flutter/material.dart';

class ThemeService {
  ThemeService._();

  static const Color brandGreen = Color(0xFF10B981);
  static const Color brandGreenDark = Color(0xFF059669);
  static const Color brandSurface = Color(0xFFF0FDF4);
  static const Color brandBorder = Color(0xFFD1FAE5);
  static const Color brandText = Color(0xFF1E293B);
  static const Color brandMuted = Color(0xFF64748B);
  static const Color appCanvas = Color(0xFFF8FAFC);

  static Future<void> init() async {}

  static ThemeData getLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brandGreen,
        brightness: Brightness.light,
      ),
      fontFamilyFallback: const ['Roboto', 'Arial'],
      scaffoldBackgroundColor: appCanvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: appCanvas,
        foregroundColor: brandText,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: appCanvas,
        titleTextStyle: TextStyle(
          color: brandText,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brandText,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(
          color: brandMuted,
          fontWeight: FontWeight.w700,
        ),
        hintStyle: TextStyle(
          color: brandMuted.withValues(alpha: 0.72),
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: brandMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: brandGreen, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: brandGreen,
        foregroundColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandGreen,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brandGreenDark,
          side: BorderSide(color: brandGreen.withValues(alpha: 0.38)),
          minimumSize: const Size(0, 46),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brandGreenDark,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandGreen,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: brandGreen.withValues(alpha: 0.12),
        disabledColor: const Color(0xFFF1F5F9),
        checkmarkColor: brandGreen,
        labelStyle: const TextStyle(
          color: brandText,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: brandGreenDark,
          fontWeight: FontWeight.w800,
        ),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      checkboxTheme: const CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(4)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return brandGreen;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return brandGreen.withValues(alpha: 0.34);
          }
          return const Color(0xFFE2E8F0);
        }),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: brandMuted,
        textColor: brandText,
        titleTextStyle: TextStyle(
          color: brandText,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        subtitleTextStyle: TextStyle(
          color: brandMuted,
          fontSize: 13,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: brandGreen.withValues(alpha: 0.12),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? brandGreenDark : brandMuted,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12,
          );
        }),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE2E8F0)),
    );
  }
}
