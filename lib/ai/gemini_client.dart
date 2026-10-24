import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/curriculum.dart';
import '../core/quest_theme.dart';
import '../data/ai_settings.dart';
import 'api_key.dart';
import '../dictee/dictee_text.dart';
import 'prompt.dart';
import 'exercise.dart';
import 'quest.dart';
import 'tutor.dart';

enum GeminiErrorKind {
  noKey,
  invalidKey,
  keyRejected,
  auth,
  quota,
  network,
  serviceBlocked,
  permissionDenied,
  modelNotFound,
  blocked,
  badResponse,
  server,
  unknown,
}

class GeminiException implements Exception {
  GeminiException(this.kind, [this.detail]);

  final GeminiErrorKind kind;
  final String? detail;

  /// Message destiné à l'enfant (jamais de détail technique ni de clé).
  String get childMessage => switch (kind) {
        GeminiErrorKind.noKey =>
          "Demande à un parent de préparer l'application dans l'Espace parent.",
        GeminiErrorKind.invalidKey ||
        GeminiErrorKind.keyRejected ||
        GeminiErrorKind.modelNotFound ||
        GeminiErrorKind.serviceBlocked ||
        GeminiErrorKind.permissionDenied ||
        GeminiErrorKind.auth =>
          "L'application n'arrive pas à se connecter. Demande à un parent de vérifier la clé.",
        GeminiErrorKind.quota =>
          'Trop de demandes pour le moment. Réessaie dans une minute.',
        GeminiErrorKind.network =>
          'Pas de connexion internet. Vérifie le réseau puis réessaie.',
        GeminiErrorKind.blocked =>
          "Je ne peux pas analyser cette photo. Essaie avec ta feuille d'exercice.",
        GeminiErrorKind.badResponse ||
        GeminiErrorKind.server ||
        GeminiErrorKind.unknown =>
          "Oups, je n'ai pas réussi à analyser ton exercice. Réessaie !",
      };

  @override
  String toString() => 'GeminiException($kind${detail == null ? '' : ': $detail'})';
}

/// Ce dont l'interface a besoin : facile à remplacer dans les tests.
abstract class QuestGenerator {
  Future<QuestResult> createQuest({
    Uint8List? image,
    String? mimeType,
    required QuestTheme theme,
    required Curriculum curriculum,
    String? note,
  });
}

/// Client minimal de l'API Gemini (REST). La clé voyage dans l'en-tête
/// `x-goog-api-key`, jamais dans l'URL.
class GeminiClient
    implements QuestGenerator, TutorService, DicteeService, ExerciseService {
  GeminiClient({required this.apiKey, required this.model, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  static const _host = 'generativelanguage.googleapis.com';

  Uri get _endpoint => Uri.https(_host, '/v1beta/models/$model:generateContent');

  /// Message d'erreur renvoyé par Google dans le corps de la réponse, raccourci.
  static String? _apiMessage(String body) {
    try {
      final m = (jsonDecode(body) as Map)['error']?['message'] as String?;
      if (m == null) return null;
      final one = m.replaceAll(RegExp(r'\s+'), ' ').trim();
      return one.length > 160 ? '${one.substring(0, 160)}…' : one;
    } catch (_) {
      return null;
    }
  }

  /// Envoie une requête et traduit tous les refus de Google en erreurs claires.
  Future<http.Response> _send(Future<http.Response> Function() call) async {
    // Une clé mal copiée (caractère invisible, espace) rend l'en-tête invalide :
    // on le dit clairement au lieu de le faire passer pour une panne réseau.
    if (!isValidKeyFormat(apiKey)) {
      throw GeminiException(GeminiErrorKind.invalidKey);
    }
    final http.Response res;
    try {
      res = await call().timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw GeminiException(GeminiErrorKind.network, 'délai dépassé (60 s)');
    } on http.ClientException catch (e) {
      // Safari affiche « Load failed » aussi quand Google répond 401 : le corps
      // de la réponse est alors illisible. Le détail reste donc ambigu.
      throw GeminiException(GeminiErrorKind.network, e.message);
    } catch (e) {
      // Sur mobile et ordinateur, une coupure arrive sous forme d'erreurs système
      // (SocketException, HandshakeException…) qu'on ne peut pas nommer ici sans
      // importer dart:io, absent du web : on reconnaît le type par son nom.
      final type = e.runtimeType.toString();
      if (RegExp(r'Socket|Handshake|Tls|HttpException|Connection').hasMatch(type)) {
        throw GeminiException(GeminiErrorKind.network, type);
      }
      // Autre cause (ni réseau, ni Google) : on garde son type pour le diagnostic.
      throw GeminiException(GeminiErrorKind.unknown, type);
    }

    if (res.statusCode == 200) return res;
    final body = res.body;
    final why = _apiMessage(body);

    if (res.statusCode == 401 && res.body.contains('ACCESS_TOKEN_TYPE_UNSUPPORTED')) {
      throw GeminiException(GeminiErrorKind.keyRejected, '401');
    }
    // Google répond 400 (et non 401) pour une clé invalide : on lit le motif.
    if (res.statusCode == 400 && body.contains('API_KEY_INVALID')) {
      throw GeminiException(GeminiErrorKind.auth, '400');
    }
    if (res.statusCode == 401) throw GeminiException(GeminiErrorKind.auth, why);
    if (res.statusCode == 403) {
      // L'API Gemini désactivée ou interdite pour le projet de la clé.
      if (RegExp(r'SERVICE_DISABLED|API_KEY_SERVICE_BLOCKED|has not been used in project|is disabled')
          .hasMatch(body)) {
        throw GeminiException(GeminiErrorKind.serviceBlocked, why);
      }
      throw GeminiException(GeminiErrorKind.permissionDenied, why);
    }
    if (res.statusCode == 404) throw GeminiException(GeminiErrorKind.modelNotFound, model);
    if (res.statusCode == 429) throw GeminiException(GeminiErrorKind.quota, why);
    if (res.statusCode >= 500) {
      throw GeminiException(GeminiErrorKind.server, '${res.statusCode}');
    }
    throw GeminiException(GeminiErrorKind.badResponse, '${res.statusCode}${why == null ? '' : ' : $why'}');
  }

  /// Modèles utilisables avec cette clé (génération de texte et d'images en
  /// entrée), pour proposer un autre modèle si celui par défaut est refusé.
  /// Valide aussi la clé elle-même, indépendamment du modèle.
  Future<List<String>> listModels() async {
    final res = await _send(() => _client.get(
          Uri.https(_host, '/v1beta/models', {'pageSize': '100'}),
          headers: {'x-goog-api-key': apiKey},
        ));
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final out = <String>[];
      for (final m in (j['models'] as List? ?? const [])) {
        final name = (m['name'] as String? ?? '').replaceFirst('models/', '');
        final methods = List<String>.from(m['supportedGenerationMethods'] as List? ?? const []);
        if (!name.startsWith('gemini')) continue;
        if (!methods.contains('generateContent')) continue;
        if (RegExp(r'embedding|tts|image|live|audio|robotics|computer|aqa|learnlm|deep-research')
            .hasMatch(name)) {
          continue;
        }
        out.add(name);
      }
      // Les modèles « flash » rapides et stables d'abord, les préversions à la fin.
      int rank(String n) =>
          (n.contains('flash') && !n.contains('lite') ? 0 : n.contains('pro') ? 2 : 1) +
          (RegExp(r'preview|exp|latest').hasMatch(n) ? 10 : 0);
      out.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : b.compareTo(a);
      });
      return out.take(8).toList();
    } catch (_) {
      throw GeminiException(GeminiErrorKind.badResponse, 'liste illisible');
    }
  }

  Future<String> _generate(Map<String, dynamic> body) async {
    final res = await _send(() => _client.post(
          _endpoint,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: jsonEncode(body),
        ));

    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (j['promptFeedback']?['blockReason'] != null) {
        throw GeminiException(GeminiErrorKind.blocked);
      }
      final candidates = j['candidates'] as List?;
      final parts = candidates?.firstOrNull?['content']?['parts'] as List?;
      final text = parts
          ?.map((p) => (p as Map)['text'])
          .whereType<String>()
          .join();
      if (text == null || text.isEmpty) {
        throw GeminiException(GeminiErrorKind.blocked);
      }
      return text;
    } on GeminiException {
      rethrow;
    } catch (_) {
      throw GeminiException(GeminiErrorKind.badResponse);
    }
  }

  /// Vérifie que la clé et le modèle fonctionnent (requête texte minimale).
  Future<void> testConnection() async {
    await _generate({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'Réponds uniquement par : ok'},
          ],
        },
      ],
      'generationConfig': {'maxOutputTokens': 64},
    });
  }

  @override
  Future<QuestResult> createQuest({
    Uint8List? image,
    String? mimeType,
    required QuestTheme theme,
    required Curriculum curriculum,
    String? note,
  }) async {
    final text = await _generate({
      'systemInstruction': {
        'parts': [
          {'text': buildSystemInstruction(curriculum, theme)},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': questRequestText(note, hasImage: image != null)},
            if (image != null)
              {
                'inlineData': {
                  'mimeType': mimeType ?? 'image/jpeg',
                  'data': base64Encode(image),
                },
              },
          ],
        },
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'temperature': 0.6,
      },
    });
    try {
      return parseQuestResponse(text, curriculum);
    } on QuestParseException {
      throw GeminiException(GeminiErrorKind.badResponse, 'parse');
    }
  }

  @override
  Future<Verification> verifyAnswer({
    required Uint8List image,
    required String mimeType,
    required Quest quest,
    required Competence? competence,
    required QuestTheme theme,
    required int attemptNumber,
  }) async {
    final text = await _generate({
      'systemInstruction': {
        'parts': [
          {
            'text': buildVerifyInstruction(
              quest: quest,
              competence: competence,
              theme: theme,
              attemptNumber: attemptNumber,
            ),
          },
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': "Voici la photo de la réponse de l'élève. Vérifie-la et réponds en JSON."},
            {
              'inlineData': {'mimeType': mimeType, 'data': base64Encode(image)},
            },
          ],
        },
      ],
      'generationConfig': {'responseMimeType': 'application/json', 'temperature': 0.3},
    });
    try {
      return parseVerification(text);
    } on TutorParseException {
      throw GeminiException(GeminiErrorKind.badResponse, 'parse');
    }
  }

  @override
  Future<Capsule> createCapsule({
    required Quest quest,
    required Competence? competence,
    required QuestTheme theme,
  }) async {
    final text = await _generate({
      'systemInstruction': {
        'parts': [
          {
            'text': buildCapsuleInstruction(
              quest: quest,
              competence: competence,
              theme: theme,
            ),
          },
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': 'Écris la capsule « Bon à savoir » et réponds en JSON.'},
          ],
        },
      ],
      'generationConfig': {'responseMimeType': 'application/json', 'temperature': 0.5},
    });
    try {
      return parseCapsule(text);
    } on TutorParseException {
      throw GeminiException(GeminiErrorKind.badResponse, 'parse');
    }
  }

  Future<String> _dicteeCall({
    required String system,
    required List<Map<String, dynamic>> parts,
    double temperature = 0.3,
  }) =>
      _generate({
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': [
          {'role': 'user', 'parts': parts},
        ],
        'generationConfig': {
          'responseMimeType': 'application/json',
          'temperature': temperature,
        },
      });

  Map<String, dynamic> _image(Uint8List image, String mimeType) => {
        'inlineData': {'mimeType': mimeType, 'data': base64Encode(image)},
      };

  @override
  Future<DicteeText> extractText({
    required Uint8List image,
    required String mimeType,
  }) async {
    final text = await _dicteeCall(
      system: buildExtractDicteeInstruction(),
      parts: [
        {'text': 'Voici la photo du texte de la dictée. Recopie-le et réponds en JSON.'},
        _image(image, mimeType),
      ],
      temperature: 0.1,
    );
    try {
      return parseDicteeText(text);
    } on DicteeParseException {
      throw GeminiException(GeminiErrorKind.badResponse, 'parse');
    }
  }

  @override
  Future<DicteeText> generateText({
    required QuestTheme theme,
    required Curriculum curriculum,
  }) async {
    final text = await _dicteeCall(
      system: buildGenerateDicteeInstruction(curriculum, theme),
      parts: [
        {'text': 'Écris la dictée et réponds en JSON.'},
      ],
      temperature: 0.8,
    );
    try {
      return parseDicteeText(text);
    } on DicteeParseException {
      throw GeminiException(GeminiErrorKind.badResponse, 'parse');
    }
  }

  @override
  Future<DicteeCorrection> correct({
    required Uint8List image,
    required String mimeType,
    required String texteSource,
    required Curriculum curriculum,
  }) async {
    final text = await _dicteeCall(
      system: buildCorrectDicteeInstruction(
        texteSource: texteSource,
        curriculum: curriculum,
      ),
      parts: [
        {'text': "Voici la photo de la dictée écrite par l'élève. Corrige-la et réponds en JSON."},
        _image(image, mimeType),
      ],
    );
    try {
      return parseDicteeCorrection(text, curriculum);
    } on DicteeParseException {
      throw GeminiException(GeminiErrorKind.badResponse, 'parse');
    }
  }

  @override
  Future<Quest> generateExercise({
    required Competence competence,
    required QuestTheme theme,
    required ExerciseLevel level,
  }) async {
    final text = await _generate({
      'systemInstruction': {
        'parts': [
          {
            'text': buildExerciseInstruction(
              competence: competence,
              theme: theme,
              level: level,
              variation: DateTime.now().microsecondsSinceEpoch % 10000,
            ),
          },
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': "Crée l'exercice et réponds en JSON."},
          ],
        },
      ],
      'generationConfig': {'responseMimeType': 'application/json', 'temperature': 0.9},
    });
    try {
      return parseExercise(text, competence);
    } on QuestParseException {
      throw GeminiException(GeminiErrorKind.badResponse, 'parse');
    }
  }
}

/// Générateur de quêtes configuré avec la clé du parent. Lève
/// [GeminiException] `noKey` tant que la clé n'est pas saisie.
///
/// `retry: null` : Riverpod 3 réessaie sinon à l'infini un fournisseur en
/// échec, et l'enfant resterait devant un indicateur de chargement.
final questGeneratorProvider = FutureProvider<QuestGenerator>(
  (ref) async {
    final settings = await ref.watch(aiSettingsProvider.future);
    if (!settings.hasKey) throw GeminiException(GeminiErrorKind.noKey);
    return GeminiClient(apiKey: settings.apiKey!, model: settings.model);
  },
  retry: (_, _) => null,
);

final tutorServiceProvider = FutureProvider<TutorService>(
  (ref) async {
    final settings = await ref.watch(aiSettingsProvider.future);
    if (!settings.hasKey) throw GeminiException(GeminiErrorKind.noKey);
    return GeminiClient(apiKey: settings.apiKey!, model: settings.model);
  },
  retry: (_, _) => null,
);

final dicteeServiceProvider = FutureProvider<DicteeService>(
  (ref) async {
    final settings = await ref.watch(aiSettingsProvider.future);
    if (!settings.hasKey) throw GeminiException(GeminiErrorKind.noKey);
    return GeminiClient(apiKey: settings.apiKey!, model: settings.model);
  },
  retry: (_, _) => null,
);

/// Fabrique de clients, remplaçable dans les tests (écran de réglages).
final geminiClientFactoryProvider =
    Provider<GeminiClient Function(String apiKey, String model)>(
  (ref) => (apiKey, model) => GeminiClient(apiKey: apiKey, model: model),
);

final exerciseServiceProvider = FutureProvider<ExerciseService>(
  (ref) async {
    final settings = await ref.watch(aiSettingsProvider.future);
    if (!settings.hasKey) throw GeminiException(GeminiErrorKind.noKey);
    return GeminiClient(apiKey: settings.apiKey!, model: settings.model);
  },
  retry: (_, _) => null,
);
