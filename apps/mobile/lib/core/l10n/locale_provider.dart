import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../api/client.dart';
import '../offline/local_cache.dart';
import '../theme/tokens.dart';
import 'strings.dart';

/// Préférences UX locales (langue + mode icônes + voix + thème).
/// Défauts terrain Burkina : icônes + voix activés (faible littératie).
class UxPrefs {
  const UxPrefs({
    this.language = 'fr',
    this.iconMode = true,
    this.voiceAssist = true,
    /// Suit les réglages du téléphone au premier lancement.
    this.theme = 'system',
  });

  final String language;
  final bool iconMode;
  final bool voiceAssist;

  /// `system` | `light` | `dark`
  final String theme;

  UxPrefs copyWith({
    String? language,
    bool? iconMode,
    bool? voiceAssist,
    String? theme,
  }) =>
      UxPrefs(
        language: language ?? this.language,
        iconMode: iconMode ?? this.iconMode,
        voiceAssist: voiceAssist ?? this.voiceAssist,
        theme: theme ?? this.theme,
      );
}

class UxPrefsNotifier extends StateNotifier<UxPrefs> {
  UxPrefsNotifier(this._ref) : super(_readInitial(_ref)) {
    try {
      final cached =
          _ref.read(localCacheProvider).getMap(LocalCacheKeys.uxPrefs);
      _themeChosen = cached?['themeChosen'] == true;
    } catch (_) {}
    _applyTokens(state.theme);
    Future(() => _saveLocal(state));
  }

  final Ref _ref;
  bool _themeChosen = false;

  NfStrings get strings => NfStrings(state.language);

  /// État initial passé à [super] — pas de `state =` pendant la création
  /// du provider (évite l’erreur Riverpod pendant le build).
  static UxPrefs _readInitial(Ref ref) {
    var prefs = const UxPrefs();
    try {
      final cached = ref.read(localCacheProvider).getMap(LocalCacheKeys.uxPrefs);
      if (cached != null) {
        final chosen = cached['themeChosen'] == true;
        var theme = cached.containsKey('theme')
            ? _normalizeTheme(cached['theme']?.toString())
            : 'system';
        // Ancien forçage « light » (themeDefaultV2) : revenir au téléphone
        // si l’utilisateur n’a jamais choisi manuellement.
        if (!chosen && cached['themeDefaultV2'] == true && theme == 'light') {
          theme = 'system';
        }
        prefs = UxPrefs(
          language: NfStrings.normalize(cached['language']?.toString()),
          iconMode: cached.containsKey('iconMode')
              ? cached['iconMode'] == true
              : true,
          voiceAssist: cached['voiceAssist'] != false,
          theme: theme,
        );
        // Stash chosen flag via a side channel — applied in constructor body
        // by reading cache again is fine; we set on the instance below.
      }
    } catch (_) {
      // LocalCache not ready yet — défaut téléphone
    }
    // Le thème local prime : on n’écrase pas avec /me (défaut API souvent « light »).
    final user = ref.read(authProvider).user;
    final lang = user?.language;
    if (lang != null && lang.isNotEmpty) {
      prefs = prefs.copyWith(language: NfStrings.normalize(lang));
    }
    return prefs;
  }

  /// `system` | `light` | `dark`
  static String _normalizeTheme(String? value) {
    if (value == 'light' || value == 'dark' || value == 'system') return value!;
    return 'system';
  }

  void _applyTokens(String theme) {
    final platform =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    NfTokens.applyThemeMode(theme, platformBrightness: platform);
  }

  Future<void> _saveLocal(UxPrefs prefs, {bool? themeChosen}) async {
    if (themeChosen != null) _themeChosen = themeChosen;
    try {
      final prev =
          _ref.read(localCacheProvider).getMap(LocalCacheKeys.uxPrefs);
      final chosen = themeChosen ?? (_themeChosen || prev?['themeChosen'] == true);
      _themeChosen = chosen;
      await _ref.read(localCacheProvider).putMap(LocalCacheKeys.uxPrefs, {
        'language': prefs.language,
        'iconMode': prefs.iconMode,
        'voiceAssist': prefs.voiceAssist,
        'theme': prefs.theme,
        'themeChosen': chosen,
        'themeDefaultV3': true,
      });
    } catch (_) {}
  }

  void setLanguageLocal(String lang) {
    final next = NfStrings.normalize(lang);
    if (next == state.language) return;
    state = state.copyWith(language: next);
    _saveLocal(state);
  }

  void setIconModeLocal(bool value) {
    if (value == state.iconMode) return;
    state = state.copyWith(iconMode: value);
    _saveLocal(state);
  }

  void setVoiceAssistLocal(bool value) {
    if (value == state.voiceAssist) return;
    state = state.copyWith(voiceAssist: value);
    _saveLocal(state);
  }

  void setThemeLocal(String theme) {
    final next = _normalizeTheme(theme);
    if (next == state.theme) return;
    state = state.copyWith(theme: next);
    _applyTokens(next);
    _saveLocal(state, themeChosen: true);
  }

  /// Recalcule les tokens quand le thème téléphone change (mode système).
  void syncPlatformBrightness(Brightness brightness) {
    if (state.theme != 'system') return;
    NfTokens.applyThemeMode('system', platformBrightness: brightness);
  }

  Future<void> persist({
    String? language,
    bool? iconMode,
    bool? voiceAssist,
    String? theme,
  }) async {
    final next = state.copyWith(
      language: language != null ? NfStrings.normalize(language) : null,
      iconMode: iconMode,
      voiceAssist: voiceAssist,
      theme: theme != null ? _normalizeTheme(theme) : null,
    );
    if (next.language == state.language &&
        next.iconMode == state.iconMode &&
        next.voiceAssist == state.voiceAssist &&
        next.theme == state.theme) {
      return;
    }
    state = next;
    if (theme != null) _applyTokens(next.theme);
    await _saveLocal(next, themeChosen: theme != null ? true : null);
    try {
      await _ref
          .read(apiClientProvider)
          .patch(
            '/me/preferences',
            data: {
              'language':
                  ?(language != null ? NfStrings.normalize(language) : null),
              'modeIconographique': ?iconMode,
              'assistanceVocaleActive': ?voiceAssist,
              'theme': ?(theme != null ? _normalizeTheme(theme) : null),
            },
          );
      final user = _ref.read(authProvider).user;
      if (user != null && (language != null || theme != null)) {
        _ref.read(authProvider.notifier).setUser(
              user.copyWith(
                language: language != null
                    ? NfStrings.normalize(language)
                    : user.language,
                theme: theme != null ? _normalizeTheme(theme) : user.theme,
              ),
            );
      }
    } catch (_) {
      // Préférence locale conservée hors ligne
    }
  }
}

final uxPrefsProvider = StateNotifierProvider<UxPrefsNotifier, UxPrefs>(
  (ref) {
    return UxPrefsNotifier(ref);
  },
  dependencies: [localCacheProvider, authProvider, apiClientProvider],
);

final nfStringsProvider = Provider<NfStrings>(
  (ref) {
    final lang = ref.watch(uxPrefsProvider).language;
    return NfStrings(lang);
  },
  dependencies: [uxPrefsProvider],
);
