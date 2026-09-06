import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api/client.dart';
import '../brand.dart';

/// Tokens de marque. Surfaces selon [brightness] ; brand stable.
/// Overrides white-label via Theme / [applyBranding].
class NfTokens {
  /// Défaut = luminosité téléphone (évite un flash clair sur téléphone sombre).
  static Brightness brightness =
      WidgetsBinding.instance.platformDispatcher.platformBrightness;

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

  static String appName = kAppName;
  static String? logoUrl;
  static String? supportPhone;

  /// Overrides appliqués au ThemeData (pas aux `const Color` inline).
  static Color? primaryOverride;
  static Color? secondaryOverride;

  static Color get primary => primaryOverride ?? brand;
  static Color get secondary => secondaryOverride ?? brandSoft;

  /// Brightness effective pour une préférence `system` | `light` | `dark`.
  static Brightness resolveBrightness(
    String theme, {
    Brightness? platformBrightness,
  }) {
    if (theme == 'light') return Brightness.light;
    if (theme == 'dark') return Brightness.dark;
    return platformBrightness ??
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  static void applyThemeMode(String theme, {Brightness? platformBrightness}) {
    brightness = resolveBrightness(theme, platformBrightness: platformBrightness);
  }

  /// Aligne les tokens sur le Theme Material déjà résolu (source de vérité UI).
  static void syncFromThemeBrightness(Brightness themeBrightness) {
    brightness = themeBrightness;
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

  static Color _bgOf(Brightness b) =>
      b == Brightness.dark ? _bgDark : _bgLight;
  static Color _surfaceOf(Brightness b) =>
      b == Brightness.dark ? _surfaceDark : _surfaceLight;
  static Color _elevatedOf(Brightness b) =>
      b == Brightness.dark ? _elevatedDark : _elevatedLight;
  static Color _lineOf(Brightness b) =>
      b == Brightness.dark ? _lineDark : _lineLight;
  static Color _textOf(Brightness b) =>
      b == Brightness.dark ? _textDark : _textLight;
  static Color _textMuteOf(Brightness b) =>
      b == Brightness.dark ? _textMuteDark : _textMuteLight;
}

/// Charge le branding distant (white-label IMF / partenaire).
final brandingProvider = FutureProvider<void>(
  (ref) async {
    try {
      final data = await ref.read(apiClientProvider).get<Map<String, dynamic>>(
            '/branding',
            parse: (d) => Map<String, dynamic>.from(d as Map),
          );
      final remoteName = data['appName']?.toString()?.trim();
      // TeriyaScore est un produit distinct : ne jamais l'afficher dans NeoForma.
      final isForeignBrand = remoteName != null &&
          remoteName.toLowerCase().contains('teriya');
      final appName =
          (remoteName == null || remoteName.isEmpty || isForeignBrand)
              ? kAppName
              : remoteName;
      NfTokens.applyBranding(
        appName: appName,
        primaryColor: data['primaryColor']?.toString(),
        secondaryColor: data['secondaryColor']?.toString(),
        logoUrl: data['logoUrl']?.toString(),
        supportPhone: data['supportPhone']?.toString(),
      );
    } catch (_) {
      // Défaut compile-time (kAppName)
    }
  },
  dependencies: [apiClientProvider],
);

/// Construit un ThemeData sans muter [NfTokens.brightness] (évite un basculement
/// sombre parasite quand light + dark sont construits dans le même build).
ThemeData buildNeoFormaTheme([Brightness brightness = Brightness.light]) {
  final primary = NfTokens.primary;
  final secondary = NfTokens.secondary;
  final bg = NfTokens._bgOf(brightness);
  final surface = NfTokens._surfaceOf(brightness);
  final elevated = NfTokens._elevatedOf(brightness);
  final line = NfTokens._lineOf(brightness);
  final text = NfTokens._textOf(brightness);
  final textMute = NfTokens._textMuteOf(brightness);

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: bg,
    colorScheme: brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: primary,
            secondary: secondary,
            surface: surface,
            error: NfTokens.danger,
            onPrimary: NfTokens.onBrand,
            onSurface: text,
          )
        : ColorScheme.light(
            primary: primary,
            secondary: secondary,
            surface: surface,
            error: NfTokens.danger,
            onPrimary: NfTokens.onBrand,
            onSurface: text,
          ),
  );

  return base.copyWith(
    textTheme: GoogleFonts.figtreeTextTheme(base.textTheme).apply(
      bodyColor: text,
      displayColor: text,
    ),
    primaryTextTheme: GoogleFonts.syneTextTheme(base.primaryTextTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: text,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            brightness == Brightness.light ? Brightness.dark : Brightness.light,
        statusBarBrightness:
            brightness == Brightness.light ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: bg,
        systemNavigationBarIconBrightness:
            brightness == Brightness.light ? Brightness.dark : Brightness.light,
      ),
      titleTextStyle: GoogleFonts.syne(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: text,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: elevated,
      hintStyle: TextStyle(color: textMute),
      labelStyle: TextStyle(color: textMute),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line),
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
      backgroundColor: surface,
      selectedItemColor: primary,
      unselectedItemColor: textMute,
      type: BottomNavigationBarType.fixed,
    ),
    cardTheme: CardThemeData(
      color: elevated,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: line),
      ),
    ),
  );
}
