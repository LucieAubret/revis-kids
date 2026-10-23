import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Vitesse de la voix. Les échelles diffèrent selon la plateforme : sur le web,
/// 1,0 est la vitesse normale ; sur mobile et ordinateur, c'est 0,5.
enum SpeechRate {
  lent('Lent', web: 0.6, native: 0.3),
  normal('Normal', web: 0.85, native: 0.45),
  rapide('Rapide', web: 1.1, native: 0.6);

  const SpeechRate(this.label, {required this.web, required this.native});

  final String label;
  final double web;
  final double native;

  double get value => kIsWeb ? web : native;
}

/// Voix de l'appareil (gratuite). Remplaçable dans les tests.
abstract class SpeechService {
  /// Prépare la voix française. Renvoie false si l'appareil n'a pas de voix.
  Future<bool> init();

  /// Lit le texte et se termine à la fin de la lecture (ou à l'arrêt).
  Future<void> speak(String text);

  Future<void> stop();

  Future<void> setRate(SpeechRate rate);
}

class DeviceSpeech implements SpeechService {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  /// Vrai entre le lancement d'une lecture et sa fin, son annulation ou son
  /// erreur. Sur le web, la bibliothèque ignore en silence une nouvelle lecture
  /// tant que l'arrêt de la précédente n'est pas confirmé : il faut donc
  /// attendre cette confirmation avant de relire.
  bool _busy = false;

  /// Numéro de la lecture en cours : une ancienne lecture annulée ne doit pas
  /// remettre à zéro l'état de la suivante en se terminant.
  int _generation = 0;

  @override
  Future<bool> init() async {
    if (_ready) return true;
    try {
      await _tts.awaitSpeakCompletion(true);
      final ok = await _tts.isLanguageAvailable('fr-FR');
      if (ok == false) return false;
      await _tts.setLanguage('fr-FR');
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(SpeechRate.normal.value);
      _tts.setCompletionHandler(() => _busy = false);
      _tts.setCancelHandler(() => _busy = false);
      _tts.setErrorHandler((_) => _busy = false);
      _ready = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> speak(String text) async {
    if (!await init()) return;
    final mine = ++_generation;
    _busy = true;
    try {
      await _tts.speak(text);
    } catch (_) {
      // Une voix qui échoue ne doit pas bloquer la dictée.
    } finally {
      if (mine == _generation) _busy = false;
    }
  }

  @override
  Future<void> stop() async {
    if (!_busy) return;
    try {
      await _tts.stop();
      // Attend la confirmation d'arrêt (au plus ~0,6 s).
      for (var i = 0; i < 12 && _busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } catch (_) {
      // Rien à faire : la lecture suivante repartira de toute façon.
    }
    _busy = false;
  }

  @override
  Future<void> setRate(SpeechRate rate) async {
    try {
      await _tts.setSpeechRate(rate.value);
    } catch (_) {}
  }
}

final speechServiceProvider = Provider<SpeechService>((ref) {
  final s = DeviceSpeech();
  ref.onDispose(s.stop);
  return s;
});
