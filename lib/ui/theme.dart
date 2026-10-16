import 'package:flutter/material.dart';

/// Premium jewellery-retail palette: ivory, muted gold, dark ink.
class AppColors {
  static const ivory = Color(0xFFFBF8F1);
  static const surface = Color(0xFFFFFFFF);
  static const tile = Color(0xFFF4F1EA);
  static const gold = Color(0xFFA8843A);
  static const goldDeep = Color(0xFF8A6A2B);
  static const goldSoft = Color(0xFFF1E7CF);
  static const ink = Color(0xFF1F1B16);
  static const muted = Color(0xFF6B655C);
  static const line = Color(0xFFE7E1D5);
  static const warn = Color(0xFFB7791F);
  static const warnSoft = Color(0xFFFFF4DC);
  static const error = Color(0xFFB3261E);
  static const ok = Color(0xFF2E7D4F);
  static const okSoft = Color(0xFFDFF3E6);
}

/// Global text scale (0.75 = 25% smaller than Material defaults).
const uiTextScale = 0.75;

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.gold,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.gold,
        onPrimary: Colors.white,
        secondary: AppColors.goldDeep,
        surface: AppColors.surface,
        onSurface: AppColors.ink,
        error: AppColors.error,
      );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );
  return base.copyWith(
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    scaffoldBackgroundColor: AppColors.ivory,
    textTheme: text,
    appBarTheme: const AppBarTheme(
      toolbarHeight: 46,
      backgroundColor: AppColors.ivory,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.gold, width: 2),
      ),
      labelStyle: const TextStyle(color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: Colors.white,
        minimumSize: const Size(56, 40),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.goldDeep,
        minimumSize: const Size(56, 36),
        side: const BorderSide(color: AppColors.gold),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.goldSoft
              : AppColors.surface,
        ),
        foregroundColor: const WidgetStatePropertyAll(AppColors.ink),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 20),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
