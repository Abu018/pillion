import 'package:flutter/material.dart';

/// Palette: near-black header, soft lavender sheet, bright pastel cards.
abstract final class AppColors {
  static const ink = Color(0xFF0D0D12);
  static const inkSoft = Color(0xFF1C1C24);
  static const sheet = Color(0xFFF4F4FA);
  static const lavender = Color(0xFFD9DCFB);
  static const orange = Color(0xFFF7931E);
  static const blue = Color(0xFF6E7BF2);
  static const purple = Color(0xFFA25AE6);
  static const green = Color(0xFFB6EBA6);
  static const pink = Color(0xFFF6B5D1);
  static const yellow = Color(0xFFFFD66B);
  static const muted = Color(0xFF8A8A99);
  static const danger = Color(0xFFE5484D);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    primary: AppColors.ink,
    onPrimary: Colors.white,
    secondary: AppColors.blue,
    surface: AppColors.sheet,
    error: AppColors.danger,
  );
  const pill = StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.sheet,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.ink,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        shape: pill,
        minimumSize: const Size(0, 52),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        shape: pill,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: Color(0xFFDADAE6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.ink, shape: pill)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.ink,
      inactiveTrackColor: Color(0xFFE2E2EE),
      thumbColor: AppColors.ink,
      trackHeight: 6,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.ink : const Color(0xFFE2E2EE),
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: const ChipThemeData(shape: StadiumBorder(), side: BorderSide.none),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
  );
}
