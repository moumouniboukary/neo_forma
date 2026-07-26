import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../api/client.dart';
import '../offline/local_cache.dart';
import '../theme/tokens.dart';
import 'strings.dart';

/// Préférences UX locales (langue + mode icônes + voix + thème).
class UxPrefs {
  const UxPrefs({
    this.language = 'fr',
    this.iconMode = false,
    this.voiceAssist = true,
    this.theme = 'dark',
  });

  final String language;
  final bool iconMode;
  final bool voiceAssist;

  /// `light` | `dark`
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
  UxPrefsNotifier(this._ref) : super(const UxPrefs()) {
    _hydrate();
    _ref.listen<AuthState>(authProvider, (prev, next) {
      final theme = next.user?.theme;
      if (theme != null && theme.isNotEmpty) {
        syncThemeFromUser(theme);
      }
    });
  }

  final Ref _ref;

  NfStrings get strings => NfStrings(state.language);

  void _hydrate() {
    try {
      final cached = _ref.read(localCacheProvider).getMap(LocalCacheKeys.uxPrefs);
      if (cached != null) {
        state = UxPrefs(
          language: NfStrings.normalize(cached['language']?.toString()),
          iconMode: cached['iconMode'] == true,
          voiceAssist: cached['voiceAssist'] != false,
          theme: _normalizeTheme(cached['theme']?.toString()),
        );
      }
    } catch (_) {
      // LocalCache not ready yet
    }
    final user = _ref.read(authProvider).user;
    final lang = user?.language;
    if (lang != null && lang.isNotEmpty) {
      state = state.copyWith(language: NfStrings.normalize(lang));
    }
    final theme = user?.theme;
    if (theme != null && theme.isNotEmpty) {
      state = state.copyWith(theme: _normalizeTheme(theme));
    }
    NfTokens.applyThemeMode(state.theme);
  }

  static String _normalizeTheme(String? value) =>
      value == 'light' ? 'light' : 'dark';

  Future<void> _saveLocal(UxPrefs prefs) async {
    try {
      await _ref.read(localCacheProvider).putMap(LocalCacheKeys.uxPrefs, {
        'language': prefs.language,
        'iconMode': prefs.iconMode,
        'voiceAssist': prefs.voiceAssist,
        'theme': prefs.theme,
      });
    } catch (_) {}
  }

  void setLanguageLocal(String lang) {
    state = state.copyWith(language: NfStrings.normalize(lang));
    _saveLocal(state);
  }

  void setIconModeLocal(bool value) {
    state = state.copyWith(iconMode: value);
    _saveLocal(state);
  }

  void setVoiceAssistLocal(bool value) {
    state = state.copyWith(voiceAssist: value);
    _saveLocal(state);
  }

  void setThemeLocal(String theme) {
    final next = _normalizeTheme(theme);
    state = state.copyWith(theme: next);
    NfTokens.applyThemeMode(next);
    _saveLocal(state);
  }

  /// Applique le thème renvoyé par l'API (/me, login).
  void syncThemeFromUser(String? theme) {
    if (theme == null || theme.isEmpty) return;
    final next = _normalizeTheme(theme);
    if (next == state.theme) return;
    state = state.copyWith(theme: next);
    NfTokens.applyThemeMode(next);
    _saveLocal(state);
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
    state = next;
    if (theme != null) NfTokens.applyThemeMode(next.theme);
    await _saveLocal(next);
    try {
      await _ref
          .read(apiClientProvider)
          .patch(
            '/me/preferences',
            data: {
              if (language != null) 'language': NfStrings.normalize(language),
              if (iconMode != null) 'modeIconographique': iconMode,
              if (voiceAssist != null) 'assistanceVocaleActive': voiceAssist,
              if (theme != null) 'theme': _normalizeTheme(theme),
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

final uxPrefsProvider = StateNotifierProvider<UxPrefsNotifier, UxPrefs>((ref) {
  return UxPrefsNotifier(ref);
});

final nfStringsProvider = Provider<NfStrings>((ref) {
  final lang = ref.watch(uxPrefsProvider).language;
  return NfStrings(lang);
});
