import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../l10n/locale_provider.dart';
import '../l10n/strings.dart';

/// Assistance vocale :
/// 1) audio `assets/audio/{lang}/{key}.mp3|.wav` si présent
/// 2) sinon TTS système
/// 3) STT : [listenOnce] pour dicter un montant / texte
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
  bool _busy = false;
  bool _sttReady = false;

  bool get enabled => _ref.read(uxPrefsProvider).voiceAssist;
  String get lang => _ref.read(uxPrefsProvider).language;
  NfStrings get strings => _ref.read(nfStringsProvider);

  Future<void> stop() async {
    await _player.stop();
    await _tts.stop();
    if (_stt.isListening) await _stt.stop();
    _busy = false;
  }

  /// Écoute ~5 s et renvoie le texte reconnu (FR). null si indisponible.
  Future<String?> listenOnce({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      if (!_sttReady) {
        _sttReady = await _stt.initialize(
          onError: (e) => debugPrint('STT error: $e'),
        );
      }
      if (!_sttReady) return null;

      await stop();
      String? result;
      await _stt.listen(
        onResult: (r) {
          if (r.finalResult || r.recognizedWords.isNotEmpty) {
            result = r.recognizedWords;
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: 'fr_FR',
          listenFor: timeout,
          pauseFor: const Duration(seconds: 2),
        ),
      );
      await Future<void>.delayed(timeout + const Duration(milliseconds: 400));
      await _stt.stop();
      return result?.trim();
    } catch (e) {
      debugPrint('VoiceService.listenOnce: $e');
      return null;
    }
  }

  Future<void> speakKey(
    String key, {
    Map<String, String> vars = const {},
  }) async {
    final text = vars.isEmpty ? strings.get(key) : strings.format(key, vars);
    await speakText(text, assetKey: key);
  }

  /// Ordre de repli des dossiers audio pour une langue donnée : la langue
  /// elle-même, puis mooré (langue la mieux couverte en audio), puis fr.
  List<String> _assetFallbackChain(String language) {
    if (language == 'fr') return const ['fr'];
    if (language == 'mr') return const ['mr', 'fr'];
    return [language, 'mr', 'fr'];
  }

  Future<void> speakText(String text, {String? assetKey}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_busy) await stop();
    _busy = true;
    try {
      if (assetKey != null) {
        for (final candidate in _assetFallbackChain(lang)) {
          if (await _playAsset(candidate, assetKey)) return;
        }
      }
      // Aucun audio disponible : on ne force jamais une TTS française sur un
      // texte en mooré/dioula/fulfuldé (résultat incompréhensible). On ne
      // parle en TTS que si le texte est déjà en français.
      if (lang == 'fr') {
        await _speakTts(trimmed);
      } else if (assetKey != null) {
        final fallbackText = NfStrings('fr').get(assetKey);
        if (fallbackText.trim().isNotEmpty) {
          await _speakTts(fallbackText);
        }
      }
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
  }

  void dispose() {
    _player.dispose();
  }
}

final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = VoiceService(ref);
  ref.onDispose(service.dispose);
  return service;
});
