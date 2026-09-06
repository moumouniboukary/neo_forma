import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../brand.dart';
import '../l10n/locale_provider.dart';
import '../l10n/strings.dart';
import 'spoken_amount.dart';

/// Assistance vocale :
/// 1) audio `assets/audio/{lang}/{key}.mp3|.wav` si présent
/// 2) sinon TTS système (français — montants / textes dynamiques)
/// 3) STT robuste : pause après lecture, retries, cloud / appareil.
class VoiceService {
  VoiceService(this._ref) {
    _tts.setSpeechRate(0.42);
    _tts.setVolume(1.0);
    _tts.setPitch(1.0);
  }

  final Ref _ref;
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  final SpeechToText _stt = SpeechToText();
  final Connectivity _connectivity = Connectivity();
  bool _busy = false;
  bool _sttReady = false;
  bool _listenLocked = false;

  bool get enabled => _ref.read(uxPrefsProvider).voiceAssist;
  String get lang => _ref.read(uxPrefsProvider).language;
  NfStrings get strings => _ref.read(nfStringsProvider);

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      if (_stt.isListening) await _stt.stop();
    } catch (_) {}
    _busy = false;
  }

  Future<bool> _isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  Future<void> _awaitPlayerIdle({
    Duration fallback = const Duration(milliseconds: 1800),
  }) async {
    try {
      await _player.onPlayerComplete.first.timeout(fallback);
    } catch (_) {
      await Future<void>.delayed(fallback);
    }
  }

  Future<bool> _ensureStt() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize(
        onError: (e) => debugPrint('STT error: $e'),
        onStatus: (s) => debugPrint('STT status: $s'),
      );
    } catch (e) {
      debugPrint('STT initialize failed: $e');
      _sttReady = false;
    }
    return _sttReady;
  }

  /// Coupe haut-parleur + micro, puis silence pour éviter l’écho.
  Future<void> _prepareMic() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      if (_stt.isListening) await _stt.cancel();
    } catch (_) {
      try {
        if (_stt.isListening) await _stt.stop();
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 450));
  }

  Future<String> _resolveSttLocale() async {
    List<LocaleName> locales;
    try {
      locales = await _stt.locales();
    } catch (_) {
      return 'fr_FR';
    }
    if (locales.isEmpty) return 'fr_FR';

    String norm(String id) => id.replaceAll('-', '_').toLowerCase();
    String? firstWherePrefix(List<String> prefixes) {
      for (final prefix in prefixes) {
        for (final loc in locales) {
          if (norm(loc.localeId).startsWith(prefix)) return loc.localeId;
        }
      }
      return null;
    }

    if (lang == 'mr') {
      return firstWherePrefix(const ['mos', 'fr']) ?? locales.first.localeId;
    }
    return firstWherePrefix(const ['fr']) ?? 'fr_FR';
  }

  Future<List<String>> _listenSession({
    required Duration timeout,
    required bool onDevice,
    ListenMode listenMode = ListenMode.confirmation,
  }) async {
    if (!await _ensureStt()) return const [];

    await _prepareMic();
    final localeId = await _resolveSttLocale();
    final texts = <String>[];
    final done = Completer<void>();
    var lastError = '';

    try {
      await _stt.listen(
        onResult: (r) {
          for (final a in r.alternates) {
            final w = a.recognizedWords.trim();
            if (w.isNotEmpty && !texts.contains(w)) texts.add(w);
          }
          if (r.finalResult && !done.isCompleted) {
            done.complete();
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: timeout,
          pauseFor: Duration(seconds: lang == 'mr' ? 3 : 2),
          partialResults: true,
          cancelOnError: false,
          onDevice: onDevice,
          listenMode: listenMode,
        ),
      );
      debugPrint('STT listen onDevice=$onDevice locale=$localeId');

      await done.future.timeout(
        timeout + const Duration(milliseconds: 900),
        onTimeout: () {},
      );
    } catch (e) {
      lastError = '$e';
      debugPrint('VoiceService.listenSession(onDevice=$onDevice): $e');
    } finally {
      try {
        if (_stt.isListening) await _stt.stop();
      } catch (_) {}
    }

    if (texts.isEmpty && lastError.isNotEmpty) {
      // Réinit au prochain essai si le moteur a planté.
      _sttReady = false;
    }
    return texts;
  }

  /// Écoute avec retries. Cloud si en ligne, sinon appareil (et l’inverse en secours).
  Future<List<String>> _listenAllTexts({
    required Duration timeout,
    int retries = 2,
    ListenMode listenMode = ListenMode.confirmation,
  }) async {
    if (_listenLocked) {
      // Évite deux micros en parallèle (cause fréquente d’échec).
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (_listenLocked) return const [];
    }
    _listenLocked = true;
    try {
      final online = await _isOnline();
      final primaryOnDevice = !online;
      final modes = primaryOnDevice ? [true, false] : [false, true];

      for (var attempt = 0; attempt < retries; attempt++) {
        // 1er essai : mode préféré seulement (évite d’attendre 2× le timeout).
        final tryModes = attempt == 0 ? [primaryOnDevice] : modes;
        for (final onDevice in tryModes) {
          final texts = await _listenSession(
            timeout: timeout,
            onDevice: onDevice,
            listenMode: listenMode,
          );
          if (texts.isNotEmpty) return texts;
        }
        if (attempt + 1 < retries) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      return const [];
    } finally {
      _listenLocked = false;
    }
  }

  /// Écoute courte — noms, type, etc.
  Future<String?> listenOnce({
    Duration timeout = const Duration(seconds: 7),
    int retries = 2,
  }) async {
    if (!kVoiceInputEnabled) return null;
    final texts = await _listenAllTexts(
      timeout: timeout,
      retries: retries,
      listenMode: ListenMode.confirmation,
    );
    if (texts.isEmpty) return null;
    return texts.first;
  }

  /// Dictée d’un montant : parse FR **ou** mooré selon la langue.
  Future<int?> listenAmountOnce({
    Duration timeout = const Duration(seconds: 7),
    int retries = 2,
  }) async {
    if (!kVoiceInputEnabled) return null;
    final wait = lang == 'mr'
        ? Duration(milliseconds: timeout.inMilliseconds + 1500)
        : timeout;
    final texts = await _listenAllTexts(
      timeout: wait,
      retries: retries,
      listenMode: ListenMode.dictation,
    );
    if (texts.isEmpty) return null;
    return parseSpokenAmount(
      texts.first,
      lang: lang,
      alternates: texts.skip(1),
    );
  }

  Future<void> speakKey(
    String key, {
    Map<String, String> vars = const {},
  }) async {
    if (key == 'confirmAmount' && vars.containsKey('n')) {
      await speakKey('confirmAmountPrompt');
      await speakAmountFcfa(vars['n']!);
      return;
    }
    final text = vars.isEmpty ? strings.get(key) : strings.format(key, vars);
    await speakText(text, assetKey: key);
  }

  Future<void> speakAmountFcfa(String formattedOrRaw) async {
    final raw = formattedOrRaw.replaceAll(RegExp(r'[^\d]'), '');
    final n = int.tryParse(raw);
    final spoken = n != null
        ? '${NumberFormat.decimalPattern('fr').format(n)} francs'
        : '$formattedOrRaw francs';
    await speakText(spoken);
  }

  List<String> _assetFallbackChain(String language) {
    if (language == 'fr') return const ['fr'];
    if (language == 'mr') return const ['mr', 'fr'];
    return const ['fr'];
  }

  Future<void> speakText(String text, {String? assetKey}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_busy) await stop();
    _busy = true;
    try {
      if (assetKey != null) {
        for (final candidate in _assetFallbackChain(lang)) {
          if (await _playAsset(candidate, assetKey)) {
            await _awaitPlayerIdle();
            // Laisse le haut-parleur se taire avant un éventuel micro.
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return;
          }
        }
      }
      await _speakTts(trimmed);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('VoiceService: $e');
    } finally {
      _busy = false;
    }
  }

  Future<bool> _playAsset(String language, String key) async {
    for (final ext in const ['mp3', 'wav']) {
      final path = 'audio/$language/$key.$ext';
      try {
        await rootBundle.load('assets/$path');
      } catch (_) {
        continue;
      }
      await _tts.stop();
      await _player.stop();
      await _player.play(AssetSource(path));
      return true;
    }
    return false;
  }

  Future<void> _speakTts(String text) async {
    await _player.stop();
    await _tts.setLanguage('fr-FR');
    await _tts.speak(text);
    final ms = (text.length * 55).clamp(700, 4500);
    await Future<void>.delayed(Duration(milliseconds: ms));
  }

  void dispose() {
    _player.dispose();
  }
}

final voiceServiceProvider = Provider<VoiceService>(
  (ref) {
    final service = VoiceService(ref);
    ref.onDispose(service.dispose);
    return service;
  },
  dependencies: [uxPrefsProvider, nfStringsProvider],
);
