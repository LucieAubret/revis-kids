import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revis_kids/ai/api_key.dart';
import 'package:revis_kids/ai/gemini_client.dart';

GeminiClient clientWith(MockClient m, {String key = 'AQ.Ab8RN6-fake_Key.123'}) =>
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
      expect(seen.headers['x-goog-api-key'], 'AQ.Ab8RN6-fake_Key.123');
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
