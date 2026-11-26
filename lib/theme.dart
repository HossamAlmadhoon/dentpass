import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const ground = Color(0xFFF4F6F4);
  static const ink = Color(0xFF17212B);
  static const body = Color(0xFF3D4852);
  static const muted = Color(0xFF56616B);
  static const line = Color(0xFFD9DED9);
  static const field = Color(0xFFC9D1CB);
  static const track = Color(0xFFE2E7E3);

  // Learn (watch a case, course)
  static const nile = Color(0xFF0F5C52);
  static const nileTint = Color(0xFFDDEBE7);
  // Rent
  static const blue = Color(0xFF2B4C7E);
  static const blueTint = Color(0xFFDFE6F1);
  // Cover
  static const amber = Color(0xFF7A4A0A);
  static const amberTint = Color(0xFFF6E7CF);

  static const danger = Color(0xFFB3261E);
  static const dangerTint = Color(0xFFF9DEDC);
}

/// [fontFamily] is only for screenshot tests, which load the same typeface from files.
ThemeData buildTheme({String? fontFamily}) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.nile,
      primary: AppColors.nile,
      surface: AppColors.ground,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.ground,
  );

  // IBM Plex Sans Arabic covers both Arabic and Latin, so both languages share one typeface.
  final text = (fontFamily != null
          ? base.textTheme.apply(fontFamily: fontFamily)
          : GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme))
      .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink);

  OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: w),
      );

  return base.copyWith(
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.ground,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(AppColors.field, 1.5),
      enabledBorder: border(AppColors.field, 1.5),
      focusedBorder: border(AppColors.nile, 2),
      errorBorder: border(AppColors.danger, 1.5),
      focusedErrorBorder: border(AppColors.danger, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.field, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.nileTint,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
