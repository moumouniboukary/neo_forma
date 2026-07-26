import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api/client.dart';

/// Tokens de marque. Surfaces selon [brightness] ; brand stable.
/// Overrides white-label via Theme / [applyBranding].
class NfTokens {
  static Brightness brightness = Brightness.dark;

  static bool get isDark => brightness == Brightness.dark;

  // ── Dark (Sahel night) ──
  static const Color _bgDark = Color(0xFF07140F);
  static const Color _bgMidDark = Color(0xFF0A1F18);
  static const Color _surfaceDark = Color(0xFF0C241C);
  static const Color _elevatedDark = Color(0xFF12352A);
  static const Color _lineDark = Color(0x249DC9B0);
  static const Color _textDark = Color(0xFFE8F6EF);
  static const Color _textMuteDark = Color(0xFF8FB8A3);
  static const Color _card2Dark = Color(0xFF0A1C15);

  // ── Light (Sahel day) ──
  static const Color _bgLight = Color(0xFFF2F8F5);
  static const Color _bgMidLight = Color(0xFFE8F3ED);
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _elevatedLight = Color(0xFFFFFFFF);
  static const Color _lineLight = Color(0x332DB88A);
  static const Color _textLight = Color(0xFF0A1F18);
  static const Color _textMuteLight = Color(0xFF4A6B5C);
  static const Color _card2Light = Color(0xFFE0EEE7);

  static Color get bg => isDark ? _bgDark : _bgLight;
  static Color get bgMid => isDark ? _bgMidDark : _bgMidLight;
  static Color get surface => isDark ? _surfaceDark : _surfaceLight;
  static Color get elevated => isDark ? _elevatedDark : _elevatedLight;
  static Color get line => isDark ? _lineDark : _lineLight;
  static Color get text => isDark ? _textDark : _textLight;
  static Color get textMute => isDark ? _textMuteDark : _textMuteLight;
  static Color get card2 => isDark ? _card2Dark : _card2Light;

  static const Color brand = Color(0xFF2DB88A);
  static const Color brandSoft = Color(0xFF5DCAA5);
  static const Color sand = Color(0xFFE6C07B);
  static const Color warn = Color(0xFFE0A045);
  static const Color danger = Color(0xFFD45A45);
  static const Color ok = Color(0xFF3ECF9A);

  /// Contraste sur boutons brand (fond sombre du texte).
  static const Color onBrand = Color(0xFF062018);

  static String appName = 'NeoForma';
  static String? logoUrl;
  static String? supportPhone;

  /// Overrides appliqués au ThemeData (pas aux `const Color` inline).
  static Color? primaryOverride;
  static Color? secondaryOverride;

  static Color get primary => primaryOverride ?? brand;
  static Color get secondary => secondaryOverride ?? brandSoft;

  static void applyThemeMode(String theme) {
    brightness = theme == 'light' ? Brightness.light : Brightness.dark;
  }

  static void applyBranding({
    String? appName,
    String? primaryColor,
    String? secondaryColor,
    String? logoUrl,
    String? supportPhone,
  }) {
    if (appName != null && appName.isNotEmpty) NfTokens.appName = appName;
    if (primaryColor != null) {
      primaryOverride = _parseColor(primaryColor);
    }
    if (secondaryColor != null) {
      secondaryOverride = _parseColor(secondaryColor);
    }
    NfTokens.logoUrl = logoUrl;
    NfTokens.supportPhone = supportPhone;
  }

  static Color? _parseColor(String raw) {
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return null;
    return Color(value);
  }
}

/// Charge le branding distant (white-label IMF / partenaire).
final brandingProvider = FutureProvider<void>((ref) async {
  try {
    final data = await ref.read(apiClientProvider).get<Map<String, dynamic>>(
          '/branding',
          parse: (d) => Map<String, dynamic>.from(d as Map),
        );
    NfTokens.applyBranding(
      appName: data['appName']?.toString(),
      primaryColor: data['primaryColor']?.toString(),
      secondaryColor: data['secondaryColor']?.toString(),
      logoUrl: data['logoUrl']?.toString(),
      supportPhone: data['supportPhone']?.toString(),
    );
  } catch (_) {
    // Défaut NeoForma
  }
});

ThemeData buildNeoFormaTheme([Brightness brightness = Brightness.dark]) {
  final previous = NfTokens.brightness;
  NfTokens.brightness = brightness;
  final theme = _buildThemeForCurrentTokens();
  NfTokens.brightness = previous;
  return theme;
}

ThemeData _buildThemeForCurrentTokens() {
  final primary = NfTokens.primary;
  final secondary = NfTokens.secondary;
  final brightness = NfTokens.brightness;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: NfTokens.bg,
    colorScheme: brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: primary,
            secondary: secondary,
            surface: NfTokens.surface,
            error: NfTokens.danger,
            onPrimary: NfTokens.onBrand,
            onSurface: NfTokens.text,
          )
        : ColorScheme.light(
            primary: primary,
            secondary: secondary,
            surface: NfTokens.surface,
            error: NfTokens.danger,
            onPrimary: NfTokens.onBrand,
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
      hintStyle: TextStyle(color: NfTokens.textMute),
      labelStyle: TextStyle(color: NfTokens.textMute),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: NfTokens.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: NfTokens.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primary, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: NfTokens.onBrand,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.figtree(
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: secondary),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: NfTokens.surface,
      selectedItemColor: primary,
      unselectedItemColor: NfTokens.textMute,
      type: BottomNavigationBarType.fixed,
    ),
    cardTheme: CardThemeData(
      color: NfTokens.elevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: NfTokens.line),
      ),
    ),
  );
}
