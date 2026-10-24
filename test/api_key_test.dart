import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revis_kids/ai/api_key.dart';
import 'package:revis_kids/ai/gemini_client.dart';

const kAizaKey = 'AIzaSyA-fake_Key.123';
const kAqKey = 'AQ.Ab8RN6-fake_Key.123';

GeminiClient clientWith(MockClient m, {String key = kAizaKey}) =>
    GeminiClient(apiKey: key, model: 'gemini-test', client: m);

Future<void> runTest(GeminiClient c) => c.testConnection();

void main() {
  group('nettoyage de la clé collée', () {
    test('espaces, retours à la ligne et caractères invisibles retirés', () {
      expect(sanitizeApiKey('  abc123  \n'), 'abc123');
      expect(sanitizeApiKey('abc​123 xyz﻿'), 'abc123xyz');
      expect(sanitizeApiKey('abc 123\tdef'), 'abc123def');
    });

    test('guillemets autour retirés, pas ceux de l\'intérieur inexistants', () {
      expect(sanitizeApiKey('"abc123"'), 'abc123');
      expect(sanitizeApiKey("'abc123'"), 'abc123');
      expect(sanitizeApiKey('“abc123”'), 'abc123');
    });

    test('une clé déjà propre ne change pas (formats AIza et AQ.)', () {
      expect(sanitizeApiKey('AIzaSyA-bcdEFG_hij123'), 'AIzaSyA-bcdEFG_hij123');
      expect(sanitizeApiKey('AQ.Ab8RN6-fake_Key.123'), 'AQ.Ab8RN6-fake_Key.123');
    });
  });

  group('format de la clé', () {
    test('caractères autorisés', () {
      expect(isValidKeyFormat('AIzaSyA-bcdEFG_hij123'), isTrue);
      expect(isValidKeyFormat('AQ.Ab8RN6-fake_Key.123'), isTrue);
      expect(isValidKeyFormat('INVALID-TEST-KEY'), isTrue);
    });

    test('caractères interdits', () {
      expect(isValidKeyFormat(''), isFalse);
      expect(isValidKeyFormat('abc 123'), isFalse);
      expect(isValidKeyFormat('abc\n'), isFalse);
      expect(isValidKeyFormat('clé-accentuée'), isFalse);
      expect(isValidKeyFormat('abc​123'), isFalse);
      expect(isValidKeyFormat('abc"123'), isFalse);
    });
  });

  group('modèles disponibles avec la clé', () {
    http.Response modelsReply() => http.Response(
          jsonEncode({
            'models': [
              {'name': 'models/gemini-3.6-flash', 'supportedGenerationMethods': ['generateContent']},
              {'name': 'models/gemini-3.8-flash', 'supportedGenerationMethods': ['generateContent', 'countTokens']},
              {'name': 'models/gemini-3.8-pro', 'supportedGenerationMethods': ['generateContent']},
              {'name': 'models/gemini-3.8-flash-lite', 'supportedGenerationMethods': ['generateContent']},
              {'name': 'models/gemini-3.9-flash-preview', 'supportedGenerationMethods': ['generateContent']},
              {'name': 'models/gemini-embedding-001', 'supportedGenerationMethods': ['embedContent']},
              {'name': 'models/gemini-3.8-flash-image', 'supportedGenerationMethods': ['generateContent']},
              {'name': 'models/gemini-3.8-flash-tts', 'supportedGenerationMethods': ['generateContent']},
              {'name': 'models/imagen-4', 'supportedGenerationMethods': ['predict']},
              {'name': 'models/text-bison', 'supportedGenerationMethods': ['generateContent']},
            ],
          }),
          200,
        );

    test("liste filtrée : seulement des modèles Gemini de texte, les rapides d'abord", () async {
      late http.Request seen;
      final c = clientWith(MockClient((r) async {
        seen = r;
        return modelsReply();
      }));
      final models = await c.listModels();

      expect(seen.method, 'GET');
      expect(seen.url.path, '/v1beta/models');
      expect(seen.headers['x-goog-api-key'], kAizaKey);
      expect(seen.url.toString(), isNot(contains('AQ.')));
      expect(models, ['gemini-3.8-flash', 'gemini-3.6-flash', 'gemini-3.8-flash-lite', 'gemini-3.8-pro', 'gemini-3.9-flash-preview']);
    });

    test('la liste valide aussi la clé : clé refusée = erreur claire', () async {
      final c = clientWith(MockClient((_) async => http.Response(
          '{"error":{"code":400,"details":[{"reason":"API_KEY_INVALID"}]}}', 400)));
      await expectLater(
        c.listModels(),
        throwsA(isA<GeminiException>().having((e) => e.kind, 'kind', GeminiErrorKind.auth)),
      );
    });
  });

  group('clés « AQ. » (nouveau format officiel de Google AI Studio)', () {
    test('une clé AQ. est acceptée comme n\'importe quelle clé et envoyée telle quelle', () async {
      late http.Request seen;
      final c = clientWith(
        MockClient((r) async {
          seen = r;
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'ok'},
                    ],
                  },
                },
              ],
            })),
            200,
          );
        }),
        key: kAqKey,
      );
      await runTest(c);
      expect(seen.headers['x-goog-api-key'], kAqKey);
      expect(isValidKeyFormat(kAqKey), isTrue);
    });

    test('Google répond 401 ACCESS_TOKEN_TYPE_UNSUPPORTED : clé refusée, sans accuser le format', () async {
      final c = clientWith(
        MockClient((_) async => http.Response(
            '{"error":{"code":401,"status":"UNAUTHENTICATED","details":'
            '[{"reason":"ACCESS_TOKEN_TYPE_UNSUPPORTED"}]}}',
            401)),
        key: kAqKey,
      );
      await expectLater(
        runTest(c),
        throwsA(isA<GeminiException>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.keyRejected)),
      );
    });

    test('« Load failed » de Safari reste une erreur réseau ambiguë, même avec une clé AQ.', () async {
      final c = clientWith(
        MockClient((_) async => throw http.ClientException('Load failed')),
        key: kAqKey,
      );
      await expectLater(
        runTest(c),
        throwsA(isA<GeminiException>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.network)
            .having((e) => e.detail, 'detail', 'Load failed')),
      );
    });

    test('la liste des modèles accepte aussi une clé AQ.', () async {
      final c = clientWith(
        MockClient((_) async => http.Response(
            jsonEncode({
              'models': [
                {
                  'name': 'models/gemini-3.8-flash',
                  'supportedGenerationMethods': ['generateContent'],
                },
              ],
            }),
            200)),
        key: kAqKey,
      );
      expect(await c.listModels(), ['gemini-3.8-flash']);
    });
  });

  group('diagnostic précis du test de connexion', () {
    test('clé invalide : on le dit, sans envoyer de requête', () async {
      var calls = 0;
      final c = clientWith(
        MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
        key: 'abc​123',
      );
      await expectLater(
        runTest(c),
        throwsA(isA<GeminiException>().having((e) => e.kind, 'kind', GeminiErrorKind.invalidKey)),
      );
      expect(calls, 0);
    });

    test('réseau coupé : « réseau » avec le détail', () async {
      final c = clientWith(MockClient((_) async => throw http.ClientException('Failed to fetch')));
      await expectLater(
        runTest(c),
        throwsA(isA<GeminiException>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.network)
            .having((e) => e.detail, 'detail', contains('Failed to fetch'))),
      );
    });

    test('délai dépassé : « réseau » avec le détail', () async {
      final c = clientWith(MockClient((_) async => throw TimeoutException('lent')));
      await expectLater(
        runTest(c),
        throwsA(isA<GeminiException>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.network)
            .having((e) => e.detail, 'detail', contains('délai'))),
      );
    });

    test("autre erreur interne : jamais prise pour une panne réseau", () async {
      final c = clientWith(MockClient((_) async => throw const FormatException('bizarre')));
      await expectLater(
        runTest(c),
        throwsA(isA<GeminiException>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.unknown)
            .having((e) => e.detail, 'detail', 'FormatException')),
      );
    });

    test('modèle inexistant (404) : message dédié avec son nom', () async {
      final c = clientWith(MockClient((_) async => http.Response('{}', 404)));
      await expectLater(
        runTest(c),
        throwsA(isA<GeminiException>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.modelNotFound)
            .having((e) => e.detail, 'detail', 'gemini-test')),
      );
    });

    test('une clé valide passe : requête envoyée avec l\'en-tête', () async {
      late http.Request seen;
      final c = clientWith(MockClient((r) async {
        seen = r;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'ok'},
                  ],
                },
              },
            ],
          })),
          200,
        );
      }));
      await runTest(c);
      expect(seen.headers['x-goog-api-key'], kAizaKey);
    });

    test('403 « API désactivée » : service bloqué, avec le motif de Google', () async {
      final c = clientWith(MockClient((_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 403,
              'message': 'Generative Language API has not been used in project 123 before or it is disabled.',
              'status': 'PERMISSION_DENIED',
              'details': [
                {'reason': 'SERVICE_DISABLED'},
              ],
            },
          }),
          403)));
      await expectLater(
        runTest(c),
        throwsA(isA<GeminiException>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.serviceBlocked)
            .having((e) => e.detail, 'detail', contains('has not been used'))),
      );
    });

    test('403 sans motif de service : permission refusée', () async {
      final c = clientWith(MockClient((_) async => http.Response(
          jsonEncode({
            'error': {'code': 403, 'message': 'Model access denied.', 'status': 'PERMISSION_DENIED'},
          }),
          403)));
      await expectLater(
        runTest(c),
        throwsA(isA<GeminiException>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.permissionDenied)
            .having((e) => e.detail, 'detail', 'Model access denied.')),
      );
    });

    test('429 : quota, avec le message de Google', () async {
      final c = clientWith(MockClient((_) async => http.Response(
          jsonEncode({
            'error': {'code': 429, 'message': 'Quota exceeded for metric, limit: 0'},
          }),
          429)));
      await expectLater(
        runTest(c),
        throwsA(isA<GeminiException>()
            .having((e) => e.kind, 'kind', GeminiErrorKind.quota)
            .having((e) => e.detail, 'detail', contains('limit: 0'))),
      );
    });

    test("le message pour l'enfant ne contient ni clé ni détail technique", () {
      for (final k in GeminiErrorKind.values) {
        final msg = GeminiException(k, 'Failed to fetch SECRET-123').childMessage;
        expect(msg, isNot(contains('SECRET')), reason: k.name);
        expect(msg, isNot(contains('Failed')), reason: k.name);
      }
    });
  });
}
