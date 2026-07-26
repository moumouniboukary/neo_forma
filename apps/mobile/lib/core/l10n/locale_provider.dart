import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_provider.dart';
import '../api/client.dart';
import 'strings.dart';

/// Préférences UX locales (langue + mode icônes + voix).
class UxPrefs {
  const UxPrefs({
    this.language = 'fr',
    this.iconMode = false,
    this.voiceAssist = true,
  });

  final String language;
  final bool iconMode;
  final bool voiceAssist;

  UxPrefs copyWith({String? language, bool? iconMode, bool? voiceAssist}) =>
      UxPrefs(
        language: language ?? this.language,
        iconMode: iconMode ?? this.iconMode,
        voiceAssist: voiceAssist ?? this.voiceAssist,
      );
}

class UxPrefsNotifier extends StateNotifier<UxPrefs> {
  UxPrefsNotifier(this._ref) : super(const UxPrefs()) {
    final lang = _ref.read(authProvider).user?.language;
    if (lang != null && lang.isNotEmpty) {
      state = state.copyWith(language: NfStrings.normalize(lang));
    }
  }

  final Ref _ref;

  NfStrings get strings => NfStrings(state.language);

  void setLanguageLocal(String lang) {
    state = state.copyWith(language: NfStrings.normalize(lang));
  }

  void setIconModeLocal(bool value) {
    state = state.copyWith(iconMode: value);
  }

  void setVoiceAssistLocal(bool value) {
    state = state.copyWith(voiceAssist: value);
  }

  Future<void> persist({
    String? language,
    bool? iconMode,
    bool? voiceAssist,
  }) async {
    final next = state.copyWith(
      language: language != null ? NfStrings.normalize(language) : null,
      iconMode: iconMode,
      voiceAssist: voiceAssist,
    );
    state = next;
    try {
      await _ref
          .read(apiClientProvider)
          .patch(
            '/me/preferences',
            data: {
              if (language != null) 'language': NfStrings.normalize(language),
              if (iconMode != null) 'modeIconographique': iconMode,
              if (voiceAssist != null) 'assistanceVocaleActive': voiceAssist,
            },
          );
      final user = _ref.read(authProvider).user;
      if (user != null && language != null) {
        _ref
            .read(authProvider.notifier)
            .setUser(user.copyWith(language: NfStrings.normalize(language)));
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
