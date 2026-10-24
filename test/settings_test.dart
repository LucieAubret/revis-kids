import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revis_kids/ai/gemini_client.dart';
import 'package:revis_kids/data/progress.dart';
import 'package:revis_kids/features/parent/ai_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const modelsJson = {
  'models': [
    {'name': 'models/gemini-3.8-flash', 'supportedGenerationMethods': ['generateContent']},
    {'name': 'models/gemini-3.6-flash', 'supportedGenerationMethods': ['generateContent']},
    {'name': 'models/gemini-3.8-pro', 'supportedGenerationMethods': ['generateContent']},
  ],
};

http.Response okReply() => http.Response.bytes(
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

/// Faux serveur Google : [generate] décide de la réponse pour chaque modèle.
MockClient fakeGoogle(http.Response Function(String model) generate, {int listStatus = 200}) {
  return MockClient((req) async {
    if (req.method == 'GET' && req.url.path == '/v1beta/models') {
      return listStatus == 200
          ? http.Response(jsonEncode(modelsJson), 200)
          : http.Response('{"error":{"code":400,"details":[{"reason":"API_KEY_INVALID"}]}}', listStatus);
    }
    final model = RegExp(r'models/([^:]+):generateContent').firstMatch(req.url.path)!.group(1)!;
    return generate(model);
  });
}

void main() {
  Future<void> open(WidgetTester tester, MockClient google) async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
        geminiClientFactoryProvider.overrideWithValue(
          (key, model) => GeminiClient(apiKey: key, model: model, client: google),
        ),
      ],
      child: const MaterialApp(home: AiSettingsScreen()),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> typeKeyAndTest(WidgetTester tester, String key) async {
    await tester.enterText(find.byType(TextField).first, key);
    await tester.tap(find.text('Tester la connexion'));
    await settle(tester);
  }

  testWidgets('clé et modèle valides : succès, autres modèles proposés', (tester) async {
    await open(tester, fakeGoogle((_) => okReply()));
    await typeKeyAndTest(tester, 'AQ.Ab8RN6-fake_Key.123');

    expect(find.textContaining('Connexion réussie : la clé et « gemini-3.8-flash » fonctionnent'),
        findsOneWidget);
    expect(find.text('Modèles disponibles avec votre clé :'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'gemini-3.6-flash'), findsOneWidget);
    // Le modèle déjà testé n'est pas reproposé.
    expect(find.widgetWithText(ActionChip, 'gemini-3.8-flash'), findsNothing);
  });

  testWidgets("modèle refusé : la clé est reconnue, un autre modèle se choisit d'un clic",
      (tester) async {
    await open(
      tester,
      fakeGoogle((model) => model == 'gemini-3.8-flash'
          ? http.Response(
              jsonEncode({
                'error': {'code': 403, 'message': 'Model not available for this key.', 'status': 'PERMISSION_DENIED'},
              }),
              403)
          : okReply()),
    );
    await typeKeyAndTest(tester, 'AQ.Ab8RN6-fake_Key.123');

    expect(find.textContaining('La clé est valide, mais « gemini-3.8-flash » ne répond pas'),
        findsOneWidget);
    expect(find.textContaining('Model not available for this key.'), findsOneWidget);
    expect(find.textContaining('Essayez un autre modèle'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'gemini-3.6-flash'));
    await settle(tester);

    expect(find.textContaining('la clé et « gemini-3.6-flash » fonctionnent'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        'gemini-3.6-flash');
  });

  testWidgets("API désactivée pour le projet : message qui dit quoi faire", (tester) async {
    await open(
      tester,
      fakeGoogle((_) => http.Response(
          jsonEncode({
            'error': {
              'code': 403,
              'message': 'Generative Language API has not been used in project 1 before or it is disabled.',
              'details': [
                {'reason': 'SERVICE_DISABLED'},
              ],
            },
          }),
          403)),
    );
    await typeKeyAndTest(tester, 'AQ.Ab8RN6-fake_Key.123');

    expect(find.textContaining('API Gemini est désactivée ou bloquée'), findsOneWidget);
    expect(find.textContaining('Generative Language API'), findsWidgets);
  });

  testWidgets('clé invalide : message clair, aucun modèle proposé', (tester) async {
    await open(tester, fakeGoogle((_) => okReply(), listStatus: 400));
    await typeKeyAndTest(tester, 'AQ.Ab8RN6-fake_Key.123');

    expect(find.textContaining('Clé refusée par Google'), findsOneWidget);
    expect(find.text('Modèles disponibles avec votre clé :'), findsNothing);
  });

  testWidgets('clé collée avec des espaces : nettoyée avant le test', (tester) async {
    late String sentKey;
    await open(
      tester,
      MockClient((req) async {
        sentKey = req.headers['x-goog-api-key']!;
        return req.method == 'GET'
            ? http.Response(jsonEncode(modelsJson), 200)
            : okReply();
      }),
    );
    await typeKeyAndTest(tester, '  AQ.Ab8RN6-fake_Key.123 \n');

    expect(sentKey, 'AQ.Ab8RN6-fake_Key.123');
    expect(find.textContaining('Connexion réussie'), findsOneWidget);
  });

  testWidgets('sans clé : on demande de la saisir, rien n\'est envoyé', (tester) async {
    var calls = 0;
    await open(tester, MockClient((_) async {
      calls++;
      return okReply();
    }));
    await tester.tap(find.text('Tester la connexion'));
    await settle(tester);

    expect(find.text("Saisissez d'abord une clé."), findsOneWidget);
    expect(calls, 0);
  });
}
