import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sahel night — aligné sur apps/web/src/styles/tokens.css
class NfTokens {
  static const bg = Color(0xFF07140F);
  static const bgMid = Color(0xFF0A1F18);
  static const surface = Color(0xFF0C241C);
  static const elevated = Color(0xFF12352A);
  static const line = Color(0x249DC9B0);
  static const text = Color(0xFFE8F6EF);
  static const textMute = Color(0xFF8FB8A3);
  static const brand = Color(0xFF2DB88A);
  static const brandSoft = Color(0xFF5DCAA5);
  static const sand = Color(0xFFE6C07B);
  static const warn = Color(0xFFE0A045);
  static const danger = Color(0xFFD45A45);
  static const ok = Color(0xFF3ECF9A);
  static const card2 = Color(0xFF0A1C15);
}

ThemeData buildNeoFormaTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: NfTokens.bg,
    colorScheme: const ColorScheme.dark(
      primary: NfTokens.brand,
      secondary: NfTokens.brandSoft,
      surface: NfTokens.surface,
      error: NfTokens.danger,
      onPrimary: NfTokens.bg,
      onSurface: NfTokens.text,
    ),
  );

  return base.copyWith(
    textTheme: GoogleFonts.figtreeTextTheme(base.textTheme).apply(
      bodyColor: NfTokens.text,
      displayColor: NfTokens.text,
    ),
    primaryTextTheme: GoogleFonts.syneTextTheme(base.primaryTextTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: NfTokens.bg,
      foregroundColor: NfTokens.text,
      elevation: 0,
      titleTextStyle: GoogleFonts.syne(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: NfTokens.text,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NfTokens.elevated,
      hintStyle: const TextStyle(color: NfTokens.textMute),
      labelStyle: const TextStyle(color: NfTokens.textMute),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NfTokens.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NfTokens.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: NfTokens.brand, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: NfTokens.brand,
        foregroundColor: NfTokens.bg,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.figtree(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: NfTokens.brandSoft),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: NfTokens.surface,
      selectedItemColor: NfTokens.brand,
      unselectedItemColor: NfTokens.textMute,
      type: BottomNavigationBarType.fixed,
    ),
    cardTheme: CardThemeData(
      color: NfTokens.elevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: NfTokens.line),
      ),
    ),
  );
}
