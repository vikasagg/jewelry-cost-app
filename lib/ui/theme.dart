import 'package:flutter/material.dart';

/// Premium jewellery-retail palette (cream, antique gold, dark brown),
/// matching the shop's design mock-ups.
class AppColors {
  static const ivory = Color(0xFFFBF6EC); // page background
  static const surface = Color(0xFFFFFDF8); // cards
  static const tile = Color(0xFFF6EEDF); // quiet fills
  static const gold = Color(0xFFA9802F);
  static const goldLight = Color(0xFFC49A4A); // gradient start
  static const goldDeep = Color(0xFF8A6524);
  static const goldSoft = Color(0xFFF3E6CC); // chips, icon squares
  static const ink = Color(0xFF3A2D1F); // dark brown text
  static const muted = Color(0xFF8A7A63);
  static const line = Color(0xFFEADDC6);
  static const warn = Color(0xFFB7791F);
  static const warnSoft = Color(0xFFFFF4DC);
  static const error = Color(0xFFB3261E);
  static const ok = Color(0xFF2E7D4F);
  static const okSoft = Color(0xFFDFF3E6);

  /// Gold gradient for primary actions and highlight cards.
  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, gold, goldDeep],
  );
}

/// Text font for the whole app; [serifFont] is used for the brand title.
const appFont = 'Inter';
const serifFont = 'PlayfairDisplay';

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
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: appFont,
  );
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
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: appFont,
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
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
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
              ? AppColors.gold
              : AppColors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Colors.white : AppColors.ink,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, space: 20),
    listTileTheme: const ListTileThemeData(iconColor: AppColors.gold),
    iconTheme: const IconThemeData(color: AppColors.goldDeep),
    datePickerTheme: const DatePickerThemeData(
      backgroundColor: AppColors.surface,
      headerBackgroundColor: AppColors.gold,
      headerForegroundColor: Colors.white,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
