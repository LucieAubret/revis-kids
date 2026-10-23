import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/curriculum.dart';
import '../core/quest_theme.dart';
import '../data/ai_settings.dart';
import 'prompt.dart';
import 'quest.dart';

enum GeminiErrorKind { noKey, auth, quota, network, blocked, badResponse, server }

class GeminiException implements Exception {
  GeminiException(this.kind, [this.detail]);

  final GeminiErrorKind kind;
  final String? detail;

  /// Message destiné à l'enfant (jamais de détail technique ni de clé).
  String get childMessage => switch (kind) {
        GeminiErrorKind.noKey =>
          "Demande à un parent de préparer l'application dans l'Espace parent.",
        GeminiErrorKind.auth =>
          "L'application n'arrive pas à se connecter. Demande à un parent de vérifier la clé.",
        GeminiErrorKind.quota =>
          'Trop de demandes pour le moment. Réessaie dans une minute.',
        GeminiErrorKind.network =>
          'Pas de connexion internet. Vérifie le réseau puis réessaie.',
        GeminiErrorKind.blocked =>
          "Je ne peux pas analyser cette photo. Essaie avec ta feuille d'exercice.",
        GeminiErrorKind.badResponse ||
        GeminiErrorKind.server =>
          "Oups, je n'ai pas réussi à préparer ta quête. Réessaie !",
      };

  @override
  String toString() => 'GeminiException($kind${detail == null ? '' : ': $detail'})';
}

/// Ce dont l'interface a besoin : facile à remplacer dans les tests.
abstract class QuestGenerator {
  Future<QuestResult> createQuest({
    required Uint8List image,
    required String mimeType,
    required QuestTheme theme,
    required Curriculum curriculum,
  });
}

/// Client minimal de l'API Gemini (REST). La clé voyage dans l'en-tête
/// `x-goog-api-key`, jamais dans l'URL.
class GeminiClient implements QuestGenerator {
  GeminiClient({required this.apiKey, required this.model, http.Client? client})
      : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final http.Client _client;

  static const _host = 'generativelanguage.googleapis.com';

  Uri get _endpoint => Uri.https(_host, '/v1beta/models/$model:generateContent');

  Future<String> _generate(Map<String, dynamic> body) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw GeminiException(GeminiErrorKind.network, 'timeout');
    } catch (_) {
      throw GeminiException(GeminiErrorKind.network);
    }

    // Google répond 400 (et non 401) pour une clé invalide : on lit le motif.
    final invalidKey = res.statusCode == 400 && res.body.contains('API_KEY_INVALID');
    if (res.statusCode == 401 || res.statusCode == 403 || invalidKey) {
      throw GeminiException(GeminiErrorKind.auth, '${res.statusCode}');
    }
    if (res.statusCode == 429) throw GeminiException(GeminiErrorKind.quota);
    if (res.statusCode >= 500) {
      throw GeminiException(GeminiErrorKind.server, '${res.statusCode}');
    }
    if (res.statusCode != 200) {
      throw GeminiException(GeminiErrorKind.badResponse, '${res.statusCode}');
    }

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
    required Uint8List image,
    required String mimeType,
    required QuestTheme theme,
    required Curriculum curriculum,
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
            {'text': questUserPrompt},
            {
              'inlineData': {'mimeType': mimeType, 'data': base64Encode(image)},
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
}

/// Générateur de quêtes configuré avec la clé du parent. Lève
/// [GeminiException] `noKey` tant que la clé n'est pas saisie.
final questGeneratorProvider = FutureProvider<QuestGenerator>((ref) async {
  final settings = await ref.watch(aiSettingsProvider.future);
  if (!settings.hasKey) throw GeminiException(GeminiErrorKind.noKey);
  return GeminiClient(apiKey: settings.apiKey!, model: settings.model);
});
