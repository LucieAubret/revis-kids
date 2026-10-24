import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Dictée vocale de la description d'un exercice (voix vers texte).
/// Remplaçable dans les tests.
abstract class VoiceInput {
  /// Prépare la reconnaissance. Renvoie false si l'appareil ou le navigateur
  /// ne la propose pas, ou si le micro est refusé.
  Future<bool> init();

  bool get isListening;

  /// Écoute en français. [onText] reçoit le texte reconnu (provisoire, puis
  /// final) ; [onDone] est appelé quand l'écoute s'arrête ; [onError] reçoit
  /// un message lisible.
  Future<void> start({
    required void Function(String text, {required bool isFinal}) onText,
    required void Function() onDone,
    required void Function(String message) onError,
  });

  Future<void> stop();
}

class DeviceVoiceInput implements VoiceInput {
  final SpeechToText _stt = SpeechToText();
  bool _ready = false;
  void Function()? _onDone;
  void Function(String)? _onError;

  @override
  bool get isListening => _stt.isListening;

  @override
  Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onError: _handleError,
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') _onDone?.call();
        },
      );
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  void _handleError(SpeechRecognitionError e) {
    final id = e.errorMsg;
    _onError?.call(switch (id) {
      'error_permission' || 'not-allowed' || 'service-not-allowed' =>
        "Le micro n'est pas autorisé. Autorise-le dans les réglages de l'appareil ou du navigateur.",
      'error_no_match' || 'no-speech' || 'error_speech_timeout' =>
        "Je n'ai rien entendu. Réessaie en parlant un peu plus près.",
      'network' || 'error_network' =>
        'La reconnaissance vocale a besoin de réseau. Vérifie ta connexion.',
      _ => 'La dictée vocale a rencontré un problème ($id).',
    });
  }

  @override
  Future<void> start({
    required void Function(String text, {required bool isFinal}) onText,
    required void Function() onDone,
    required void Function(String message) onError,
  }) async {
    _onDone = onDone;
    _onError = onError;
    if (!await init()) {
      onError("La dictée vocale n'est pas disponible ici. Tu peux écrire l'exercice à la place.");
      onDone();
      return;
    }
    await _stt.listen(
      onResult: (r) => onText(r.recognizedWords, isFinal: r.finalResult),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        localeId: await _frenchLocale(),
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 6),
      ),
    );
  }

  Future<String?> _frenchLocale() async {
    try {
      final locales = await _stt.locales();
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith('fr')) return l.localeId;
      }
    } catch (_) {}
    return 'fr_FR';
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}

final voiceInputProvider = Provider<VoiceInput>((ref) {
  final v = DeviceVoiceInput();
  ref.onDispose(v.stop);
  return v;
});
